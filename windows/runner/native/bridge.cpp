#include "bridge.h"

#include <sddl.h>
#include <shellapi.h>

#include <atomic>
#include <cstring>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace {

constexpr DWORD kMaxFrame = 1024 * 1024;  // as BridgeFraming.maxFrame
constexpr DWORD kChunk = 64 * 1024;
constexpr wchar_t kFirefoxId[] = L"bridge@sotto.app";

// ─────────────────────────── Identity ───────────────────────────

std::wstring SidOfToken(HANDLE token) {
  DWORD size = 0;
  GetTokenInformation(token, TokenUser, nullptr, 0, &size);
  if (size == 0) return std::wstring();
  std::vector<BYTE> buffer(size);
  if (!GetTokenInformation(token, TokenUser, buffer.data(), size, &size)) return std::wstring();
  LPWSTR text = nullptr;
  if (!ConvertSidToStringSidW(reinterpret_cast<TOKEN_USER*>(buffer.data())->User.Sid, &text)) {
    return std::wstring();
  }
  std::wstring sid(text);
  LocalFree(text);
  return sid;
}

std::wstring CurrentUserSid() {
  HANDLE token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return std::wstring();
  std::wstring sid = SidOfToken(token);
  CloseHandle(token);
  return sid;
}

// Whether process [pid] runs as the user [sid].
bool ProcessRunsAs(ULONG pid, const std::wstring& sid) {
  if (sid.empty()) return false;
  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (process == nullptr) return false;
  bool same = false;
  HANDLE token = nullptr;
  if (OpenProcessToken(process, TOKEN_QUERY, &token)) {
    same = SidOfToken(token) == sid;
    CloseHandle(token);
  }
  CloseHandle(process);
  return same;
}

std::wstring PipeName(const std::wstring& sid) { return L"\\\\.\\pipe\\sotto-bridge-" + sid; }

// ─────────────────────────── Overlapped I/O ───────────────────────────

// Up to [size] bytes from [handle] (opened for overlapped I/O); 0 when it
// failed, closed, or [stop] was signalled.
DWORD ReadSome(HANDLE handle, void* buffer, DWORD size, HANDLE stop) {
  OVERLAPPED ov{};
  ov.hEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (ov.hEvent == nullptr) return 0;
  DWORD got = 0;
  if (!ReadFile(handle, buffer, size, nullptr, &ov)) {
    if (GetLastError() != ERROR_IO_PENDING) {
      CloseHandle(ov.hEvent);
      return 0;
    }
    HANDLE waits[2] = {ov.hEvent, stop};
    if (WaitForMultipleObjects(stop != nullptr ? 2 : 1, waits, FALSE, INFINITE) != WAIT_OBJECT_0) {
      CancelIoEx(handle, &ov);
      GetOverlappedResult(handle, &ov, &got, TRUE);
      CloseHandle(ov.hEvent);
      return 0;
    }
  }
  if (!GetOverlappedResult(handle, &ov, &got, FALSE)) got = 0;
  CloseHandle(ov.hEvent);
  return got;
}

bool ReadExact(HANDLE handle, void* buffer, DWORD size, HANDLE stop) {
  auto* p = static_cast<uint8_t*>(buffer);
  while (size > 0) {
    const DWORD got = ReadSome(handle, p, size, stop);
    if (got == 0) return false;
    p += got;
    size -= got;
  }
  return true;
}

bool WriteAll(HANDLE handle, const uint8_t* data, size_t size) {
  OVERLAPPED ov{};
  ov.hEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (ov.hEvent == nullptr) return false;
  bool ok = true;
  while (size > 0 && ok) {
    const DWORD chunk = static_cast<DWORD>(size < kChunk ? size : kChunk);
    DWORD wrote = 0;
    ResetEvent(ov.hEvent);
    if (!WriteFile(handle, data, chunk, nullptr, &ov) && GetLastError() != ERROR_IO_PENDING) {
      ok = false;
      break;
    }
    ok = GetOverlappedResult(handle, &ov, &wrote, TRUE) && wrote > 0;
    data += wrote;
    size -= wrote;
  }
  CloseHandle(ov.hEvent);
  return ok;
}

// Synchronous handles (the browser's stdin / stdout).
bool ReadExactSync(HANDLE handle, void* buffer, DWORD size) {
  auto* p = static_cast<uint8_t*>(buffer);
  while (size > 0) {
    DWORD got = 0;
    if (!ReadFile(handle, p, size, &got, nullptr) || got == 0) return false;
    p += got;
    size -= got;
  }
  return true;
}

bool WriteAllSync(HANDLE handle, const uint8_t* data, size_t size) {
  while (size > 0) {
    DWORD wrote = 0;
    if (!WriteFile(handle, data, static_cast<DWORD>(size), &wrote, nullptr) || wrote == 0) return false;
    data += wrote;
    size -= wrote;
  }
  return true;
}

// ─────────────────────────── Server (the app) ───────────────────────────

struct Connection {
  int id = 0;
  HANDLE pipe = INVALID_HANDLE_VALUE;
  std::mutex write_mutex;
};

class Server {
 public:
  bool Start(SottoBridgeEvent callback, void* context) {
    sid_ = CurrentUserSid();
    if (sid_.empty()) return false;
    name_ = PipeName(sid_);
    // Only the current user, full access; nobody else at all.
    const std::wstring sddl = L"D:P(A;;GA;;;" + sid_ + L")";
    if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl.c_str(), SDDL_REVISION_1, &descriptor_, nullptr)) {
      return false;
    }
    HANDLE first = CreateInstance(true);
    if (first == INVALID_HANDLE_VALUE) {
      LocalFree(descriptor_);
      descriptor_ = nullptr;
      return false;
    }
    callback_ = callback;
    context_ = context;
    stop_ = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    acceptor_ = std::thread([this, first] { AcceptLoop(first); });
    return true;
  }

  void Stop() {
    if (!acceptor_.joinable()) return;
    SetEvent(stop_);
    acceptor_.join();
    {
      std::lock_guard<std::mutex> lock(mutex_);
      for (auto& entry : connections_) CancelIoEx(entry.second->pipe, nullptr);
    }
    // Readers are detached; each one leaves on stop_ and counts itself out.
    for (int i = 0; i < 300 && readers_.load() > 0; i++) Sleep(10);
    CloseHandle(stop_);
    stop_ = nullptr;
    LocalFree(descriptor_);
    descriptor_ = nullptr;
    callback_ = nullptr;
  }

  bool Write(int id, const uint8_t* data, size_t size) {
    std::shared_ptr<Connection> c = Find(id);
    if (!c) return false;
    std::lock_guard<std::mutex> lock(c->write_mutex);
    return c->pipe != INVALID_HANDLE_VALUE && WriteAll(c->pipe, data, size);
  }

  void Close(int id) {
    std::shared_ptr<Connection> c = Find(id);
    if (c) CancelIoEx(c->pipe, nullptr);
  }

 private:
  HANDLE CreateInstance(bool first) {
    SECURITY_ATTRIBUTES sa{sizeof(sa), descriptor_, FALSE};
    const DWORD open = PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED | (first ? FILE_FLAG_FIRST_PIPE_INSTANCE : 0);
    return CreateNamedPipeW(name_.c_str(), open, PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS,
                            PIPE_UNLIMITED_INSTANCES, kChunk, kChunk, 0, &sa);
  }

  std::shared_ptr<Connection> Find(int id) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto it = connections_.find(id);
    return it == connections_.end() ? nullptr : it->second;
  }

  // Waits for a client on [pipe]; false when stopping or it failed.
  bool WaitForClient(HANDLE pipe) {
    OVERLAPPED ov{};
    ov.hEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (ov.hEvent == nullptr) return false;
    bool connected = false;
    if (ConnectNamedPipe(pipe, &ov)) {
      connected = true;
    } else if (GetLastError() == ERROR_PIPE_CONNECTED) {
      connected = true;
    } else if (GetLastError() == ERROR_IO_PENDING) {
      HANDLE waits[2] = {ov.hEvent, stop_};
      DWORD n = 0;
      if (WaitForMultipleObjects(2, waits, FALSE, INFINITE) == WAIT_OBJECT_0) {
        connected = GetOverlappedResult(pipe, &ov, &n, FALSE) != FALSE;
      } else {
        CancelIoEx(pipe, &ov);
        GetOverlappedResult(pipe, &ov, &n, TRUE);
      }
    }
    CloseHandle(ov.hEvent);
    return connected;
  }

  void AcceptLoop(HANDLE pipe) {
    for (;;) {
      if (pipe == INVALID_HANDLE_VALUE) {
        if (WaitForSingleObject(stop_, 500) == WAIT_OBJECT_0) return;
        pipe = CreateInstance(false);
        continue;
      }
      const bool connected = WaitForClient(pipe);
      if (WaitForSingleObject(stop_, 0) == WAIT_OBJECT_0) {
        CloseHandle(pipe);
        return;
      }
      ULONG pid = 0;
      // Only a process of the current user gets in, whatever the DACL says.
      if (!connected || !GetNamedPipeClientProcessId(pipe, &pid) || !ProcessRunsAs(pid, sid_)) {
        DisconnectNamedPipe(pipe);
        CloseHandle(pipe);
        pipe = CreateInstance(false);
        continue;
      }
      auto c = std::make_shared<Connection>();
      c->pipe = pipe;
      {
        std::lock_guard<std::mutex> lock(mutex_);
        c->id = next_id_++;
        connections_[c->id] = c;
      }
      readers_++;
      callback_(context_, c->id, 0, nullptr, 0);
      std::thread([this, c] { ReadLoop(c); }).detach();
      pipe = CreateInstance(false);
    }
  }

  void ReadLoop(std::shared_ptr<Connection> c) {
    std::vector<uint8_t> buffer(kChunk);
    for (;;) {
      const DWORD got = ReadSome(c->pipe, buffer.data(), kChunk, stop_);
      if (got == 0) break;
      callback_(context_, c->id, 1, buffer.data(), got);
    }
    {
      std::lock_guard<std::mutex> lock(mutex_);
      connections_.erase(c->id);
    }
    {
      std::lock_guard<std::mutex> lock(c->write_mutex);
      DisconnectNamedPipe(c->pipe);
      CloseHandle(c->pipe);
      c->pipe = INVALID_HANDLE_VALUE;
    }
    callback_(context_, c->id, 2, nullptr, 0);
    readers_--;
  }

  std::wstring sid_;
  std::wstring name_;
  PSECURITY_DESCRIPTOR descriptor_ = nullptr;
  SottoBridgeEvent callback_ = nullptr;
  void* context_ = nullptr;
  HANDLE stop_ = nullptr;
  std::thread acceptor_;
  std::mutex mutex_;
  std::map<int, std::shared_ptr<Connection>> connections_;
  int next_id_ = 1;
  std::atomic<int> readers_{0};
};

Server g_server;

// ─────────────────────────── Host (started by a browser) ───────────────────────────

// The host keeps the browser's port open while Sotto isn't running and
// connects (again) whenever it is. A frame from the browser that arrives
// with no app to take it is dropped; the extension's request times out and
// Sotto falls back to accessibility.
class Host {
 public:
  int Run() {
    in_ = GetStdHandle(STD_INPUT_HANDLE);
    out_ = GetStdHandle(STD_OUTPUT_HANDLE);
    if (in_ == nullptr || in_ == INVALID_HANDLE_VALUE || out_ == nullptr || out_ == INVALID_HANDLE_VALUE) return 1;
    sid_ = CurrentUserSid();
    if (sid_.empty()) return 1;
    name_ = PipeName(sid_);
    std::thread([this] { BrowserToApp(); }).detach();
    AppToBrowser();
    return 0;
  }

 private:
  // stdin → pipe, one whole frame at a time.
  void BrowserToApp() {
    std::vector<uint8_t> frame;
    for (;;) {
      uint32_t size = 0;
      if (!ReadExactSync(in_, &size, 4) || size == 0 || size > kMaxFrame) break;
      frame.resize(4 + size);
      memcpy(frame.data(), &size, 4);
      if (!ReadExactSync(in_, frame.data() + 4, size)) break;
      std::lock_guard<std::mutex> lock(pipe_mutex_);
      if (pipe_ != INVALID_HANDLE_VALUE) WriteAll(pipe_, frame.data(), frame.size());
    }
    // The browser closed the port (or broke the protocol): done.
    ExitProcess(0);
  }

  HANDLE Connect() {
    for (;;) {
      HANDLE h = CreateFileW(name_.c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr, OPEN_EXISTING,
                             FILE_FLAG_OVERLAPPED | SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION, nullptr);
      if (h != INVALID_HANDLE_VALUE) {
        ULONG pid = 0;
        // The app at the other end must be this user's too.
        if (GetNamedPipeServerProcessId(h, &pid) && ProcessRunsAs(pid, sid_)) return h;
        CloseHandle(h);
      } else if (GetLastError() == ERROR_PIPE_BUSY) {
        WaitNamedPipeW(name_.c_str(), 2000);
        continue;
      }
      Sleep(2000);  // Sotto isn't running yet.
    }
  }

  // Tells the extension whether Sotto is at the other end (its toolbar icon
  // and popup show it). Only this thread writes to stdout.
  void SayConnected(bool connected) {
    const std::string body =
        std::string("{\"v\":1,\"event\":\"sotto\",\"connected\":") + (connected ? "true" : "false") + "}";
    const uint32_t size = static_cast<uint32_t>(body.size());
    std::vector<uint8_t> frame(4 + body.size());
    memcpy(frame.data(), &size, 4);
    memcpy(frame.data() + 4, body.data(), body.size());
    if (!WriteAllSync(out_, frame.data(), frame.size())) ExitProcess(0);
  }

  // pipe → stdout, one whole frame at a time; reconnects when the app goes.
  void AppToBrowser() {
    std::vector<uint8_t> frame;
    for (;;) {
      HANDLE h = Connect();
      {
        std::lock_guard<std::mutex> lock(pipe_mutex_);
        pipe_ = h;
      }
      SayConnected(true);
      for (;;) {
        uint32_t size = 0;
        if (!ReadExact(h, &size, 4, nullptr) || size == 0 || size > kMaxFrame) break;
        frame.resize(4 + size);
        memcpy(frame.data(), &size, 4);
        if (!ReadExact(h, frame.data() + 4, size, nullptr)) break;
        if (!WriteAllSync(out_, frame.data(), frame.size())) ExitProcess(0);
      }
      {
        std::lock_guard<std::mutex> lock(pipe_mutex_);
        pipe_ = INVALID_HANDLE_VALUE;
        CloseHandle(h);
      }
      SayConnected(false);
      Sleep(500);
    }
  }

  HANDLE in_ = nullptr;
  HANDLE out_ = nullptr;
  std::wstring sid_;
  std::wstring name_;
  std::mutex pipe_mutex_;
  HANDLE pipe_ = INVALID_HANDLE_VALUE;
};

}  // namespace

bool SottoBridgeStart(SottoBridgeEvent callback, void* context) {
  try {
    return callback != nullptr && g_server.Start(callback, context);
  } catch (...) {
    return false;
  }
}

void SottoBridgeStop() {
  try {
    g_server.Stop();
  } catch (...) {
  }
}

bool SottoBridgeWrite(int conn, const uint8_t* data, size_t size) {
  try {
    return g_server.Write(conn, data, size);
  } catch (...) {
    return false;
  }
}

void SottoBridgeClose(int conn) {
  try {
    g_server.Close(conn);
  } catch (...) {
  }
}

bool SottoBridgeRegisterHost(const wchar_t* key, const wchar_t* manifest_path) {
  HKEY handle = nullptr;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, key, 0, nullptr, 0, KEY_SET_VALUE, nullptr, &handle, nullptr) != ERROR_SUCCESS) {
    return false;
  }
  const DWORD bytes = static_cast<DWORD>((wcslen(manifest_path) + 1) * sizeof(wchar_t));
  const bool ok = RegSetValueExW(handle, nullptr, 0, REG_SZ, reinterpret_cast<const BYTE*>(manifest_path), bytes) ==
                  ERROR_SUCCESS;
  RegCloseKey(handle);
  return ok;
}

bool SottoBridgeIsHostLaunch() {
  int argc = 0;
  LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  if (argv == nullptr) return false;
  bool host = false;
  for (int i = 1; i < argc && !host; i++) {
    const std::wstring arg(argv[i]);
    host = arg.rfind(L"chrome-extension://", 0) == 0 || arg == L"--native-host" || arg == kFirefoxId;
  }
  LocalFree(argv);
  return host;
}

int SottoBridgeHostMain() {
  try {
    Host host;
    return host.Run();
  } catch (...) {
    return 1;
  }
}

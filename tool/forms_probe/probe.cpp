// Drives windows/runner/native/forms.cpp — the code Sotto fills forms with —
// against a real window, for test/integration/form_fixture_live_test.dart
// and for checking a page by hand. Build with build.bat.
//   probe read <title> <out.json>          what Sotto reads in that window
//   probe exec <title> <commands> <out>    read, then run one command per line
//   probe close <title>                    close the windows with that title
// <title>: parts of the window title, '&'-separated ("long page&Edge").
// Commands: setValue <id> <text> | setRange <id> <n> | select <id> |
//   toggle <id> <0|1> | choose <id> <label> | invoke <id> | focus <id> |
//   state <id> | canScroll <id|-> | scrollDown <id|-> | key <name[+name]> |
//   type - <text> | click <x,y> | wheel <x,y> | sleep <ms> | read <out.json> |
//   capture <out.jpg> <out.json>
#include <windows.h>
#include <objbase.h>

#include <cstdio>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#include "forms.h"
#include "input.h"
#include "screen_capture.h"

static HWND g_found = nullptr;
static std::wstring g_want;

static bool Matches(const std::wstring& title);

static BOOL CALLBACK CloseAll(HWND h, LPARAM n) {
  wchar_t t[512] = {};
  GetWindowTextW(h, t, 512);
  if (IsWindowVisible(h) && Matches(t)) {
    PostMessageW(h, WM_CLOSE, 0, 0);
    ++*reinterpret_cast<int*>(n);
  }
  return TRUE;
}

// Every '&'-separated part of g_want must appear in the title.
static bool Matches(const std::wstring& title) {
  size_t at = 0;
  while (at <= g_want.size()) {
    const size_t amp = g_want.find(L'&', at);
    const std::wstring part = g_want.substr(at, amp == std::wstring::npos ? std::wstring::npos : amp - at);
    if (title.find(part) == std::wstring::npos) return false;
    if (amp == std::wstring::npos) break;
    at = amp + 1;
  }
  return true;
}

static BOOL CALLBACK Enum(HWND h, LPARAM) {
  if (!IsWindowVisible(h)) return TRUE;
  wchar_t t[512] = {};
  GetWindowTextW(h, t, 512);
  if (Matches(t)) {
    g_found = h;
    return FALSE;
  }
  return TRUE;
}

static bool Front(HWND h) {
  // Already in front: leave focus where it is (a lone Alt would move it to
  // the browser's menu button).
  if (GetForegroundWindow() == h) return true;
  keybd_event(VK_MENU, 0, 0, 0);
  keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, 0);
  ShowWindow(h, SW_RESTORE);
  SetForegroundWindow(h);
  Sleep(400);
  return GetForegroundWindow() == h;
}

static std::wstring Wide(const std::string& s) {
  const int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), nullptr, 0);
  std::wstring w(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), w.data(), n);
  return w;
}

static std::string Read(DWORD* ms, bool* ok, const char** error) {
  const DWORD t0 = GetTickCount();
  char* json = nullptr;
  *ok = SottoFormRead(800, &json, error);
  *ms = GetTickCount() - t0;
  std::string out = *ok && json ? json : "[]";
  if (json) SottoFormFree(json);
  return out;
}

int wmain(int argc, wchar_t** argv) {
  if (argc < 3) {
    fwprintf(stderr, L"usage: probe read <title part> <out.json> | exec <title part> <cmds> <out>\n");
    return 2;
  }
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  const std::wstring mode = argv[1];
  g_want = argv[2];
  if (mode == L"close") {
    int n = 0;
    EnumWindows(CloseAll, reinterpret_cast<LPARAM>(&n));
    printf("closed %d\n", n);
    return 0;
  }
  EnumWindows(Enum, 0);
  if (g_found == nullptr) {
    fwprintf(stderr, L"no window with \"%s\"\n", argv[2]);
    return 1;
  }
  const bool front = Front(g_found);
  DWORD ms = 0;
  bool ok = false;
  const char* error = "";
  const std::string elements = Read(&ms, &ok, &error);
  if (mode == L"read") {
    FILE* f = _wfopen(argv[3], L"wb");
    if (f != nullptr) {
      fprintf(f, "{\"front\":%s,\"ok\":%s,\"error\":\"%s\",\"ms\":%lu,\"elements\":%s}", front ? "true" : "false",
              ok ? "true" : "false", error, ms, elements.c_str());
      fclose(f);
    }
    printf("front=%d ok=%d error=%s ms=%lu\n", front, ok, error, ms);
    return ok ? 0 : 1;
  }
  if (argc < 5) return 2;
  std::ifstream in(argv[3], std::ios::binary);
  std::ofstream out(argv[4], std::ios::binary);
  out << "front " << front << " read " << ok << " " << ms << "ms\n";
  std::string line;
  while (std::getline(in, line)) {
    if (!line.empty() && line.back() == '\r') line.pop_back();
    if (line.empty() || line[0] == '#') continue;
    std::istringstream s(line);
    std::string op, id;
    s >> op >> id;
    std::string arg;
    std::getline(s, arg);
    if (!arg.empty() && arg[0] == ' ') arg.erase(0, 1);
    std::string result;
    const DWORD t0 = GetTickCount();
    if (op == "setValue") {
      result = SottoFormSetValue(id.c_str(), Wide(arg).c_str()) ? "true" : "false";
    } else if (op == "setRange") {
      result = SottoFormSetRange(id.c_str(), std::stod(arg)) ? "true" : "false";
    } else if (op == "select") {
      result = SottoFormSelect(id.c_str()) ? "true" : "false";
    } else if (op == "toggle") {
      result = SottoFormToggle(id.c_str(), arg == "1") ? "true" : "false";
    } else if (op == "choose") {
      result = SottoFormChoose(id.c_str(), Wide(arg).c_str()) ? "true" : "false";
    } else if (op == "state") {
      char* json = nullptr;
      result = SottoFormState(id.c_str(), &json) && json ? json : "null";
      if (json) SottoFormFree(json);
    } else if (op == "canScroll") {
      result = std::to_string(SottoFormCanScrollDown(id == "-" ? "" : id.c_str()));
    } else if (op == "scrollDown") {
      result = std::to_string(SottoFormScrollDown(id == "-" ? "" : id.c_str()));
    } else if (op == "focus") {
      result = SottoFormFocus(id.c_str()) ? "true" : "false";
    } else if (op == "invoke") {
      result = SottoFormInvoke(id.c_str()) ? "true" : "false";
    } else if (op == "key") {
      // "ctrl+f5" -> {"ctrl", "f5"}
      std::vector<std::string> parts;
      size_t at = 0;
      while (at <= id.size()) {
        const size_t plus = id.find('+', at);
        parts.push_back(id.substr(at, plus == std::string::npos ? std::string::npos : plus - at));
        if (plus == std::string::npos) break;
        at = plus + 1;
      }
      std::vector<const char*> keys;
      for (auto& k : parts) keys.push_back(k.c_str());
      result = SottoPressKeys(keys.data(), static_cast<int>(keys.size())) ? "true" : "false";
    } else if (op == "click") {
      const int comma = static_cast<int>(id.find(','));
      result = SottoMouseClick(std::stoi(id.substr(0, comma)), std::stoi(id.substr(comma + 1)), 0, 1) ? "true" : "false";
    } else if (op == "type") {
      result = SottoTypeText(Wide(arg).c_str()) ? "true" : "false";
    } else if (op == "wheel") {
      const int comma = static_cast<int>(id.find(','));
      result = SottoMouseScroll(std::stoi(id.substr(0, comma)), std::stoi(id.substr(comma + 1)), true, 0, 5) ? "true" : "false";
    } else if (op == "capture") {
      // capture <out.jpg> <out.json>: the window's display, as the model
      // sees it, and the text OCR finds on it.
      SottoCapture c{};
      const HMONITOR monitor = MonitorFromWindow(g_found, MONITOR_DEFAULTTOPRIMARY);
      if (SottoCaptureMonitor(monitor, 1300, 80, true, &c)) {
        std::ofstream(Wide(id), std::ios::binary).write(reinterpret_cast<const char*>(c.jpeg), c.jpeg_size);
        std::ofstream(Wide(arg), std::ios::binary) << (c.ocr_json ? c.ocr_json : "null");
        result = std::to_string(c.width) + "x" + std::to_string(c.height) + (c.ocr_json ? " ocr" : " no-ocr");
        SottoCaptureFree(&c);
      } else {
        result = std::string("failed: ") + c.error;
      }
    } else if (op == "sleep") {
      Sleep(std::stoi(id));
      result = "ok";
    } else if (op == "read") {
      DWORD rms = 0;
      bool rok = false;
      const char* rerr = "";
      const std::string again = Read(&rms, &rok, &rerr);
      std::ofstream(Wide(id), std::ios::binary) << again;
      result = std::to_string(rms) + "ms";
    }
    out << op << " " << id << " " << arg << " => " << result << " (" << (GetTickCount() - t0) << "ms)\n";
  }
  return 0;
}

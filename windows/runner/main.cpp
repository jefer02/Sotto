#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <cstdio>
#include <cwctype>
#include <string>

#include "flutter_window.h"
#include "native/bridge.h"
#include "utils.h"

namespace {

// The executable's file name, lower-cased ("sotto.exe"), for [process].
std::wstring ImageName(HANDLE process) {
  wchar_t path[MAX_PATH];
  DWORD size = MAX_PATH;
  if (!::QueryFullProcessImageNameW(process, 0, path, &size)) return L"";
  std::wstring name(path, size);
  const size_t slash = name.find_last_of(L"\\/");
  if (slash != std::wstring::npos) name = name.substr(slash + 1);
  for (auto& c : name) c = static_cast<wchar_t>(::towlower(c));
  return name;
}

struct FindMain {
  std::wstring image;
  DWORD self;
  HWND found = nullptr;
};

// The first top-level Flutter window owned by another process running the
// same executable.
BOOL CALLBACK FindRunningWindow(HWND hwnd, LPARAM param) {
  auto* find = reinterpret_cast<FindMain*>(param);
  wchar_t cls[64];
  if (!::GetClassNameW(hwnd, cls, 64) ||
      std::wstring(cls) != L"FLUTTER_RUNNER_WIN32_WINDOW") {
    return TRUE;
  }
  DWORD pid = 0;
  ::GetWindowThreadProcessId(hwnd, &pid);
  if (pid == find->self) return TRUE;
  HANDLE process =
      ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!process) return TRUE;
  const bool same = ImageName(process) == find->image;
  ::CloseHandle(process);
  if (!same) return TRUE;
  find->found = hwnd;
  return FALSE;
}

// Sotto keeps its data in locked files, so a second copy can't start: it
// brings the running one forward instead. Held for the life of the
// process; Windows releases it on exit, crash included.
bool AnotherInstanceRunning() {
  ::CreateMutexW(nullptr, TRUE, L"Local\\SottoSingleInstance");
  if (::GetLastError() != ERROR_ALREADY_EXISTS) return false;

  FindMain find{ImageName(::GetCurrentProcess()), ::GetCurrentProcessId()};
  ::EnumWindows(FindRunningWindow, reinterpret_cast<LPARAM>(&find));
  if (find.found) {
    ::ShowWindow(find.found, ::IsIconic(find.found) ? SW_RESTORE : SW_SHOW);
    ::SetForegroundWindow(find.found);
  }
  std::fputs(
      "Sotto is already running, so this copy brought it to the front and "
      "quit. Close the running Sotto (including from the tray or overlay) "
      "to start a new build.\n",
      stderr);
  std::fflush(stderr);
  return true;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Started by a browser as the extension's native messaging host: relay
  // between stdin / stdout and the running app's pipe. No window, no
  // Flutter, no console.
  if (SottoBridgeIsHostLaunch()) {
    return SottoBridgeHostMain();
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  if (AnotherInstanceRunning()) {
    return EXIT_SUCCESS;
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Sotto", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}

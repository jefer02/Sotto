#include "flutter_window.h"

#include <dwmapi.h>
#include <flutter/standard_method_codec.h>

#include <optional>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "native/screen_capture.h"

namespace {

// Constants from newer SDK headers, defined here so older SDKs still build.
constexpr DWORD kExcludeFromCapture = 0x00000011;  // WDA_EXCLUDEFROMCAPTURE
constexpr DWORD kDwmUseImmersiveDarkMode = 20;       // DWMWA_USE_IMMERSIVE_DARK_MODE
constexpr DWORD kDwmCornerPreference = 33;           // DWMWA_WINDOW_CORNER_PREFERENCE
constexpr DWORD kDwmBorderColor = 34;                // DWMWA_BORDER_COLOR
constexpr DWORD kDwmSystemBackdropType = 38;         // DWMWA_SYSTEMBACKDROP_TYPE
constexpr int kCornerDoNotRound = 1;                 // DWMWCP_DONOTROUND
constexpr int kCornerRound = 2;                      // DWMWCP_ROUND
constexpr COLORREF kColorNone = 0xFFFFFFFE;          // DWMWA_COLOR_NONE
constexpr COLORREF kColorDefault = 0xFFFFFFFF;       // DWMWA_COLOR_DEFAULT
constexpr int kBackdropNone = 1;                     // DWMSBT_NONE
constexpr int kBackdropTransient = 3;                // DWMSBT_TRANSIENTWINDOW (acrylic)

int GetInt(const flutter::EncodableMap& args, const char* key, int fallback) {
  auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) return fallback;
  const int* value = std::get_if<int>(&it->second);
  return value != nullptr ? *value : fallback;
}

std::string GetString(const flutter::EncodableMap& args, const char* key) {
  auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) return std::string();
  const std::string* value = std::get_if<std::string>(&it->second);
  return value != nullptr ? *value : std::string();
}

bool GetBool(const flutter::EncodableMap& args, const char* key) {
  auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) return false;
  const bool* value = std::get_if<bool>(&it->second);
  return value != nullptr && *value;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  overlay_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "app.sotto/overlay",
      &flutter::StandardMethodCodec::GetInstance());
  overlay_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() != "configure") {
          result->NotImplemented();
          return;
        }
        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
        if (args == nullptr) {
          result->Error("bad_args", "Expected a map");
          return;
        }
        ConfigureOverlay(GetBool(*args, "enabled"), GetBool(*args, "excludeFromCapture"),
                         GetBool(*args, "blur"), GetBool(*args, "dark"),
                         GetBool(*args, "textOnly"));
        result->Success();
      });

  screen_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "app.sotto/screen",
      &flutter::StandardMethodCodec::GetInstance());
  screen_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        HandleScreenCall(call, std::move(result));
      });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::ConfigureOverlay(bool enabled, bool exclude_from_capture, bool blur,
                                     bool dark, bool text_only) {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) return;
  overlay_ = enabled;

  // A tool window stays out of Alt+Tab and the taskbar; NOACTIVATE keeps a
  // click on the overlay from pulling focus away from the meeting app.
  LONG_PTR ex = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
  if (enabled) {
    ex |= WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE;
    ex &= ~WS_EX_APPWINDOW;
  } else {
    ex &= ~(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE);
    ex |= WS_EX_APPWINDOW;
  }
  SetWindowLongPtr(hwnd, GWL_EXSTYLE, ex);
  SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);

  // Hide from screen capture (Windows 10 2004+); older builds fall back to
  // showing a black rectangle in captures instead of the script.
  DWORD affinity = (enabled && exclude_from_capture) ? kExcludeFromCapture : WDA_NONE;
  if (!SetWindowDisplayAffinity(hwnd, affinity) && affinity != WDA_NONE) {
    SetWindowDisplayAffinity(hwnd, WDA_MONITOR);
  }

  // Windows 11: rounded corners and an acrylic backdrop. Ignored elsewhere.
  // Text only: nothing of the window may show — no backdrop, no rounded
  // frame, no 1 px DWM border — only the glyphs Flutter draws.
  const bool bare = enabled && text_only;
  BOOL dark_mode = dark ? TRUE : FALSE;
  DwmSetWindowAttribute(hwnd, kDwmUseImmersiveDarkMode, &dark_mode, sizeof(dark_mode));
  int corner = bare ? kCornerDoNotRound : kCornerRound;
  DwmSetWindowAttribute(hwnd, kDwmCornerPreference, &corner, sizeof(corner));
  COLORREF border = bare ? kColorNone : kColorDefault;
  DwmSetWindowAttribute(hwnd, kDwmBorderColor, &border, sizeof(border));
  int backdrop = (enabled && blur && !text_only) ? kBackdropTransient : kBackdropNone;
  DwmSetWindowAttribute(hwnd, kDwmSystemBackdropType, &backdrop, sizeof(backdrop));
}

void FlutterWindow::HandleScreenCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();
  // Windows needs no permission for screen capture.
  if (method == "permission") {
    result->Success(flutter::EncodableValue("granted"));
    return;
  }
  if (method != "capture") {
    result->NotImplemented();
    return;
  }
  const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
  const flutter::EncodableMap empty;
  const auto& a = args != nullptr ? *args : empty;
  // The display the overlay sits on, or the one under the mouse pointer.
  HMONITOR monitor;
  if (GetString(a, "target") == "cursor") {
    POINT pt{};
    GetCursorPos(&pt);
    monitor = MonitorFromPoint(pt, MONITOR_DEFAULTTOPRIMARY);
  } else {
    monitor = MonitorFromWindow(GetHandle(), MONITOR_DEFAULTTOPRIMARY);
  }
  // Sotto must never be in its own screenshots, even with "Hide from
  // screen capture" turned off: exclude the window for this one capture.
  HWND hwnd = GetHandle();
  DWORD previous = WDA_NONE;
  GetWindowDisplayAffinity(hwnd, &previous);
  SetWindowDisplayAffinity(hwnd, kExcludeFromCapture);
  SottoCapture capture{};
  const bool ok = SottoCaptureMonitor(monitor, GetInt(a, "maxSide", 1300), GetInt(a, "quality", 80), &capture);
  SetWindowDisplayAffinity(hwnd, previous);
  if (!ok) {
    result->Error("capture_failed", capture.error);
    return;
  }
  std::vector<uint8_t> jpeg(capture.jpeg, capture.jpeg + capture.jpeg_size);
  SottoCaptureFree(&capture);
  result->Success(flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("jpeg"), flutter::EncodableValue(std::move(jpeg))},
      {flutter::EncodableValue("width"), flutter::EncodableValue(capture.width)},
      {flutter::EncodableValue("height"), flutter::EncodableValue(capture.height)},
      {flutter::EncodableValue("left"), flutter::EncodableValue(capture.left)},
      {flutter::EncodableValue("top"), flutter::EncodableValue(capture.top)},
      {flutter::EncodableValue("screenWidth"), flutter::EncodableValue(capture.screen_width)},
      {flutter::EncodableValue("screenHeight"), flutter::EncodableValue(capture.screen_height)},
      {flutter::EncodableValue("scale"), flutter::EncodableValue(capture.scale)},
      {flutter::EncodableValue("method"), flutter::EncodableValue(std::string(capture.method))},
  }));
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // The overlay never activates on click; checked before plugins so no
  // handler can override it.
  if (overlay_ && message == WM_MOUSEACTIVATE) {
    return MA_NOACTIVATE;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

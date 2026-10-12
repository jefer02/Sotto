#include "flutter_window.h"

#include <dwmapi.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <optional>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "native/bridge.h"
#include "native/forms.h"
#include "native/input.h"
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

double GetDouble(const flutter::EncodableMap& args, const char* key) {
  auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) return 0;
  if (const double* d = std::get_if<double>(&it->second)) return *d;
  if (const int* i = std::get_if<int>(&it->second)) return *i;
  return 0;
}

std::wstring Wide(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  const int n = MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), nullptr, 0);
  std::wstring out(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), out.data(), n);
  return out;
}

std::string Utf8(const wchar_t* wide) {
  const int n = WideCharToMultiByte(CP_UTF8, 0, wide, -1, nullptr, 0, nullptr, nullptr);
  if (n <= 1) return std::string();
  std::string out(n - 1, '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide, -1, out.data(), n, nullptr, nullptr);
  return out;
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
  forms_worker_.Start(GetHandle());
  capture_worker_.Start(GetHandle());

  overlay_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "app.sotto/overlay",
      &flutter::StandardMethodCodec::GetInstance());
  overlay_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
        if (call.method_name() == "keyboard") {
          SetOverlayKeyboard(args != nullptr && GetBool(*args, "on"));
          result->Success();
          return;
        }
        if (call.method_name() != "configure") {
          result->NotImplemented();
          return;
        }
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

  input_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "app.sotto/input",
      &flutter::StandardMethodCodec::GetInstance());
  input_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        HandleInputCall(call, std::move(result));
      });

  forms_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "app.sotto/forms",
      &flutter::StandardMethodCodec::GetInstance());
  forms_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        HandleFormsCall(call, std::move(result));
      });

  // Battery saver: background polling (auto-fill) slows down.
  power_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "app.sotto/power",
      &flutter::StandardMethodCodec::GetInstance());
  power_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() != "saver") {
          result->NotImplemented();
          return;
        }
        SYSTEM_POWER_STATUS status{};
        const bool saver = GetSystemPowerStatus(&status) && status.SystemStatusFlag == 1;
        result->Success(flutter::EncodableValue(saver));
      });

  bridge_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "app.sotto/bridge",
      &flutter::StandardMethodCodec::GetInstance());
  bridge_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        HandleBridgeCall(call, std::move(result));
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
  // A maximised window would stay maximised through the frame change below
  // and ignore the overlay's bounds.
  if (enabled && IsZoomed(hwnd)) ShowWindow(hwnd, SW_RESTORE);
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
  if (method == "captureRegion") {
    CaptureRegion(call, std::move(result));
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
  const std::string target = GetString(a, "target");
  HWND foreground = GetForegroundWindow();
  if (target == "cursor") {
    POINT pt{};
    GetCursorPos(&pt);
    monitor = MonitorFromPoint(pt, MONITOR_DEFAULTTOPRIMARY);
  } else if (target == "foreground" && foreground != nullptr && foreground != GetHandle()) {
    // The display of the window being worked on (a questionnaire).
    monitor = MonitorFromWindow(foreground, MONITOR_DEFAULTTOPRIMARY);
  } else {
    monitor = MonitorFromWindow(GetHandle(), MONITOR_DEFAULTTOPRIMARY);
  }
  // Sotto must never be in its own screenshots, even with "Hide from
  // screen capture" turned off: exclude the window while captures run.
  HWND hwnd = GetHandle();
  if (captures_in_flight_++ == 0) {
    affinity_before_capture_ = WDA_NONE;
    GetWindowDisplayAffinity(hwnd, &affinity_before_capture_);
    SetWindowDisplayAffinity(hwnd, kExcludeFromCapture);
  }
  const int max_side = GetInt(a, "maxSide", 1300);
  const int quality = GetInt(a, "quality", 80);
  std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>> reply(std::move(result));
  // Back on the platform thread: the window's affinity first.
  auto done = [this, hwnd]() {
    if (--captures_in_flight_ == 0) SetWindowDisplayAffinity(hwnd, affinity_before_capture_);
  };
  // Capture and JPEG encoding run on the capture thread; the raw pixels are
  // freed there and only the JPEG crosses back.
  capture_worker_.Post(
      [monitor, max_side, quality, reply, done]() -> NativeWorker::Reply {
        SottoCapture capture{};
        if (!SottoCaptureMonitor(monitor, max_side, quality, &capture)) {
          std::string error(capture.error);
          return [reply, done, error]() {
            done();
            reply->Error("capture_failed", error);
          };
        }
        auto value = std::make_shared<flutter::EncodableValue>(flutter::EncodableMap{
            {flutter::EncodableValue("jpeg"),
             flutter::EncodableValue(std::vector<uint8_t>(capture.jpeg, capture.jpeg + capture.jpeg_size))},
            {flutter::EncodableValue("width"), flutter::EncodableValue(capture.width)},
            {flutter::EncodableValue("height"), flutter::EncodableValue(capture.height)},
            {flutter::EncodableValue("left"), flutter::EncodableValue(capture.left)},
            {flutter::EncodableValue("top"), flutter::EncodableValue(capture.top)},
            {flutter::EncodableValue("screenWidth"), flutter::EncodableValue(capture.screen_width)},
            {flutter::EncodableValue("screenHeight"), flutter::EncodableValue(capture.screen_height)},
            {flutter::EncodableValue("scale"), flutter::EncodableValue(capture.scale)},
            {flutter::EncodableValue("method"), flutter::EncodableValue(std::string(capture.method))},
        });
        SottoCaptureFree(&capture);
        return [reply, done, value]() {
          done();
          reply->Success(*value);
        };
      },
      [reply, done]() {
        done();
        reply->Error("capture_failed", "Screen capture failed");
      });
}

void FlutterWindow::HandleInputCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();
  const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
  const flutter::EncodableMap empty;
  const auto& a = args != nullptr ? *args : empty;
  const int x = static_cast<int>(GetDouble(a, "x"));
  const int y = static_cast<int>(GetDouble(a, "y"));
  bool ok = true;
  if (method == "permission") {
    result->Success(flutter::EncodableValue("granted"));  // Windows needs none
    return;
  } else if (method == "move") {
    ok = SottoMouseMove(x, y);
  } else if (method == "mouseButton") {
    ok = SottoMouseButton(x, y, GetBool(a, "down"));
  } else if (method == "click") {
    ok = SottoMouseClick(x, y, GetString(a, "button") == "right" ? 1 : 0, GetInt(a, "count", 1));
  } else if (method == "scroll") {
    ok = SottoMouseScroll(x, y, GetBool(a, "atPoint"), GetInt(a, "dx", 0), GetInt(a, "dy", 0));
  } else if (method == "type") {
    ok = SottoTypeText(Wide(GetString(a, "text")).c_str());
  } else if (method == "keys") {
    std::vector<std::string> names;
    auto it = a.find(flutter::EncodableValue("keys"));
    if (it != a.end()) {
      if (const auto* list = std::get_if<flutter::EncodableList>(&it->second)) {
        for (const auto& v : *list) {
          if (const auto* s = std::get_if<std::string>(&v)) names.push_back(*s);
        }
      }
    }
    std::vector<const char*> raw;
    for (const auto& n : names) raw.push_back(n.c_str());
    ok = !raw.empty() && SottoPressKeys(raw.data(), static_cast<int>(raw.size()));
  } else if (method == "releaseAll") {
    SottoReleaseAll();
  } else if (method == "focused") {
    bool password = false;
    wchar_t name[256];
    wchar_t role[64];
    if (!SottoFocusedElement(&password, name, 256, role, 64)) {
      result->Success();
      return;
    }
    result->Success(flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue("isPassword"), flutter::EncodableValue(password)},
        {flutter::EncodableValue("name"), flutter::EncodableValue(Utf8(name))},
        {flutter::EncodableValue("role"), flutter::EncodableValue(Utf8(role))},
    }));
    return;
  } else {
    result->NotImplemented();
    return;
  }
  if (ok) {
    result->Success();
  } else {
    result->Error("input_failed", method);
  }
}

void FlutterWindow::SetOverlayKeyboard(bool on) {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr || !overlay_ || on == overlay_keyboard_) return;
  overlay_keyboard_ = on;
  LONG_PTR ex = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
  if (on) {
    focus_before_keyboard_ = GetForegroundWindow();
    SetWindowLongPtr(hwnd, GWL_EXSTYLE, ex & ~WS_EX_NOACTIVATE);
    SetForegroundWindow(hwnd);
  } else {
    SetWindowLongPtr(hwnd, GWL_EXSTYLE, ex | WS_EX_NOACTIVATE);
    // Give the keyboard back to Zoom / PowerPoint.
    if (focus_before_keyboard_ != nullptr && IsWindow(focus_before_keyboard_)) {
      SetForegroundWindow(focus_before_keyboard_);
    }
    focus_before_keyboard_ = nullptr;
  }
}

void FlutterWindow::HandleFormsCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string method = call.method_name();
  const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
  const flutter::EncodableMap a = args != nullptr ? *args : flutter::EncodableMap();
  if (method == "permission") {
    result->Success(flutter::EncodableValue("granted"));  // UI Automation needs none
    return;
  }
  static const char* const kMethods[] = {"foreground", "canScrollDown", "read",   "setValue",       "select",
                                         "toggle",     "choose",        "invoke", "scrollIntoView", "focus"};
  if (std::none_of(std::begin(kMethods), std::end(kMethods), [&](const char* m) { return method == m; })) {
    result->NotImplemented();
    return;
  }
  // A page's tree can take a while to walk: never on the platform thread.
  std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>> reply(std::move(result));
  forms_worker_.Post(
      [method, a, reply]() -> NativeWorker::Reply {
        using flutter::EncodableValue;
        if (method == "foreground" || method == "read") {
          char* json = nullptr;
          const char* error = "no_window";
          const bool ok = method == "read" ? SottoFormRead(GetInt(a, "max", 800), &json, &error)
                                           : SottoForegroundInfo(&json);
          if (!ok) {
            std::string code(error);
            return [reply, code]() { reply->Error(code, code); };
          }
          auto out = std::make_shared<EncodableValue>(std::string(json));
          SottoFormFree(json);
          return [reply, out]() { reply->Success(*out); };
        }
        if (method == "canScrollDown") {
          const int r = SottoFormCanScrollDown();
          return [reply, r]() { reply->Success(r < 0 ? EncodableValue() : EncodableValue(r == 1)); };
        }
        const std::string id = GetString(a, "id");
        bool ok = false;
        if (method == "setValue") {
          ok = SottoFormSetValue(id.c_str(), Wide(GetString(a, "text")).c_str());
        } else if (method == "select") {
          ok = SottoFormSelect(id.c_str());
        } else if (method == "toggle") {
          ok = SottoFormToggle(id.c_str(), GetBool(a, "on"));
        } else if (method == "choose") {
          ok = SottoFormChoose(id.c_str(), Wide(GetString(a, "label")).c_str());
        } else if (method == "invoke") {
          ok = SottoFormInvoke(id.c_str());
        } else if (method == "focus") {
          ok = SottoFormFocus(id.c_str());
        } else if (method == "scrollIntoView") {
          ok = SottoFormScrollIntoView(id.c_str());
        }
        return [reply, ok]() { reply->Success(EncodableValue(ok)); };
      },
      [reply]() { reply->Error("uia_failed", "UI Automation failed"); });
}

// A few pixels of what is behind the overlay, for the text-contrast check:
// GDI StretchBlt (HALFTONE averages the pixels) of the region into a tiny
// 32-bit DIB, with this window excluded from the capture for the moment.
// Rect arrives in window_manager's logical pixels.
void FlutterWindow::CaptureRegion(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
  const flutter::EncodableMap empty;
  const auto& a = args != nullptr ? *args : empty;
  double dpr = GetDouble(a, "devicePixelRatio");
  if (dpr <= 0) dpr = 1;
  const int left = static_cast<int>(GetDouble(a, "left") * dpr);
  const int top = static_cast<int>(GetDouble(a, "top") * dpr);
  const int w = static_cast<int>(GetDouble(a, "width") * dpr);
  const int h = static_cast<int>(GetDouble(a, "height") * dpr);
  if (w <= 0 || h <= 0) {
    result->Error("capture_failed", "Empty region");
    return;
  }
  const int max_side = GetInt(a, "maxSide", 48);
  const double k = (std::min)(1.0, static_cast<double>(max_side) / (std::max)(w, h));
  const int ow = (std::max)(1, static_cast<int>(w * k));
  const int oh = (std::max)(1, static_cast<int>(h * k));

  HWND hwnd = GetHandle();
  DWORD previous = WDA_NONE;
  GetWindowDisplayAffinity(hwnd, &previous);
  if (previous != kExcludeFromCapture) SetWindowDisplayAffinity(hwnd, kExcludeFromCapture);

  HDC screen = GetDC(nullptr);
  HDC mem = CreateCompatibleDC(screen);
  BITMAPINFO bi{};
  bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bi.bmiHeader.biWidth = ow;
  bi.bmiHeader.biHeight = -oh;  // top-down
  bi.bmiHeader.biPlanes = 1;
  bi.bmiHeader.biBitCount = 32;
  bi.bmiHeader.biCompression = BI_RGB;
  void* bits = nullptr;
  HBITMAP dib = CreateDIBSection(screen, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
  std::vector<uint8_t> pixels;
  bool ok = false;
  if (dib != nullptr && bits != nullptr) {
    HGDIOBJ old = SelectObject(mem, dib);
    SetStretchBltMode(mem, HALFTONE);
    SetBrushOrgEx(mem, 0, 0, nullptr);
    ok = StretchBlt(mem, 0, 0, ow, oh, screen, left, top, w, h, SRCCOPY | CAPTUREBLT) != FALSE;
    if (ok) {
      const auto* p = static_cast<const uint8_t*>(bits);
      pixels.assign(p, p + static_cast<size_t>(ow) * oh * 4);
      // GDI leaves alpha at 0; every captured pixel is opaque.
      for (size_t i = 3; i < pixels.size(); i += 4) pixels[i] = 255;
    }
    SelectObject(mem, old);
    DeleteObject(dib);
  }
  DeleteDC(mem);
  ReleaseDC(nullptr, screen);
  if (previous != kExcludeFromCapture) SetWindowDisplayAffinity(hwnd, previous);

  if (!ok) {
    result->Error("capture_failed", "Region capture failed");
    return;
  }
  result->Success(flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("pixels"), flutter::EncodableValue(std::move(pixels))},
      {flutter::EncodableValue("width"), flutter::EncodableValue(ow)},
      {flutter::EncodableValue("height"), flutter::EncodableValue(oh)},
      {flutter::EncodableValue("order"), flutter::EncodableValue(std::string("bgra"))},
  }));
}

void FlutterWindow::HandleBridgeCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
  const std::string& method = call.method_name();
  if (method == "start") {
    result->Success(flutter::EncodableValue(SottoBridgeStart(&FlutterWindow::OnBridgeEvent, this)));
    return;
  }
  if (method == "stop") {
    SottoBridgeStop();
    result->Success();
    return;
  }
  if (args == nullptr) {
    result->Error("bad_args", "Expected a map");
    return;
  }
  if (method == "write") {
    auto it = args->find(flutter::EncodableValue("bytes"));
    const auto* bytes = it == args->end() ? nullptr : std::get_if<std::vector<uint8_t>>(&it->second);
    if (bytes == nullptr) {
      result->Error("bad_args", "Expected bytes");
      return;
    }
    result->Success(flutter::EncodableValue(SottoBridgeWrite(GetInt(*args, "conn", -1), bytes->data(), bytes->size())));
    return;
  }
  if (method == "close") {
    SottoBridgeClose(GetInt(*args, "conn", -1));
    result->Success();
    return;
  }
  if (method == "registerHost") {
    const std::wstring key = Wide(GetString(*args, "key"));
    const std::wstring manifest = Wide(GetString(*args, "manifest"));
    result->Success(flutter::EncodableValue(!key.empty() && !manifest.empty() &&
                                            SottoBridgeRegisterHost(key.c_str(), manifest.c_str())));
    return;
  }
  result->NotImplemented();
}

void FlutterWindow::OnBridgeEvent(void* context, int conn, int event, const uint8_t* data, size_t size) {
  auto* self = static_cast<FlutterWindow*>(context);
  std::vector<uint8_t> bytes(data, data + size);
  auto* reply = new NativeWorker::Reply([self, conn, event, bytes = std::move(bytes)]() mutable {
    if (!self->bridge_channel_) return;
    flutter::EncodableMap args{
        {flutter::EncodableValue("conn"), flutter::EncodableValue(conn)},
        {flutter::EncodableValue("kind"),
         flutter::EncodableValue(std::string(event == 0 ? "open" : event == 1 ? "data" : "close"))},
    };
    if (event == 1) args[flutter::EncodableValue("bytes")] = flutter::EncodableValue(std::move(bytes));
    self->bridge_channel_->InvokeMethod("event", std::make_unique<flutter::EncodableValue>(std::move(args)));
  });
  if (!PostMessage(self->GetHandle(), NativeWorker::kWorkerReply, 0, reinterpret_cast<LPARAM>(reply))) delete reply;
}

void FlutterWindow::OnDestroy() {
  SottoBridgeStop();
  forms_worker_.Stop();
  capture_worker_.Stop();
  NativeWorker::DropReplies(GetHandle());
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // A screen capture or UI Automation call finished on its worker thread.
  if (message == NativeWorker::kWorkerReply) {
    NativeWorker::RunReply(lparam);
    return 0;
  }
  // The overlay never activates on click; checked before plugins so no
  // handler can override it.
  if (overlay_ && !overlay_keyboard_ && message == WM_MOUSEACTIVATE) {
    return MA_NOACTIVATE;
  }
  // The overlay is a small floating window: never maximised by a
  // double-click on its drag area or by the system menu. (Without
  // WS_MAXIMIZEBOX, set from Dart, Aero Snap won't fill the screen when it
  // is dragged to the top edge either.) Resizing by its edges still works.
  if (overlay_) {
    if (message == WM_NCLBUTTONDBLCLK) return 0;
    if (message == WM_SYSCOMMAND && (wparam & 0xFFF0) == SC_MAXIMIZE) return 0;
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

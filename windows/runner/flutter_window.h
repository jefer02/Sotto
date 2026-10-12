#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "native/worker.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // "app.sotto/overlay": native overlay behaviour window_manager lacks.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> overlay_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> screen_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> input_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> forms_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> power_channel_;

  // "app.sotto/bridge": the browser extension's named pipe (native/bridge.h).
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> bridge_channel_;
  void HandleBridgeCall(const flutter::MethodCall<flutter::EncodableValue>& call,
                        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  // Runs on a bridge thread: posts the event to the platform thread.
  static void OnBridgeEvent(void* context, int conn, int event, const uint8_t* data, size_t size);

  // UI Automation (one thread: its element cache is not shared) and screen
  // capture run off the platform thread; replies come back as messages.
  NativeWorker forms_worker_;
  NativeWorker capture_worker_;

  // Captures in flight: the window stays excluded from capture until the
  // last one is done, then gets its previous affinity back.
  int captures_in_flight_ = 0;
  DWORD affinity_before_capture_ = WDA_NONE;

  // True while the window is the live overlay.
  bool overlay_ = false;

  // The overlay accepts the keyboard for a moment (chat input, editing an
  // answer); the app that had focus gets it back afterwards.
  bool overlay_keyboard_ = false;
  HWND focus_before_keyboard_ = nullptr;
  void SetOverlayKeyboard(bool on);

  // Screen capture for 'Ask about screen' (services/screen on the Dart side).
  void CaptureRegion(const flutter::MethodCall<flutter::EncodableValue>& call,
                     std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void HandleScreenCall(const flutter::MethodCall<flutter::EncodableValue>& call,
                        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Synthetic input for agent mode (services/agent on the Dart side).
  void HandleInputCall(const flutter::MethodCall<flutter::EncodableValue>& call,
                       std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Questionnaire filling through UI Automation (services/screen/form_access).
  void HandleFormsCall(const flutter::MethodCall<flutter::EncodableValue>& call,
                       std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void ConfigureOverlay(bool enabled, bool exclude_from_capture, bool blur, bool dark, bool text_only);
};

#endif  // RUNNER_FLUTTER_WINDOW_H_

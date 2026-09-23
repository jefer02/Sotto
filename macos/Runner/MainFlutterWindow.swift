import Cocoa
import FlutterMacOS

/// Sotto's single window. While preparing it is an ordinary titled window;
/// while live it becomes the overlay: a non-activating panel that floats
/// above full-screen slides on every Space and never takes the keyboard
/// from Zoom or Keynote (all live control is through global shortcuts).
///
/// It subclasses NSPanel so `.nonactivatingPanel` is available.
class MainFlutterWindow: NSPanel {
  private var overlayActive = false
  private var blurView: NSVisualEffectView?
  private var savedLevel: NSWindow.Level = .normal
  private var savedBehavior: NSWindow.CollectionBehavior = []

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Panels hide when the app deactivates by default; Sotto's must not.
    self.hidesOnDeactivate = false
    self.isFloatingPanel = false
    self.becomesKeyOnlyIfNeeded = false

    // Lets the overlay's rounded, translucent surface show what's behind it.
    flutterViewController.backgroundColor = .clear
    self.isOpaque = false
    self.backgroundColor = .clear

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(
      name: "app.sotto/overlay",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "configure":
        let args = call.arguments as? [String: Any] ?? [:]
        self.configureOverlay(
          enabled: args["enabled"] as? Bool ?? false,
          excludeFromCapture: args["excludeFromCapture"] as? Bool ?? false,
          blur: args["blur"] as? Bool ?? false,
          dark: args["dark"] as? Bool ?? true,
          radius: CGFloat(args["radius"] as? Double ?? 16))
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }

  // In the overlay, never become key: keystrokes keep going to the app the
  // presenter is actually using.
  override var canBecomeKey: Bool { !overlayActive }
  override var canBecomeMain: Bool { !overlayActive }

  private func configureOverlay(
    enabled: Bool, excludeFromCapture: Bool, blur: Bool, dark: Bool, radius: CGFloat
  ) {
    if enabled && !overlayActive {
      savedLevel = level
      savedBehavior = collectionBehavior
    }
    overlayActive = enabled

    if enabled {
      styleMask.insert(.nonactivatingPanel)
      level = .statusBar
      collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
      // Best effort only: on macOS 15+, ScreenCaptureKit can still capture
      // the window during a full-screen share. Pre-flight says so.
      sharingType = excludeFromCapture ? .none : .readOnly
      hasShadow = true
      setBlur(blur, dark: dark, radius: radius)
    } else {
      styleMask.remove(.nonactivatingPanel)
      level = savedLevel
      collectionBehavior = savedBehavior
      sharingType = .readOnly
      setBlur(false, dark: dark, radius: radius)
    }
    invalidateShadow()
  }

  /// Vibrancy behind the Flutter view, clipped to the overlay's radius.
  private func setBlur(_ on: Bool, dark: Bool, radius: CGFloat) {
    guard let content = contentView else { return }
    if !on {
      blurView?.removeFromSuperview()
      blurView = nil
      return
    }
    let view = blurView ?? NSVisualEffectView()
    view.material = dark ? .hudWindow : .popover
    view.blendingMode = .behindWindow
    view.state = .active
    view.wantsLayer = true
    view.layer?.cornerRadius = radius
    view.layer?.masksToBounds = true
    view.frame = content.bounds
    view.autoresizingMask = [.width, .height]
    if blurView == nil {
      content.addSubview(view, positioned: .below, relativeTo: content.subviews.first)
      blurView = view
    }
  }
}

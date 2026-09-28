import Cocoa
import FlutterMacOS
import ScreenCaptureKit

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
          radius: CGFloat(args["radius"] as? Double ?? 16),
          textOnly: args["textOnly"] as? Bool ?? false)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let screenChannel = FlutterMethodChannel(
      name: "app.sotto/screen",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    screenChannel.setMethodCallHandler { [weak self] call, result in
      self?.handleScreen(call, result: result)
    }

    super.awakeFromNib()
  }

  // In the overlay, never become key: keystrokes keep going to the app the
  // presenter is actually using.
  override var canBecomeKey: Bool { !overlayActive }
  override var canBecomeMain: Bool { !overlayActive }

  private func configureOverlay(
    enabled: Bool, excludeFromCapture: Bool, blur: Bool, dark: Bool, radius: CGFloat,
    textOnly: Bool
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
      // Text only: no vibrancy and no window shadow — a shadow would outline
      // the invisible window rectangle. Glyphs bring their own.
      hasShadow = !textOnly
      setBlur(blur && !textOnly, dark: dark, radius: radius)
    } else {
      styleMask.remove(.nonactivatingPanel)
      level = savedLevel
      collectionBehavior = savedBehavior
      sharingType = .readOnly
      hasShadow = true
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

// MARK: - Screen capture ("Ask about screen")

extension MainFlutterWindow {
  fileprivate func handleScreen(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "permission":
      result(CGPreflightScreenCaptureAccess() ? "granted" : "denied")
    case "requestPermission":
      result(CGRequestScreenCaptureAccess())
    case "openSettings":
      let anchor = (args["pane"] as? String) == "accessibility" ? "Privacy_Accessibility" : "Privacy_ScreenCapture"
      if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
        NSWorkspace.shared.open(url)
      }
      result(nil)
    case "capture":
      captureScreen(
        cursor: (args["target"] as? String) == "cursor",
        maxSide: args["maxSide"] as? Int ?? 1300,
        quality: args["quality"] as? Int ?? 80,
        result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func captureScreen(cursor: Bool, maxSide: Int, quality: Int, result: @escaping FlutterResult) {
    guard CGPreflightScreenCaptureAccess() else {
      result(FlutterError(code: "permission_denied", message: "Screen Recording permission is off", details: nil))
      return
    }
    let mouse = NSEvent.mouseLocation
    let target = cursor
      ? NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
      : self.screen
    guard let screen = target ?? NSScreen.main,
      let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    else {
      result(FlutterError(code: "capture_failed", message: "No display", details: nil))
      return
    }
    let displayID = CGDirectDisplayID(number.uint32Value)
    let scale = screen.backingScaleFactor
    // Global display coordinates (top-left origin, points) — what CGEvent uses.
    let bounds = CGDisplayBounds(displayID)
    let pixelW = bounds.width * scale
    let pixelH = bounds.height * scale
    let k = min(1.0, CGFloat(maxSide) / max(pixelW, pixelH))
    let outW = Int((pixelW * k).rounded())
    let outH = Int((pixelH * k).rounded())

    func finish(_ image: CGImage?, method: String) {
      DispatchQueue.main.async {
        guard let image = image,
          let jpeg = MainFlutterWindow.jpeg(image, width: outW, height: outH, quality: quality)
        else {
          result(FlutterError(code: "capture_failed", message: "Screen capture failed", details: nil))
          return
        }
        result([
          "jpeg": FlutterStandardTypedData(bytes: jpeg),
          "width": outW,
          "height": outH,
          "left": Double(bounds.origin.x * scale),
          "top": Double(bounds.origin.y * scale),
          "screenWidth": Double(pixelW),
          "screenHeight": Double(pixelH),
          "scale": Double(scale),
          "method": method,
        ])
      }
    }

    if #available(macOS 14.0, *) {
      SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, _ in
        guard let content = content,
          let display = content.displays.first(where: { $0.displayID == displayID })
        else {
          finish(nil, method: "sck")
          return
        }
        // Sotto never appears in its own screenshots — even where
        // sharingType = .none isn't honoured (macOS 15+ ScreenCaptureKit).
        let pid = ProcessInfo.processInfo.processIdentifier
        let own = content.applications.filter { $0.processID == pid }
        let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = outW
        config.height = outH
        config.showsCursor = false
        SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { image, _ in
          finish(image, method: "sck")
        }
      }
    } else {
      // macOS 12–13: this API honours sharingType = .none — set it for the
      // capture even if "Hide from screen capture" is off.
      let previous = sharingType
      sharingType = .none
      let image = CGDisplayCreateImage(displayID)
      sharingType = previous
      finish(image, method: "cg")
    }
  }

  /// Scales [image] to width × height and encodes a JPEG.
  fileprivate static func jpeg(_ image: CGImage, width: Int, height: Int, quality: Int) -> Data? {
    guard
      let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return nil }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let scaled = ctx.makeImage() else { return nil }
    let rep = NSBitmapImageRep(cgImage: scaled)
    return rep.representation(
      using: .jpeg, properties: [.compressionFactor: NSNumber(value: Double(quality) / 100.0)])
  }
}

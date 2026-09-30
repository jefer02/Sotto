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

  /// The overlay takes the keyboard for a moment (chat input, editing an
  /// answer); the app that had it gets it back afterwards.
  private var allowKey = false
  private var appBeforeKeyboard: NSRunningApplication?

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
      case "keyboard":
        let args = call.arguments as? [String: Any] ?? [:]
        self.setOverlayKeyboard(args["on"] as? Bool ?? false)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let formsChannel = FlutterMethodChannel(
      name: "app.sotto/forms",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    formsChannel.setMethodCallHandler { [weak self] call, result in
      self?.handleForms(call, result: result)
    }

    let inputChannel = FlutterMethodChannel(
      name: "app.sotto/input",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    inputChannel.setMethodCallHandler { call, result in
      SyntheticInput.handle(call, result: result)
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
  override var canBecomeKey: Bool { !overlayActive || allowKey }
  override var canBecomeMain: Bool { !overlayActive }

  private func setOverlayKeyboard(_ on: Bool) {
    guard overlayActive, on != allowKey else { return }
    allowKey = on
    if on {
      appBeforeKeyboard = NSWorkspace.shared.frontmostApplication
      NSApp.activate(ignoringOtherApps: true)
      makeKey()
    } else {
      resignKey()
      // Give the keyboard back to Zoom / Keynote.
      appBeforeKeyboard?.activate()
      appBeforeKeyboard = nil
    }
  }

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
        foreground: (args["target"] as? String) == "foreground",
        maxSide: args["maxSide"] as? Int ?? 1300,
        quality: args["quality"] as? Int ?? 80,
        result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func captureScreen(
    cursor: Bool, foreground: Bool = false, maxSide: Int, quality: Int, result: @escaping FlutterResult
  ) {
    guard CGPreflightScreenCaptureAccess() else {
      result(FlutterError(code: "permission_denied", message: "Screen Recording permission is off", details: nil))
      return
    }
    let mouse = NSEvent.mouseLocation
    let target = foreground
      ? MainFlutterWindow.foregroundScreen()
      : (cursor ? NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } : self.screen)
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

// MARK: - Questionnaires on screen: the AX API

/// Reads and fills the frontmost app's form controls. Needs Accessibility
/// permission — and an app outside the App Sandbox, which blocks AX access
/// to other apps (see the README). Element ids are valid until the next read.
extension MainFlutterWindow {
  private static var formElements: [String: AXUIElement] = [:]

  /// The screen of the frontmost app's front window (no permission needed:
  /// window bounds come from the window server).
  static func foregroundScreen() -> NSScreen? {
    guard let app = NSWorkspace.shared.frontmostApplication,
      app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
      let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]]
    else { return NSScreen.main }
    for w in info {
      guard (w[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier,
        (w[kCGWindowLayer as String] as? Int) == 0,
        let b = w[kCGWindowBounds as String] as? [String: CGFloat]
      else { continue }
      let center = CGPoint(x: (b["X"] ?? 0) + (b["Width"] ?? 0) / 2, y: (b["Y"] ?? 0) + (b["Height"] ?? 0) / 2)
      return screen(containing: center) ?? NSScreen.main
    }
    return NSScreen.main
  }

  /// The screen whose display bounds (global, top-left points) hold [p].
  fileprivate static func screen(containing p: CGPoint) -> NSScreen? {
    NSScreen.screens.first { s in
      guard let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
      return CGDisplayBounds(CGDirectDisplayID(n.uint32Value)).contains(p)
    }
  }

  fileprivate func handleForms(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let id = args["id"] as? String ?? ""
    let element = MainFlutterWindow.formElements[id]
    switch call.method {
    case "permission":
      result(AXIsProcessTrusted() ? "granted" : "denied")
    case "requestPermission":
      let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
      result(AXIsProcessTrustedWithOptions([key: true] as CFDictionary))
    case "read":
      readForm(max: args["max"] as? Int ?? 800, result: result)
    case "setValue":
      guard let e = element else { return result(false) }
      AXUIElementSetAttributeValue(e, kAXFocusedAttribute as CFString, kCFBooleanTrue)
      let text = (args["text"] as? String ?? "") as CFString
      result(AXUIElementSetAttributeValue(e, kAXValueAttribute as CFString, text) == .success)
    case "select", "invoke":
      guard let e = element else { return result(false) }
      result(AXUIElementPerformAction(e, kAXPressAction as CFString) == .success)
    case "toggle":
      guard let e = element else { return result(false) }
      let on = args["on"] as? Bool ?? false
      let current = (MainFlutterWindow.attr(e, kAXValueAttribute) as? NSNumber)?.intValue == 1
      result(current == on || AXUIElementPerformAction(e, kAXPressAction as CFString) == .success)
    case "choose":
      guard let e = element else { return result(false) }
      chooseOption(e, label: args["label"] as? String ?? "", result: result)
    case "focus":
      guard let e = element else { return result(false) }
      result(AXUIElementSetAttributeValue(e, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success)
    case "scrollIntoView":
      guard let e = element else { return result(false) }
      result(AXUIElementPerformAction(e, "AXScrollToVisible" as CFString) == .success)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  fileprivate static func attr(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
  }

  fileprivate static func string(_ e: AXUIElement, _ name: String) -> String? {
    let s = attr(e, name) as? String
    return (s?.isEmpty ?? true) ? nil : s
  }

  fileprivate static func children(_ e: AXUIElement) -> [AXUIElement] {
    (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? []
  }

  /// The visible label: title, description, the linked title element, or
  /// the placeholder.
  fileprivate static func label(_ e: AXUIElement) -> String {
    if let t = string(e, kAXTitleAttribute) { return t }
    if let d = string(e, kAXDescriptionAttribute) { return d }
    if let titled = attr(e, kAXTitleUIElementAttribute), CFGetTypeID(titled) == AXUIElementGetTypeID() {
      let t = titled as! AXUIElement
      if let v = string(t, kAXValueAttribute) ?? string(t, kAXTitleAttribute) { return v }
    }
    return string(e, kAXPlaceholderValueAttribute) ?? ""
  }

  private func readForm(max: Int, result: @escaping FlutterResult) {
    guard AXIsProcessTrusted() else {
      return result(FlutterError(code: "permission_denied", message: "Accessibility permission is off", details: nil))
    }
    guard let app = NSWorkspace.shared.frontmostApplication else {
      return result(FlutterError(code: "no_window", message: nil, details: nil))
    }
    if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
      return result(FlutterError(code: "own_window", message: nil, details: nil))
    }
    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    // Chrome, Edge and Electron apps build their web-content AX tree only
    // when an assistive app asks; these switch it on (others ignore them).
    // Firefox and some pages still expose little: those fields fall back to
    // clicking and typing where the screenshot shows them.
    AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    guard let w = MainFlutterWindow.attr(axApp, kAXFocusedWindowAttribute),
      CFGetTypeID(w) == AXUIElementGetTypeID()
    else {
      return result(FlutterError(code: "no_window", message: nil, details: nil))
    }
    let window = w as! AXUIElement
    // Physical pixels, like the screenshot: global points × the display scale.
    var scale: CGFloat = 2
    if let pos = MainFlutterWindow.attr(window, kAXPositionAttribute) {
      var p = CGPoint.zero
      AXValueGetValue(pos as! AXValue, .cgPoint, &p)
      scale = MainFlutterWindow.screen(containing: p)?.backingScaleFactor ?? 2
    }

    MainFlutterWindow.formElements = [:]
    var out: [[String: Any]] = []
    var counter = 0

    func visit(_ e: AXUIElement, parent: String?, depth: Int) {
      if out.count >= max || depth > 60 { return }
      let role = MainFlutterWindow.string(e, kAXRoleAttribute) ?? ""
      let subrole = MainFlutterWindow.string(e, kAXSubroleAttribute) ?? ""
      let type: String?
      switch role {
      case "AXTextField", "AXTextArea", "AXSearchField": type = "edit"
      case "AXRadioButton": type = "radio"
      case "AXCheckBox", "AXSwitch": type = "checkbox"
      case "AXPopUpButton", "AXComboBox": type = "combo"
      case "AXButton": type = "button"
      case "AXRadioGroup", "AXGroup", "AXList", "AXForm": type = "group"
      default: type = nil
      }
      var here = parent
      if let type = type {
        counter += 1
        let id = "ax\(counter)"
        MainFlutterWindow.formElements[id] = e
        here = id
        let name = MainFlutterWindow.label(e)
        // Unlabelled groups only exist to group radios and checkboxes.
        if type != "group" || !name.isEmpty {
          var m: [String: Any] = ["id": id, "type": type, "name": name]
          if let parent = parent { m["parent"] = parent }
          let value = MainFlutterWindow.attr(e, kAXValueAttribute)
          if let v = value as? String { m["value"] = v }
          if type == "checkbox" || type == "radio" { m["checked"] = (value as? NSNumber)?.intValue == 1 }
          if let pos = MainFlutterWindow.attr(e, kAXPositionAttribute),
            let size = MainFlutterWindow.attr(e, kAXSizeAttribute)
          {
            var p = CGPoint.zero
            var z = CGSize.zero
            AXValueGetValue(pos as! AXValue, .cgPoint, &p)
            AXValueGetValue(size as! AXValue, .cgSize, &z)
            m["bounds"] = [p.x * scale, p.y * scale, z.width * scale, z.height * scale]
          }
          m["enabled"] = (MainFlutterWindow.attr(e, kAXEnabledAttribute) as? Bool) ?? true
          m["password"] = subrole == "AXSecureTextField"
          m["multiline"] = role == "AXTextArea"
          var patterns: [String] = []
          var settable: DarwinBoolean = false
          if AXUIElementIsAttributeSettable(e, kAXValueAttribute as CFString, &settable) == .success,
            settable.boolValue
          {
            patterns.append("value")
          }
          var actions: CFArray?
          if AXUIElementCopyActionNames(e, &actions) == .success, let names = actions as? [String] {
            if names.contains(kAXPressAction) { patterns += ["invoke", "select", "toggle"] }
            if names.contains(kAXShowMenuAction) || role == "AXPopUpButton" { patterns.append("expand") }
            if names.contains("AXScrollToVisible") { patterns.append("scroll") }
          }
          m["patterns"] = patterns
          if type == "combo" {
            // A pop-up's menu items, when the app exposes them closed.
            var options: [String] = []
            for menu in MainFlutterWindow.children(e) {
              for item in MainFlutterWindow.children(menu) {
                if let t = MainFlutterWindow.string(item, kAXTitleAttribute) { options.append(t) }
              }
            }
            if !options.isEmpty { m["options"] = options }
          }
          out.append(m)
        }
        if type == "combo" { return }  // its menu items are options, not fields
      }
      for child in MainFlutterWindow.children(e) {
        visit(child, parent: here, depth: depth + 1)
      }
    }
    visit(window, parent: nil, depth: 0)

    guard let data = try? JSONSerialization.data(withJSONObject: out),
      let json = String(data: data, encoding: .utf8)
    else {
      return result(FlutterError(code: "uia_failed", message: "Could not encode the form", details: nil))
    }
    result(json)
  }

  /// Opens a pop-up, presses the item titled [label], or sets the value of
  /// an editable combo box.
  private func chooseOption(_ e: AXUIElement, label: String, result: @escaping FlutterResult) {
    AXUIElementPerformAction(e, kAXPressAction as CFString)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
      let want = label.lowercased()
      for menu in MainFlutterWindow.children(e) {
        for item in MainFlutterWindow.children(menu)
        where MainFlutterWindow.string(item, kAXTitleAttribute)?.lowercased() == want {
          return result(AXUIElementPerformAction(item, kAXPressAction as CFString) == .success)
        }
      }
      AXUIElementPerformAction(e, kAXCancelAction as CFString)
      result(AXUIElementSetAttributeValue(e, kAXValueAttribute as CFString, label as CFString) == .success)
    }
  }
}

// MARK: - Synthetic input (CGEvent)

/// Synthetic mouse and keyboard over CGEvent — the macOS half of
/// `app.sotto/input` (InputService): the click-and-type fallback for
/// questionnaire fields that browsers don't expose to the AX API, and agent
/// mode. Needs Accessibility permission (and no App Sandbox).
///
/// Coordinates are global display points, top-left origin — what CGEvent
/// uses; the Dart side converts from physical pixels.
enum SyntheticInput {
  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let a = call.arguments as? [String: Any] ?? [:]
    let point = CGPoint(x: number(a["x"]), y: number(a["y"]))
    switch call.method {
    case "permission":
      result(AXIsProcessTrusted() ? "granted" : "denied")
    case "requestPermission":
      let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
      result(AXIsProcessTrustedWithOptions([key: true] as CFDictionary))
    case "move":
      post(CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left))
      result(nil)
    case "click":
      click(at: point, right: (a["button"] as? String) == "right", count: a["count"] as? Int ?? 1)
      result(nil)
    case "scroll":
      if a["atPoint"] as? Bool ?? false {
        post(CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left))
      }
      // Wheel units are lines; positive dy scrolls down (content moves up).
      let dy = Int32(-(a["dy"] as? Int ?? 0))
      let dx = Int32(-(a["dx"] as? Int ?? 0))
      post(CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 2, wheel1: dy * 3, wheel2: dx * 3, wheel3: 0))
      result(nil)
    case "type":
      type(a["text"] as? String ?? "")
      result(nil)
    case "keys":
      result(pressKeys((a["keys"] as? [String]) ?? []) ? nil : FlutterError(code: "input_failed", message: "unknown key", details: nil))
    case "releaseAll":
      releaseAll()
      result(nil)
    case "focused":
      result(focused())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static let source = CGEventSource(stateID: .hidSystemState)

  private static func number(_ v: Any?) -> CGFloat {
    if let d = v as? Double { return CGFloat(d) }
    if let i = v as? Int { return CGFloat(i) }
    return 0
  }

  private static func post(_ e: CGEvent?) {
    e?.post(tap: .cghidEventTap)
  }

  private static func click(at p: CGPoint, right: Bool, count: Int) {
    let down: CGEventType = right ? .rightMouseDown : .leftMouseDown
    let up: CGEventType = right ? .rightMouseUp : .leftMouseUp
    let button: CGMouseButton = right ? .right : .left
    post(CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: button))
    for n in 1...max(1, min(count, 2)) {
      for type in [down, up] {
        let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: button)
        e?.setIntegerValueField(.mouseEventClickState, value: Int64(n))
        post(e)
      }
    }
  }

  /// One Unicode key event per character — web inputs see real typing, and
  /// no keyboard layout gets in the way. Line breaks press Return.
  private static func type(_ text: String) {
    for ch in text {
      if ch == "\n" || ch == "\r\n" {
        tap(36, flags: [])
        continue
      }
      let units = Array(String(ch).utf16)
      for down in [true, false] {
        let e = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
        units.withUnsafeBufferPointer { buf in
          e?.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
        }
        post(e)
      }
    }
  }

  private static func tap(_ key: CGKeyCode, flags: CGEventFlags) {
    for down in [true, false] {
      let e = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
      e?.flags = flags
      post(e)
    }
  }

  /// "cmd"+"a", "enter", "escape"… pressed together. On macOS "ctrl" is
  /// Control and "cmd" / "meta" is Command.
  private static func pressKeys(_ names: [String]) -> Bool {
    var flags: CGEventFlags = []
    var keys: [CGKeyCode] = []
    for raw in names {
      let n = raw.lowercased()
      switch n {
      case "cmd", "command", "meta", "super", "win": flags.insert(.maskCommand)
      case "ctrl", "control": flags.insert(.maskControl)
      case "alt", "option": flags.insert(.maskAlternate)
      case "shift": flags.insert(.maskShift)
      default:
        guard let code = keyCodes[n] else { return false }
        keys.append(code)
      }
    }
    if keys.isEmpty { return false }
    for k in keys { tap(k, flags: flags) }
    return true
  }

  private static func releaseAll() {
    for code: CGKeyCode in [55, 54, 56, 60, 58, 61, 59, 62] {  // cmd, shift, option, control (both sides)
      let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
      e?.flags = []
      post(e)
    }
    let p = CGEvent(source: nil)?.location ?? .zero
    post(CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left))
    post(CGEvent(mouseEventSource: source, mouseType: .rightMouseUp, mouseCursorPosition: p, mouseButton: .right))
  }

  /// The focused control, for the safety gate: never type into a password.
  private static func focused() -> [String: Any]? {
    let system = AXUIElementCreateSystemWide()
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) == .success,
      let v = value, CFGetTypeID(v) == AXUIElementGetTypeID()
    else { return nil }
    let e = v as! AXUIElement
    func string(_ name: String) -> String {
      var s: CFTypeRef?
      return AXUIElementCopyAttributeValue(e, name as CFString, &s) == .success ? (s as? String ?? "") : ""
    }
    return [
      "isPassword": string(kAXSubroleAttribute) == "AXSecureTextField",
      "name": string(kAXTitleAttribute).isEmpty ? string(kAXDescriptionAttribute) : string(kAXTitleAttribute),
      "role": string(kAXRoleAttribute),
    ]
  }

  /// ANSI virtual key codes (Carbon's kVK_*).
  private static let keyCodes: [String: CGKeyCode] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
    "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
    "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34,
    "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46,
    ".": 47, "`": 50,
    "enter": 36, "return": 36, "tab": 48, "space": 49, "backspace": 51, "escape": 53, "esc": 53,
    "delete": 117, "del": 117, "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
    "left": 123, "right": 124, "down": 125, "up": 126,
    "arrowleft": 123, "arrowright": 124, "arrowdown": 125, "arrowup": 126,
    "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100, "f9": 101,
    "f10": 109, "f11": 103, "f12": 111,
  ]
}

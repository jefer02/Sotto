import 'dart:async';
import 'dart:io';

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../../data/models/settings.dart';
import '../design/tokens.dart';
import 'overlay_geometry.dart';

export 'overlay_geometry.dart' show DisplayArea, OverlayGeometry;

/// Native pieces window_manager doesn't cover:
/// * macOS — non-activating NSPanel behaviour, `.statusBar` level on every
///   Space and over full-screen apps, `sharingType = .none`, vibrancy blur,
///   and no zoom / tiling to fill the screen.
/// * Windows — WS_EX_NOACTIVATE / TOOLWINDOW, WDA_EXCLUDEFROMCAPTURE, DWM
///   acrylic backdrop with rounded corners, and no maximise / Aero Snap.
class _OverlayNative {
  static const _channel = MethodChannel('app.sotto/overlay');

  static Future<void> configure({
    required bool enabled,
    bool excludeFromCapture = false,
    bool blur = false,
    bool dark = true,
    bool textOnly = false,
    double radius = Radii.xl,
  }) async {
    try {
      await _channel.invokeMethod('configure', {
        'enabled': enabled,
        'excludeFromCapture': excludeFromCapture,
        'blur': blur,
        'dark': dark,
        'textOnly': textOnly,
        'radius': radius,
      });
    } on MissingPluginException {
      // Linux / tests: the overlay still works, just without the extras.
    } on PlatformException catch (e) {
      debugPrint('overlay native configure failed: ${e.message}');
    }
  }

  /// The next frame change may fill the screen: the presenter dragged the
  /// overlay that big last time. Otherwise macOS refuses screen-filling
  /// frames it didn't get from a live resize (window tiling, zoom).
  static Future<void> allowFill() async {
    try {
      await _channel.invokeMethod('allowFill');
    } on MissingPluginException {
      // Windows / Linux / tests: nothing to allow.
    } on PlatformException catch (e) {
      debugPrint('overlay allowFill failed: ${e.message}');
    }
  }
}

/// The overlay never takes the keyboard — except, for a moment, when the
/// presenter clicks a text field in it (chat input, an answer to edit).
/// Off gives focus back to the app that had it.
Future<void> setOverlayKeyboard(bool on) async {
  try {
    await _OverlayNative._channel.invokeMethod('keyboard', {'on': on});
  } on MissingPluginException {
    // Tests / Linux.
  } on PlatformException catch (e) {
    debugPrint('overlay keyboard failed: ${e.message}');
  }
}

/// The window operations Sotto needs: window_manager and screen_retriever
/// in the app ([PluginWindowHost]), a fake in tests.
abstract class WindowHost {
  Future<void> init();
  Future<List<DisplayArea>> displays();
  Future<Rect> getBounds();
  Future<void> setBounds(Rect bounds, {bool animate = false});
  Future<void> setPosition(Offset position, {bool animate = false});
  Future<bool> isMaximized();
  Future<void> maximize();
  Future<void> unmaximize();
  Future<bool> isFullScreen();
  Future<void> setFullScreen(bool on);
  Future<bool> isMinimized();
  Future<void> restore();

  /// The floating overlay's window chrome: frameless, always on top, out of
  /// the taskbar, not maximisable, resizable down to [minimumSize] — or,
  /// with [on] false, the main window's again.
  Future<void> setOverlayChrome(bool on, {required Size minimumSize, bool shadow = true});
  Future<void> show({bool inactive = false});
  Future<void> hide();
  Future<void> focus();
  Future<void> setIgnoreMouseEvents(bool on);
  Future<void> startDragging();
  Future<void> startResizing(ResizeEdge edge);
}

class PluginWindowHost implements WindowHost {
  @override
  Future<void> init() async {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1280, 820),
      minimumSize: Layout.windowMin,
      center: true,
      title: 'Sotto',
      backgroundColor: Color(0x00000000),
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: true,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  @override
  Future<List<DisplayArea>> displays() async {
    final all = await screenRetriever.getAllDisplays();
    final primary = await screenRetriever.getPrimaryDisplay();
    return [
      for (final d in all)
        DisplayArea(
          id: d.id,
          visible: (d.visiblePosition ?? Offset.zero) & (d.visibleSize ?? d.size),
          primary: d.id == primary.id,
        ),
    ];
  }

  @override
  Future<Rect> getBounds() => windowManager.getBounds();

  @override
  Future<void> setBounds(Rect bounds, {bool animate = false}) => windowManager.setBounds(bounds, animate: animate);

  @override
  Future<void> setPosition(Offset position, {bool animate = false}) =>
      windowManager.setPosition(position, animate: animate);

  @override
  Future<bool> isMaximized() => windowManager.isMaximized();

  @override
  Future<void> maximize() => windowManager.maximize();

  @override
  Future<void> unmaximize() => windowManager.unmaximize();

  @override
  Future<bool> isFullScreen() => windowManager.isFullScreen();

  @override
  Future<void> setFullScreen(bool on) => windowManager.setFullScreen(on);

  @override
  Future<bool> isMinimized() => windowManager.isMinimized();

  @override
  Future<void> restore() => windowManager.restore();

  @override
  Future<void> setOverlayChrome(bool on, {required Size minimumSize, bool shadow = true}) async {
    if (on) {
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
      if (!Platform.isMacOS) await windowManager.setAsFrameless();
      await windowManager.setMinimumSize(minimumSize);
      await windowManager.setBackgroundColor(const Color(0x00000000));
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setSkipTaskbar(true);
      await windowManager.setResizable(true);
      // No maximise button: no double-click maximise, no Aero Snap to fill.
      await windowManager.setMaximizable(false);
      if (Platform.isMacOS) await windowManager.setVisibleOnAllWorkspaces(true, visibleOnFullScreen: true);
      await windowManager.setHasShadow(shadow);
    } else {
      await windowManager.setHasShadow(true);
      if (Platform.isMacOS) await windowManager.setVisibleOnAllWorkspaces(false);
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setSkipTaskbar(false);
      await windowManager.setMaximizable(true);
      await windowManager.setMinimumSize(minimumSize);
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: true);
    }
  }

  @override
  Future<void> show({bool inactive = false}) => windowManager.show(inactive: inactive);

  @override
  Future<void> hide() => windowManager.hide();

  @override
  Future<void> focus() => windowManager.focus();

  @override
  Future<void> setIgnoreMouseEvents(bool on) => windowManager.setIgnoreMouseEvents(on, forward: on);

  @override
  Future<void> startDragging() => windowManager.startDragging();

  @override
  Future<void> startResizing(ResizeEdge edge) => windowManager.startResizing(edge);
}

/// Sotto uses one native window with two personalities: the main window for
/// preparing, and — while live — the overlay for performing. Going live
/// morphs the window; ending the session restores it exactly.
///
/// The overlay is always a small floating window. The main window may be
/// maximised or in full screen when a session starts; that state is left
/// first (a maximised window ignores new bounds, and a full-screen one keeps
/// the whole display), and the overlay can't be maximised, zoomed or tiled
/// to fill the screen while it is one. Only dragging its edges makes it big.
class WindowService {
  WindowService({WindowHost? host, this.supportedOverride}) : _host = host ?? PluginWindowHost();

  final WindowHost _host;

  /// Tests run the overlay logic on any host OS.
  final bool? supportedOverride;

  Rect? _mainBounds;
  bool _mainMaximized = false;
  bool _mainFullScreen = false;
  bool _overlay = false;
  bool _hidden = false;
  bool _clickThrough = false;
  String? _displayId;

  /// The overlay's last frame that was not forced on it by the OS.
  Rect? _overlayFrame;

  bool get isOverlay => _overlay;
  bool get isHidden => _hidden;
  bool get isClickThrough => _clickThrough;

  static bool get platformSupported => Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  bool get supported => supportedOverride ?? platformSupported;

  Future<void> init() async {
    if (!supported) return;
    await _host.init();
  }

  Future<List<DisplayArea>> _displays() async {
    final all = await _host.displays();
    return all.isEmpty ? [const DisplayArea(id: 'main', visible: Rect.fromLTWH(0, 0, 1920, 1080), primary: true)] : all;
  }

  /// The display under the window's centre, else the primary one.
  Future<DisplayArea> _currentDisplay([List<DisplayArea>? all]) async {
    final displays = all ?? await _displays();
    final center = (await _host.getBounds()).center;
    for (final d in displays) {
      if (d.visible.contains(center)) return d;
    }
    return displays.firstWhere((d) => d.primary, orElse: () => displays.first);
  }

  /// Top-left position for a placement on a display's visible area.
  static Offset placementOffset(OverlayPlacement p, Rect area, Size size) =>
      OverlayGeometry.placementOffset(p, area, size);

  /// Leaves full screen and maximised states, waiting for macOS's
  /// full-screen animation to finish — until then new bounds are ignored.
  Future<void> _leaveFilledState() async {
    if (await _host.isFullScreen()) {
      await _host.setFullScreen(false);
      for (var i = 0; i < 30 && await _host.isFullScreen(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    if (await _host.isMaximized()) await _host.unmaximize();
  }

  /// [height]: a panel (questionnaire, agent, auto-fill) that needs at
  /// least this much room; the reading overlay takes its saved size.
  Future<void> enterOverlay(AppSettings s, {double? height}) async {
    if (!supported || _overlay) return;
    _overlay = true;
    _mainFullScreen = await _host.isFullScreen();
    _mainMaximized = !_mainFullScreen && await _host.isMaximized();
    await _leaveFilledState();
    _mainBounds = await _host.getBounds();

    final displays = await _displays();
    final display = OverlayGeometry.displayFor(s, displays, current: await _currentDisplay(displays));
    _displayId = display.id;
    var frame = OverlayGeometry.frame(s, display);
    if (height != null && frame.height < height) {
      frame = OverlayGeometry.clampInto(
        Rect.fromLTWH(frame.left, frame.top, frame.width, height.clamp(frame.height, display.visible.height)),
        display.visible,
      );
    }

    await _host.setOverlayChrome(
      true,
      minimumSize: OverlayGeometry.minimum,
      // Text only: the frame's shadow would draw the invisible window's box.
      shadow: s.overlayStyle != OverlayStyle.textOnly,
    );
    await _OverlayNative.configure(
      enabled: true,
      excludeFromCapture: s.excludeFromCapture,
      blur: s.blurBehind,
      dark: s.overlayTheme != OverlayThemeMode.light,
      textOnly: s.overlayStyle == OverlayStyle.textOnly,
    );
    // Only the presenter's own drag makes it this big; say so to macOS.
    if (OverlayGeometry.fills(frame, display.visible)) await _OverlayNative.allowFill();
    // After the style changes: some of them reset the frame on their way.
    await _host.setBounds(frame);
    _overlayFrame = frame;
    await _host.show(inactive: true);
  }

  Future<void> exitOverlay() async {
    if (!supported || !_overlay) return;
    _overlay = false;
    _hidden = false;
    await setClickThrough(false);
    await _OverlayNative.configure(enabled: false);
    await _host.setOverlayChrome(false, minimumSize: Layout.windowMin);
    if (_mainBounds != null) await _host.setBounds(_mainBounds!);
    if (_mainMaximized) await _host.maximize();
    if (_mainFullScreen) await _host.setFullScreen(true);
    await _host.show();
    await _host.focus();
  }

  /// The OS maximised, zoomed or tiled the overlay (a double-click on its
  /// top edge, a drag to the top of the screen): put it back.
  Future<void> undoFill() async {
    if (!_overlay) return;
    await _leaveFilledState();
    final frame = _overlayFrame;
    if (frame != null) await _host.setBounds(frame);
  }

  /// The overlay's current frame is one the presenter chose (dragged or
  /// resized) — false while the OS holds it maximised or full screen.
  Future<bool> ownsFrame() async => _overlay && !await _host.isFullScreen() && !await _host.isMaximized();

  /// Records the frame the overlay should return to if the OS fills it.
  void noteFrame(Rect frame) => _overlayFrame = frame;

  /// The main window, in front (a global shortcut opened a page). Nothing
  /// while it is the overlay.
  Future<void> bringToFront() async {
    if (!supported || _overlay) return;
    if (await _host.isMinimized()) await _host.restore();
    await _host.show();
    await _host.focus();
  }

  /// Hide instantly — no animation; speed is the feature.
  Future<void> toggleHidden() async {
    if (!_overlay) return;
    _hidden = !_hidden;
    if (_hidden) {
      await _host.hide();
    } else {
      await _host.show(inactive: true);
    }
  }

  Future<void> setClickThrough(bool on) async {
    if (!supported || _clickThrough == on) return;
    _clickThrough = on;
    await _host.setIgnoreMouseEvents(on);
  }

  /// Answers grow away from the camera edge: downward when docked at the
  /// top, so the eye-line never moves.
  Future<void> resizeOverlay(double height, {bool fromBottom = false, double maxFraction = 0.6}) async {
    if (!_overlay) return;
    final b = await _host.getBounds();
    final display = await _currentDisplay();
    final minH = OverlayGeometry.minimum.height;
    final maxH = display.visible.height * maxFraction;
    final h = height.clamp(minH, maxH < minH ? minH : maxH);
    final top = fromBottom ? b.bottom - h : b.top;
    final frame = Rect.fromLTWH(b.left, top, b.width, h);
    await _host.setBounds(frame, animate: Platform.isMacOS);
    _overlayFrame = frame;
  }

  int _heightAnimation = 0;

  /// Eases the overlay to [height] over [duration] (ease-out), growing away
  /// from the docked edge. A newer call cancels one still running. The
  /// caller clamps [height].
  Future<void> animateHeight(
    double height, {
    bool fromBottom = false,
    Duration duration = const Duration(milliseconds: 150),
  }) async {
    if (!_overlay) return;
    final id = ++_heightAnimation;
    final b = await _host.getBounds();
    if ((height - b.height).abs() < 1) return;
    const frame = Duration(milliseconds: 16);
    final steps = duration.inMilliseconds ~/ frame.inMilliseconds;
    for (var i = 1; i <= (steps < 1 ? 1 : steps); i++) {
      if (id != _heightAnimation || !_overlay) return;
      final h = b.height + (height - b.height) * Curves.easeOut.transform(steps < 1 ? 1 : i / steps);
      final r = Rect.fromLTWH(b.left, fromBottom ? b.bottom - h : b.top, b.width, h);
      await _host.setBounds(r);
      _overlayFrame = r;
      if (i < steps) await Future<void>.delayed(frame);
    }
  }

  Future<void> setOverlayWidth(double width) async {
    if (!_overlay) return;
    final b = await _host.getBounds();
    final frame = Rect.fromLTWH(b.left, b.top, width, b.height);
    await _host.setBounds(frame);
    _overlayFrame = frame;
  }

  Future<Rect> bounds() => _host.getBounds();

  /// The visible area of the display the overlay is on.
  Future<Rect> displayArea() async => (await _currentDisplay()).visible;

  String? get displayId => _displayId;

  /// Cycles the overlay to the next display, keeping its placement.
  Future<String?> moveToNextDisplay(AppSettings s) async {
    if (!_overlay) return null;
    final displays = await _displays();
    if (displays.length < 2) return _displayId;
    final current = await _currentDisplay(displays);
    final i = displays.indexWhere((d) => d.id == current.id);
    final next = displays[(i + 1) % displays.length];
    final b = await _host.getBounds();
    final remembered = s.rememberPositionPerDisplay ? s.overlayPositions[next.id] : null;
    final pos = remembered != null
        ? Offset(remembered.$1, remembered.$2)
        : placementOffset(s.placement, next.visible, b.size);
    final frame = OverlayGeometry.clampInto(pos & b.size, next.visible);
    await _host.setPosition(frame.topLeft);
    _overlayFrame = frame;
    _displayId = next.id;
    return next.id;
  }

  /// Snaps within 12 px of the camera (top centre), the edges and centre.
  Future<Offset?> snapAfterDrag() async {
    if (!_overlay) return null;
    final b = await _host.getBounds();
    final d = await _currentDisplay();
    final area = d.visible;
    const snap = 12.0;
    var x = b.left, y = b.top;
    final centerX = area.left + (area.width - b.width) / 2;
    if ((x - centerX).abs() <= snap) x = centerX;
    if ((x - area.left).abs() <= snap * 2) x = area.left + snap;
    if ((area.right - b.right).abs() <= snap * 2) x = area.right - b.width - snap;
    if ((y - area.top).abs() <= snap * 2) y = area.top + snap;
    if ((area.bottom - b.bottom).abs() <= snap * 2) y = area.bottom - b.height - snap;
    if (x != b.left || y != b.top) await _host.setPosition(Offset(x, y), animate: true);
    _overlayFrame = Offset(x, y) & b.size;
    _displayId = d.id;
    return Offset(x, y);
  }

  Future<void> startDragging() => _host.startDragging();

  Future<void> startResizing(ResizeEdge edge) => _host.startResizing(edge);
}

final windowServiceProvider = Provider<WindowService>((ref) => WindowService());

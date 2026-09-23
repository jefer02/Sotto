import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../../data/models/settings.dart';
import '../design/tokens.dart';

/// Native pieces window_manager doesn't cover:
/// * macOS — non-activating NSPanel behaviour, `.statusBar` level on every
///   Space and over full-screen apps, `sharingType = .none`, vibrancy blur.
/// * Windows — WS_EX_NOACTIVATE / TOOLWINDOW, WDA_EXCLUDEFROMCAPTURE, DWM
///   acrylic backdrop with rounded corners.
class _OverlayNative {
  static const _channel = MethodChannel('app.sotto/overlay');

  static Future<void> configure({
    required bool enabled,
    bool excludeFromCapture = false,
    bool blur = false,
    bool dark = true,
    double radius = Radii.xl,
  }) async {
    try {
      await _channel.invokeMethod('configure', {
        'enabled': enabled,
        'excludeFromCapture': excludeFromCapture,
        'blur': blur,
        'dark': dark,
        'radius': radius,
      });
    } on MissingPluginException {
      // Linux / tests: the overlay still works, just without the extras.
    } on PlatformException catch (e) {
      debugPrint('overlay native configure failed: ${e.message}');
    }
  }
}

/// Sotto uses one native window with two personalities: the main window for
/// preparing, and — while live — the overlay for performing. Going live
/// morphs the window; ending the session restores it exactly.
class WindowService {
  Rect? _mainBounds;
  bool _overlay = false;
  bool _hidden = false;
  bool _clickThrough = false;
  String? _displayId;

  bool get isOverlay => _overlay;
  bool get isHidden => _hidden;
  bool get isClickThrough => _clickThrough;

  static bool get supported => Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  Future<void> init() async {
    if (!supported) return;
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

  Future<Display> _currentDisplay() async {
    final displays = await screenRetriever.getAllDisplays();
    final bounds = await windowManager.getBounds();
    final center = bounds.center;
    for (final d in displays) {
      final origin = d.visiblePosition ?? Offset.zero;
      final size = d.visibleSize ?? d.size;
      if ((origin & size).contains(center)) return d;
    }
    return screenRetriever.getPrimaryDisplay();
  }

  /// Top-left position for a placement on a display's visible area.
  static Offset placementOffset(OverlayPlacement p, Rect area, Size size) {
    const margin = 12.0;
    final x = switch (p) {
      OverlayPlacement.topLeft || OverlayPlacement.middleLeft || OverlayPlacement.bottomLeft => area.left + margin,
      OverlayPlacement.topRight ||
      OverlayPlacement.middleRight ||
      OverlayPlacement.bottomRight => area.right - size.width - margin,
      _ => area.left + (area.width - size.width) / 2,
    };
    final y = switch (p) {
      // "Under the camera": hug the top edge so eyes stay near the lens.
      OverlayPlacement.topLeft || OverlayPlacement.topCenter || OverlayPlacement.topRight => area.top + margin,
      OverlayPlacement.bottomLeft ||
      OverlayPlacement.bottomCenter ||
      OverlayPlacement.bottomRight => area.bottom - size.height - margin,
      _ => area.top + (area.height - size.height) / 2,
    };
    return Offset(x, y);
  }

  Future<void> enterOverlay(AppSettings s) async {
    if (!supported || _overlay) return;
    _mainBounds = await windowManager.getBounds();
    _overlay = true;

    final display = await _currentDisplay();
    _displayId = display.id;
    final size = Size(s.overlaySize.$1, s.overlaySize.$2);
    final area = (display.visiblePosition ?? Offset.zero) & (display.visibleSize ?? display.size);
    final remembered = s.rememberPositionPerDisplay ? s.overlayPositions[display.id] : null;
    final pos = remembered != null ? Offset(remembered.$1, remembered.$2) : placementOffset(s.placement, area, size);

    await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
    if (!Platform.isMacOS) await windowManager.setAsFrameless();
    await windowManager.setMinimumSize(const Size(300, 96));
    await windowManager.setBackgroundColor(const Color(0x00000000));
    await windowManager.setBounds(pos & size);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSkipTaskbar(true);
    await windowManager.setResizable(true);
    if (Platform.isMacOS) {
      await windowManager.setVisibleOnAllWorkspaces(true, visibleOnFullScreen: true);
    }
    await _OverlayNative.configure(
      enabled: true,
      excludeFromCapture: s.excludeFromCapture,
      blur: s.blurBehind,
      dark: s.overlayTheme != OverlayThemeMode.light,
    );
    await windowManager.show(inactive: true);
  }

  Future<void> exitOverlay() async {
    if (!supported || !_overlay) return;
    _overlay = false;
    _hidden = false;
    await setClickThrough(false);
    await _OverlayNative.configure(enabled: false);
    if (Platform.isMacOS) await windowManager.setVisibleOnAllWorkspaces(false);
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setSkipTaskbar(false);
    await windowManager.setMinimumSize(Layout.windowMin);
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: true);
    if (_mainBounds != null) await windowManager.setBounds(_mainBounds!);
    await windowManager.show();
    await windowManager.focus();
  }

  /// Hide instantly — no animation; speed is the feature.
  Future<void> toggleHidden() async {
    if (!_overlay) return;
    _hidden = !_hidden;
    if (_hidden) {
      await windowManager.hide();
    } else {
      await windowManager.show(inactive: true);
    }
  }

  Future<void> setClickThrough(bool on) async {
    if (!supported || _clickThrough == on) return;
    _clickThrough = on;
    await windowManager.setIgnoreMouseEvents(on, forward: on);
  }

  /// Answers grow away from the camera edge: downward when docked at the
  /// top, so the eye-line never moves.
  Future<void> resizeOverlay(double height, {bool fromBottom = false}) async {
    if (!_overlay) return;
    final b = await windowManager.getBounds();
    final display = await _currentDisplay();
    final maxH = (display.visibleSize ?? display.size).height * 0.6;
    final h = height.clamp(96.0, maxH);
    final top = fromBottom ? b.bottom - h : b.top;
    await windowManager.setBounds(Rect.fromLTWH(b.left, top, b.width, h), animate: Platform.isMacOS);
  }

  Future<void> setOverlayWidth(double width) async {
    if (!_overlay) return;
    final b = await windowManager.getBounds();
    await windowManager.setBounds(Rect.fromLTWH(b.left, b.top, width, b.height));
  }

  Future<Rect> bounds() => windowManager.getBounds();

  String? get displayId => _displayId;

  /// Cycles the overlay to the next display, keeping its placement.
  Future<String?> moveToNextDisplay(AppSettings s) async {
    if (!_overlay) return null;
    final displays = await screenRetriever.getAllDisplays();
    if (displays.length < 2) return _displayId;
    final current = await _currentDisplay();
    final i = displays.indexWhere((d) => d.id == current.id);
    final next = displays[(i + 1) % displays.length];
    final b = await windowManager.getBounds();
    final area = (next.visiblePosition ?? Offset.zero) & (next.visibleSize ?? next.size);
    final remembered = s.rememberPositionPerDisplay ? s.overlayPositions[next.id] : null;
    final pos = remembered != null ? Offset(remembered.$1, remembered.$2) : placementOffset(s.placement, area, b.size);
    await windowManager.setPosition(pos);
    _displayId = next.id;
    return next.id;
  }

  /// Snaps within 12 px of the camera (top centre), the edges and centre.
  Future<Offset?> snapAfterDrag() async {
    if (!_overlay) return null;
    final b = await windowManager.getBounds();
    final d = await _currentDisplay();
    final area = (d.visiblePosition ?? Offset.zero) & (d.visibleSize ?? d.size);
    const snap = 12.0;
    var x = b.left, y = b.top;
    final centerX = area.left + (area.width - b.width) / 2;
    if ((x - centerX).abs() <= snap) x = centerX;
    if ((x - area.left).abs() <= snap * 2) x = area.left + snap;
    if ((area.right - b.right).abs() <= snap * 2) x = area.right - b.width - snap;
    if ((y - area.top).abs() <= snap * 2) y = area.top + snap;
    if ((area.bottom - b.bottom).abs() <= snap * 2) y = area.bottom - b.height - snap;
    if (x != b.left || y != b.top) await windowManager.setPosition(Offset(x, y), animate: true);
    _displayId = d.id;
    return Offset(x, y);
  }

  Future<void> startDragging() => windowManager.startDragging();

  Future<void> startResizing(ResizeEdge edge) => windowManager.startResizing(edge);
}

final windowServiceProvider = Provider<WindowService>((ref) => WindowService());

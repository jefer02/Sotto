import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/overlay/backdrop_tone.dart';

/// Which display to capture.
enum CaptureTarget {
  /// The display the overlay sits on — usually the one with the slides.
  overlayDisplay,

  /// The display under the mouse pointer.
  cursorDisplay,

  /// The display of the window in front (a questionnaire being filled).
  foregroundDisplay,
}

enum ScreenPermission { granted, denied, unsupported }

/// One screenshot, already scaled down and JPEG-encoded by the native side.
class ScreenCapture {
  const ScreenCapture({
    required this.jpeg,
    required this.width,
    required this.height,
    required this.screen,
    required this.scale,
    this.method = '',
  });

  final Uint8List jpeg;

  /// Size of the encoded image, in its own pixels.
  final int width;
  final int height;

  /// The captured display in physical screen pixels (virtual-desktop
  /// coordinates on Windows, global display points × scale on macOS).
  final Rect screen;

  /// Display scale factor (DPI / 96 on Windows, backing scale on macOS).
  final double scale;

  /// "wgc", "gdi" or "sck" — for diagnostics only.
  final String method;

  /// For DeepSeek's `image_url` content part.
  String get dataUrl => 'data:image/jpeg;base64,${base64Encode(jpeg)}';

  factory ScreenCapture.fromMap(Map<Object?, Object?> m) => ScreenCapture(
    jpeg: m['jpeg']! as Uint8List,
    width: m['width']! as int,
    height: m['height']! as int,
    screen: Rect.fromLTWH(
      (m['left']! as num).toDouble(),
      (m['top']! as num).toDouble(),
      (m['screenWidth']! as num).toDouble(),
      (m['screenHeight']! as num).toDouble(),
    ),
    scale: (m['scale']! as num).toDouble(),
    method: m['method'] as String? ?? '',
  );
}

/// Raw pixels of a small screen region, 4 bytes each.
class RegionPixels {
  const RegionPixels({required this.pixels, required this.width, required this.height, this.order = PixelOrder.rgba});

  final Uint8List pixels;
  final int width;
  final int height;
  final PixelOrder order;

  double get luma => averageLuma(pixels, width: width, height: height, order: order);
}

class ScreenCaptureException implements Exception {
  ScreenCaptureException(this.message, {this.permissionDenied = false});
  final String message;
  final bool permissionDenied;

  @override
  String toString() => message;
}

/// Screenshots on demand — never in the background. The overlay excludes
/// itself from capture (WDA_EXCLUDEFROMCAPTURE / sharingType none, plus an
/// explicit window filter on macOS), so a screenshot never contains Sotto.
class ScreenService {
  static const _channel = MethodChannel('app.sotto/screen');

  /// Downscaled so the long side is at most this many pixels.
  static const maxSide = 1300;

  static bool get supported => Platform.isWindows || Platform.isMacOS;

  Future<ScreenCapture> capture({CaptureTarget target = CaptureTarget.overlayDisplay}) async {
    if (!supported) throw ScreenCaptureException('Screen capture is not available on this platform.');
    try {
      final m = await _channel.invokeMethod<Map<Object?, Object?>>('capture', {
        'target': switch (target) {
          CaptureTarget.cursorDisplay => 'cursor',
          CaptureTarget.foregroundDisplay => 'foreground',
          CaptureTarget.overlayDisplay => 'overlay',
        },
        'maxSide': maxSide,
        'quality': 80,
      });
      return ScreenCapture.fromMap(m!);
    } on PlatformException catch (e) {
      throw ScreenCaptureException(e.message ?? e.code, permissionDenied: e.code == 'permission_denied');
    } on MissingPluginException {
      throw ScreenCaptureException('Screen capture is not available on this platform.');
    }
  }

  /// A few raw pixels of the screen inside [rect] — the overlay's own
  /// frame, in the coordinates `WindowService.bounds()` uses (logical pixels
  /// on Windows, multiplied back by [devicePixelRatio]; points on macOS).
  /// Sotto's windows are left out, so this is what is *behind* the overlay.
  /// Downscaled to at most [maxSide] px: it only feeds on-device pixel math
  /// (text contrast) and is never encoded, stored or sent anywhere.
  Future<RegionPixels> captureRegion(Rect rect, {double devicePixelRatio = 1, int maxSide = 48}) async {
    if (!supported) throw ScreenCaptureException('Screen capture is not available on this platform.');
    try {
      final m = await _channel.invokeMethod<Map<Object?, Object?>>('captureRegion', {
        'left': rect.left,
        'top': rect.top,
        'width': rect.width,
        'height': rect.height,
        'devicePixelRatio': devicePixelRatio,
        'maxSide': maxSide,
      });
      return RegionPixels(
        pixels: m!['pixels']! as Uint8List,
        width: m['width']! as int,
        height: m['height']! as int,
        order: m['order'] == 'bgra' ? PixelOrder.bgra : PixelOrder.rgba,
      );
    } on PlatformException catch (e) {
      throw ScreenCaptureException(e.message ?? e.code, permissionDenied: e.code == 'permission_denied');
    } on MissingPluginException {
      throw ScreenCaptureException('Screen capture is not available on this platform.');
    }
  }

  /// macOS needs Screen Recording permission; Windows needs none.
  Future<ScreenPermission> permission() async {
    if (!supported) return ScreenPermission.unsupported;
    try {
      final r = await _channel.invokeMethod<String>('permission');
      return r == 'granted' ? ScreenPermission.granted : ScreenPermission.denied;
    } on MissingPluginException {
      return ScreenPermission.unsupported;
    }
  }

  /// Shows the system prompt (macOS, first time) — returns whether granted.
  Future<bool> requestPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens System Settings → Privacy & Security at [pane]
  /// ("screen" or "accessibility"). macOS only.
  Future<void> openPrivacySettings(String pane) async {
    try {
      await _channel.invokeMethod<void>('openSettings', {'pane': pane});
    } on MissingPluginException {
      // Nothing to open elsewhere.
    }
  }
}

final screenServiceProvider = Provider<ScreenService>((ref) => ScreenService());

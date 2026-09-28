import 'dart:ui' show Offset, Rect;

/// Maps points the model gives in screenshot pixels to real screen
/// coordinates.
///
/// The screenshot is the captured display scaled down (e.g. a 2560×1440
/// display at 150 % becomes 1300×731). [screen] is that display in physical
/// pixels, in virtual-desktop coordinates — so displays left of or above
/// the primary one have negative origins. The native input layer takes
/// physical pixels on Windows and divides by [scale] on macOS (points).
class CoordinateMapper {
  const CoordinateMapper({
    required this.imageWidth,
    required this.imageHeight,
    required this.screen,
    required this.scale,
  });

  final int imageWidth;
  final int imageHeight;
  final Rect screen;
  final double scale;

  /// Physical screen pixels for image point ([x], [y]); null when the point
  /// is outside the screenshot, which the loop reports back to the model.
  Offset? toScreen(double x, double y) {
    if (x.isNaN || y.isNaN || x < 0 || y < 0 || x > imageWidth || y > imageHeight) return null;
    final px = screen.left + x * screen.width / imageWidth;
    final py = screen.top + y * screen.height / imageHeight;
    // Stay one pixel inside the display, so a click on the very edge
    // doesn't land on the neighbouring monitor.
    return Offset(
      px.clamp(screen.left, screen.right - 1).roundToDouble(),
      py.clamp(screen.top, screen.bottom - 1).roundToDouble(),
    );
  }

  /// Logical (DIP / point) coordinates for [physical].
  Offset toLogical(Offset physical) => physical / scale;
}

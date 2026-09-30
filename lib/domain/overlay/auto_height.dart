import 'dart:math' as math;

/// The overlay's height follows its text: after every beat it becomes just
/// tall enough for the lines that are showing, with nothing empty under the
/// last one. Pure, so the rules are tested without a window.
abstract final class AutoHeight {
  static const minimum = 60.0;

  /// Space left under the last visible line.
  static const bottomPad = 14.0;

  /// The reading area's height that ends [bottomPad] under the last visible
  /// line. The current line's top sits at [anchorY] − half a line; the
  /// visible lines below it run [belowCurrent] further (from the current
  /// line's top to the last visible line's bottom).
  static double fitted({required double anchorY, required double lineHeight, required double belowCurrent}) =>
      anchorY - lineHeight / 2 + belowCurrent + bottomPad;

  /// The window height for [wanted]: at least [minimum], at most
  /// [maxFraction] of the display — or, once the presenter has dragged the
  /// height themselves this session, at most what they chose ([userCap]
  /// replaces the setting for the rest of the session).
  static double clamp(double wanted, {required double screenHeight, required double maxFraction, double? userCap}) {
    final cap = userCap ?? screenHeight * maxFraction;
    return wanted.clamp(minimum, math.max(minimum, cap));
  }
}

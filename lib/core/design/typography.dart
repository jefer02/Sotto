import 'package:flutter/painting.dart';

/// Font families bundled in assets/fonts (all OFL).
abstract final class Fonts {
  static const interface = 'Geist';
  static const reading = 'AtkinsonHyperlegibleNext';
  static const mono = 'GeistMono';
}

/// Builds a style for a variable font. Flutter does not map [FontWeight] onto
/// the `wght` axis of variable fonts on every platform, so both are set.
TextStyle _v(
  String family,
  double size,
  double lineHeight,
  int weight, {
  double tracking = 0,
  List<FontFeature>? features,
  FontStyle? style,
}) {
  return TextStyle(
    fontFamily: family,
    fontSize: size,
    height: lineHeight / size,
    fontWeight: FontWeight.values[(weight ~/ 100) - 1],
    fontVariations: [FontVariation.weight(weight.toDouble())],
    letterSpacing: size * tracking,
    fontFeatures: features,
    fontStyle: style,
    leadingDistribution: TextLeadingDistribution.even,
  );
}

TextStyle withWeight(TextStyle base, int weight) => base.copyWith(
  fontWeight: FontWeight.values[(weight ~/ 100) - 1],
  fontVariations: [FontVariation.weight(weight.toDouble())],
);

const _tnum = [FontFeature.tabularFigures()];

/// Interface scale · Geist. Compact, crisp at 12–13 px.
abstract final class TypeScale {
  static final display = _v(Fonts.interface, 32, 36, 600, tracking: -0.032);
  static final title1 = _v(Fonts.interface, 22, 28, 600, tracking: -0.022);
  static final title2 = _v(Fonts.interface, 17, 24, 600, tracking: -0.016);
  static final title3 = _v(Fonts.interface, 14, 20, 600, tracking: -0.010);
  static final body = _v(Fonts.interface, 13, 20, 400, tracking: -0.006);
  static final bodyStrong = _v(Fonts.interface, 13, 20, 500, tracking: -0.006);
  static final caption = _v(Fonts.interface, 12, 16, 400);
  static final captionStrong = _v(Fonts.interface, 12, 16, 500);
  static final micro = _v(Fonts.interface, 11, 14, 500, tracking: 0.01);
  static final mono = _v(Fonts.mono, 12, 16, 500, features: _tnum);
  static final monoSmall = _v(Fonts.mono, 11, 14, 400, features: _tnum);
  static final monoLabel = _v(Fonts.mono, 10, 14, 400, tracking: 0.03, features: _tnum);
  static final keycap = _v(Fonts.mono, 11, 11, 500, tracking: 0.02);
}

/// Reading sizes for the live overlay (S / M / L / XL).
enum ReadingSize {
  s(22, 30),
  m(26, 35),
  l(30, 40),
  xl(36, 46);

  const ReadingSize(this.fontSize, this.lineHeight);
  final double fontSize;
  final double lineHeight;

  String get label => name.toUpperCase();
}

/// Reading scale · Atkinson Hyperlegible Next.
abstract final class ReadingType {
  static TextStyle live(double size, {double? lineHeight}) =>
      _v(Fonts.reading, size, lineHeight ?? size * 1.34, 500, tracking: -0.005);

  static final editor = _v(Fonts.reading, 17, 28, 400);
  static final editorStrong = _v(Fonts.reading, 17, 28, 700);

  static final answerHeadline = _v(Fonts.reading, 22, 29, 600, tracking: -0.01);
  static final answerPoint = _v(Fonts.reading, 16, 23, 400);
  static final answerQuote = _v(Fonts.reading, 14, 20, 400, style: FontStyle.italic);
  static final question = _v(Fonts.reading, 19, 28, 600);
}

/// Scales overlay text with the window: clamp(18px, 4.5cqi + 1px, 44px) ×
/// the user's text-size multiplier, where M (26 px) at 560 px wide is 1×.
double overlayFontSize(double width, ReadingSize size) {
  final fluid = (0.045 * width + 1).clamp(18.0, 44.0);
  final multiplier = size.fontSize / ReadingSize.m.fontSize;
  return (fluid * multiplier).clamp(16.0, 52.0);
}

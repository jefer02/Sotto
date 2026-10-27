import 'package:flutter/painting.dart';

import 'typography.dart';

/// Where a script font comes from: bundled with Sotto (assets/fonts, all
/// SIL OFL 1.1) or installed on this computer.
enum FontSource { bundled, system }

/// One of the fonts Sotto ships for script text.
class BundledFont {
  const BundledFont({
    required this.family,
    required this.label,
    required this.license,
    required this.minWeight,
    required this.maxWeight,
    this.scale = 1,
  });

  /// The family name in pubspec.yaml.
  final String family;
  final String label;

  /// Its license, as shipped beside it in assets/fonts.
  final String license;

  /// The variable font's weight axis.
  final int minWeight;
  final int maxWeight;

  /// Size compensation: a small x-height (Cormorant) reads smaller at the
  /// same point size, so it's drawn this much larger.
  final double scale;

  /// The weights offered, in steps of 100 within the axis.
  List<int> get weights => [for (var w = minWeight; w <= maxWeight; w += 100) w];
}

/// The font, weight and letter spacing of script text — the overlay's or
/// the editor's (Settings → Appearance → Script font).
class ScriptFont {
  const ScriptFont({required this.family, this.source = FontSource.bundled, this.weight = 500, this.letterSpacing = 0});

  /// Tolerant of old and odd values: a bundled family Sotto no longer ships
  /// becomes [fallback]; weight and spacing are kept in range.
  factory ScriptFont.fromJson(Object? json, {required ScriptFont fallback}) {
    if (json is! Map) return fallback;
    final source = FontSource.values.asNameMap()[json['source']] ?? FontSource.bundled;
    final family = json['family'];
    if (family is! String || family.trim().isEmpty) return fallback;
    final bundled = ScriptFonts.bundled(family);
    if (source == FontSource.bundled && bundled == null) return fallback;
    final weight = (json['weight'] as num?)?.round() ?? fallback.weight;
    final spacing = (json['letterSpacing'] as num?)?.toDouble() ?? fallback.letterSpacing;
    return ScriptFont(
      family: family,
      source: source,
      weight: ScriptFonts.clampWeight(bundled, weight),
      letterSpacing: spacing.clamp(ScriptFonts.minSpacing, ScriptFonts.maxSpacing),
    );
  }

  final String family;
  final FontSource source;

  /// 100–900.
  final int weight;

  /// In ems: a share of the font size.
  final double letterSpacing;

  bool get isSystem => source == FontSource.system;

  ScriptFont copyWith({String? family, FontSource? source, int? weight, double? letterSpacing}) => ScriptFont(
    family: family ?? this.family,
    source: source ?? this.source,
    weight: weight ?? this.weight,
    letterSpacing: letterSpacing ?? this.letterSpacing,
  );

  Map<String, Object?> toJson() => {
    'family': family,
    'source': source.name,
    'weight': weight,
    'letterSpacing': letterSpacing,
  };

  @override
  bool operator ==(Object other) =>
      other is ScriptFont &&
      other.family == family &&
      other.source == source &&
      other.weight == weight &&
      other.letterSpacing == letterSpacing;

  @override
  int get hashCode => Object.hash(family, source, weight, letterSpacing);

  @override
  String toString() => 'ScriptFont($family, ${source.name}, $weight, $letterSpacing em)';
}

/// The curated script fonts and how a choice becomes a text style.
abstract final class ScriptFonts {
  static const atkinson = BundledFont(
    family: Fonts.reading,
    label: 'Atkinson Hyperlegible Next',
    license: 'OFL-Atkinson.txt',
    minWeight: 200,
    maxWeight: 800,
  );
  static const geist = BundledFont(
    family: Fonts.interface,
    label: 'Geist',
    license: 'OFL-Geist.txt',
    minWeight: 100,
    maxWeight: 900,
  );

  /// A thin, high-contrast serif: the karaoke highlight's suggested font.
  static const cormorant = BundledFont(
    family: 'Cormorant',
    label: 'Cormorant',
    license: 'OFL-Cormorant.txt',
    minWeight: 300,
    maxWeight: 700,
    scale: 1.14,
  );

  /// Humanist sans with open shapes, comfortable over long reads.
  static const sourceSans = BundledFont(
    family: 'SourceSans3',
    label: 'Source Sans 3',
    license: 'OFL-SourceSans3.txt',
    minWeight: 200,
    maxWeight: 900,
  );

  /// Wide letterforms designed for reading fluency.
  static const lexend = BundledFont(
    family: 'Lexend',
    label: 'Lexend',
    license: 'OFL-Lexend.txt',
    minWeight: 100,
    maxWeight: 900,
  );
  static const mono = BundledFont(
    family: Fonts.mono,
    label: 'Geist Mono',
    license: 'OFL-Geist.txt',
    minWeight: 100,
    maxWeight: 900,
  );

  static const all = [atkinson, geist, cormorant, sourceSans, lexend, mono];

  /// What the overlay and the editor use until the presenter picks.
  static const overlayDefault = ScriptFont(family: Fonts.reading, weight: 500, letterSpacing: -0.005);
  static const editorDefault = ScriptFont(family: Fonts.reading, weight: 400);

  static const karaokeSuggestion = cormorant;

  static const minSpacing = -0.04;
  static const maxSpacing = 0.12;

  static BundledFont? bundled(String family) => all.where((f) => f.family == family).firstOrNull;

  static int clampWeight(BundledFont? font, int weight) {
    final w = (weight / 100).round() * 100;
    return font == null ? w.clamp(100, 900) : w.clamp(font.minWeight, font.maxWeight);
  }

  /// The font to draw [font] with. A system font that is no longer
  /// installed — [installed] lists the families on this computer, null
  /// while unknown — falls back to [fallback]. A missing family also falls
  /// back at draw time ([styleFor]'s fallback list), so text never shows in
  /// some random face.
  static ScriptFont resolve(ScriptFont font, {Set<String>? installed, required ScriptFont fallback}) {
    if (!font.isSystem) return bundled(font.family) == null ? fallback : font;
    if (installed != null && !installed.contains(font.family)) return fallback;
    return font;
  }

  /// [base] (size, line height…) drawn in [font]: family, weight on the
  /// variable axis too, letter spacing in ems, and the bundled font's size
  /// compensation.
  static TextStyle styleFor(TextStyle base, ScriptFont font) {
    final bundledFont = bundled(font.family);
    final size = (base.fontSize ?? 14) * (bundledFont?.scale ?? 1);
    final weight = clampWeight(bundledFont, font.weight);
    // The line box stays the same height whatever the font.
    final lineHeight = base.height == null ? null : base.height! * (base.fontSize ?? 14);
    return base.copyWith(
      fontFamily: font.family,
      fontFamilyFallback: const [Fonts.reading],
      fontSize: size,
      height: lineHeight == null ? null : lineHeight / size,
      fontWeight: FontWeight.values[(weight ~/ 100) - 1],
      fontVariations: [FontVariation.weight(weight.toDouble())],
      letterSpacing: size * font.letterSpacing,
    );
  }
}

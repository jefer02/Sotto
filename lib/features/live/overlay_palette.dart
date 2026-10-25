import 'dart:ui';

import '../../core/design/tokens.dart';
import '../../data/models/settings.dart';
import '../../domain/overlay/backdrop_tone.dart';

/// Outline that contrasts with [text]: dark around light text, light around
/// dark text.
Color autoOutline(Color text) => text.computeLuminance() > 0.4 ? const Color(0xFF000000) : const Color(0xFFFFFFFF);

/// Text-only ink for a tone: near-white or near-black.
const lightInk = Color(0xFFFAF7F3);
const darkInk = Color(0xFF14120F);

/// Whether text-only glyphs are light, for [OverlayTextColor] and the tone
/// sampled behind the overlay — null means "the chosen custom colors" (or
/// Auto before its first reading).
bool? lightTextFor(OverlayTextColor mode, BackdropTone? backdrop) => switch (mode) {
  OverlayTextColor.light => true,
  OverlayTextColor.dark => false,
  OverlayTextColor.custom => null,
  OverlayTextColor.auto => backdrop == null ? null : backdrop == BackdropTone.dark,
};

/// The overlay's palette for the current settings. [dark] resolves the
/// panel theme; [opacity] overrides the panel ground (previews); [backdrop]
/// is what live mode sees behind the overlay (Overlay text color: Auto).
OverlayPalette overlayPaletteFor(AppSettings s, {required bool dark, double? opacity, BackdropTone? backdrop}) {
  if (s.overlayStyle == OverlayStyle.textOnly) {
    final light = lightTextFor(s.overlayTextColor, backdrop) ?? (s.overlayTextColor == OverlayTextColor.auto);
    if (s.overlayTextColor != OverlayTextColor.custom) {
      // Light text reads on dark slides, near-black text on light ones. A
      // thin, soft outline and shadow in the opposite color keep each
      // glyph's edge where the slide is mixed (a chart, a photo) and vanish
      // into a uniform one. Auto starts light until its first reading.
      final ink = light ? lightInk : darkInk;
      return OverlayPalette.textOnly(
        ink: ink,
        outline: (light ? darkInk : lightInk).withValues(alpha: OverlayPalette.contrastOutlineAlpha),
        outlineWidth: s.outlineWidth * OverlayPalette.contrastOutlineScale,
        shadowStrength: s.shadowStrength,
        shadowColor: light ? OverlayPalette.shadowUnderLight : OverlayPalette.glowUnderDark,
      );
    }
    final ink = Color(s.textColor);
    return OverlayPalette.textOnly(
      ink: ink,
      outline: s.outlineColor == null ? autoOutline(ink) : Color(s.outlineColor!),
      outlineWidth: s.outlineWidth,
      shadowStrength: s.shadowStrength,
    );
  }
  return (dark ? OverlayPalette.dark : OverlayPalette.light).withGroundOpacity(opacity ?? s.overlayOpacity);
}

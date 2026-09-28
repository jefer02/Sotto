import 'dart:ui';

import '../../core/design/tokens.dart';
import '../../data/models/settings.dart';

/// Outline that contrasts with [text]: dark around light text, light around
/// dark text.
Color autoOutline(Color text) => text.computeLuminance() > 0.4 ? const Color(0xFF000000) : const Color(0xFFFFFFFF);

/// The overlay's palette for the current settings. [dark] resolves the
/// panel theme; [opacity] overrides the panel ground (previews).
OverlayPalette overlayPaletteFor(AppSettings s, {required bool dark, double? opacity}) {
  if (s.overlayStyle == OverlayStyle.textOnly) {
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

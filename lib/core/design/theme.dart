import 'package:flutter/material.dart';

import 'tokens.dart';
import 'typography.dart';

class SottoTheme extends ThemeExtension<SottoTheme> {
  const SottoTheme({required this.palette, required this.overlay});

  final SottoPalette palette;
  final OverlayPalette overlay;

  @override
  SottoTheme copyWith({SottoPalette? palette, OverlayPalette? overlay}) =>
      SottoTheme(palette: palette ?? this.palette, overlay: overlay ?? this.overlay);

  @override
  SottoTheme lerp(SottoTheme? other, double t) => t < 0.5 ? this : (other ?? this);
}

extension SottoThemeContext on BuildContext {
  SottoPalette get palette => Theme.of(this).extension<SottoTheme>()!.palette;
  OverlayPalette get overlayPalette => Theme.of(this).extension<SottoTheme>()!.overlay;
}

ThemeData buildSottoTheme(SottoPalette p, {OverlayPalette? overlay}) {
  final base = p.isDark ? ThemeData.dark() : ThemeData.light();
  final text = TextTheme(
    displayLarge: TypeScale.display.copyWith(color: p.inkPrimary),
    headlineMedium: TypeScale.title1.copyWith(color: p.inkPrimary),
    titleLarge: TypeScale.title2.copyWith(color: p.inkPrimary),
    titleMedium: TypeScale.title3.copyWith(color: p.inkPrimary),
    bodyMedium: TypeScale.body.copyWith(color: p.inkPrimary),
    bodySmall: TypeScale.caption.copyWith(color: p.inkTertiary),
    labelLarge: TypeScale.bodyStrong.copyWith(color: p.inkPrimary),
    labelSmall: TypeScale.micro.copyWith(color: p.inkTertiary),
  );

  return base.copyWith(
    brightness: p.brightness,
    scaffoldBackgroundColor: p.ground,
    canvasColor: p.ground,
    dividerColor: p.hairline,
    focusColor: p.cueFill.withValues(alpha: 0.25),
    hoverColor: p.hoverWash,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    splashColor: Colors.transparent,
    colorScheme: ColorScheme(
      brightness: p.brightness,
      primary: p.cueFill,
      onPrimary: p.onCue,
      secondary: p.cueFill,
      onSecondary: p.onCue,
      error: p.liveCapture,
      onError: p.ground,
      surface: p.panel,
      onSurface: p.inkPrimary,
    ),
    textTheme: text,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.cueFill,
      selectionColor: p.cueFill.withValues(alpha: 0.28),
      selectionHandleColor: p.cueFill,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(3),
      thumbColor: WidgetStatePropertyAll(p.emphasis.withValues(alpha: 0.7)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: p.float,
        borderRadius: Radii.rS,
        border: Border.all(color: p.control),
      ),
      textStyle: TypeScale.caption.copyWith(color: p.inkPrimary),
      waitDuration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    ),
    extensions: [SottoTheme(palette: p, overlay: overlay ?? (p.isDark ? OverlayPalette.dark : OverlayPalette.light))],
  );
}

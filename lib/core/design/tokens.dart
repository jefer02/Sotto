import 'dart:math' as math;
import 'dart:ui' show Brightness;

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

/// OKLCH-derived primitive ramps from the "Ghost light on a dark stage" board.
/// Product code should reach for [SottoPalette] (semantic tokens) instead;
/// primitives exist only to derive them.
abstract final class Primitives {
  // Graphite · h 76°
  static const graphite50 = Color(0xFFF9F7F5);
  static const graphite100 = Color(0xFFECE9E5);
  static const graphite200 = Color(0xFFDAD7D2);
  static const graphite300 = Color(0xFFBDBAB5);
  static const graphite400 = Color(0xFF928D86);
  static const graphite500 = Color(0xFF6D6862);
  static const graphite600 = Color(0xFF423F3C);
  static const graphite700 = Color(0xFF2F2C29);
  static const graphite800 = Color(0xFF24221F);
  static const graphite850 = Color(0xFF1A1816);
  static const graphite900 = Color(0xFF131210);
  static const graphite950 = Color(0xFF0D0C0A);

  // Tungsten · h 72° — "marks where you are"
  static const tungsten300 = Color(0xFFF4B55C);
  static const tungsten400 = Color(0xFFF3AA40);
  static const tungsten700 = Color(0xFF975407);
  static const tungsten950 = Color(0xFF251807);
  static const tungstenHover = Color(0xFFF7C173);
  static const tungstenPressed = Color(0xFFE79E45);

  // Tally · h 29° — "the mic is capturing the room"
  static const tally400 = Color(0xFFF96050);
  static const tally600 = Color(0xFFD22F25);
  static const tallyLight = Color(0xFFCC291F);

  // Go · h 158° — "confirms, never celebrates"
  static const go300 = Color(0xFF68CE97);
  static const goLight = Color(0xFF10764A);
}

/// Semantic tokens. One instance per theme (Stage = dark, House lights = light).
class SottoPalette {
  const SottoPalette({
    required this.brightness,
    required this.ground,
    required this.panel,
    required this.raised,
    required this.float,
    required this.hairline,
    required this.control,
    required this.emphasis,
    required this.inkPrimary,
    required this.inkSecondary,
    required this.inkTertiary,
    required this.inkDisabled,
    required this.cueFill,
    required this.cueText,
    required this.onCue,
    required this.cueHover,
    required this.cuePressed,
    required this.liveCapture,
    required this.confirmed,
    required this.hoverWash,
    required this.pressWash,
  });

  final Brightness brightness;

  // surface/*
  final Color ground;
  final Color panel;
  final Color raised;
  final Color float;

  // line/*
  final Color hairline;
  final Color control;
  final Color emphasis;

  // ink/*
  final Color inkPrimary;
  final Color inkSecondary;
  final Color inkTertiary;
  final Color inkDisabled;

  // signal/*
  final Color cueFill;
  final Color cueText;
  final Color onCue;
  final Color cueHover;
  final Color cuePressed;
  final Color liveCapture;
  final Color confirmed;

  /// Ghost-button washes (rgba(255,244,230,.045 / .08) on dark).
  final Color hoverWash;
  final Color pressWash;

  bool get isDark => brightness == Brightness.dark;

  Color get focusRing => cueFill.withValues(alpha: 0.9);

  static const stage = SottoPalette(
    brightness: Brightness.dark,
    ground: Color(0xFF0D0C0A),
    panel: Color(0xFF131210),
    raised: Color(0xFF1A1816),
    float: Color(0xFF24221F),
    hairline: Color(0xFF22201E),
    control: Color(0xFF2F2C29),
    emphasis: Color(0xFF423F3C),
    inkPrimary: Color(0xFFF2EFE9),
    inkSecondary: Color(0xFFBAB5AE),
    inkTertiary: Color(0xFF928D86),
    inkDisabled: Color(0xFF5B5753),
    cueFill: Primitives.tungsten300,
    cueText: Primitives.tungsten300,
    onCue: Primitives.tungsten950,
    cueHover: Primitives.tungstenHover,
    cuePressed: Primitives.tungstenPressed,
    liveCapture: Primitives.tally400,
    confirmed: Primitives.go300,
    hoverWash: Color(0x0BFFF4E6),
    pressWash: Color(0x14FFF4E6),
  );

  static const houseLights = SottoPalette(
    brightness: Brightness.light,
    ground: Color(0xFFF9F7F5),
    panel: Color(0xFFF2F0ED),
    raised: Color(0xFFFFFFFF),
    float: Color(0xFFECE9E5),
    hairline: Color(0xFFE8E6E2),
    control: Color(0xFFDAD7D2),
    emphasis: Color(0xFFBDBAB5),
    inkPrimary: Color(0xFF1C1916),
    inkSecondary: Color(0xFF544F49),
    inkTertiary: Color(0xFF6D6862),
    inkDisabled: Color(0xFFABA7A2),
    cueFill: Primitives.tungsten400,
    cueText: Primitives.tungsten700,
    onCue: Primitives.tungsten950,
    cueHover: Color(0xFFF5B658),
    cuePressed: Color(0xFFE39A33),
    liveCapture: Primitives.tallyLight,
    confirmed: Primitives.goLight,
    hoverWash: Color(0x0A1C1916),
    pressWash: Color(0x141C1916),
  );
}

/// Overlay-only tokens. The overlay is the one surface where text uses
/// opacity, to express reading levels (now / next / later / done).
class OverlayPalette {
  const OverlayPalette({
    required this.ground,
    required this.ink,
    required this.edge,
    required this.shadow,
    required this.innerHighlight,
    required this.cue,
    required this.capture,
    required this.confirmed,
    required this.readNow,
    required this.readNext,
    required this.readLater,
    required this.readDone,
    this.textOnly = false,
    this.outline = const Color(0xFF000000),
    this.outlineWidth = 0,
    this.shadowStrength = 0,
  });

  /// "Text only" style: no ground, no card, no edge — legibility comes from
  /// an outline and a soft shadow around every glyph.
  factory OverlayPalette.textOnly({
    required Color ink,
    required Color outline,
    required double outlineWidth,
    required double shadowStrength,
  }) => OverlayPalette(
    ground: const Color(0x00000000),
    ink: ink,
    edge: const Color(0x00000000),
    shadow: const BoxShadow(color: Color(0x00000000)),
    innerHighlight: const Color(0x00000000),
    cue: Primitives.tungsten300,
    capture: Primitives.tally400,
    confirmed: Primitives.go300,
    // Dimmed words need more weight without a ground behind them.
    readNow: 1,
    readNext: 0.78,
    readLater: 0.6,
    readDone: 0.5,
    textOnly: true,
    outline: outline,
    outlineWidth: outlineWidth,
    shadowStrength: shadowStrength,
  );

  final Color ground;
  final Color ink;
  final Color edge;
  final BoxShadow shadow;
  final Color innerHighlight;
  final Color cue;
  final Color capture;
  final Color confirmed;

  // Reading levels, as alpha multipliers for [ink].
  final double readNow;
  final double readNext;
  final double readLater;
  final double readDone;

  final bool textOnly;
  final Color outline;
  final double outlineWidth;

  /// 0..1: how strong the soft drop shadow under text-only glyphs is.
  final double shadowStrength;

  Color inkAt(double alpha) => ink.withValues(alpha: alpha);

  /// Behind controls that must stay usable when the overlay has no ground
  /// (the hover pill, history): a solid dark surface.
  Color get chromeGround => textOnly ? const Color(0xE6141210) : ground;

  /// Outline + soft shadow for text-only glyphs, faded with the glyph's own
  /// [alpha]. [small] text (captions, labels) gets a thinner outline so it
  /// doesn't clog. Null in panel style, so styles inherit nothing.
  List<Shadow>? textShadows([double alpha = 1, bool small = false]) {
    if (!textOnly) return null;
    final a = alpha.clamp(0.0, 1.0);
    final out = <Shadow>[];
    final outlineWidth = small ? math.min(this.outlineWidth, 1.2) : this.outlineWidth;
    if (outlineWidth > 0) {
      final c = outline.withValues(alpha: outline.a * a);
      // A ring of hard shadows reads as a stroke that sits behind the fill.
      const steps = 12;
      for (var i = 0; i < steps; i++) {
        final t = 2 * math.pi * i / steps;
        out.add(
          Shadow(color: c, offset: Offset(math.cos(t) * outlineWidth, math.sin(t) * outlineWidth), blurRadius: 0.6),
        );
      }
    }
    if (shadowStrength > 0) {
      out.add(
        Shadow(
          color: Color.fromRGBO(0, 0, 0, 0.9 * shadowStrength * a),
          offset: const Offset(0, 1.5),
          blurRadius: (small ? 2 : 3) + (small ? 5 : 9) * shadowStrength,
        ),
      );
    }
    return out;
  }

  /// Shadows matching a span colored [c] (null: inherit from the parent).
  List<Shadow>? shadowsFor(Color? c) => c == null || !textOnly ? null : textShadows(c.a / (ink.a == 0 ? 1 : ink.a));

  /// 80 % ground over a white slide still gives 10.5:1 on the current line.
  static const dark = OverlayPalette(
    ground: Color(0xCC0B0A08),
    ink: Color(0xFFFAF7F3),
    edge: Color(0x17FFF4E6),
    shadow: BoxShadow(color: Color(0xB3000000), offset: Offset(0, 28), blurRadius: 70, spreadRadius: -18),
    innerHighlight: Color(0x0DFFFFFF),
    cue: Primitives.tungsten300,
    capture: Primitives.tally400,
    confirmed: Primitives.go300,
    readNow: 1,
    readNext: 0.62,
    readLater: 0.40,
    readDone: 0.36,
  );

  /// 88 % ground, used when the room lights are on.
  static const light = OverlayPalette(
    ground: Color(0xE0FBFAF8),
    ink: Color(0xFF12100E),
    edge: Color(0x1A1C1916),
    shadow: BoxShadow(color: Color(0x591C1916), offset: Offset(0, 28), blurRadius: 70, spreadRadius: -20),
    innerHighlight: Color(0xB3FFFFFF),
    cue: Primitives.tungsten400,
    capture: Primitives.tallyLight,
    confirmed: Primitives.goLight,
    readNow: 1,
    readNext: 0.64,
    readLater: 0.42,
    readDone: 0.36,
  );

  OverlayPalette withGroundOpacity(double opacity) => OverlayPalette(
    ground: ground.withValues(alpha: opacity),
    ink: ink,
    edge: edge,
    shadow: shadow,
    innerHighlight: innerHighlight,
    cue: cue,
    capture: capture,
    confirmed: confirmed,
    readNow: readNow,
    readNext: readNext,
    readLater: readLater,
    readDone: readDone,
    textOnly: textOnly,
    outline: outline,
    outlineWidth: outlineWidth,
    shadowStrength: shadowStrength,
  );
}

/// space-n = n × 4 px. 8 / 16 / 24 do 80 % of the work.
abstract final class Space {
  static const double s0_5 = 2;
  static const double s1 = 4;
  static const double s1_5 = 6;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;
  static const double s10 = 40;
  static const double s12 = 48;
  static const double s16 = 64;
  static const double s20 = 80;
}

abstract final class Radii {
  static const double xs = 4; // keycaps, chips
  static const double s = 6; // inputs, small buttons
  static const double m = 8; // buttons, menus
  static const double l = 12; // cards, panels
  static const double xl = 16; // overlay, sheets
  static const double control = 7; // buttons & inputs in the component sheet

  static const rXs = BorderRadius.all(Radius.circular(xs));
  static const rS = BorderRadius.all(Radius.circular(s));
  static const rM = BorderRadius.all(Radius.circular(m));
  static const rL = BorderRadius.all(Radius.circular(l));
  static const rXl = BorderRadius.all(Radius.circular(xl));
  static const rControl = BorderRadius.all(Radius.circular(control));
}

/// Motion tokens and curves from "Space, grid, depth, motion".
abstract final class Motion {
  static const instant = Duration.zero;
  static const quick = Duration(milliseconds: 90);
  static const snappy = Duration(milliseconds: 160);
  static const smooth = Duration(milliseconds: 240);
  static const glide = Duration(milliseconds: 420);
  static const settle = Duration(milliseconds: 560);

  static const glideEnter = Cubic(0.22, 1, 0.36, 1);
  static const shiftMove = Cubic(0.65, 0, 0.35, 1);
  static const leaveExit = Cubic(0.55, 0, 1, 0.45);

  // Micro-interaction timings (Motion boards).
  static const wordDim = Duration(milliseconds: 180);
  static const cuePulse = Duration(milliseconds: 300);
  static const reducedMotionFade = Duration(milliseconds: 120);
  static const hoverIntent = Duration(milliseconds: 150);
  static const hoverHide = Duration(milliseconds: 800);
  static const holdToSend = Duration(milliseconds: 500);
  static const answerPointStagger = Duration(milliseconds: 120);
}

/// Main-window layout constants.
abstract final class Layout {
  static const double sidebar = 240;
  static const double sidebarCollapsed = 56;
  static const double inspectorMin = 360;
  static const double inspectorMax = 400;
  static const double contentMargin = 40;
  static const double titleBar = 52;
  static const Size windowMin = Size(960, 600);

  // Overlay anatomy · 560 × 232 default.
  static const Size overlayDefault = Size(560, 232);
  static const double overlayMeta = 36;
  static const double overlayCueColumn = 15;
  static const double overlayTextInset = 34;
  static const double overlayAnchor = 0.30;
}

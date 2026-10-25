import 'dart:math' as math;
import 'dart:ui' show Brightness;

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

/// OKLCH-derived primitive ramps from the "Ghost light on a dark stage" board.
/// Product code should reach for [SottoPalette] (semantic tokens) instead;
/// primitives exist only to derive them.
abstract final class Primitives {
  // Graphite · neutral with a cold hint — the stage is dark, not brown.
  static const graphite50 = Color(0xFFF7F8FA);
  static const graphite100 = Color(0xFFE9ECF1);
  static const graphite200 = Color(0xFFD5DAE1);
  static const graphite300 = Color(0xFFB6BDC8);
  static const graphite400 = Color(0xFF8A919E);
  static const graphite500 = Color(0xFF636B78);
  static const graphite600 = Color(0xFF3D4350);
  static const graphite700 = Color(0xFF2C313B);
  static const graphite800 = Color(0xFF1F232A);
  static const graphite850 = Color(0xFF171A1F);
  static const graphite900 = Color(0xFF111317);
  static const graphite950 = Color(0xFF0B0C0F);

  /// Below the stage: the house with its lights down.
  static const blackout = Color(0xFF040507);

  // Electric · h 262° — "marks where you are". White on 500 holds 4.5:1.
  static const electric300 = Color(0xFF6EA8FF);
  static const electric400 = Color(0xFF4C8DFF);
  static const electric500 = Color(0xFF2F6BFF);
  static const electric600 = Color(0xFF2563EB);
  static const electric700 = Color(0xFF1D4ED8);
  static const electricHover = Color(0xFF4A7FFF);
  static const electricPressed = Color(0xFF2458E6);

  // Indigo · h 280° — the deep end of electric gradients; gives it depth.
  static const indigo400 = Color(0xFF6D5BFF);
  static const indigoLight = Color(0xFF5B45F0);

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
    required this.caution,
    required this.hoverWash,
    required this.pressWash,
    required this.collectionTones,
    required this.cueDeep,
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

  /// Amber: worth a look before going live, never an error.
  final Color caution;

  /// Ghost-button washes (rgba(255,244,230,.045 / .08) on dark).
  final Color hoverWash;
  final Color pressWash;

  /// collection/* — orchid, teal, green, sky, iris, rose. Equal lightness
  /// and full chroma, so each collection is easy to tell apart. No amber or
  /// coral: those read as caution and the tally (mic live, errors), and
  /// they were the old tungsten brand's — off-key next to electric.
  final List<Color> collectionTones;

  /// The deep end of cue gradients (indigo) and the second,
  /// lower glow on the stage.
  final Color cueDeep;

  /// A collection's color; null (no collection) reads as quiet ink.
  Color collectionColor(int? tone) => tone == null ? inkTertiary : collectionTones[tone % collectionTones.length];

  bool get isDark => brightness == Brightness.dark;

  Color get focusRing => cueFill.withValues(alpha: 0.9);

  // brand/primary — the electric cue is the brand color; these name it.
  Color get primary => cueFill;
  Color get primaryText => cueText;
  Color get onPrimary => onCue;
  Color get primaryHover => cueHover;
  Color get primaryPressed => cuePressed;

  /// Electric wash behind selected rows — color without shouting.
  Color get primaryWash => primary.withValues(alpha: isDark ? 0.16 : 0.10);

  /// The house with its lights down (going live) — darker than the stage
  /// in either theme — and the ink and lamp shown on it.
  Color get blackout => Primitives.blackout;
  Color get blackoutInk => SottoPalette.stage.inkPrimary;

  /// The white-hot core of a lamp as it ignites.
  Color get lampCore => onCue;

  /// Behind dialogs; [scrimStrong] behind the one that leads on stage.
  Color get scrim => const Color(0x8A000000);
  Color get scrimStrong => const Color(0x99000000);

  /// Amber wash behind something that needs fixing before going live, and
  /// the edge of its icon. Amber, not tally: red only ever means the mic is
  /// capturing the room.
  Color get cautionWash => caution.withValues(alpha: isDark ? 0.10 : 0.08);
  Color get cautionEdge => caution.withValues(alpha: isDark ? 0.55 : 0.50);

  /// The ghost light: a pool of light falling on the stage from above.
  Color get stageGlow => primary.withValues(alpha: isDark ? 0.18 : 0.10);

  /// Indigo spill low on the opposite side, so the ground has two lights.
  Color get depthGlow => cueDeep.withValues(alpha: isDark ? 0.12 : 0.06);

  /// Unplayed section segments — an electric track rather than grey.
  Color get primaryTrack => primary.withValues(alpha: isDark ? 0.30 : 0.22);

  /// Card faces: lit top, settled bottom, and an edge that holds its shape
  /// against the ground.
  Color get cardTop => isDark ? float : raised;
  Color get cardBottom => isDark ? raised : panel;
  Color get cardEdge => isDark ? Color.lerp(hairline, control, 0.55)! : hairline;

  /// Blends two palettes, so switching theme crossfades every surface and
  /// ink instead of snapping halfway through.
  static SottoPalette lerp(SottoPalette a, SottoPalette b, double t) {
    if (t <= 0) return a;
    if (t >= 1) return b;
    Color c(Color x, Color y) => Color.lerp(x, y, t)!;
    return SottoPalette(
      brightness: t < 0.5 ? a.brightness : b.brightness,
      ground: c(a.ground, b.ground),
      panel: c(a.panel, b.panel),
      raised: c(a.raised, b.raised),
      float: c(a.float, b.float),
      hairline: c(a.hairline, b.hairline),
      control: c(a.control, b.control),
      emphasis: c(a.emphasis, b.emphasis),
      inkPrimary: c(a.inkPrimary, b.inkPrimary),
      inkSecondary: c(a.inkSecondary, b.inkSecondary),
      inkTertiary: c(a.inkTertiary, b.inkTertiary),
      inkDisabled: c(a.inkDisabled, b.inkDisabled),
      cueFill: c(a.cueFill, b.cueFill),
      cueText: c(a.cueText, b.cueText),
      onCue: c(a.onCue, b.onCue),
      cueHover: c(a.cueHover, b.cueHover),
      cuePressed: c(a.cuePressed, b.cuePressed),
      liveCapture: c(a.liveCapture, b.liveCapture),
      confirmed: c(a.confirmed, b.confirmed),
      caution: c(a.caution, b.caution),
      hoverWash: c(a.hoverWash, b.hoverWash),
      pressWash: c(a.pressWash, b.pressWash),
      collectionTones: [
        for (var i = 0; i < a.collectionTones.length; i++)
          c(a.collectionTones[i], b.collectionTones[i % b.collectionTones.length]),
      ],
      cueDeep: c(a.cueDeep, b.cueDeep),
    );
  }

  static const stage = SottoPalette(
    brightness: Brightness.dark,
    ground: Primitives.graphite950,
    panel: Primitives.graphite900,
    raised: Primitives.graphite850,
    float: Primitives.graphite800,
    hairline: Color(0xFF22262E),
    control: Primitives.graphite700,
    emphasis: Primitives.graphite600,
    inkPrimary: Color(0xFFEEF1F6),
    inkSecondary: Color(0xFFA4ABB8),
    inkTertiary: Primitives.graphite400,
    inkDisabled: Color(0xFF555B66),
    cueFill: Primitives.electric500,
    cueText: Primitives.electric300,
    onCue: Color(0xFFFFFFFF),
    cueHover: Primitives.electricHover,
    cuePressed: Primitives.electricPressed,
    liveCapture: Primitives.tally400,
    confirmed: Primitives.go300,
    caution: Color(0xFFFFB547),
    hoverWash: Color(0x0BFFFFFF),
    pressWash: Color(0x14FFFFFF),
    collectionTones: [
      Color(0xFFD27BFF),
      Color(0xFF3FD4C4),
      Color(0xFF5FD88A),
      Color(0xFF5AAEFF),
      Color(0xFFA58BFF),
      Color(0xFFFF7EB6),
    ],
    cueDeep: Primitives.indigo400,
  );

  static const houseLights = SottoPalette(
    brightness: Brightness.light,
    ground: Primitives.graphite50,
    panel: Color(0xFFF0F2F5),
    raised: Color(0xFFFFFFFF),
    float: Primitives.graphite100,
    hairline: Color(0xFFE3E6EB),
    control: Primitives.graphite200,
    emphasis: Primitives.graphite300,
    inkPrimary: Color(0xFF101318),
    inkSecondary: Color(0xFF4A5160),
    inkTertiary: Primitives.graphite500,
    inkDisabled: Color(0xFFA8AEB8),
    cueFill: Primitives.electric600,
    cueText: Primitives.electric700,
    onCue: Color(0xFFFFFFFF),
    cueHover: Color(0xFF3B74F0),
    cuePressed: Color(0xFF1E50C8),
    liveCapture: Primitives.tallyLight,
    confirmed: Primitives.goLight,
    caution: Color(0xFFB45309),
    hoverWash: Color(0x0A101318),
    pressWash: Color(0x14101318),
    collectionTones: [
      Color(0xFF9B3FD0),
      Color(0xFF0E8C80),
      Color(0xFF1F9150),
      Color(0xFF1F6FD1),
      Color(0xFF6B43D6),
      Color(0xFFC93D82),
    ],
    cueDeep: Primitives.indigoLight,
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
    this.shadowColor = const Color(0xFF000000),
  });

  /// "Text only" style: no ground, no card, no edge — legibility comes from
  /// an outline and a soft shadow around every glyph.
  factory OverlayPalette.textOnly({
    required Color ink,
    required Color outline,
    required double outlineWidth,
    required double shadowStrength,
    Color shadowColor = const Color(0xFF000000),
  }) => OverlayPalette(
    ground: const Color(0x00000000),
    ink: ink,
    edge: const Color(0x00000000),
    shadow: const BoxShadow(color: Color(0x00000000)),
    innerHighlight: const Color(0x00000000),
    cue: Primitives.electric400,
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
    shadowColor: shadowColor,
  );

  /// Light or dark text (Auto, Always light / dark) is outlined in the
  /// opposite color, kept thin and a little soft — this share of the
  /// "Outline width" setting, at this opacity — so a uniform slide never
  /// shows a hard ring.
  static const contrastOutlineScale = 0.6;
  static const contrastOutlineAlpha = 0.85;

  /// The soft shadow under light text, and the soft glow under dark text.
  static const shadowUnderLight = Color(0xFF000000);
  static const glowUnderDark = Color(0xB3FFFFFF);

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

  /// Black under light-on-dark… and dark-on-light text; a soft white glow
  /// when the backdrop is dark and the text light ("Overlay text color").
  final Color shadowColor;

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
          color: shadowColor.withValues(alpha: shadowColor.a * 0.9 * shadowStrength * a),
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
    cue: Primitives.electric400,
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
    cue: Primitives.electric600,
    capture: Primitives.tallyLight,
    confirmed: Primitives.goLight,
    readNow: 1,
    readNext: 0.64,
    readLater: 0.42,
    readDone: 0.36,
  );

  /// Crossfade between two palettes (the text color following the slide).
  static OverlayPalette lerp(OverlayPalette a, OverlayPalette b, double t) {
    if (t <= 0) return a;
    if (t >= 1) return b;
    Color c(Color x, Color y) => Color.lerp(x, y, t)!;
    double d(double x, double y) => x + (y - x) * t;
    return OverlayPalette(
      ground: c(a.ground, b.ground),
      ink: c(a.ink, b.ink),
      edge: c(a.edge, b.edge),
      shadow: BoxShadow.lerp(a.shadow, b.shadow, t)!,
      innerHighlight: c(a.innerHighlight, b.innerHighlight),
      cue: c(a.cue, b.cue),
      capture: c(a.capture, b.capture),
      confirmed: c(a.confirmed, b.confirmed),
      readNow: d(a.readNow, b.readNow),
      readNext: d(a.readNext, b.readNext),
      readLater: d(a.readLater, b.readLater),
      readDone: d(a.readDone, b.readDone),
      textOnly: t < 0.5 ? a.textOnly : b.textOnly,
      outline: c(a.outline, b.outline),
      outlineWidth: d(a.outlineWidth, b.outlineWidth),
      shadowStrength: d(a.shadowStrength, b.shadowStrength),
      shadowColor: c(a.shadowColor, b.shadowColor),
    );
  }

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
    shadowColor: shadowColor,
  );
}

/// WCAG 2 contrast thresholds and the ratio itself.
abstract final class Contrast {
  /// Body text (AA).
  static const double aa = 4.5;

  /// Large text and UI parts (AA).
  static const double large = 3.0;

  static double ratio(Color a, Color b) {
    final l1 = a.computeLuminance(), l2 = b.computeLuminance();
    return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
  }
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
///
/// Micro-interactions (hover, press, focus, toggles) take 120–200 ms;
/// panels 250–400 ms. [glide] and [settle] are kept for the signature
/// moments only (curtain, greeting). Widgets take every duration and curve
/// from here, and resolve it with `context.motion(…)` so that reduced
/// motion (system or Settings › Appearance) makes it instant.
abstract final class Motion {
  static const instant = Duration.zero;
  static const quick = Duration(milliseconds: 120);
  static const snappy = Duration(milliseconds: 160);
  static const smooth = Duration(milliseconds: 240);
  static const glide = Duration(milliseconds: 420);
  static const settle = Duration(milliseconds: 560);

  /// Hover and press.
  static const micro = Duration(milliseconds: 120);

  /// Toggles, the segment pill, the focus ring.
  static const microOut = Duration(milliseconds: 160);

  /// Panels, the sidebar pill, Settings pages.
  static const panel = Duration(milliseconds: 280);

  /// Route changes that move between levels.
  static const page = Duration(milliseconds: 320);

  /// Sibling routes: the arriving page fades through, quickly.
  static const pageFade = Duration(milliseconds: 200);

  /// Content arriving in place (a Settings page, the sidebar resizing).
  static const contentFade = snappy;

  /// Dialogs settle in, and leave faster than they came.
  static const dialogIn = snappy;
  static const dialogOut = quick;

  /// The nav highlight sliding from one row to the next.
  static const navSlide = Duration(milliseconds: 180);

  /// One step of a list's first-time stagger, capped at [staggerCap] items.
  static const staggerStep = Duration(milliseconds: 30);
  static const staggerCap = 6;

  /// The delay of item [i] in a staggered list.
  static Duration stagger(int i) => staggerStep * (i < staggerCap ? i : staggerCap);

  /// The home's first look: one beat between the greeting's parts, and
  /// the cards rising in after them.
  static const introStep = Duration(milliseconds: 60);
  static const introLead = Duration(milliseconds: 160);
  static const introCardStep = Duration(milliseconds: 35);

  /// The delay of card [i] in the home's first look.
  static Duration introStagger(int i) => introLead + introCardStep * (i < staggerCap ? i : staggerCap);

  static const glideEnter = Cubic(0.22, 1, 0.36, 1);
  static const shiftMove = Cubic(0.65, 0, 0.35, 1);
  static const leaveExit = Cubic(0.55, 0, 1, 0.45);

  /// Things arriving or reacting: fast out, soft landing.
  static const standard = glideEnter;

  /// Things leaving: they accelerate away.
  static const exit = leaveExit;

  /// Things moving from one place to another (pills, panels).
  static const move = Cubic(0.4, 0, 0.2, 1);

  /// A confident arrival for light and lamps: very fast out, long landing.
  static const arrive = Cubic(0.16, 1, 0.3, 1);

  /// Opacity alone: fades in and out.
  static const fade = Curves.easeOut;
  static const fadeOut = Curves.easeIn;

  /// One color becoming another (the overlay following the slide).
  static const crossfade = Curves.easeInOut;

  // Micro-interaction timings (Motion boards).
  static const wordDim = Duration(milliseconds: 180);
  static const cuePulse = Duration(milliseconds: 300);
  static const hoverIntent = Duration(milliseconds: 150);
  static const hoverHide = Duration(milliseconds: 800);
  static const holdToSend = Duration(milliseconds: 500);
  static const answerPointStagger = Duration(milliseconds: 120);

  /// A press giving under the pointer.
  static const press = Duration(milliseconds: 100);

  /// The voice bars following the level — a meter, so barely eased.
  static const meter = Duration(milliseconds: 90);

  /// A recognized word of the question coming into focus.
  static const wordIn = quick;

  /// After Dismiss, a line of cue re-anchors the eye on the script.
  static const cueSweep = cuePulse;

  /// The overlay's text color crossfading when the backdrop changes.
  static const backdropFade = Duration(milliseconds: 200);

  /// The overlay window easing to the height its lines need.
  static const overlayFit = Duration(milliseconds: 150);

  // Signature moments — each is skipped entirely under reduced motion.
  static const curtain = Duration(milliseconds: 1250);
  static const lightsUp = Duration(milliseconds: 700);

  /// House lights down before the overlay: short, so the session starts
  /// within this of pressing Go live.
  static const goLive = Duration(milliseconds: 400);
  static const overlayEntrance = Duration(milliseconds: 900);

  // Loops — each one stops under reduced motion.
  static const pingPeriod = Duration(milliseconds: 1800);
  static const draftingLoop = Duration(milliseconds: 900);
  static const organizingLoop = Duration(milliseconds: 1400);
  static const beamLap = Duration(seconds: 4);

  /// The stage's ambient light: one slow, seamless loop.
  static const stageLoop = Duration(seconds: 60);
}

/// The karaoke highlight on the overlay's current line (Appearance →
/// Highlight effect). Lengths are in ems — shares of the line's font size —
/// or in characters, so the look holds at any text size and in any font.
abstract final class Karaoke {
  /// Around light text: a cold cyan-white bloom with a near-white core,
  /// added over the glyphs (the line stays white; its edges light up).
  static const glowOnLightInk = Color(0xFF8FCBFF);
  static const coreOnLightInk = Color(0xFFE6F5FF);

  /// Around dark text (Auto over a light slide): electric blue, so the halo
  /// reads as light without lifting the glyphs' own dark.
  static const glowOnDarkInk = Primitives.electric500;
  static const coreOnDarkInk = Primitives.electric300;

  /// Halo spread (Gaussian sigma) and how strong it is; dark text gets a
  /// fainter halo so it never washes the letters out.
  static const haloBlur = 0.22;
  static const coreBlur = 0.05;
  static const haloAlpha = 0.9;
  static const coreAlpha = 1.0;

  /// The glyphs are thickened by these strokes before blurring.
  static const haloStroke = 0.12;
  static const coreStroke = 0.04;
  static const darkInkStrength = 0.6;

  /// The glow covers the letter being said and trails off over this many
  /// characters behind it; it ends this many characters past the head.
  static const trailChars = 1.8;

  /// Past the head the light rolls off over this many ems (about a letter).
  static const headFeather = 0.45;

  /// Sparkles: a fixed pool, spawned per character swept.
  static const particleCap = 60;
  static const particlesPerChar = 0.6;
  static const particleLifeMin = Duration(milliseconds: 600);
  static const particleLifeMax = Duration(milliseconds: 1400);
  static const particleSizeMin = 0.16;
  static const particleSizeMax = 0.34;

  /// Rise speed (ems a second) and twinkle rate (Hz).
  static const particleRiseMin = 0.25;
  static const particleRiseMax = 0.8;
  static const twinkleMin = 3.0;
  static const twinkleMax = 7.0;

  /// After the voice stops, the glow holds, then fades out.
  static const idleHold = Duration(milliseconds: 500);
  static const idleFade = Duration(milliseconds: 900);

  /// "Simple": the letters being said take the cue color.
  static const simpleTrailChars = 3.0;
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

  /// Settings rows are at least this tall, subtitle or not.
  static const double rowMin = 52;

  /// Below this window height the sidebar's readiness card folds to one line.
  static const double sidebarCompactBelow = 720;

  // Overlay anatomy · 560 × 232 default.
  static const Size overlayDefault = Size(560, 232);
  static const double overlayMeta = 36;
  static const double overlayCueColumn = 15;
  static const double overlayTextInset = 34;
  static const double overlayAnchor = 0.30;

  /// The hover controls' own band (30 px buttons, their padding and a
  /// little air): the reading area ends above it, so the controls never
  /// cover a word of the script.
  static const double overlayControlsBand = 40;

  /// The rail's side column, which holds the controls in that layout.
  static const double overlayRailSide = 300;
}

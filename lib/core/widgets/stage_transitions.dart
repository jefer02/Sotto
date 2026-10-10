import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import 'motion_effects.dart';

// The show's three big moments, staged like a theatre: the curtain rises
// when Sotto opens, the house goes dark and the tally lights when you go
// live, and the house lights come back up when the show is over. Each one
// is skipped entirely under reduced motion.

bool _still(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// The far corner's distance from [c] — what an iris must reach to be open.
double _reach(Size size, Offset c) => [
  Offset.zero,
  Offset(size.width, 0),
  Offset(0, size.height),
  Offset(size.width, size.height),
].map((o) => (o - c).distance).reduce(math.max);

/// [color] everywhere except a soft-edged circle around [center], [open] of
/// the way to the far corner (0 shut, 1 fully open).
void _paintIris(Canvas canvas, Size size, Offset center, double open, Color color) {
  final rect = Offset.zero & size;
  if (open <= 0) {
    canvas.drawRect(rect, Paint()..color = color);
    return;
  }
  final far = _reach(size, center);
  final feather = far * 0.22;
  final r = open * (far + feather);
  final inner = ((r - feather) / r).clamp(0.0, 1.0);
  canvas.drawRect(
    rect,
    Paint()
      ..shader = ui.Gradient.radial(
        center,
        math.max(r, 0.001),
        [color.withValues(alpha: 0), color.withValues(alpha: 0), color],
        [0, inner, 1],
      ),
  );
}

class _IrisPainter extends CustomPainter {
  _IrisPainter({required this.open, required this.color, this.center = Alignment.center});
  final double open;
  final Color color;
  final Alignment center;

  @override
  void paint(Canvas canvas, Size size) => _paintIris(canvas, size, center.alongSize(size), open, color);

  @override
  bool shouldRepaint(_IrisPainter old) => old.open != open || old.color != color || old.center != center;
}

double _seg(double t, double from, double to, [Curve curve = Curves.linear]) =>
    curve.transform(((t - from) / (to - from)).clamp(0.0, 1.0));

// ─────────────────────────── Curtain up ───────────────────────────

/// Wraps the main window. The first time in a run it raises the curtain:
/// the cue mark comes into focus, its lamp ignites and a line of light draws
/// out beneath the wordmark; then the mark lifts away and the stage opens in
/// an iris from the lamp. Every later mount — coming back from a live
/// session — is the house lights coming up: the iris alone, quicker.
class LaunchCurtain extends StatefulWidget {
  const LaunchCurtain({super.key, required this.child});

  final Widget child;

  static const full = Duration(milliseconds: 1250);
  static const lightsUp = Duration(milliseconds: 700);

  /// Where in the full curtain the stage starts to open.
  static const opensAt = 0.5;

  static bool _raised = false;

  /// For tests: play the full curtain again.
  @visibleForTesting
  static void reset() => _raised = false;

  @override
  State<LaunchCurtain> createState() => _LaunchCurtainState();
}

class _LaunchCurtainState extends State<LaunchCurtain> with SingleTickerProviderStateMixin {
  // Read before initState marks the curtain raised.
  final bool _first = !LaunchCurtain._raised;
  late final _c = AnimationController(vsync: this, duration: _first ? LaunchCurtain.full : LaunchCurtain.lightsUp);
  bool _done = false;

  @override
  void initState() {
    super.initState();
    LaunchCurtain._raised = true;
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) setState(() => _done = true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_done || _c.isAnimating) return;
    if (_still(context)) {
      _done = true;
      return;
    }
    // What's revealed under the curtain waits for it to open.
    final opens = _first ? LaunchCurtain.full * LaunchCurtain.opensAt : Duration.zero;
    Entrance.holdUntil(DateTime.now().add(opens));
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    final p = context.palette;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = _c.value;
        final irisFrom = _first ? LaunchCurtain.opensAt : 0.0;
        final open = _seg(t, irisFrom, 1, const Cubic(0.65, 0, 0.35, 1));
        // The stage settles back as it's uncovered.
        final settle = _seg(t, irisFrom, 1, Motion.glideEnter);
        return Stack(
          fit: StackFit.expand,
          children: [
            Transform.scale(scale: 1.025 - 0.025 * settle, child: child),
            IgnorePointer(
              child: CustomPaint(
                painter: _IrisPainter(open: open, color: p.ground, center: const Alignment(0, -0.08)),
              ),
            ),
            // Above the navigator there's no Material to give text its style.
            if (_first && t < 0.8)
              IgnorePointer(
                child: Material(
                  type: MaterialType.transparency,
                  child: _BrandMoment(t: t),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The cue mark and wordmark, alone on the dark stage.
class _BrandMoment extends StatelessWidget {
  const _BrandMoment({required this.t});
  final double t;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final appear = _seg(t, 0, 0.32, Motion.glideEnter);
    final ignite = _seg(t, 0.1, 0.46, Curves.easeOutCubic);
    final line = _seg(t, 0.16, 0.48, const Cubic(0.16, 1, 0.3, 1));
    final word = _seg(t, 0.2, 0.46, Motion.glideEnter);
    final leave = _seg(t, 0.5, 0.74, Motion.leaveExit);

    final blur = 8 * (1 - appear) + 6 * leave;
    final bloom = 120 * (0.6 + 0.4 * ignite);
    Widget mark = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 140,
          height: 64,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // The lamp's bloom, flaring as it lights, then settling. The
              // lamp sits at (6, 16) of the mark's 32 × 32 box.
              Positioned(
                left: (140 - 64) / 2 + 64 * 6 / 32 - bloom / 2,
                top: 64 * 16 / 32 - bloom / 2,
                child: Container(
                  width: bloom,
                  height: bloom,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        p.primary.withValues(alpha: (p.isDark ? 0.55 : 0.4) * ignite * (1 - 0.45 * word)),
                        p.primary.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              Transform.scale(
                scale: 0.9 + 0.1 * appear,
                child: CueMark(size: 64, ink: p.inkPrimary, cue: p.primary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // A line of light draws out from the middle.
        SizedBox(
          width: 160,
          height: 2,
          child: Center(
            child: Container(
              width: 160 * line,
              height: 1.5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(1),
                gradient: LinearGradient(
                  colors: [p.primary.withValues(alpha: 0), p.primary, p.primary.withValues(alpha: 0)],
                ),
                boxShadow: [BoxShadow(color: p.primary.withValues(alpha: 0.6 * line), blurRadius: 8)],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Opacity(
          opacity: word,
          child: Text(
            'Sotto',
            style: withWeight(
              TypeScale.title2,
              600,
            ).copyWith(color: p.inkPrimary, letterSpacing: 10 * (1 - word) - 0.2, height: 1),
          ),
        ),
      ],
    );
    if (blur > 0.05) {
      mark = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur, tileMode: TileMode.decal),
        child: mark,
      );
    }
    return Align(
      alignment: const Alignment(0, -0.08),
      child: Opacity(
        opacity: (appear * (1 - leave)).clamp(0.0, 1.0),
        child: Transform.scale(scale: 1 + 0.08 * leave, child: mark),
      ),
    );
  }
}

// ─────────────────────────── Going live ───────────────────────────

/// House lights down, tally on: the window closes to black around the
/// middle, the tally lamp ignites there with its rings going out, and the
/// mode and script appear beneath it. Resolves when the stage is set, so
/// the caller can turn the window into the overlay in the dark, with a call
/// that lifts the dark again (needed only if the session didn't start — the
/// overlay otherwise replaces the whole window).
Future<VoidCallback> playGoLive(
  OverlayState overlay, {
  required bool rehearsal,
  required String label,
  required String title,
  required Color lamp,
  required bool still,
}) async {
  if (still) return () {};
  final done = Completer<void>();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _GoLive(
      label: label,
      title: title,
      lamp: lamp,
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
    ),
  );
  overlay.insert(entry);
  await done.future;
  return () {
    if (entry.mounted) entry.remove();
  };
}

class _GoLive extends StatefulWidget {
  const _GoLive({required this.label, required this.title, required this.lamp, required this.onDone});
  final String label;
  final String title;
  final Color lamp;
  final VoidCallback onDone;

  static const duration = Duration(milliseconds: 950);

  @override
  State<_GoLive> createState() => _GoLiveState();
}

class _GoLiveState extends State<_GoLive> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: _GoLive.duration)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    })
    ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static const _dark = Color(0xFF040507);

  @override
  Widget build(BuildContext context) => AbsorbPointer(
    child: Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final close = _seg(t, 0, 0.5, const Cubic(0.65, 0, 0.35, 1));
          final ignite = _seg(t, 0.34, 0.62, const Cubic(0.16, 1, 0.3, 1));
          final label = _seg(t, 0.42, 0.78, Motion.glideEnter);
          final title = _seg(t, 0.52, 0.86, Motion.glideEnter);
          final lamp = widget.lamp;
          return Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _IrisPainter(open: 1 - close, color: _dark),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: 120,
                      child: CustomPaint(
                        painter: _TallyPainter(
                          color: lamp,
                          ignite: ignite,
                          ring1: _seg(t, 0.38, 0.95),
                          ring2: _seg(t, 0.5, 1),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Opacity(
                      opacity: label,
                      child: Text(
                        widget.label.toUpperCase(),
                        style: TypeScale.mono.copyWith(
                          color: Color.lerp(lamp, const Color(0xFFFFFFFF), 0.25),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          letterSpacing: 4 + 10 * (1 - label),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Opacity(
                      opacity: title * 0.72,
                      child: Transform.translate(
                        offset: Offset(0, 6 * (1 - title)),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TypeScale.title3.copyWith(color: const Color(0xFFEEF1F6)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

/// The tally lamp: a bright core, a bloom, and two rings going out.
class _TallyPainter extends CustomPainter {
  _TallyPainter({required this.color, required this.ignite, required this.ring1, required this.ring2});
  final Color color;
  final double ignite, ring1, ring2;

  @override
  void paint(Canvas canvas, Size size) {
    if (ignite <= 0) return;
    final c = size.center(Offset.zero);
    final bloom = 48 * ignite;
    canvas.drawCircle(
      c,
      bloom,
      Paint()
        ..shader = ui.Gradient.radial(c, bloom, [color.withValues(alpha: 0.55 * ignite), color.withValues(alpha: 0)]),
    );
    for (final r in [ring1, ring2]) {
      if (r <= 0 || r >= 1) continue;
      final e = Curves.easeOutCubic.transform(r);
      canvas.drawCircle(
        c,
        7 + 50 * e,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4 * (1 - e) + 0.4
          ..color = color.withValues(alpha: 0.7 * (1 - e)),
      );
    }
    canvas.drawCircle(c, 7 * ignite, Paint()..color = color);
    canvas.drawCircle(c, 3 * ignite, Paint()..color = Color.lerp(color, const Color(0xFFFFFFFF), 0.6)!);
  }

  @override
  bool shouldRepaint(_TallyPainter old) =>
      old.ignite != ignite || old.ring1 != ring1 || old.ring2 != ring2 || old.color != color;
}

// ─────────────────────────── Overlay entrance ───────────────────────────

/// The overlay comes into focus out of the dark: it grows from just below
/// full size, sharpens from a blur, and a line of light runs along its top
/// edge once — the lamp over the reading desk switching on.
class OverlayEntrance extends StatefulWidget {
  const OverlayEntrance({super.key, required this.child, required this.enabled, this.sweep});

  final Widget child;
  final bool enabled;

  /// The top edge's light; null for none (text-only style has no edge).
  final Color? sweep;

  @override
  State<OverlayEntrance> createState() => _OverlayEntranceState();
}

class _OverlayEntranceState extends State<OverlayEntrance> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      _c.forward();
    } else {
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (context, child) {
      final t = _c.value;
      if (t >= 1) return child!;
      final e = _seg(t, 0, 0.6, const Cubic(0.16, 1, 0.3, 1));
      Widget out = Transform.scale(
        scale: 0.94 + 0.06 * e,
        alignment: Alignment.topCenter,
        child: Transform.translate(offset: Offset(0, 10 * (1 - e)), child: child),
      );
      final sigma = 10 * (1 - e);
      if (sigma > 0.05) {
        out = ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal),
          child: out,
        );
      }
      out = Opacity(opacity: _seg(t, 0, 0.35, Curves.easeOut), child: out);
      final sweep = widget.sweep;
      if (sweep == null) return out;
      final s = _seg(t, 0.25, 1, Curves.easeInOutCubic);
      return Stack(
        fit: StackFit.passthrough,
        children: [
          out,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: LayoutBuilder(
                builder: (context, box) {
                  const w = 180.0;
                  final x = -w + (box.maxWidth + w) * s;
                  return SizedBox(
                    height: 2,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: x,
                          width: w,
                          top: 0,
                          height: 1.5,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [sweep.withValues(alpha: 0), sweep, sweep.withValues(alpha: 0)],
                              ),
                              boxShadow: [
                                BoxShadow(color: sweep.withValues(alpha: 0.5 * math.sin(math.pi * s)), blurRadius: 10),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      );
    },
  );
}

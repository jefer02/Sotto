import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../design/theme.dart';
import '../design/tokens.dart';

/// The ground of the main window: an empty stage before the show. A ghost
/// light pours down from above in a slow, swaying beam, an indigo spill
/// breathes from the far corner, and dust drifts up through the light.
///
/// One loop of [period]; every motion is a whole number of cycles in it, so
/// the wrap is seamless.
///
/// Costs almost nothing at idle: it repaints [frame] apart from a plain
/// timer (no per-vsync ticker), and freezes on its last frame — never
/// blanks — while the window is hidden or unfocused, its route is offstage,
/// or motion is reduced (system or Settings › Appearance).
class StageGlow extends StatefulWidget {
  const StageGlow({super.key, required this.child, this.alignment = const Alignment(-0.35, -1.25)});

  final Widget child;

  /// Where the ghost light hangs.
  final Alignment alignment;

  static const period = Duration(seconds: 60);

  /// Everything drifts over tens of seconds, so ~15 repaints a second look
  /// as smooth as 60 and leave the frame budget to the UI.
  static const frame = Duration(milliseconds: 66);

  @override
  State<StageGlow> createState() => _StageGlowState();
}

class _StageGlowState extends State<StageGlow> {
  /// Position in the loop, 0–1.
  final _time = ValueNotifier<double>(0);
  final _clock = Stopwatch();
  Timer? _timer;
  late final AppLifecycleListener _lifecycle;
  bool _foreground = true;
  bool _still = false;
  bool _onstage = true;

  /// For tests: whether the light is moving.
  @visibleForTesting
  bool get running => _timer != null;

  @override
  void initState() {
    super.initState();
    final state = SchedulerBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    _lifecycle = AppLifecycleListener(
      onStateChange: (s) {
        _foreground = s == AppLifecycleState.resumed;
        _sync();
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _onstage = TickerMode.valuesOf(context).enabled;
    _sync();
  }

  void _sync() {
    final run = _foreground && _onstage && !_still;
    if (run && _timer == null) {
      _clock.start();
      _timer = Timer.periodic(StageGlow.frame, (_) {
        _time.value = (_clock.elapsedMicroseconds / StageGlow.period.inMicroseconds) % 1.0;
      });
    } else if (!run && _timer != null) {
      // Freeze where it is; resuming carries on from the same frame.
      _clock.stop();
      _timer!.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _StagePainter(time: _time, palette: p, source: widget.alignment),
            ),
          ),
        ),
        // The page repaints on its own layer, never with the light.
        RepaintBoundary(child: widget.child),
      ],
    );
  }
}

/// One mote of dust: where it starts (0–1 of the stage), how it moves.
class _Mote {
  _Mote(math.Random r)
    : x = r.nextDouble(),
      y = r.nextDouble(),
      radius = 0.6 + r.nextDouble() * 1.4,
      rise = 1 + r.nextInt(2),
      sway = 4 + r.nextDouble() * 14,
      swayCycles = 1 + r.nextInt(3),
      twinkleCycles = 3 + r.nextInt(6),
      phase = r.nextDouble() * math.pi * 2;

  final double x, y, radius, sway, phase;

  /// Whole trips up the stage, sway and twinkle cycles per loop.
  final int rise, swayCycles, twinkleCycles;
}

class _StagePainter extends CustomPainter {
  _StagePainter({required this.time, required this.palette, required this.source}) : super(repaint: time);

  final ValueListenable<double> time;
  final SottoPalette palette;
  final Alignment source;

  static final _motes = List.generate(42, (_) => _Mote(_seed));
  static final _seed = math.Random(7);

  @override
  void paint(Canvas canvas, Size size) {
    final p = palette;
    final t = time.value;
    final turn = t * math.pi * 2;
    final rect = Offset.zero & size;

    canvas.drawRect(rect, Paint()..color = p.ground);

    // Light doesn't show on a white stage, so the light theme paints with
    // tinted color instead: deeper pools, a cool beam, blue dust.
    final dark = p.isDark;
    final poolColor = dark ? p.stageGlow : p.primary.withValues(alpha: 0.17);
    final spillColor = dark ? p.depthGlow : p.cueDeep.withValues(alpha: 0.13);

    // The ghost light: its pool drifts a little and breathes.
    final pool = Alignment(source.x + 0.07 * math.sin(turn), source.y + 0.04 * math.cos(turn * 2));
    final breathe = 1 + 0.12 * math.sin(turn * 3);
    _radial(canvas, rect, pool, 1.15 + 0.05 * math.sin(turn * 2), poolColor, breathe);

    // The far, lower indigo spill sways the other way.
    final spill = Alignment(1.1 - 0.08 * math.sin(turn), 1.2 - 0.05 * math.cos(turn));
    _radial(canvas, rect, spill, 1.0, spillColor, 1 + 0.15 * math.cos(turn * 2));

    // A third, faint lamp crosses the back of the stage once per loop.
    final wander = Alignment(math.cos(turn) * 0.9, 0.15 + 0.35 * math.sin(turn * 2));
    _radial(canvas, rect, wander, 0.7, p.cueDeep.withValues(alpha: dark ? 0.05 : 0.08), 1);

    // The beam: a soft cone from the light, swaying a few degrees.
    final apex = pool.alongSize(size);
    final angle = 0.38 + 0.05 * math.sin(turn * 2);
    final reach = size.longestSide * 1.1;
    canvas.save();
    canvas.translate(apex.dx, apex.dy);
    canvas.rotate(-angle);
    final cone = Path()
      ..moveTo(-24, 0)
      ..lineTo(24, 0)
      ..lineTo(reach * 0.34, reach)
      ..lineTo(-reach * 0.34, reach)
      ..close();
    final beamRect = Rect.fromLTRB(-reach * 0.34, 0, reach * 0.34, reach);
    final beam = p.primary.withValues(alpha: (dark ? 0.075 : 0.11) * breathe);
    canvas.saveLayer(beamRect, Paint());
    // Soft sides…
    canvas.drawPath(
      cone,
      Paint()
        ..shader = LinearGradient(
          colors: [beam.withValues(alpha: 0), beam, beam.withValues(alpha: 0)],
          stops: const [0.18, 0.5, 0.82],
        ).createShader(beamRect),
    );
    // …fading as it falls.
    canvas.drawRect(
      beamRect,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFFFF), Color(0x66FFFFFF), Color(0x00FFFFFF)],
          stops: [0, 0.45, 1],
        ).createShader(beamRect),
    );
    canvas.restore();
    canvas.restore();

    // Dust in the light: brightest where the beam is.
    final dust = dark ? const Color(0xFFDCE6FF) : p.primary;
    final paint = Paint();
    for (final m in _motes) {
      final y = (m.y - t * m.rise) % 1.0;
      final x = m.x + m.sway / size.width * math.sin(turn * m.swayCycles + m.phase);
      final at = Offset(x * size.width, y * size.height);
      final lit = 1 - ((at - apex).distance / size.longestSide).clamp(0.0, 1.0);
      final twinkle = 0.5 + 0.5 * math.sin(turn * m.twinkleCycles + m.phase);
      final alpha = (dark ? 0.34 : 0.42) * lit * lit * (0.35 + 0.65 * twinkle);
      if (alpha < 0.01) continue;
      canvas.drawCircle(at, dark ? m.radius : m.radius * 1.25, paint..color = dust.withValues(alpha: alpha));
    }
  }

  void _radial(Canvas canvas, Rect rect, Alignment center, double radius, Color color, double gain) {
    final c = color.withValues(alpha: (color.a * gain).clamp(0.0, 1.0));
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: center,
          radius: radius,
          colors: [c, c.withValues(alpha: 0)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_StagePainter old) => old.palette != palette || old.source != source;
}

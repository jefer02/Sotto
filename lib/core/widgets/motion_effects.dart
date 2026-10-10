import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../design/tokens.dart';

bool _still(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// While a curtain still covers the window, entrances wait for it to open.
abstract final class Entrance {
  static DateTime _until = DateTime.fromMillisecondsSinceEpoch(0);

  static void holdUntil(DateTime t) => _until = t;

  /// How much longer anything revealed now should wait.
  static Duration get hold {
    final left = _until.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }
}

/// Comes into focus once, when first built: rises a few pixels, fades in and
/// sharpens from a blur. [delay] staggers a group. No timers — the delay is
/// the head of one animation, so nothing is left pending.
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = Motion.settle,
    this.rise = 12,
    this.blur = 6,
    this.enabled = true,
  });

  final Widget child;

  /// False shows the child at once — for anything that isn't a first look.
  final bool enabled;
  final Duration delay;
  final Duration duration;

  /// Pixels it rises from.
  final double rise;

  /// Blur sigma it sharpens from; 0 for none.
  final double blur;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  // Taken when first used, so a curtain that's still up adds to the delay.
  late final _delay = widget.delay + (widget.enabled ? Entrance.hold : Duration.zero);
  late final _c = AnimationController(vsync: this, duration: _delay + widget.duration);
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: Interval(_delay.inMicroseconds / (_delay + widget.duration).inMicroseconds, 1, curve: Motion.glideEnter),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_still(context) || !widget.enabled) {
      _c.value = 1;
    } else if (_c.isDismissed) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _t,
    child: widget.child,
    builder: (context, child) {
      final t = _t.value;
      if (t >= 1) return child!;
      Widget out = Transform.translate(offset: Offset(0, widget.rise * (1 - t)), child: child);
      final sigma = widget.blur * (1 - t);
      if (sigma > 0.05) {
        out = ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal),
          child: out,
        );
      }
      return Opacity(opacity: t, child: out);
    },
  );
}

/// A line of text whose words come into focus one after another.
class RevealWords extends StatelessWidget {
  const RevealWords(
    this.text, {
    super.key,
    required this.style,
    this.delay = Duration.zero,
    this.stagger = const Duration(milliseconds: 60),
    this.enabled = true,
  });

  final String text;
  final bool enabled;
  final TextStyle style;
  final Duration delay;
  final Duration stagger;

  @override
  Widget build(BuildContext context) {
    final words = text.split(' ');
    return Semantics(
      label: text,
      child: ExcludeSemantics(
        child: Wrap(
          children: [
            for (var i = 0; i < words.length; i++)
              Reveal(
                enabled: enabled,
                delay: delay + stagger * i,
                rise: 18,
                blur: 10,
                child: Text(i == words.length - 1 ? words[i] : '${words[i]} ', style: style),
              ),
          ],
        ),
      ),
    );
  }
}

/// A soft pool of [color] that follows the pointer across its child — the
/// card catches the light where you point. Paints over the child without
/// taking any of its pointer events.
class CursorSpotlight extends StatefulWidget {
  const CursorSpotlight({
    super.key,
    required this.child,
    required this.color,
    this.radius = 220,
    this.borderRadius = Radii.rL,
  });

  final Widget child;
  final Color color;
  final double radius;
  final BorderRadius borderRadius;

  @override
  State<CursorSpotlight> createState() => _CursorSpotlightState();
}

class _CursorSpotlightState extends State<CursorSpotlight> {
  final _at = ValueNotifier<Offset?>(null);
  bool _in = false;

  @override
  void dispose() {
    _at.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_still(context)) return widget.child;
    return MouseRegion(
      opaque: false,
      onEnter: (e) {
        _at.value = e.localPosition;
        setState(() => _in = true);
      },
      onHover: (e) => _at.value = e.localPosition,
      onExit: (_) => setState(() => _in = false),
      child: Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                duration: _in ? Motion.smooth : Motion.glide,
                curve: Motion.glideEnter,
                opacity: _in ? 1 : 0,
                child: ClipRRect(
                  borderRadius: widget.borderRadius,
                  child: CustomPaint(
                    painter: _SpotPainter(at: _at, color: widget.color, radius: widget.radius),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotPainter extends CustomPainter {
  _SpotPainter({required this.at, required this.color, required this.radius}) : super(repaint: at);
  final ValueListenable<Offset?> at;
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final c = at.value;
    if (c == null) return;
    canvas.drawCircle(c, radius, Paint()..shader = ui.Gradient.radial(c, radius, [color, color.withValues(alpha: 0)]));
  }

  @override
  bool shouldRepaint(_SpotPainter old) => old.color != color || old.radius != radius;
}

/// A spark of light that runs around the border of its child, trailing a
/// fading tail — the featured card is "on". One lap per [period].
class BorderBeam extends StatefulWidget {
  const BorderBeam({
    super.key,
    required this.child,
    required this.color,
    this.borderRadius = Radii.rL,
    this.period = const Duration(seconds: 7),
    this.length = 0.18,
  });

  final Widget child;
  final Color color;
  final BorderRadius borderRadius;
  final Duration period;

  /// The beam's share of the perimeter.
  final double length;

  @override
  State<BorderBeam> createState() => _BorderBeamState();
}

class _BorderBeamState extends State<BorderBeam> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: widget.period);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_still(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_still(context)) return widget.child;
    return CustomPaint(
      foregroundPainter: _BeamPainter(
        time: _c,
        color: widget.color,
        radius: widget.borderRadius,
        length: widget.length,
      ),
      child: widget.child,
    );
  }
}

class _BeamPainter extends CustomPainter {
  _BeamPainter({required this.time, required this.color, required this.radius, required this.length})
    : super(repaint: time);

  final Animation<double> time;
  final Color color;
  final BorderRadius radius;
  final double length;

  static const _slices = 14;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = radius.toRRect((Offset.zero & size).deflate(0.5));
    final metric = (Path()..addRRect(rrect)).computeMetrics().first;
    final total = metric.length;
    final span = total * length;
    final head = time.value * total;

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    // The tail in slices, brightening toward the head.
    for (var i = 0; i < _slices; i++) {
      final a = (i + 1) / _slices;
      final from = head - span + span * i / _slices;
      final to = head - span + span * (i + 1) / _slices;
      final piece = _extract(metric, from, to, total);
      final strength = math.pow(a, 1.6).toDouble();
      canvas.drawPath(piece, glow..color = color.withValues(alpha: 0.55 * strength));
      canvas.drawPath(
        piece,
        line..color = Color.lerp(color, const Color(0xFFFFFFFF), 0.35 * a)!.withValues(alpha: strength),
      );
    }
  }

  /// A piece of the perimeter, wrapping past the start.
  static Path _extract(ui.PathMetric m, double from, double to, double total) {
    final a = from % total, b = to % total;
    if (a <= b) return m.extractPath(a, b);
    return m.extractPath(a, total)..addPath(m.extractPath(0, b), Offset.zero);
  }

  @override
  bool shouldRepaint(_BeamPainter old) => old.color != color || old.radius != radius || old.length != length;
}

/// Lifts its child a couple of pixels while [lifted], as if picked up.
class HoverLift extends StatelessWidget {
  const HoverLift({super.key, required this.lifted, required this.child, this.by = 3});

  final bool lifted;
  final Widget child;
  final double by;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: lifted ? -by : 0),
    duration: _still(context) ? Duration.zero : Motion.smooth,
    curve: Motion.glideEnter,
    child: child,
    builder: (context, dy, child) => Transform.translate(offset: Offset(0, dy), child: child),
  );
}

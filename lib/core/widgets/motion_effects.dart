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

/// Comes into focus once, when first built: rises a few pixels and fades in
/// (sharpening from a blur when [blur] is set). [delay] staggers a group. No timers — the delay is
/// the head of one animation, so nothing is left pending.
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = Motion.settle,
    this.rise = 8,
    this.blur = 0,
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
    // One shape from start to end — a wrapper that came or went would
    // rebuild the child from scratch mid-entrance.
    builder: (context, child) {
      final t = _t.value;
      final sigma = widget.blur * (1 - t);
      // A FadeTransition leaves no layer behind once fully shown.
      return FadeTransition(
        opacity: _t,
        child: Transform.translate(
          offset: Offset(0, widget.rise * (1 - t)),
          child: ImageFiltered(
            enabled: sigma > 0.05,
            imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal),
            child: child,
          ),
        ),
      );
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
    this.stagger = Motion.introStep,
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
                rise: 8,
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
                // The light follows the pointer on its own layer.
                child: RepaintBoundary(
                  child: ClipRRect(
                    borderRadius: widget.borderRadius,
                    child: CustomPaint(
                      painter: _SpotPainter(at: _at, color: widget.color, radius: widget.radius),
                    ),
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
/// fading tail — the featured card is "on". It runs [laps] laps when the
/// card first appears, then only while the pointer is over it, and fades
/// out between; at rest it costs nothing. One rotating sweep gradient on a
/// single stroke, on its own layer.
class BorderBeam extends StatefulWidget {
  const BorderBeam({
    super.key,
    required this.child,
    required this.color,
    this.borderRadius = Radii.rL,
    this.period = Motion.beamLap,
    this.length = 0.18,
    this.laps = 2,
  });

  final Widget child;
  final Color color;
  final BorderRadius borderRadius;
  final Duration period;

  /// The beam's share of the perimeter.
  final double length;

  /// Laps run on first appearance.
  final int laps;

  @override
  State<BorderBeam> createState() => _BorderBeamState();
}

class _BorderBeamState extends State<BorderBeam> with TickerProviderStateMixin {
  late final _spin = AnimationController(vsync: this, duration: widget.period);
  late final _shown = AnimationController(vsync: this, duration: Motion.panel);
  int _lapsLeft = 0;
  bool _hovered = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _lapsLeft = widget.laps;
    _spin.addStatusListener((s) {
      if (s != AnimationStatus.completed) return;
      if (_lapsLeft > 0) _lapsLeft--;
      _next();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_still(context)) {
      _spin.stop();
      _shown.value = 0;
    } else if (!_started) {
      _started = true;
      _next();
    }
  }

  /// Another lap while there are intro laps left or the pointer is over it;
  /// otherwise fade out and rest.
  void _next() {
    if (!mounted || _still(context)) return;
    if (_lapsLeft > 0 || _hovered) {
      _shown.forward();
      _spin.forward(from: 0);
    } else {
      _shown.reverse();
    }
  }

  void _hover(bool on) {
    _hovered = on;
    if (on && !_spin.isAnimating) _next();
  }

  @override
  void dispose() {
    _spin.dispose();
    _shown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_still(context)) return widget.child;
    return MouseRegion(
      opaque: false,
      onEnter: (_) => _hover(true),
      onExit: (_) => _hover(false),
      child: CustomPaint(
        foregroundPainter: _BeamPainter(
          time: _spin,
          shown: _shown,
          color: widget.color,
          radius: widget.borderRadius,
          length: widget.length,
        ),
        child: RepaintBoundary(child: widget.child),
      ),
    );
  }
}

class _BeamPainter extends CustomPainter {
  _BeamPainter({
    required this.time,
    required this.shown,
    required this.color,
    required this.radius,
    required this.length,
  }) : super(repaint: Listenable.merge([time, shown]));

  final Animation<double> time;
  final Animation<double> shown;
  final Color color;
  final BorderRadius radius;
  final double length;

  @override
  void paint(Canvas canvas, Size size) {
    final alpha = Motion.standard.transform(shown.value);
    if (alpha <= 0.01) return;
    final rect = Offset.zero & size;
    final rrect = radius.toRRect(rect.deflate(0.5));
    final turn = time.value * math.pi * 2;
    // Tail → head over [length] of a turn, then nothing for the rest.
    final head = Color.lerp(color, const Color(0xFFFFFFFF), 0.35)!;
    final shader = SweepGradient(
      colors: [
        color.withValues(alpha: 0),
        color.withValues(alpha: 0.9 * alpha),
        head.withValues(alpha: alpha),
        color.withValues(alpha: 0),
      ],
      stops: [0, length * 0.85, length, length + 0.001],
      transform: GradientRotation(turn - math.pi / 2),
    ).createShader(rect);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
        ..shader = shader,
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = shader,
    );
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

/// Gives a little under the pointer while [pressed]: shrinks to [scale] and
/// springs back on release.
class PressScale extends StatelessWidget {
  const PressScale({super.key, required this.pressed, required this.child, this.scale = 0.98});

  final bool pressed;
  final Widget child;
  final double scale;

  @override
  Widget build(BuildContext context) => AnimatedScale(
    scale: pressed ? scale : 1,
    duration: _still(context) ? Duration.zero : Motion.press,
    curve: Motion.standard,
    child: child,
  );
}

/// Content that changes in place (a filter, grid to list, empty to
/// filled): the old content goes at once and the new fades in. Key [child]
/// by what it shows. The first child shows without animating.
class FadeSwitch extends StatelessWidget {
  const FadeSwitch({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: _still(context) ? Duration.zero : Motion.snappy,
    reverseDuration: Duration.zero,
    switchInCurve: Motion.fade,
    // Only the incoming child is laid out, so the old one is never shown
    // alongside it.
    layoutBuilder: (current, previous) => current ?? const SizedBox.shrink(),
    child: child,
  );
}

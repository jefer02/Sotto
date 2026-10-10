import 'package:flutter/material.dart';

/// A dot that sends out a fading ring every 1.8 s — "this is happening right
/// now". Still when [active] is false or the system asks for less motion.
/// Adapted from ObsidianUI's status ping (MIT, obsidianui.dev).
class PingDot extends StatefulWidget {
  const PingDot({super.key, required this.color, this.size = 8, this.active = true});

  final Color color;
  final double size;
  final bool active;

  static const period = Duration(milliseconds: 1800);

  /// The ring grows to this multiple of the dot, as in the original.
  static const reach = 2.4;

  @override
  State<PingDot> createState() => _PingDotState();
}

class _PingDotState extends State<PingDot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: PingDot.period);

  // 0 → 75 % of the period: grow and fade; the rest is a pause.
  static const _curve = Interval(0, 0.75, curve: Cubic(0, 0, 0.2, 1));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(PingDot old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final run = widget.active && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (run && !_c.isAnimating) {
      _c.repeat();
    } else if (!run && _c.isAnimating) {
      _c.reset();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = DecoratedBox(
      decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
    );
    return SizedBox.square(
      dimension: widget.size,
      child: Stack(
        clipBehavior: Clip.none,
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (context, child) {
              if (!_c.isAnimating) return const SizedBox.shrink();
              final t = _curve.transform(_c.value);
              return Opacity(
                opacity: 0.6 * (1 - t),
                child: Transform.scale(scale: 1 + (PingDot.reach - 1) * t, child: child),
              );
            },
            child: dot,
          ),
          dot,
        ],
      ),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// The script's scroll offset. It glides to wherever the reading position
/// is on one ticker, as a critically damped spring: fast when the target is
/// far, slowing into it, never past it — reading text must not drift back.
/// A new target keeps the current velocity, so the speed follows the
/// presenter's pace instead of starting over at every word.
///
/// This is the script moving because the presenter spoke — content, like
/// the voice meter, not decoration — so reduced motion makes it calmer
/// (a softer spring, smaller steps), never instant.
class ScriptScroll extends ValueNotifier<double> {
  ScriptScroll(TickerProvider vsync) : super(0) {
    _ticker = vsync.createTicker(_tick);
  }

  late final Ticker _ticker;
  double _target = 0;
  double _velocity = 0;
  Duration _last = Duration.zero;
  double _omega = normalOmega;
  double _floor = 18;

  /// Spring stiffness as angular frequency (1/s): settles in ≈ 4.7 / ω —
  /// about half a second normally, a little over one under reduced motion.
  static const normalOmega = 9.0;
  static const calmOmega = 4.0;

  /// Where the offset is heading.
  double get target => _target;
  bool get moving => _ticker.isActive;

  /// Places the offset at once — only before anything is shown.
  void jumpTo(double offset) {
    _ticker.stop();
    _target = offset;
    _velocity = 0;
    value = offset;
  }

  /// Glides to [offset]. [line]: the text's line height — normal reading
  /// moves at most about a line per frame ([calm]: a third of one); a far
  /// move (a relock, a manual jump) is spread over at least ~30 frames.
  void glideTo(double offset, {required bool calm, required double line}) {
    _target = offset;
    _omega = calm ? calmOmega : normalOmega;
    _floor = line * (calm ? 0.35 : 0.75);
    if ((value - offset).abs() < 0.3 && _velocity.abs() < 3) {
      value = offset;
      return;
    }
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    // A stalled frame must not become one long step.
    final dt = math.min((elapsed - _last).inMicroseconds / 1e6, 1 / 20);
    _last = elapsed;
    if (dt <= 0) return;
    final w = _omega;
    final e0 = value - _target;
    final v0 = _velocity;
    // Exact critically damped motion over dt: e(t) = (e0 + (v0 + ω·e0)·t)·e^(−ωt).
    final decay = math.exp(-w * dt);
    var e = (e0 + (v0 + w * e0) * dt) * decay;
    var v = (v0 - w * (v0 + w * e0) * dt) * decay;
    // Never past the target.
    if (e0 != 0 && e != 0 && e.sign != e0.sign) {
      e = 0;
      v = 0;
    }
    var step = e - e0;
    final maxStep = math.max(_floor, e0.abs() / 30);
    if (step.abs() > maxStep) {
      step = maxStep * step.sign;
      v = step / dt;
    }
    _velocity = v;
    final next = value + step;
    if ((next - _target).abs() < 0.3 && v.abs() < 3) {
      _velocity = 0;
      value = _target;
      _ticker.stop();
    } else {
      value = next;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

import 'dart:async';

/// A periodic tick that never overlaps itself: a tick that comes due while
/// the previous one is still running is dropped — not queued — so a slow
/// screen read can't pile up work behind it. The interval can change while
/// it runs (battery saver).
class SkippingTicker {
  SkippingTicker(this._onTick, {this._interval = const Duration(milliseconds: 1500)});

  final Future<void> Function() _onTick;
  Duration _interval;
  Timer? _timer;
  bool _running = false;
  int _skipped = 0;

  Duration get interval => _interval;
  bool get active => _timer != null;

  /// A tick is in progress.
  bool get running => _running;

  /// Ticks dropped because the previous one hadn't finished.
  int get skipped => _skipped;

  set interval(Duration d) {
    if (d == _interval) return;
    _interval = d;
    if (active) start();
  }

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => unawaited(tick()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// One tick now, unless one is already running. True when it ran.
  Future<bool> tick() async {
    if (_running) {
      _skipped++;
      return false;
    }
    _running = true;
    try {
      await _onTick();
    } finally {
      _running = false;
    }
    return true;
  }
}

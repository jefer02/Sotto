import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Profile builds only, opt-in:
///   flutter run --profile -d windows --dart-define=SOTTO_FRAME_STATS=true
/// Every few seconds it prints, per screen, how many frames were drawn and
/// their build / raster times at p50, p90 and max, flagging any frame over
/// the 16 ms budget:
///   [frames] home: 42 frames · build p50 1.2 p90 2.0 max 3.1 · raster p50 2.4 p90 3.8 max 6.0 ms · 0 over 16 ms
abstract final class FrameStats {
  static const enabled = kProfileMode && bool.fromEnvironment('SOTTO_FRAME_STATS');

  static const budget = Duration(milliseconds: 16);
  static const window = Duration(seconds: 5);

  /// What's on screen: a route, or "overlay" in a session.
  static String label = 'start';

  static final _build = <String, List<int>>{};
  static final _raster = <String, List<int>>{};
  static Timer? _timer;

  static void start() {
    if (!enabled || _timer != null) return;
    SchedulerBinding.instance.addTimingsCallback(_record);
    _timer = Timer.periodic(window, (_) => report());
  }

  static void _record(List<FrameTiming> timings) {
    for (final t in timings) {
      (_build[label] ??= []).add(t.buildDuration.inMicroseconds);
      (_raster[label] ??= []).add(t.rasterDuration.inMicroseconds);
    }
  }

  /// Prints and clears what was gathered since the last report.
  static void report() {
    for (final screen in _build.keys) {
      final b = _build[screen]!, r = _raster[screen]!;
      if (b.isEmpty) continue;
      final over = [
        for (var i = 0; i < b.length; i++)
          if (math.max(b[i], r[i]) > budget.inMicroseconds) i,
      ].length;
      debugPrint(
        '[frames] $screen: ${b.length} frames · build ${summarize(b)} · raster ${summarize(r)} ms · '
        '$over over ${budget.inMilliseconds} ms',
      );
    }
    _build.clear();
    _raster.clear();
  }

  /// "p50 1.2 p90 2.0 max 3.1" for durations in microseconds.
  @visibleForTesting
  static String summarize(List<int> micros) {
    final s = [...micros]..sort();
    String ms(int us) => (us / 1000).toStringAsFixed(1);
    int at(double q) => s[math.min(s.length - 1, (q * s.length).floor())];
    return 'p50 ${ms(at(0.5))} p90 ${ms(at(0.9))} max ${ms(s.last)}';
  }
}

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/core/utils/skipping_ticker.dart';

void main() {
  test('a tick still running makes the next ones skip — none queue up behind it', () {
    fakeAsync((time) {
      var started = 0;
      var finished = 0;
      // Each read takes 4 s: longer than two intervals.
      final ticker = SkippingTicker(() async {
        started++;
        await Future<void>.delayed(const Duration(seconds: 4));
        finished++;
      }, interval: const Duration(milliseconds: 1500));

      ticker.start();
      time.elapse(const Duration(milliseconds: 1500)); // t=1.5: tick 1 starts
      expect(started, 1);
      time.elapse(const Duration(milliseconds: 3000)); // t=3.0 and 4.5 come due while it runs
      expect(started, 1);
      expect(ticker.skipped, 2);
      time.elapse(const Duration(milliseconds: 1000)); // t=5.5: tick 1 done, nothing replayed
      expect(finished, 1);
      expect(started, 1, reason: 'skipped ticks are dropped, not queued');
      expect(ticker.running, isFalse);
      time.elapse(const Duration(milliseconds: 500)); // t=6.0: the next regular tick
      expect(started, 2);
      ticker.stop();
    });
  });

  test('a manual tick while one runs is skipped too', () {
    fakeAsync((time) {
      final gate = Completer<void>();
      var runs = 0;
      final ticker = SkippingTicker(() async {
        runs++;
        await gate.future;
      });
      bool? first;
      bool? second;
      ticker.tick().then((r) => first = r);
      ticker.tick().then((r) => second = r);
      time.flushMicrotasks();
      expect(second, isFalse);
      gate.complete();
      time.flushMicrotasks();
      expect(first, isTrue);
      expect(runs, 1);
    });
  });

  test('a tick that throws frees the ticker for the next one', () {
    fakeAsync((time) {
      var runs = 0;
      final ticker = SkippingTicker(() async {
        runs++;
        throw StateError('read failed');
      });
      ticker.tick().catchError((Object _) => false);
      time.flushMicrotasks();
      expect(ticker.running, isFalse);
      ticker.tick().catchError((Object _) => false);
      time.flushMicrotasks();
      expect(runs, 2);
    });
  });

  test('battery saver: the interval changes while it runs (1.5 s → 3 s)', () {
    fakeAsync((time) {
      var runs = 0;
      final ticker = SkippingTicker(() async => runs++, interval: const Duration(milliseconds: 1500));
      ticker.start();
      time.elapse(const Duration(seconds: 3));
      expect(runs, 2);
      ticker.interval = const Duration(seconds: 3);
      time.elapse(const Duration(seconds: 6));
      expect(runs, 4);
      ticker.stop();
      time.elapse(const Duration(seconds: 6));
      expect(runs, 4);
    });
  });
}

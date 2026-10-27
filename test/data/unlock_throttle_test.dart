import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/data/lock/throttle.dart';

void main() {
  late Directory dir;
  late File file;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('sotto_throttle');
    file = File('${dir.path}/lock_attempts.json');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('the delay grows after five failures and tops out at an hour', () {
    expect([for (var i = 0; i <= 4; i++) UnlockThrottle.delayAfter(i)], everyElement(Duration.zero));
    expect(UnlockThrottle.delayAfter(5), const Duration(seconds: 30));
    expect(UnlockThrottle.delayAfter(6), const Duration(minutes: 1));
    expect(UnlockThrottle.delayAfter(7), const Duration(minutes: 5));
    expect(UnlockThrottle.delayAfter(8), const Duration(minutes: 15));
    expect(UnlockThrottle.delayAfter(9), const Duration(hours: 1));
    expect(UnlockThrottle.delayAfter(40), const Duration(hours: 1));
  });

  test('blocks after the fifth failure and lets the next try through once the wait is over', () {
    fakeAsync((async) {
      final clock = async.getClock(DateTime(2026, 10, 27, 9));
      final t = UnlockThrottle(file, now: clock.now);
      for (var i = 0; i < 4; i++) {
        t.recordFailure();
        async.flushMicrotasks();
        expect(t.blocked, isFalse, reason: 'failure ${i + 1} is free');
      }
      t.recordFailure();
      async.flushMicrotasks();
      expect(t.blocked, isTrue);
      expect(t.remaining, const Duration(seconds: 30));

      async.elapse(const Duration(seconds: 29));
      expect(t.remaining, const Duration(seconds: 1));
      async.elapse(const Duration(seconds: 1));
      expect(t.blocked, isFalse);

      t.recordFailure();
      async.flushMicrotasks();
      expect(t.remaining, const Duration(minutes: 1));
    });
  });

  test('survives a restart', () async {
    final now = DateTime(2026, 10, 27, 9);
    final first = UnlockThrottle(file, now: () => now);
    for (var i = 0; i < 6; i++) {
      await first.recordFailure();
    }

    final again = UnlockThrottle(file, now: () => now.add(const Duration(seconds: 20)));
    await again.load();
    expect(again.failures, 6);
    expect(again.remaining, const Duration(seconds: 40));
  });

  test('success resets and removes the file', () async {
    final t = UnlockThrottle(file);
    for (var i = 0; i < 5; i++) {
      await t.recordFailure();
    }
    expect(t.blocked, isTrue);
    await t.recordSuccess();
    expect(t.failures, 0);
    expect(t.blocked, isFalse);
    expect(file.existsSync(), isFalse);
  });

  test('a damaged file starts from zero', () async {
    file.writeAsStringSync('not json');
    final t = UnlockThrottle(file);
    await t.load();
    expect(t.failures, 0);
    expect(t.blocked, isFalse);
  });

  test('a far-future wait (clock set back) is capped at the longest step', () async {
    final now = DateTime(2026, 10, 27, 9);
    file.writeAsStringSync(
      '{"failures": 9, "until": "${now.add(const Duration(days: 30)).toUtc().toIso8601String()}"}',
    );
    final t = UnlockThrottle(file, now: () => now);
    await t.load();
    expect(t.remaining, const Duration(hours: 1));
  });
}

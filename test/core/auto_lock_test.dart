import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/app/auto_lock.dart';

void main() {
  const timeout = Duration(minutes: 15);

  ({AutoLock auto, List<DateTime> locks}) make(FakeAsync async, {Duration t = timeout}) {
    final clock = async.getClock(DateTime(2026, 10, 27, 9));
    final locks = <DateTime>[];
    final auto = AutoLock(timeout: t, onLock: () => locks.add(clock.now()), now: clock.now);
    return (auto: auto, locks: locks);
  }

  test('locks after the timeout without input', () {
    fakeAsync((async) {
      final (:auto, :locks) = make(async);
      async.elapse(const Duration(minutes: 14, seconds: 59));
      expect(locks, isEmpty);
      async.elapse(const Duration(seconds: 1));
      expect(locks, hasLength(1));
      auto.dispose();
    });
  });

  test('input restarts the count', () {
    fakeAsync((async) {
      final (:auto, :locks) = make(async);
      async.elapse(const Duration(minutes: 10));
      auto.activity();
      async.elapse(const Duration(minutes: 10));
      expect(locks, isEmpty);
      async.elapse(const Duration(minutes: 5));
      expect(locks, hasLength(1));
    });
  });

  test('never during a live session, and right after it if the time is up', () {
    fakeAsync((async) {
      final (:auto, :locks) = make(async);
      auto.busy = true; // going live
      async.elapse(const Duration(hours: 1));
      expect(locks, isEmpty, reason: 'a 45-minute talk overran the timeout');
      auto.busy = false; // the session ended
      async.flushMicrotasks();
      expect(locks, hasLength(1));
    });
  });

  test('a session that ends before the timeout leaves the rest of the count', () {
    fakeAsync((async) {
      final (:auto, :locks) = make(async);
      auto.busy = true;
      async.elapse(const Duration(minutes: 5));
      auto.busy = false;
      expect(locks, isEmpty);
      async.elapse(const Duration(minutes: 10));
      expect(locks, hasLength(1));
    });
  });

  test('Off never locks; changing the timeout applies at once', () {
    fakeAsync((async) {
      final (:auto, :locks) = make(async, t: Duration.zero);
      async.elapse(const Duration(hours: 5));
      expect(locks, isEmpty);
      auto.timeout = const Duration(minutes: 5);
      // Five idle hours already: it locks straight away.
      async.flushTimers();
      expect(locks, hasLength(1));
    });
  });

  test('locks once, and not after dispose', () {
    fakeAsync((async) {
      final (:auto, :locks) = make(async, t: const Duration(minutes: 5));
      async.elapse(const Duration(hours: 1));
      expect(locks, hasLength(1));
      auto.activity();
      async.elapse(const Duration(hours: 1));
      expect(locks, hasLength(1));

      final other = make(async);
      other.auto.dispose();
      async.elapse(const Duration(hours: 1));
      expect(other.locks, isEmpty);
    });
  });
}

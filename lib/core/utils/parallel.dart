import 'dart:async';
import 'dart:math' as math;

/// Runs [task] for every item, at most [concurrency] at a time, in order of
/// [items]. Completes when all have finished; the first error is rethrown
/// only after the others settle, so nothing is left running.
Future<void> forEachParallel<T>(List<T> items, int concurrency, Future<void> Function(T item) task) async {
  var next = 0;
  Object? error;
  StackTrace? stack;
  Future<void> worker() async {
    while (next < items.length) {
      final item = items[next++];
      try {
        await task(item);
      } catch (e, s) {
        error ??= e;
        stack ??= s;
      }
    }
  }

  await Future.wait([for (var i = 0; i < math.min(concurrency, items.length); i++) worker()]);
  if (error != null) Error.throwWithStackTrace(error!, stack!);
}

/// Exponential backoff: [base], 2 × [base], 4 × [base]… plus up to 25 %
/// jitter, for at most [maxAttempts] tries in all.
class RetryPolicy {
  const RetryPolicy({this.maxAttempts = 4, this.base = const Duration(milliseconds: 600)});

  final int maxAttempts;
  final Duration base;

  Duration delayFor(int attempt, math.Random random) {
    final ms = base.inMilliseconds * math.pow(2, attempt - 1);
    return Duration(milliseconds: (ms * (1 + random.nextDouble() * 0.25)).round());
  }
}

/// Calls [fn] until it succeeds, [retryIf] says an error is final, or the
/// policy runs out. [sleep] is injectable for tests.
Future<T> withRetry<T>(
  Future<T> Function() fn, {
  required bool Function(Object error) retryIf,
  RetryPolicy policy = const RetryPolicy(),
  Future<void> Function(Duration)? sleep,
  math.Random? random,
}) async {
  final rng = random ?? math.Random();
  for (var attempt = 1; ; attempt++) {
    try {
      return await fn();
    } catch (e) {
      if (attempt >= policy.maxAttempts || !retryIf(e)) rethrow;
      await (sleep ?? Future<void>.delayed)(policy.delayFor(attempt, rng));
    }
  }
}

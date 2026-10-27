import 'dart:convert';
import 'dart:io';

import 'atomic_file.dart';

/// Slows down guessing at the unlock screen: the first [freeAttempts]
/// wrong passwords cost nothing, then each one waits longer before the next
/// try ([delayAfter]). Kept in `lock_attempts.json`, so quitting Sotto
/// doesn't reset it. Nothing is ever wiped for failing.
///
/// This is a speed bump for someone at the keyboard; the real cost of a
/// guess is Argon2id, which also applies to anyone copying the files away.
class UnlockThrottle {
  UnlockThrottle(this.file, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final File file;
  final DateTime Function() _now;

  static const freeAttempts = 5;
  static const _steps = [
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(hours: 1),
  ];

  int _failures = 0;
  DateTime? _until;

  int get failures => _failures;

  /// The wait after [failures] wrong attempts in a row.
  static Duration delayAfter(int failures) {
    if (failures < freeAttempts) return Duration.zero;
    final step = failures - freeAttempts;
    return _steps[step < _steps.length ? step : _steps.length - 1];
  }

  /// How long until the next attempt is allowed; zero when it is now.
  Duration get remaining {
    final until = _until;
    if (until == null) return Duration.zero;
    final left = until.difference(_now());
    return left.isNegative ? Duration.zero : left;
  }

  bool get blocked => remaining > Duration.zero;

  /// Reads the saved count. A missing or unreadable file starts at zero.
  Future<void> load() async {
    try {
      if (!await file.exists()) return;
      final j = jsonDecode(await file.readAsString()) as Map;
      _failures = (j['failures'] as int?) ?? 0;
      _until = DateTime.tryParse(j['until'] as String? ?? '');
      // A clock set back can't extend the wait past the longest step.
      final until = _until;
      if (until != null && until.difference(_now()) > _steps.last) _until = _now().add(_steps.last);
    } catch (_) {
      _failures = 0;
      _until = null;
    }
  }

  Future<void> recordFailure() async {
    _failures++;
    final delay = delayAfter(_failures);
    _until = delay == Duration.zero ? null : _now().add(delay);
    await writeFileAtomic(
      file,
      jsonEncode({'failures': _failures, if (_until != null) 'until': _until!.toUtc().toIso8601String()}),
    );
  }

  Future<void> recordSuccess() async {
    _failures = 0;
    _until = null;
    await clear(file);
  }

  /// Deletes the saved count (unlock, Reset Sotto, turning the lock off).
  static Future<void> clear(File file) async {
    if (await file.exists()) await file.delete();
  }
}

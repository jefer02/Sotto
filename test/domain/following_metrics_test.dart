// Measures voice following on recorded and synthetic takes (see
// following_harness.dart) and prints two tables; per-update logs go to
// build/following_harness/:
// * every take through the previous rules and the current ones;
// * before / after: what Spanish used to follow with (segmented Whisper,
//   previous rules) against what it follows with now (the streaming model,
//   current rules), on the same audio.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/domain/following/follow_engine.dart';
import 'package:sotto/domain/following/heard_update.dart';
import 'package:sotto/domain/following/script_aligner.dart';

import 'following_harness.dart';
import 'previous_following.dart';

/// The rules before streaming recognition (see previous_following.dart).
class PreviousFollower implements Follower {
  PreviousFollower(FlatScript script, AppSettings settings)
    : _engine = PreviousFollowEngine(script, settings: settings, clock: () => _now);

  static DateTime _now = DateTime(2026);
  final PreviousFollowEngine _engine;

  @override
  void feed(HeardUpdate update, double at) {
    _now = DateTime(2026).add(Duration(milliseconds: (at * 1000).round()));
    _engine.onUpdate(update);
  }

  @override
  (int, int) get shown => (_engine.position.saidBeat, _engine.position.saidWords);

  @override
  void startAt(int beat) => _engine.jumpTo(beat);

  @override
  String get decision => _engine.lastDecision.toString();
}

/// The current rules, on committed words and partials kept apart.
class CurrentFollower implements Follower {
  CurrentFollower(FlatScript script, AppSettings settings)
    : _engine = FollowEngine(script, settings: settings, clock: () => _now);

  static DateTime _now = DateTime(2026);
  final FollowEngine _engine;

  @override
  void feed(HeardUpdate update, double at) {
    _now = DateTime(2026).add(Duration(milliseconds: (at * 1000).round()));
    _engine.onUpdate(update);
  }

  /// Where the script scrolls to: the word really said.
  @override
  (int, int) get shown => (_engine.position.saidBeat, _engine.position.saidWords);

  @override
  void startAt(int beat) => _engine.jumpTo(beat);

  @override
  String get decision => _engine.lastDecision.toString();

  double? get charsPerSecond => _engine.charsPerSecond;
}

typedef FollowerFactory = Follower Function(FlatScript script, AppSettings settings);

/// The settings a Spanish presenter runs with (sensitivity high, as the
/// reported sessions).
const settings = AppSettings(language: 'es-MX', sensitivity: Sensitivity.high, advanceThreshold: 1);

Metrics measure(String engine, FollowerFactory make, Take take) {
  final dir = Directory('build/following_harness')..createSync(recursive: true);
  final log = StringBuffer('# ${take.name} — $engine\n');
  final m = replay(take, make(take.script, settings), log: log);
  final file = take.name.replaceAll(RegExp('[^a-z0-9]+'), '_');
  File('${dir.path}/${file}_$engine.log').writeAsStringSync(log.toString());
  return m;
}

String _f(double v) => v.toStringAsFixed(1);

const header =
    '| take | rules | moves | rec gap s | move gap s | words/move | lag w (mean/p90) | latency s (mean/p90) '
    '| jumps ≥ $bigJump | false adv. | in ad-lib/silence | max ahead | relock |';

String row(String take, String engine, Metrics m) =>
    '| $take | $engine | ${m.moves}/${m.updates} | ${_f(m.updateGap)} | ${_f(m.moveGap)} | ${_f(m.wordsPerMove)} '
    '| ${_f(m.meanLag)} / ${_f(m.p90Lag)} '
    '| ${m.wordLatencies.isEmpty ? '—' : '${_f(m.meanLatency)} / ${_f(m.p90Latency)}'} '
    '| ${m.bigJumps} | ${m.falseAdvances} | ${m.quietAdvances} | ${m.maxAhead} '
    '| ${m.relockSeconds == null ? (m.relockedEarly ? 'early' : '—') : '${m.relockedEarly ? 'early ' : ''}${_f(m.relockSeconds!)} s'} |';

void main() {
  final takes = [...recordedTakes(), ...syntheticTakes()];

  test('following metrics', () {
    final engines = <String, FollowerFactory>{'previous': PreviousFollower.new, 'current': CurrentFollower.new};
    final results = {
      for (final take in takes) take.name: {for (final e in engines.entries) e.key: measure(e.key, e.value, take)},
    };
    final table = StringBuffer()
      ..writeln('## Every take, previous and current rules')
      ..writeln()
      ..writeln(header)
      ..writeln('|${'---|' * 13}');
    for (final take in takes) {
      for (final e in engines.keys) {
        table.writeln(row(take.name, e, results[take.name]![e]!));
      }
    }
    // Before: segmented Whisper with the previous rules. After: the
    // streaming model with the current ones. Same audio.
    table
      ..writeln()
      ..writeln('## Before (Whisper Base, previous rules) / after (streaming, current rules)')
      ..writeln()
      ..writeln(header)
      ..writeln('|${'---|' * 13}');
    for (final name in ['natural', 'skip', 'long']) {
      final before = takes.where((t) => t.path == 'whisper' && t.name.endsWith(': $name')).firstOrNull;
      final after = takes.where((t) => t.path == 'streaming' && t.name.endsWith(': $name')).firstOrNull;
      if (before != null) table.writeln(row(name, 'before', results[before.name]!['previous']!));
      if (after != null) table.writeln(row(name, 'after', results[after.name]!['current']!));
    }
    // ignore: avoid_print
    print(table);
    File('build/following_harness/metrics.md').writeAsStringSync(table.toString());
  });
}

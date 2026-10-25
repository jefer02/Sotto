// Where following's latency comes from, stage by stage, on long.wav played in
// real time through the real streaming engine (worker isolate included):
//
//   word ends (truth) → audio chunk delivered → decoder emits the word →
//   word marked final (or shown tentatively) → FollowEngine moves past it.
//
// Opt-in (slow, needs the model and the native libraries):
//   $env:SOTTO_LATENCY=1; flutter test --no-pub test/integration/latency_stages_test.dart
// Writes build/following_harness/latency_stages.md. SOTTO_MODELS_ROOT adds
// folders to look for models in.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/data/models/script.dart';
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/domain/following/follow_engine.dart';
import 'package:sotto/domain/following/script_aligner.dart';
import 'package:sotto/domain/following/text_normalizer.dart';
import 'package:sotto/services/speech/model_manager.dart';
import 'package:sotto/services/speech/recognizers.dart';

import 'native_speech.dart';

const _fixtures = 'test/fixtures/speech_es';

typedef _Word = ({int word, double start, double end});

int _beatOf(List<int> offset, int word) {
  var b = 0;
  while (b + 1 < offset.length && offset[b + 1] <= word) {
    b++;
  }
  return b;
}

double _mean(List<double> v) => v.isEmpty ? double.nan : v.reduce((a, b) => a + b) / v.length;
double _pct(List<double> v, double p) {
  if (v.isEmpty) return double.nan;
  final s = [...v]..sort();
  return s[math.min(s.length - 1, (s.length * p).floor())];
}

void main() {
  final run = Platform.environment['SOTTO_LATENCY'] == '1';
  final native = run && loadNativeSpeech();

  test(
    'latency by stage, streaming Spanish',
    () async {
      final beats = File('$_fixtures/long_beats.txt').readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();
      final now = DateTime(2026);
      final script = Script(
        id: 's',
        title: 'T',
        createdAt: now,
        updatedAt: now,
        sections: [
          Section(id: 'a', title: 'A', beats: [for (final b in beats) Beat.create(b)]),
        ],
      );
      final flat = FlatScript.from(script, language: 'es-MX');
      final offset = <int>[];
      var n = 0;
      for (final b in flat.beats) {
        offset.add(n);
        n += b.displayWords.length;
      }
      final truth = jsonDecode(File('$_fixtures/long_truth.json').readAsStringSync()) as Map<String, Object?>;
      final words = <_Word>[
        for (final w in truth['words']! as List)
          (
            word: offset[(w as Map)['beat'] as int] + (w['word'] as int),
            start: (w['start'] as num).toDouble(),
            end: (w['end'] as num).toDouble(),
          ),
      ];

      final files = await ModelManager.findFiles(modelDir(ModelCatalog.streamingEs.id)!);
      // SOTTO_LATENCY_STREAMS=1 and SOTTO_LATENCY_TENTATIVE=0 measure the
      // pipeline as it was: one decoder, final words only.
      final streams = int.parse(
        Platform.environment['SOTTO_LATENCY_STREAMS'] ??
            '${OffsetStreams.countFor(ModelCatalog.streamingEs.chunkSeconds)}',
      );
      final tentativeOn = Platform.environment['SOTTO_LATENCY_TENTATIVE'] != '0';
      final engine = await SherpaEngine.start(streaming: files, streams: streams);
      final follow = FollowEngine(
        flat,
        settings: const AppSettings(language: 'es-MX', sensitivity: Sensitivity.high, advanceThreshold: 1),
      )..jumpTo(0);

      // Every heard word by its place in the whole transcript (committed and
      // partial words share one count): its text as last heard, when (audio
      // clock) the decoder first emitted it, when it was offered tentatively
      // and when it became final. Mapped to the truth by aligning the words
      // themselves afterwards — the model's timestamps lag the true onsets.
      final heardText = <int, String>{};
      final emittedAt = <int, double>{}, tentativeAt = <int, double>{}, finalAt = <int, double>{};
      // Wall time the update that made each word ready arrived, and how long
      // the worker took from the audio to that update (decode + message).
      final readyWall = <int, double>{};
      final compute = <double>[];
      // When (wall) following moved past each truth word.
      final moved = <int, double>{};
      // Loaded before the clock starts: it takes a moment.
      final audio = readWav('$_fixtures/long.wav');
      final clock = Stopwatch()..start();
      var shown = 0;
      var updates = 0;
      final sub = engine.updates.listen((heard) {
        final u = tentativeOn
            ? heard
            : HeardUpdate(
                committed: heard.committed,
                committedTotal: heard.committedTotal,
                partial: heard.partial,
                stable: heard.stable,
                times: heard.times,
                clock: heard.clock,
              );
        updates++;
        final at = u.clock ?? clock.elapsedMilliseconds / 1000;
        final wall = clock.elapsedMilliseconds / 1000;
        compute.add(wall - at);
        final first = u.committedTotal - u.committed.length;
        final partial = u.partialWords;
        final all = [...u.committed, ...partial];
        final stableCount = u.committed.length + (u.stable ?? 0);
        for (var k = 0; k < all.length; k++) {
          final g = first + k;
          heardText[g] = all[k];
          emittedAt.putIfAbsent(g, () => at);
          if (k < stableCount) finalAt.putIfAbsent(g, () => at);
          if (k < stableCount + (u.tentative ?? 0)) {
            tentativeAt.putIfAbsent(g, () => at);
            readyWall.putIfAbsent(g, () => wall);
          }
        }
        follow.onUpdate(u);
        final p = follow.position;
        final s = offset[p.saidBeat] + p.saidWords;
        final tShown = clock.elapsedMilliseconds / 1000;
        for (var w = shown; w < s; w++) {
          moved.putIfAbsent(w, () => tShown);
        }
        shown = math.max(shown, s);
      });
      await playInto(engine, audio);
      await Future<void>.delayed(const Duration(seconds: 2));
      await sub.cancel();
      await engine.dispose();

      // Align heard words to truth words (edit distance on normalized text).
      String norm(String w) => TextNormalizer.normalizeHeard(w, language: 'es').join(' ');
      final heard = (heardText.keys.toList()..sort()).where((g) => norm(heardText[g]!).isNotEmpty).toList();
      final truthText = [
        for (final w in words)
          norm(flat.beats[_beatOf(offset, w.word)].displayWords[w.word - offset[_beatOf(offset, w.word)]]),
      ];
      final h = heard.length, t = truthText.length;
      final dp = List.generate(h + 1, (i) => List<int>.filled(t + 1, 0));
      for (var i = 0; i <= h; i++) {
        dp[i][0] = i;
      }
      for (var j = 0; j <= t; j++) {
        dp[0][j] = j;
      }
      bool same(int i, int j) =>
          TextNormalizer.similarity(norm(heardText[heard[i]]!), truthText[j], spanish: true) >= 0.8;
      for (var i = 1; i <= h; i++) {
        for (var j = 1; j <= t; j++) {
          dp[i][j] = math.min(
            math.min(dp[i - 1][j] + 1, dp[i][j - 1] + 1),
            dp[i - 1][j - 1] + (same(i - 1, j - 1) ? 0 : 1),
          );
        }
      }
      final truthOf = <int, int>{}; // truth index → heard global index
      for (var i = h, j = t; i > 0 && j > 0;) {
        if (dp[i][j] == dp[i - 1][j - 1] + (same(i - 1, j - 1) ? 0 : 1)) {
          if (same(i - 1, j - 1)) truthOf[j - 1] = heard[i - 1];
          i--;
          j--;
        } else if (dp[i][j] == dp[i - 1][j] + 1) {
          i--;
        } else {
          j--;
        }
      }
      final emitted = <int, double>{}, tentative = <int, double>{}, final_ = <int, double>{}, ready = <int, double>{};
      for (final MapEntry(key: ti, value: g) in truthOf.entries) {
        final w = words[ti].word;
        if (emittedAt[g] case final e?) emitted[w] = e;
        if (tentativeAt[g] case final e?) tentative[w] = e;
        if (finalAt[g] case final e?) final_[w] = e;
        if (readyWall[g] case final e?) ready[w] = e;
      }

      // Stage latencies, per word that reached each stage.
      final chunkWait = <double>[], decode = <double>[], stable = <double>[], shownTentative = <double>[];
      final engineHold = <double>[], total = <double>[];
      for (final w in words) {
        final e = emitted[w.word], f = final_[w.word], t = tentative[w.word], m = moved[w.word];
        // Audio arrives in 100 ms chunks: the one holding the word's end.
        chunkWait.add(((w.end / 0.1).ceil() * 0.1) - w.end);
        if (e != null) decode.add(e - w.end);
        if (e != null && f != null) stable.add(f - e);
        if (e != null && t != null) shownTentative.add(t - e);
        final r = ready[w.word];
        if (r != null && m != null) engineHold.add(math.max(0, m - r));
        if (m != null) total.add(m - w.end);
      }
      String row(String stage, List<double> v) =>
          '| $stage | ${_mean(v).toStringAsFixed(2)} | ${_pct(v, 0.5).toStringAsFixed(2)} | '
          '${_pct(v, 0.9).toStringAsFixed(2)} | ${v.length} |';
      final mode = Platform.environment['SOTTO_LATENCY_LABEL'] ?? 'current';
      final table = StringBuffer()
        ..writeln('### $mode — long.wav, ${words.length} script words, $updates updates')
        ..writeln()
        ..writeln('| stage | mean s | p50 s | p90 s | words |')
        ..writeln('|---|---|---|---|---|')
        ..writeln(row('audio chunk delivered (after the word ends)', chunkWait))
        ..writeln(row('decoder emits the word (after it ends)', decode))
        ..writeln(row('emitted → final', stable))
        ..writeln(row('emitted → shown tentatively', shownTentative))
        ..writeln(row('worker: audio in → update out (decode + message)', compute))
        ..writeln(row('update in → FollowEngine moves past it', engineHold))
        ..writeln(row('total: word ends → following moved past it', total));
      final sortedCompute = [...compute]..sort();
      // ignore: avoid_print
      print(
        'worker offset: min ${sortedCompute.first.toStringAsFixed(3)} max ${sortedCompute.last.toStringAsFixed(3)}',
      );
      // ignore: avoid_print
      print(table);
      Directory('build/following_harness').createSync(recursive: true);
      File('build/following_harness/latency_stages.md').writeAsStringSync('$table\n', mode: FileMode.append);
    },
    skip: !run
        ? 'set SOTTO_LATENCY=1'
        : !native
        ? 'native speech libraries not built'
        : modelDir(ModelCatalog.streamingEs.id) == null
        ? 'model not installed'
        : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

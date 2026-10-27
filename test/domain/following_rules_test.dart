// The following rules on recorded recognizer output (segmented Whisper and
// the streaming model) and hand-built sequences (see following_harness.dart):
// what must move the script, and what never may.
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/domain/following/follow_engine.dart';
import 'package:sotto/domain/following/heard_update.dart';
import 'package:sotto/domain/following/script_aligner.dart';
import 'package:sotto/domain/following/text_normalizer.dart';

import 'following_harness.dart';
import 'following_metrics_test.dart' show CurrentFollower, PreviousFollower, settings;

Metrics _run(Take take) => replay(take, CurrentFollower(take.script, settings));

Take _take(String name) => [...recordedTakes(), ...syntheticTakes()].firstWhere((t) => t.name.contains(name));

FlatScript _spanish() => FlatScript.from(scriptOf(spanishBeats()), language: 'es-MX');

void main() {
  group('stays put', () {
    test('off-script talk that borrows script words never moves it', () {
      final m = _run(_take('off-script'));
      expect(m.moves, 0);
    });

    test('silence and Whisper caption hallucinations never move it', () {
      final m = _run(_take('silence + noise'));
      expect(m.moves, 0);
    });

    test('no new words, no move — the same transcript twice', () {
      final e = FollowEngine(_spanish(), settings: settings)..jumpTo(0);
      const u = HeardUpdate(committed: ['Buenos', 'días', 'a', 'todos'], committedTotal: 4);
      e.onUpdate(u);
      final after = e.position;
      expect(e.onUpdate(u), FollowEvent.none);
      expect(e.position.saidWords, after.saidWords);
      expect(e.lastDecision.reason, 'no new stable words');
    });

    test('one fuzzy word is not enough', () {
      final e = FollowEngine(_spanish(), settings: settings)..jumpTo(5);
      // "muchas" sounds like the beat's first word "Muchos" — not enough.
      e.onUpdate(const HeardUpdate(committed: ['Muchas', 'gracias.'], committedTotal: 2));
      expect((e.position.saidBeat, e.position.saidWords), (5, 0));
    });
  });

  group('partials', () {
    test('a partial word moves nothing until a second update agrees', () {
      final e = FollowEngine(_spanish(), settings: settings)..jumpTo(0);
      e.onUpdate(const HeardUpdate(partial: 'Buenos días a todos'));
      expect(e.position.saidWords, 0);
      e.onUpdate(const HeardUpdate(partial: 'Buenos días a todos y gracias'));
      // The four words seen twice count; "y gracias" waits.
      expect(e.position.saidWords, 4);
    });

    test('words that are later rewritten never move the script', () {
      final m = _run(_take('unstable partials'));
      expect(m.maxAhead, lessThanOrEqualTo(0));
      expect(m.falseAdvances, 0);
    });

    test('a word the recognizer slips in front keeps the rest stable', () {
      final e = FollowEngine(_spanish(), settings: settings)..jumpTo(4);
      e.onUpdate(const HeardUpdate(partial: 'también tuvimos problemas'));
      e.onUpdate(const HeardUpdate(partial: 'lo también tuvimos problemas con los tiempos'));
      expect(e.position.saidBeat, 4);
      expect(e.position.saidWords, greaterThanOrEqualTo(3));
    });
  });

  group('streaming input', () {
    test('words the recognizer calls final count at once, with no second update', () {
      final e = FollowEngine(_spanish(), settings: settings)..jumpTo(0);
      e.onUpdate(const HeardUpdate(partial: 'Buenos días a todos y', stable: 4, times: [0.2, 0.5, 0.9, 1.0, 1.3]));
      expect(e.position.saidWords, 4);
    });

    test('the last word, still open, never moves the script', () {
      final e = FollowEngine(_spanish(), settings: settings)..jumpTo(0);
      e.onUpdate(const HeardUpdate(partial: 'Buenos días', stable: 1));
      expect(e.position.saidWords, 1);
      // The same open word in a later update: still not final, still no move.
      e.onUpdate(const HeardUpdate(partial: 'Buenos días', stable: 1));
      expect(e.position.saidWords, 1);
      e.onUpdate(const HeardUpdate(partial: 'Buenos días a', stable: 2));
      expect(e.position.saidWords, 2);
    });

    test('an open word that is the next script word shows at once; finals confirm it', () {
      final e = FollowEngine(_spanish(), settings: settings)..jumpTo(0);
      e.onUpdate(const HeardUpdate(committed: ['Buenos', 'días'], committedTotal: 2));
      expect(e.position.saidWords, 2);
      // "a" is heard but may still grow: shown now, not yet confirmed.
      final shown = e.onUpdate(
        const HeardUpdate(committed: ['Buenos', 'días'], committedTotal: 2, partial: 'a', stable: 0, tentative: 1),
      );
      expect(shown, FollowEvent.dimmed);
      expect(e.position.saidWords, 3);
      expect(e.token, 1, reason: 'the engine itself moves on final words only');
      e.onUpdate(const HeardUpdate(committed: ['Buenos', 'días', 'a'], committedTotal: 3, stable: 0, tentative: 0));
      expect(e.position.saidWords, 3);
      expect(e.token, 2);
    });

    test('an open word that is revised takes the display back', () {
      final e = FollowEngine(_spanish(), settings: settings)..jumpTo(0);
      e.onUpdate(const HeardUpdate(committed: ['Buenos', 'días'], committedTotal: 2));
      e.onUpdate(const HeardUpdate(committed: ['Buenos', 'días'], committedTotal: 2, partial: 'a', tentative: 1));
      expect(e.position.saidWords, 3);
      // It grew into another word: back to what is final.
      e.onUpdate(const HeardUpdate(committed: ['Buenos', 'días'], committedTotal: 2, partial: 'ahora', tentative: 1));
      expect(e.position.saidWords, 2);
    });

    test('an open word that is not the next script word never shows', () {
      final e = FollowEngine(_spanish(), settings: settings)..jumpTo(0);
      e.onUpdate(const HeardUpdate(committed: ['Buenos', 'días'], committedTotal: 2));
      // "todos" is two words ahead: an open word shows only as the very next.
      e.onUpdate(const HeardUpdate(committed: ['Buenos', 'días'], committedTotal: 2, partial: 'todos', tentative: 1));
      expect(e.position.saidWords, 2);
    });

    test('open words never show during an ad-lib hold', () {
      var now = DateTime(2026);
      final e = FollowEngine(_spanish(), settings: settings, clock: () => now)..jumpTo(0);
      e.onUpdate(const HeardUpdate(committed: ['Buenos', 'días'], committedTotal: 2));
      now = now.add(const Duration(seconds: 10));
      e.onUpdate(const HeardUpdate(committed: ['Buenos', 'días', 'bueno'], committedTotal: 3));
      expect(e.position.holding, isTrue);
      e.onUpdate(
        const HeardUpdate(committed: ['Buenos', 'días', 'bueno'], committedTotal: 3, partial: 'a', tentative: 1),
      );
      expect(e.position.saidWords, 2);
    });

    test('the speaking rate comes from when each word began', () {
      final e = FollowEngine(_spanish(), settings: settings)..jumpTo(0);
      // "Buenos días a todos y gracias por estar" at 3 words a second.
      const words = ['Buenos', 'días', 'a', 'todos', 'y', 'gracias', 'por', 'estar'];
      e.onUpdate(
        HeardUpdate(partial: words.join(' '), stable: words.length, times: [for (var i = 0; i < 8; i++) i / 3]),
      );
      // Characters said (word + space) over the time they took — smoothed
      // as the words came, so close to the whole stretch's average.
      final chars = words.take(7).fold<int>(0, (n, w) => n + w.length + 1);
      final average = chars / (7 / 3);
      expect(e.charsPerSecond, closeTo(average, average * 0.15));
      expect(e.position.charsPerSecond, e.charsPerSecond);
    });

    test('on the recorded streaming takes it never advances on ad-libs or silence', () {
      for (final take in recordedTakes().where((t) => t.path == 'streaming')) {
        final m = _run(take);
        expect(m.falseAdvances, 0, reason: take.name);
        expect(m.quietAdvances, 0, reason: take.name);
        expect(m.relockedEarly, isFalse, reason: take.name);
        expect(m.maxAhead, lessThanOrEqualTo(aheadTolerance), reason: take.name);
      }
    }, skip: recordedTakes().every((t) => t.path != 'streaming') ? 'no streaming recordings' : false);

    test('on the same audio it shows words sooner than segmented Whisper did', () {
      final previous = {
        for (final t in recordedTakes().where((t) => t.path == 'whisper'))
          t.name.split(': ').last: replay(t, PreviousFollower(t.script, settings)),
      };
      for (final t in recordedTakes().where((t) => t.path == 'streaming')) {
        final now = _run(t), before = previous[t.name.split(': ').last];
        if (before == null) continue;
        expect(now.meanLatency, lessThan(before.meanLatency), reason: t.name);
        expect(now.p90Lag, lessThanOrEqualTo(before.p90Lag), reason: t.name);
      }
    }, skip: recordedTakes().every((t) => t.path != 'streaming') ? 'no streaming recordings' : false);
  });

  group('jumps', () {
    test('a phrase the script repeats elsewhere causes no jump', () {
      final m = _run(_take('repeated phrase'));
      expect(m.bigJumps, 0);
      expect(m.maxAhead, lessThanOrEqualTo(aheadTolerance));
    });

    test('a skipped section relocks only on sustained evidence', () {
      for (final take in recordedTakes().where((t) => t.name.endsWith('skip'))) {
        final m = _run(take);
        expect(m.relockedEarly, isFalse, reason: take.name);
        expect(m.relockSeconds, isNotNull, reason: take.name);
        expect(m.relockSeconds, lessThan(10), reason: take.name);
        expect(m.falseAdvances, 0, reason: take.name);
      }
    }, skip: recordedTakes().isEmpty ? 'no recorded takes' : false);

    test('one distinctive far match waits for the next update', () {
      final e = FollowEngine(_spanish(), settings: settings)..jumpTo(0);
      e.onUpdate(
        const HeardUpdate(committed: ['respondieron', 'más', 'de', 'diez', 'mil', 'solicitudes'], committedTotal: 6),
      );
      expect(e.position.saidBeat, 0);
      expect(e.lastDecision.reason, contains('waiting'));
      e.onUpdate(
        const HeardUpdate(
          committed: ['respondieron', 'más', 'de', 'diez', 'mil', 'solicitudes', 'con', 'una', 'nota'],
          committedTotal: 9,
        ),
      );
      expect(e.position.saidBeat, 9);
    });

    test('backwards only on a long re-read, twice', () {
      final e = FollowEngine(_spanish(), settings: settings)..jumpTo(6);
      e.onUpdate(const HeardUpdate(committed: ['las', 'ventas'], committedTotal: 2));
      expect(e.position.saidBeat, 6);
    });
  });

  group('reading', () {
    test('tracks a natural read with a small lag and no jumps', () {
      for (final take in recordedTakes().where((t) => t.name.endsWith('natural'))) {
        final m = _run(take);
        expect(m.falseAdvances, 0, reason: take.name);
        expect(m.bigJumps, 0, reason: take.name);
        expect(m.maxAhead, lessThanOrEqualTo(aheadTolerance), reason: take.name);
        expect(m.meanLag, lessThan(10), reason: take.name);
        // The read ends on the last beat.
        final f = CurrentFollower(take.script, settings)..startAt(0);
        for (final u in take.updates) {
          f.feed(u.update, u.t);
        }
        expect(f.shown.$1, greaterThanOrEqualTo(take.script.length - 2), reason: take.name);
      }
    }, skip: recordedTakes().isEmpty ? 'no recorded takes' : false);

    test('word by word: the position never skips the unsaid end of a line', () {
      final flat = _spanish();
      final e = FollowEngine(flat, settings: const AppSettings(language: 'es-MX', advanceThreshold: 0.8))..jumpTo(2);
      e.onUpdate(
        const HeardUpdate(
          committed: ['Las', 'ventas', 'crecieron', 'un', 'doce', 'por', 'ciento', 'frente', 'al'],
          committedTotal: 9,
        ),
      );
      // 9 of the line's 11 spoken words: past 80 %.
      // Past "Move on when said" the next line is current, but the script
      // scrolls by the word really said.
      expect(e.position.beat, 3);
      expect((e.position.saidBeat, e.position.saidWords), (2, 9));
    });
  });

  group('manual keys win', () {
    test('words heard before a key never count after it', () {
      final e = FollowEngine(_spanish(), settings: settings)..jumpTo(0);
      e.onUpdate(const HeardUpdate(partial: 'Buenos días a todos y gracias'));
      e.jumpTo(3);
      // The same partial, now stable: it was heard before the key.
      e.onUpdate(const HeardUpdate(partial: 'Buenos días a todos y gracias'));
      expect((e.position.beat, e.position.saidWords), (3, 0));
    });

    test('"previous beat" pauses following for 3 s', () {
      var now = DateTime(2026);
      final e = FollowEngine(_spanish(), settings: settings, clock: () => now)..jumpTo(3);
      e.jumpTo(2, suspend: true);
      e.onUpdate(const HeardUpdate(committed: ['Las', 'ventas', 'crecieron', 'un', 'doce'], committedTotal: 5));
      expect(e.position.saidWords, 0);
      now = now.add(const Duration(seconds: 4));
      e.onUpdate(
        const HeardUpdate(committed: ['Las', 'ventas', 'crecieron', 'un', 'doce', 'por', 'ciento'], committedTotal: 7),
      );
      expect(e.position.saidBeat, 2);
      expect(e.position.saidWords, greaterThan(0));
    });
  });

  group('Spanish normalization', () {
    test('accents, numbers, contractions and the decimal word', () {
      bool same(String a, String b) => TextNormalizer.similarity(a, b, spanish: true) >= 0.8;
      expect(TextNormalizer.normalizeHeard('Crecieron un 12%', language: 'es'), [
        'crecieron',
        'un',
        'doce',
        'por',
        'ciento',
      ]);
      expect(TextNormalizer.normalizeHeard('almacén', language: 'es'), ['almacen']);
      expect(same('al', 'a'), isTrue);
      expect(same('del', 'de'), isTrue);
      expect(same('punto', 'coma'), isTrue);
      expect(same('vamos', 'bamos'), isTrue);
      expect(same('hizo', 'izo'), isTrue);
      expect(same('ventas', 'gracias'), isFalse);
    });

    test('rare words weigh more than repeated ones, stop words least', () {
      final flat = _spanish();
      expect(flat.weightOf('monterrey'), 1.0);
      expect(flat.weightOf('ano'), lessThan(flat.weightOf('monterrey')));
      expect(flat.weightOf('de'), ScriptAligner.stopWeight);
    });
  });
}

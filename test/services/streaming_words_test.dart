import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/services/speech/recognizers.dart';

// How the streaming recognizer's tokens become words, and when a word is
// final: greedy transducer search only appends, so only the last word can
// still change (it may grow, "día" → "días").
void main() {
  // 100 ms of audio at 16 kHz, as the microphone delivers it.
  const chunk = 1600;

  test('tokens become words, with when each began on one clock', () {
    final w = StreamingWords();
    final r = w.next(
      ['B', 'u', 'e', 'nos', ' día', 's', ' a'],
      [0.24, 0.28, 0.48, 0.6, 0.88, 1.0, 1.28],
      chunk * 15,
      decoded: true,
      endpoint: false,
    )!;
    expect(r.words, ['Buenos', 'días', 'a']);
    expect(r.times, [0.24, 0.88, 1.28]);
    // "a" was heard 0.22 s before the end of the audio: it may still grow.
    expect(r.stable, 2);
  });

  test('the last word is final once enough decoded silence follows it', () {
    final w = StreamingWords();
    w.next(['Hoy', ' les'], [0.2, 0.5], chunk * 6, decoded: true, endpoint: false);
    // 0.3 s later, nothing new and not decoded yet: unchanged, no update.
    expect(w.next(['Hoy', ' les'], [0.2, 0.5], chunk * 3, decoded: false, endpoint: false), isNull);
    // A decoded chunk with ≥ 0.35 s after "les": final.
    final r = w.next(['Hoy', ' les'], [0.2, 0.5], chunk * 2, decoded: true, endpoint: false)!;
    expect(r.stable, 2);
  });

  test('a word called final stays final', () {
    final w = StreamingWords();
    w.next(['Hoy', ' les'], [0.2, 0.5], chunk * 10, decoded: true, endpoint: false);
    final r = w.next(['Hoy', ' les', ' qui'], [0.2, 0.5, 0.95], chunk, decoded: true, endpoint: false)!;
    expect(r.stable, 2, reason: '"qui" may still grow into "quiero"');
    final grown = w.next(
      ['Hoy', ' les', ' qui', 'ero'],
      [0.2, 0.5, 0.95, 1.05],
      chunk,
      decoded: false,
      endpoint: false,
    )!;
    expect(grown.words, ['Hoy', 'les', 'quiero']);
    expect(grown.stable, 2);
  });

  test('the end of an utterance makes every word final, and the next one keeps the clock', () {
    final w = StreamingWords();
    final end = w.next(['Gracias', ' por'], [0.3, 0.7], chunk * 9, decoded: true, endpoint: true)!;
    expect(end.endpoint, isTrue);
    expect(end.stable, 2);
    w.reset();
    // sherpa's timestamps restart at the reset; the clock carries on.
    final next = w.next(['Las'], [0.4], chunk * 10, decoded: true, endpoint: false)!;
    expect(next.times.single, closeTo(0.9 + 0.4, 1e-9));
  });

  test('a stream started mid-word drops the fragment it hears first', () {
    // Started 0.32 s into the session, in the middle of "yellow".
    final w = StreamingWords(startSamples: chunk * 32 ~/ 10);
    final r = w.next([' ow', ' lamps'], [0.02, 0.4], chunk * 8, decoded: true, endpoint: false)!;
    expect(r.words, ['lamps']);
    expect(r.times.single, closeTo(0.32 + 0.4, 1e-9));
  });

  test('one decoder per 0.32 s of a model chunk', () {
    expect(OffsetStreams.countFor(0.32), 1);
    expect(OffsetStreams.countFor(1.28), 4);
  });

  group('offset streams merged', () {
    StreamingResult r(List<String> words, List<double> times, int stable, double clock) =>
        (words: words, times: times, stable: stable, endpoint: false, clock: clock);

    test('a word two streams heard counts once, whoever heard it first', () {
      final m = MergedWords();
      // Stream A, then stream B half a chunk later with the same words (its
      // timestamps a frame off) and one more.
      final a = m.add(r(['Buenos', 'días', 'a'], [0.24, 0.88, 1.28], 2, 1.41))!;
      expect(a.finals, ['Buenos', 'días']);
      expect(a.open, ['a']);
      final b = m.add(r(['Buenos', 'días', 'a', 'todos'], [0.28, 0.92, 1.30, 1.40], 3, 2.05))!;
      expect(b.finals, ['a'], reason: 'Buenos and días were already final');
      expect(b.open, ['todos']);
    });

    test('punctuation the model writes as a word is no word', () {
      final m = MergedWords();
      final out = m.add(r(['.', 'Hoy', 'les'], [0.44, 1.28, 1.56], 2, 2.0))!;
      expect(out.finals, ['Hoy']);
    });

    test('nothing new, nothing sent', () {
      final m = MergedWords();
      m.add(r(['Hoy', 'les'], [1.28, 1.56], 1, 2.0));
      expect(m.add(r(['Hoy', 'les'], [1.30, 1.58], 1, 2.6)), isNull);
    });

    test('words keep their order: nothing at or before the last final word is added', () {
      final m = MergedWords();
      m.add(r(['crecieron', 'un', 'doce'], [7.0, 7.7, 7.9], 3, 8.4));
      // A stream that lags behind re-reports earlier words, worded apart.
      final late = m.add(r(['ventas', 'crecieron', 'uno'], [6.6, 7.04, 7.7], 3, 8.8));
      expect(late, isNull);
    });
  });

  test('silence with no words sends nothing', () {
    final w = StreamingWords();
    expect(w.next([], [], chunk * 10, decoded: true, endpoint: false), isNull);
    expect(w.next([], [], chunk * 10, decoded: true, endpoint: true), isNull);
  });
}

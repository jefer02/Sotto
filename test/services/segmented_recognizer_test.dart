import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/services/speech/recognizers.dart';

/// A transcriber that answers only when the test says so, and counts how
/// many requests are in flight at once.
class _SlowTranscriber implements Transcriber {
  final calls = <(Float32List, Completer<String>)>[];
  int inFlight = 0, maxInFlight = 0;

  @override
  Future<String> transcribe(Float32List audio, {String? language, String? prompt}) {
    inFlight++;
    maxInFlight = math.max(maxInFlight, inFlight);
    final c = Completer<String>();
    calls.add((audio, c));
    return c.future.whenComplete(() => inFlight--);
  }

  void answer(String text) => calls.firstWhere((c) => !c.$2.isCompleted).$2.complete(text);

  @override
  Future<void> dispose() async {}
}

Float32List _frames(int ms, double amplitude) =>
    Float32List.fromList([for (var i = 0; i < 16 * ms; i++) amplitude * math.sin(2 * math.pi * 220 * i / 16000)]);

/// Feeds an utterance, then enough silence to close it.
void _utterance(SegmentedRecognizer r, {int ms = 1500}) {
  r.accept(_frames(ms, 0.08));
  r.accept(_frames(600, 0));
}

void main() {
  test('a slow model never has more than one transcription in flight', () async {
    final t = _SlowTranscriber();
    final r = SegmentedRecognizer(t, language: 'es', refresh: Duration.zero);
    final heard = <String>[];
    r.heard.listen(heard.add);

    // Three utterances end while the first transcription is still running.
    _utterance(r);
    _utterance(r);
    _utterance(r);
    expect(t.maxInFlight, 1);
    final first = t.calls.length;

    // The first request was a refresh of the open utterance.
    t.answer('uno');
    await pumpEventQueue();
    // The utterances that closed meanwhile go out together, in one pass.
    expect(t.calls.length, first + 1);
    expect(t.calls.last.$1.length, greaterThanOrEqualTo(3 * 16 * 1500));
    expect(t.maxInFlight, 1);
    t.answer('uno dos tres');
    await pumpEventQueue();

    expect(heard.last, 'uno dos tres');
    await r.dispose();
  });

  test('the open utterance is refreshed only when nothing else is pending', () async {
    final t = _SlowTranscriber();
    final r = SegmentedRecognizer(t, language: 'es', refresh: Duration.zero);
    r.heard.listen((_) {});

    r.accept(_frames(1500, 0.08)); // speaking, not closed → a refresh
    expect(t.calls.length, 1);
    r.accept(_frames(1500, 0.08)); // still busy → no second request
    expect(t.calls.length, 1);
    t.answer('hola a');
    await pumpEventQueue();
    r.accept(_frames(300, 0.08)); // free again → refresh the open utterance
    expect(t.calls.length, 2);
    await r.dispose();
  });
}

// The speech tests wait for the recognizer to catch up instead of sleeping a
// fixed time, and judge its speed on their own: these fakes check that a
// decoder keeping up passes and one at half real-time speed still fails —
// the load tolerance hides no real slowdown. Real time, ~20 s; no models.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/services/speech/recognizers.dart';

import 'native_speech.dart';

/// Hears one word per 100 ms chunk, [speed] × real time after it arrives
/// (1.0 keeps up; 0.5 takes twice as long as the audio lasts).
class _FakeDecoder implements LiveRecognizer {
  _FakeDecoder(this.speed);
  final double speed;
  final _updates = StreamController<HeardUpdate>.broadcast();
  final _clock = Stopwatch()..start();
  var _chunks = 0;
  var _busyUntil = Duration.zero;

  @override
  Stream<HeardUpdate> get updates => _updates.stream;

  @override
  Stream<String> get heard => _updates.stream.map((u) => u.text);

  @override
  void accept(Float32List samples) {
    final n = ++_chunks;
    // Work queues up: each chunk takes 100 ms / speed of decoding.
    final start = _busyUntil > _clock.elapsed ? _busyUntil : _clock.elapsed;
    _busyUntil = start + Duration(microseconds: (100000 / speed).round());
    Timer(_busyUntil - _clock.elapsed, () {
      if (!_updates.isClosed) _updates.add(HeardUpdate(partial: 'word$n', clock: n * 0.1));
    });
  }

  @override
  void clear() {}

  @override
  Future<void> dispose() => _updates.close();
}

Future<(Playback, Drained)> _run(double speed) async {
  final decoder = _FakeDecoder(speed);
  final pb = Playback();
  final sub = decoder.updates.listen((u) => pb.heard(u.clock));
  await playInto(decoder, Float32List(16000 * 6), playback: pb);
  final drained = await drain(pb);
  await sub.cancel();
  await decoder.dispose();
  return (pb, drained);
}

void main() {
  test('a decoder that keeps up drains at once and passes', () async {
    final (pb, drained) = await _run(1.0);
    expect(drained.timedOut, isFalse);
    expect(drained.backlog, lessThan(const Duration(seconds: 1)));
    drained.expectKeptUp(pb);
  });

  test('a decoder at half real-time speed is waited for, then fails the speed check', () async {
    final (pb, drained) = await _run(0.5);
    expect(drained.timedOut, isFalse, reason: 'the drain waits for it to finish');
    expect(drained.backlog, greaterThan(const Duration(seconds: 5)));
    expect(() => drained.expectKeptUp(pb), throwsA(isA<TestFailure>()));
  });
}

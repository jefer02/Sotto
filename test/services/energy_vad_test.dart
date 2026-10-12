import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/services/speech/audio_capture.dart';

/// One 30 ms frame of a 220 Hz tone at [amplitude].
Float32List _frame(double amplitude) =>
    Float32List.fromList([for (var i = 0; i < 480; i++) amplitude * math.sin(2 * math.pi * 220 * i / 16000)]);

/// Fluent reading: loud and soft syllables, no pause long enough to end.
const _syllables = [0.08, 0.07, 0.05, 0.03, 0.02, 0.04, 0.07, 0.03];

void main() {
  group('EnergyVad', () {
    test('keeps hearing fluent reading instead of raising its floor into the voice', () {
      final vad = EnergyVad();
      var frames = 0, speaking = 0;
      for (var k = 0; k < 20000 ~/ 30; k++) {
        vad.accept(_frame(_syllables[k % _syllables.length]));
        if (k * 30 < 2000) continue;
        frames++;
        if (vad.speaking) speaking++;
      }
      // Before the fix the floor chased the voice and this was ~3 %.
      expect(speaking / frames, greaterThan(0.95));
    });

    test('ends speech after a real pause', () {
      final vad = EnergyVad();
      for (var k = 0; k < 100; k++) {
        vad.accept(_frame(_syllables[k % _syllables.length]));
      }
      expect(vad.speaking, isTrue);
      for (var k = 0; k < 1000 ~/ 30; k++) {
        vad.accept(_frame(0.002));
      }
      expect(vad.speaking, isFalse);
      expect(vad.silenceMs, greaterThanOrEqualTo(900));
    });

    test('room noise is not speech, and speech over it is heard', () {
      final vad = EnergyVad();
      for (var k = 0; k < 15000 ~/ 30; k++) {
        vad.accept(_frame(0.012));
      }
      expect(vad.speaking, isFalse);
      for (var k = 0; k < 20; k++) {
        vad.accept(_frame(_syllables[k % _syllables.length] * 2));
      }
      expect(vad.speaking, isTrue);
    });
  });
}

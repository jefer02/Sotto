// A Spanish presenter (synthesized, see test/fixtures/speech_es/generate.py)
// reads a 15-beat script with pauses, an ad-lib and room noise, played in
// real time through the same Whisper path a Spanish session uses. Skipped
// unless the model is installed and the native libraries are built (see
// native_speech.dart).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/data/models/script.dart';
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/domain/following/follow_engine.dart';
import 'package:sotto/domain/following/script_aligner.dart';
import 'package:sotto/services/speech/model_manager.dart';
import 'package:sotto/services/speech/recognizers.dart';

import 'native_speech.dart';

const _fixtures = 'test/fixtures/speech_es';

/// Follows natural.wav and returns (beat the presenter is on, beat shown)
/// for every recognizer update.
Future<List<(int, int)>> _follow(String modelId) async {
  final files = await ModelManager.findFiles(modelDir(modelId)!);
  final engine = await SherpaEngine.start(whisper: files, language: 'es');
  final seg = SegmentedRecognizer(engine, language: 'es-ES');

  final beats = File('$_fixtures/beats.txt').readAsLinesSync();
  final marks = [
    for (final l in File('$_fixtures/natural_marks.txt').readAsLinesSync())
      (double.parse(l.split(' ')[0]), int.parse(l.split(' ')[1])),
  ];
  // The ad-lib counts as still being on the beat before it.
  int presenterOn(double t) {
    var beat = 0;
    for (final (start, b) in marks) {
      if (start <= t && b >= 0) beat = b;
    }
    return beat;
  }

  final now = DateTime(2026);
  final script = Script(
    id: 's',
    title: 'Resultados',
    createdAt: now,
    updatedAt: now,
    sections: [
      Section(id: 'a', title: 'Uno', beats: [for (final b in beats) Beat.create(b)]),
    ],
  );
  final follow = FollowEngine(
    FlatScript.from(script, language: 'es-ES'),
    settings: const AppSettings(language: 'es-ES'),
  )..jumpTo(0);

  final trace = <(int, int)>[];
  final clock = Stopwatch()..start();
  final sub = seg.heard.listen((t) {
    follow.onHeard(t);
    trace.add((presenterOn(clock.elapsedMilliseconds / 1000), follow.position.beat));
  });
  await playInto(seg, readWav('$_fixtures/natural.wav'));
  await Future<void>.delayed(const Duration(seconds: 3));
  await sub.cancel();
  await seg.dispose();
  await engine.dispose();
  // ignore: avoid_print
  print('$modelId (presenter, shown): $trace');
  return trace;
}

void main() {
  final native = loadNativeSpeech();
  String? skip(SpeechModel m) => !native
      ? 'native speech libraries not built'
      : modelDir(m.id) == null
      ? 'model not installed'
      : null;

  test(
    'Whisper Base keeps up with a Spanish read and never runs ahead',
    () async {
      final trace = await _follow(ModelCatalog.whisperBase.id);
      for (final (on, shown) in trace) {
        // Advancing at 80 % of a beat may show the next one a little early,
        // never two ahead; and following stays within a beat of the voice.
        expect(shown - on, lessThanOrEqualTo(1), reason: 'ran ahead: $trace');
        expect(on - shown, lessThanOrEqualTo(1), reason: 'fell behind: $trace');
      }
      expect(trace.last.$2, greaterThanOrEqualTo(13));
    },
    skip: skip(ModelCatalog.whisperBase) ?? false,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  // Turbo is slower than real time on many CPUs; before one-at-a-time
  // transcription it fell ~5 beats behind and then raced on every pause.
  test(
    'Whisper Turbo may lag but neither piles up nor races ahead',
    () async {
      final trace = await _follow(ModelCatalog.whisperTurbo.id);
      for (final (on, shown) in trace) {
        expect(shown - on, lessThanOrEqualTo(1), reason: 'ran ahead: $trace');
        expect(on - shown, lessThanOrEqualTo(2), reason: 'fell behind: $trace');
      }
      expect(trace.last.$2, greaterThanOrEqualTo(12));
    },
    skip: skip(ModelCatalog.whisperTurbo) ?? false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

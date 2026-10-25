// A Spanish presenter (synthesized, see test/fixtures/speech_es/generate.py)
// reads a 15-beat script with pauses, an ad-lib and room noise, played in
// real time through the paths a Spanish session uses: the streaming model,
// and segmented Whisper when it isn't installed. Skipped unless the model is
// installed and the native libraries are built (see native_speech.dart).
// SOTTO_MODELS_ROOT adds folders to look for models in.
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
Future<List<(int, int)>> _follow(SpeechModel model) async {
  final files = await ModelManager.findFiles(modelDir(model.id)!);
  final streaming = model.role == ModelRole.streaming;
  final engine = streaming
      ? await SherpaEngine.start(
          streaming: files,
          streams: OffsetStreams.countFor(ModelCatalog.streamingEs.chunkSeconds),
        )
      : await SherpaEngine.start(whisper: files, language: 'es');
  final LiveRecognizer seg = streaming
      ? engine
      : SegmentedRecognizer(engine, language: 'es-ES', refresh: SegmentedRecognizer.followingRefresh);

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
  // As a live session listens: committed words apart from the partial.
  final sub = seg.updates.listen((u) {
    follow.onUpdate(u);
    trace.add((presenterOn(clock.elapsedMilliseconds / 1000), follow.position.saidBeat));
  });
  await playInto(seg, readWav('$_fixtures/natural.wav'));
  await Future<void>.delayed(const Duration(seconds: 3));
  await sub.cancel();
  if (!streaming) await seg.dispose();
  await engine.dispose();
  // ignore: avoid_print
  print('${model.id} (presenter, shown): $trace');
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
    'the streaming model follows a Spanish read within a beat and never runs ahead',
    () async {
      final trace = await _follow(ModelCatalog.streamingEs);
      for (final (on, shown) in trace) {
        // A finished beat shows the next one as current: one ahead at most.
        expect(shown - on, lessThanOrEqualTo(1), reason: 'ran ahead: $trace');
        expect(on - shown, lessThanOrEqualTo(1), reason: 'fell behind: $trace');
      }
      expect(trace.last.$2, greaterThanOrEqualTo(14));
    },
    skip: skip(ModelCatalog.streamingEs) ?? false,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'Whisper Base keeps up with a Spanish read and never runs ahead',
    () async {
      final trace = await _follow(ModelCatalog.whisperBase);
      for (final (on, shown) in trace) {
        // A finished beat shows the next one as current: one ahead at most.
        expect(shown - on, lessThanOrEqualTo(1), reason: 'ran ahead: $trace');
        // Only words a second update agrees on count, so a beat's last words
        // can still be unconfirmed as the next one starts: two behind for a
        // moment, never more…
        expect(on - shown, lessThanOrEqualTo(2), reason: 'fell behind: $trace');
      }
      // …and within a beat of the voice almost all the time.
      final close = trace.where((t) => t.$1 - t.$2 <= 1).length;
      expect(close / trace.length, greaterThanOrEqualTo(0.95), reason: 'fell behind: $trace');
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
      final trace = await _follow(ModelCatalog.whisperTurbo);
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

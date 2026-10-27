// Runs the real on-device pipeline: sherpa-onnx in its worker isolate,
// fed a recorded WAV in 100 ms chunks the way the microphone does, driving
// the follow engine over a script. Each test is skipped unless its model is
// installed (Settings → Voice & following); SOTTO_MODELS_ROOT overrides
// where models are looked for. On Windows a local build provides the
// native libraries (build/windows/x64/runner/…, or SOTTO_NATIVE_DIR).
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/data/models/script.dart';
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/domain/following/follow_engine.dart';
import 'package:sotto/domain/following/script_aligner.dart';
import 'package:sotto/services/speech/model_manager.dart';
import 'package:sotto/services/speech/recognizers.dart';

import 'native_speech.dart';

Script _script(List<String> beats) {
  final now = DateTime(2026);
  return Script(
    id: 's',
    title: 'Test',
    createdAt: now,
    updatedAt: now,
    sections: [
      Section(id: 'a', title: 'One', beats: [for (final b in beats) Beat.create(b)]),
    ],
  );
}

/// Plays [wav] into [recognizer] with a follow engine listening, the way
/// LiveController wires them, and returns the engine and the last words heard.
Future<(FollowEngine, String)> _follow(LiveRecognizer recognizer, Script script, String wav) async {
  final follow = FollowEngine(FlatScript.from(script), settings: const AppSettings())..jumpTo(0);
  var last = '';
  final events = <FollowEvent>[];
  final pb = Playback();
  final sub = recognizer.updates.listen((u) {
    pb.heard(u.clock);
    last = u.text;
    events.add(follow.onHeard(u.text));
  });
  await playInto(recognizer, readWav(wav), playback: pb);
  // Until the recognizer has caught up, not a fixed sleep.
  final drained = await drain(pb);
  await sub.cancel();
  drained.expectKeptUp(pb, share: 0.5);
  // ignore: avoid_print
  print(
    'heard: $last\nposition: beat ${follow.position.beat}, '
    'events: ${events.where((e) => e != FollowEvent.none).toList()}',
  );
  return (follow, last.toLowerCase());
}

void main() {
  final native = loadNativeSpeech();
  final streamingDir = modelDir(ModelCatalog.streamingEnLight.id);
  final whisperDir = modelDir(ModelCatalog.whisperBase.id);

  String? skip(String? dir) => !native
      ? 'native speech libraries not built'
      : dir == null
      ? 'model not installed'
      : null;

  test(
    'streaming recognizer (English) drives the follow engine',
    () async {
      final files = await ModelManager.findFiles(streamingDir!);
      expect(files, isNotNull, reason: 'model files not found in $streamingDir');
      final engine = await SherpaEngine.start(startTimeout: engineStartTimeout, streaming: files);
      final script = _script([
        'Welcome, everyone.',
        'After early nightfall the yellow lamps would light up here and there.',
        'The squalid quarter of the brothels.',
        'Thank you.',
      ]);
      final (follow, text) = await _follow(engine, script, '$streamingDir/test_wavs/0.wav');
      await engine.dispose();

      expect(text, contains('yellow lamps'));
      // It skipped the unspoken first beat and followed the reading past
      // "light up here and there".
      expect(follow.position.beat, greaterThanOrEqualTo(2));
    },
    skip: skip(streamingDir) ?? false,
    timeout: const Timeout(Duration(minutes: 5)),
  );

  // Every language but English follows through Whisper re-transcribing the
  // open utterance (SegmentedRecognizer), so this is the Spanish path.
  test(
    'Whisper through the segmented recognizer drives the follow engine',
    () async {
      final files = await ModelManager.findFiles(whisperDir!);
      expect(files, isNotNull, reason: 'model files not found in $whisperDir');
      final engine = await SherpaEngine.start(startTimeout: engineStartTimeout, whisper: files, language: 'en');
      expect(engine.canFollow, isFalse);
      final seg = SegmentedRecognizer(engine, language: 'en');
      final script = _script([
        'Good evening.',
        'God, as a direct consequence of the sin which man thus punished,',
        'had given her a lovely child,',
        'whose place was on that same dishonoured bosom,',
        'to connect her parent for ever with the race and descent of mortals,',
        'and to be finally a blessed soul in heaven.',
      ]);
      final (follow, text) = await _follow(seg, script, '$whisperDir/test_wavs/1.wav');
      await seg.dispose();
      await engine.dispose();

      expect(text, contains('lovely child'));
      expect(follow.position.beat, greaterThanOrEqualTo(4));
    },
    skip: skip(whisperDir) ?? false,
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

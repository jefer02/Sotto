// Runs the real on-device pipeline: sherpa-onnx in its worker isolate,
// fed a recorded WAV in 100 ms chunks the way the microphone does, driving
// the follow engine over a script. Skipped unless the light English
// streaming model is installed (Settings → Voice & following), or
// SOTTO_MODEL_DIR points at an extracted model folder.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/data/models/script.dart';
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/domain/following/follow_engine.dart';
import 'package:sotto/domain/following/script_aligner.dart';
import 'package:sotto/services/speech/model_manager.dart';
import 'package:sotto/services/speech/recognizers.dart';

String? _modelDir() {
  final env = Platform.environment['SOTTO_MODEL_DIR'];
  if (env != null) return env;
  final home = Platform.environment['HOME'] ?? '';
  final dir = '$home/.local/share/app.sotto.sotto/models/sherpa-onnx-streaming-zipformer-en-20M-2023-02-17';
  return Directory(dir).existsSync() ? dir : null;
}

/// 16-bit PCM mono WAV → float samples.
Float32List _readWav(String path) {
  final b = File(path).readAsBytesSync();
  final data = ByteData.sublistView(b);
  var offset = 12;
  while (offset < b.length - 8) {
    final id = String.fromCharCodes(b.sublist(offset, offset + 4));
    final size = data.getUint32(offset + 4, Endian.little);
    if (id == 'data') {
      final n = size ~/ 2;
      return Float32List.fromList([
        for (var i = 0; i < n; i++) data.getInt16(offset + 8 + i * 2, Endian.little) / 32768.0,
      ]);
    }
    offset += 8 + size;
  }
  throw StateError('no data chunk');
}

void main() {
  final dir = _modelDir();

  test(
    'sherpa streaming recognizer drives the follow engine',
    () async {
      final files = await ModelManager.findFiles(dir!);
      expect(files, isNotNull, reason: 'model files not found in $dir');

      final engine = await SherpaEngine.start(streaming: files);
      final heard = <String>[];
      final sub = engine.heard.listen(heard.add);

      final now = DateTime(2026);
      final script = Script(
        id: 's',
        title: 'Test',
        createdAt: now,
        updatedAt: now,
        sections: [
          Section(
            id: 'a',
            title: 'One',
            beats: [
              Beat.create('Welcome, everyone.'),
              Beat.create('After early nightfall the yellow lamps would light up here and there.'),
              Beat.create('The squalid quarter of the brothels.'),
              Beat.create('Thank you.'),
            ],
          ),
        ],
      );
      final follow = FollowEngine(FlatScript.from(script), settings: const AppSettings())..jumpTo(0);
      final events = <FollowEvent>[];
      final followSub = engine.heard.listen((t) => events.add(follow.onHeard(t)));

      final audio = _readWav('$dir/test_wavs/0.wav');
      const chunk = 1600; // 100 ms
      for (var i = 0; i < audio.length; i += chunk) {
        engine.accept(Float32List.sublistView(audio, i, i + chunk > audio.length ? audio.length : i + chunk));
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      // Trailing silence lets the recognizer finish the last words.
      for (var i = 0; i < 10; i++) {
        engine.accept(Float32List(chunk));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await Future<void>.delayed(const Duration(seconds: 1));

      await sub.cancel();
      await followSub.cancel();
      await engine.dispose();

      final text = heard.isEmpty ? '' : heard.last.toLowerCase();
      // ignore: avoid_print
      print(
        'heard: $text\nposition: beat ${follow.position.beat}, events: ${events.where((e) => e != FollowEvent.none).toList()}',
      );
      expect(text, contains('yellow lamps'));
      // It should have skipped the unspoken first beat and followed the reading
      // past "light up here and there".
      expect(follow.position.beat, greaterThanOrEqualTo(2));
    },
    skip: dir == null ? 'streaming model not installed' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

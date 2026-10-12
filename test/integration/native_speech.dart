// Shared setup for tests that run the real sherpa-onnx pipeline.
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sotto/services/speech/recognizers.dart';

/// Where the app keeps downloaded models on this machine.
String modelsRoot() {
  if (Platform.environment['SOTTO_MODELS_ROOT'] case final env?) return env;
  if (Platform.isWindows) return p.join(Platform.environment['APPDATA'] ?? '', 'Sotto', 'Sotto', 'models');
  if (Platform.isMacOS) {
    return p.join(Platform.environment['HOME'] ?? '', 'Library', 'Application Support', 'app.sotto.sotto', 'models');
  }
  return p.join(Platform.environment['HOME'] ?? '', '.local', 'share', 'app.sotto.sotto', 'models');
}

/// Folder of an installed model, or null.
String? modelDir(String id) {
  final dir = p.join(modelsRoot(), id);
  return Directory(dir).existsSync() ? dir : null;
}

/// The test runner is not the app, so on Windows the native libraries
/// next to sotto.exe aren't found by name. Load them by full path from a
/// local build (or SOTTO_NATIVE_DIR); returns false when none exists.
bool loadNativeSpeech() {
  if (!Platform.isWindows) return true;
  final dirs = [
    ?Platform.environment['SOTTO_NATIVE_DIR'],
    for (final mode in ['Release', 'Profile', 'Debug']) p.join('build', 'windows', 'x64', 'runner', mode),
    p.join(Platform.environment['LOCALAPPDATA'] ?? '', 'Programs', 'Sotto'),
  ];
  for (final dir in dirs) {
    final api = p.join(dir, 'sherpa-onnx-c-api.dll');
    if (!File(api).existsSync()) continue;
    preloadOnnxRuntime([dir]);
    DynamicLibrary.open(api);
    return true;
  }
  return false;
}

/// 16-bit PCM mono WAV → float samples.
Float32List readWav(String path) {
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

/// Feeds [audio] the way the microphone does: 100 ms chunks in real time
/// ([speed] > 1 plays faster), then a second of silence.
Future<void> playInto(LiveRecognizer r, Float32List audio, {double speed = 1}) async {
  const chunk = 1600; // 100 ms
  final pause = Duration(microseconds: (100000 / speed).round());
  for (var i = 0; i < audio.length; i += chunk) {
    final end = i + chunk > audio.length ? audio.length : i + chunk;
    r.accept(Float32List.sublistView(audio, i, end));
    await Future<void>.delayed(pause);
  }
  for (var i = 0; i < 10; i++) {
    r.accept(Float32List(chunk));
    await Future<void>.delayed(pause);
  }
}

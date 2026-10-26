// Shared setup for tests that run the real sherpa-onnx pipeline.
import 'dart:ffi';
import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart' show TestFailure;
import 'package:path/path.dart' as p;
import 'package:sotto/services/speech/recognizers.dart';

/// Where the app keeps downloaded models on this machine.
String modelsRoot() {
  if (Platform.isWindows) return p.join(Platform.environment['APPDATA'] ?? '', 'Sotto', 'Sotto', 'models');
  if (Platform.isMacOS) {
    return p.join(Platform.environment['HOME'] ?? '', 'Library', 'Application Support', 'app.sotto.sotto', 'models');
  }
  return p.join(Platform.environment['HOME'] ?? '', '.local', 'share', 'app.sotto.sotto', 'models');
}

/// Folders searched for models: SOTTO_MODELS_ROOT (several joined with the
/// OS path separator) before the app's own.
List<String> modelsRoots() => [
  ...?Platform.environment['SOTTO_MODELS_ROOT']?.split(Platform.isWindows ? ';' : ':').where((r) => r.isNotEmpty),
  modelsRoot(),
];

/// Folder of an installed model, or null.
String? modelDir(String id) {
  for (final root in modelsRoots()) {
    final dir = p.join(root, id);
    if (Directory(dir).existsSync()) return dir;
  }
  return null;
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

/// How long a test lets the engine load its models. The app allows 30 s;
/// a test machine running other test files in parallel can take several
/// times that just to read and map the model files. Only a worker that
/// never comes up — a real failure — runs into this.
const engineStartTimeout = Duration(minutes: 2);

/// Starts [start] and prints how long loading took, so a slow machine shows
/// in the log instead of as a mystery timeout.
Future<T> timedStart<T>(String what, Future<T> Function() start) async {
  final clock = Stopwatch()..start();
  final engine = await start();
  // ignore: avoid_print
  print('$what loaded in ${clock.elapsedMilliseconds} ms');
  return engine;
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

/// How a playback into a recognizer went, filled in as it runs, so
/// listeners can judge positions by audio time and the wait afterwards can
/// scale with how loaded the machine was.
class Playback {
  final clock = Stopwatch();
  var _chunks = 0;
  var _speed = 1.0;
  var _seconds = 0.0;
  Duration _finishedAt = Duration.zero;

  /// How far the feeder ever fell behind its own schedule: a starved test
  /// process (another job hogging the CPU) shows here.
  Duration lateness = Duration.zero;

  /// When a recognizer update last arrived, on [clock]; listeners call
  /// [heard].
  Duration lastHeard = Duration.zero;

  /// The newest `HeardUpdate.clock` seen: audio the recognizer has
  /// processed, in seconds. Null for recognizers that don't report it.
  double? recognizerClock;

  /// Wall time between consecutive updates: how often this recognizer, on
  /// this machine right now, speaks up.
  final gaps = <Duration>[];

  /// The 90th percentile of [gaps], or null before there are a few.
  Duration? get gapP90 {
    if (gaps.length < 5) return null;
    final sorted = [...gaps]..sort();
    return sorted[(sorted.length * 0.9).floor().clamp(0, sorted.length - 1)];
  }

  /// Audio fed so far, in seconds of the recording.
  double get fedSeconds => _chunks * 0.1;

  /// Seconds of audio in the recording (without the trailing silence).
  double get audioSeconds => _seconds;

  /// Wall time per second of audio while feeding: 1.0 when the machine kept
  /// up, more when it couldn't.
  double get ratio => _seconds == 0 ? 1 : math.max(1, (_finishedAt.inMicroseconds / 1e6) * _speed / fedSeconds);

  void heard([double? recognizerClock]) {
    final now = clock.elapsed;
    if (lastHeard > Duration.zero) gaps.add(now - lastHeard);
    lastHeard = now;
    if (recognizerClock != null) this.recognizerClock = recognizerClock;
  }
}

/// Feeds [audio] the way the microphone does: 100 ms chunks in real time
/// ([speed] > 1 plays faster), then a second of silence. [playback], when
/// given, follows along.
///
/// Each chunk is due at its own time on one stopwatch. Chained 100 ms
/// delays each run a little long (Windows timers tick every ~15.6 ms), and
/// over a two-minute take the "real time" drifted ~5 s ahead of the audio.
Future<Playback> playInto(LiveRecognizer r, Float32List audio, {double speed = 1, Playback? playback}) async {
  const chunk = 1600; // 100 ms
  final pb = playback ?? Playback();
  pb
    .._speed = speed
    .._seconds = audio.length / 16000;
  if (!pb.clock.isRunning) pb.clock.start();
  final start = pb.clock.elapsed;
  var n = 0;
  Future<void> feed(Float32List samples) async {
    r.accept(samples);
    n++;
    pb._chunks = n;
    final due = start + Duration(microseconds: (n * 100000 / speed).round());
    final wait = due - pb.clock.elapsed;
    if (wait > Duration.zero) {
      await Future<void>.delayed(wait);
    } else if (-wait > pb.lateness) {
      pb.lateness = -wait;
    }
  }

  for (var i = 0; i < audio.length; i += chunk) {
    await feed(Float32List.sublistView(audio, i, i + chunk > audio.length ? audio.length : i + chunk));
  }
  for (var i = 0; i < 10; i++) {
    await feed(Float32List(chunk));
  }
  pb._finishedAt = pb.clock.elapsed - start;
  return pb;
}

/// Waits for the recognizer to finish what it was fed — instead of a fixed
/// sleep, which a loaded machine overruns and an idle one wastes. Done once
/// both the end of the audio and the last update are a quiet window in the
/// past: [quiet], or twice the 90th percentile of the gaps between updates
/// seen during playback when that is longer (slow Whisper Turbo speaks up
/// seldom), scaled by how far playback fell behind real time
/// ([Playback.ratio]). Gives up after [max] (default: half the audio's
/// length plus 10 s), scaled the same way.
///
/// [Drained.backlog] is how long the recognizer kept producing output after
/// the audio ended — what a slow decoder shows, whatever the load.
Future<Drained> drain(Playback pb, {Duration quiet = const Duration(milliseconds: 1500), Duration? max}) async {
  final scale = pb.ratio;
  final limit = (max ?? Duration(milliseconds: (pb.audioSeconds * 500).round() + 10000)) * scale;
  final p90 = pb.gapP90;
  final settle = (p90 != null && p90 * 2 > quiet ? p90 * 2 : quiet) * scale;
  final started = pb.clock.elapsed;
  var timedOut = true;
  while (pb.clock.elapsed - started < limit) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final now = pb.clock.elapsed;
    if (now - started >= settle && now - pb.lastHeard >= settle) {
      timedOut = false;
      break;
    }
  }
  final backlog = pb.lastHeard > started ? pb.lastHeard - started : Duration.zero;
  final result = Drained(backlog: backlog, waited: pb.clock.elapsed - started, timedOut: timedOut);
  // ignore: avoid_print
  print(
    'playback: ${pb.audioSeconds.toStringAsFixed(1)} s of audio, wall/audio ${pb.ratio.toStringAsFixed(2)}, '
    'feeder late by up to ${pb.lateness.inMilliseconds} ms, update gap p90 ${p90?.inMilliseconds ?? '-'} ms; '
    'backlog ${result.backlog.inMilliseconds} ms, waited ${result.waited.inMilliseconds} ms'
    '${timedOut ? ' (gave up)' : ''}',
  );
  return result;
}

class Drained {
  const Drained({required this.backlog, required this.waited, required this.timedOut});
  final Duration backlog;
  final Duration waited;
  final bool timedOut;

  /// A decoder that can't keep up with real time ends far behind: at half
  /// real-time speed the backlog is about half the audio. Load slows it a
  /// little; a real regression a lot.
  void expectKeptUp(Playback pb, {double share = 0.25}) {
    final allowed = Duration(milliseconds: (pb.audioSeconds * 1000 * share * pb.ratio).round() + 2000);
    if (timedOut || backlog > allowed) {
      throw TestFailure(
        'the recognizer fell behind real time: ${backlog.inMilliseconds} ms of work left after '
        '${pb.audioSeconds.toStringAsFixed(1)} s of audio (allowed ${allowed.inMilliseconds} ms'
        '${timedOut ? ', and it never caught up' : ''})',
      );
    }
  }
}

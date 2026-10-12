import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../l10n/l10n.dart';
import 'audio_capture.dart';
import 'model_manager.dart';

/// Continuous recognition. [heard] emits the recent transcript tail
/// (finalized words + the current partial) after every update.
abstract class LiveRecognizer {
  Stream<String> get heard;
  void accept(Float32List samples);

  /// Forget history — e.g. when a question capture starts.
  void clear();
  Future<void> dispose();
}

/// One-shot, accurate transcription of a captured clip.
abstract class Transcriber {
  Future<String> transcribe(Float32List audio, {String? language, String? prompt});
  Future<void> dispose();
}

/// Windows 11 ships an older `onnxruntime.dll` in System32 (1.17), and
/// sherpa-onnx needs the one bundled next to the app (1.28). Whichever copy
/// the process loads first wins, so load ours by full path before sherpa
/// binds; otherwise the engine aborts with "API version [N] is not
/// available". [dirs] lists where to look — the app folder by default.
void preloadOnnxRuntime([List<String>? dirs]) {
  if (!Platform.isWindows) return;
  for (final dir in dirs ?? [p.dirname(Platform.resolvedExecutable)]) {
    final dll = p.join(dir, 'onnxruntime.dll');
    if (!File(dll).existsSync()) continue;
    try {
      DynamicLibrary.open(dll);
      return;
    } catch (_) {}
  }
}

String isoLanguage(String bcp47) => bcp47.split(RegExp('[-_]')).first.toLowerCase();

// ───────────────────────── sherpa-onnx worker ─────────────────────────

class _WorkerConfig {
  const _WorkerConfig({this.streaming, this.whisper, this.whisperLanguage = ''});
  final ModelFiles? streaming;
  final ModelFiles? whisper;
  final String whisperLanguage;
}

/// Runs in a background isolate: model inference never touches the UI
/// thread, so the overlay keeps its 120 Hz budget.
void _sherpaWorker((SendPort, _WorkerConfig) args) {
  final (main, cfg) = args;
  final inbox = ReceivePort();
  main.send(inbox.sendPort);

  sherpa.OnlineRecognizer? online;
  sherpa.OnlineStream? stream;
  sherpa.OfflineRecognizer? offline;

  try {
    preloadOnnxRuntime();
    sherpa.initBindings();
    if (cfg.streaming case final s?) {
      online = sherpa.OnlineRecognizer(
        sherpa.OnlineRecognizerConfig(
          model: sherpa.OnlineModelConfig(
            transducer: sherpa.OnlineTransducerModelConfig(
              encoder: s.encoder!,
              decoder: s.decoder!,
              joiner: s.joiner ?? '',
            ),
            tokens: s.tokens,
            numThreads: 2,
            debug: false,
          ),
          rule2MinTrailingSilence: 0.8,
        ),
      );
      stream = online.createStream();
    }
    if (cfg.whisper case final w?) {
      offline = sherpa.OfflineRecognizer(
        sherpa.OfflineRecognizerConfig(
          model: sherpa.OfflineModelConfig(
            whisper: sherpa.OfflineWhisperModelConfig(
              encoder: w.encoder!,
              decoder: w.decoder!,
              language: cfg.whisperLanguage,
              task: 'transcribe',
            ),
            tokens: w.tokens,
            numThreads: 3,
            debug: false,
          ),
        ),
      );
    }
    main.send(('ready', null, null));
  } catch (e) {
    main.send(('error', '$e', null));
    return;
  }

  inbox.listen((msg) {
    final (String kind, Object? payload, int? id) = msg as (String, Object?, int?);
    try {
      switch (kind) {
        case 'audio' when online != null && stream != null:
          stream.acceptWaveform(samples: payload! as Float32List, sampleRate: AudioCapture.sampleRate);
          while (online.isReady(stream)) {
            online.decode(stream);
          }
          final text = online.getResult(stream).text;
          final endpoint = online.isEndpoint(stream);
          main.send(('partial', text, endpoint ? 1 : 0));
          if (endpoint) online.reset(stream);
        case 'reset' when online != null && stream != null:
          online.reset(stream);
        case 'transcribe' when offline != null:
          final s = offline.createStream();
          // Whisper wants a little trailing silence to close the last word.
          final padded = Float32List((payload! as Float32List).length + AudioCapture.sampleRate ~/ 2)
            ..setAll(0, payload as Float32List);
          s.acceptWaveform(samples: padded, sampleRate: AudioCapture.sampleRate);
          offline.decode(s);
          final text = offline.getResult(s).text;
          s.free();
          main.send(('transcript', text, id));
        case 'dispose':
          stream?.free();
          online?.free();
          offline?.free();
          inbox.close();
          Isolate.exit();
      }
    } catch (e) {
      main.send(('error', '$e', id));
    }
  });
}

/// On-device engine: streaming transducer for following, Whisper for
/// questions. Either model may be absent.
class SherpaEngine implements LiveRecognizer, Transcriber {
  SherpaEngine._();

  late final SendPort _send;
  late final Isolate _isolate;
  final _heard = StreamController<String>.broadcast();
  final _pending = <int, Completer<String>>{};
  var _nextId = 0;
  bool _hasStreaming = false;
  bool _hasWhisper = false;

  final _committed = <String>[];
  String _partial = '';

  bool get canFollow => _hasStreaming;
  bool get canTranscribe => _hasWhisper;

  static Future<SherpaEngine> start({ModelFiles? streaming, ModelFiles? whisper, String language = ''}) async {
    final engine = SherpaEngine._();
    final port = ReceivePort();
    final ready = Completer<void>();
    engine._isolate = await Isolate.spawn(_sherpaWorker, (
      port.sendPort,
      _WorkerConfig(streaming: streaming, whisper: whisper, whisperLanguage: language),
    ), debugName: 'sherpa-onnx');
    engine._hasStreaming = streaming != null;
    engine._hasWhisper = whisper != null;

    port.listen((msg) {
      if (msg is SendPort) {
        engine._send = msg;
        return;
      }
      final (String kind, Object? payload, int? id) = msg as (String, Object?, int?);
      switch (kind) {
        case 'ready':
          ready.complete();
        case 'partial':
          engine._onPartial(payload! as String, id == 1);
        case 'transcript':
          engine._pending.remove(id)?.complete((payload! as String).trim());
        case 'error':
          if (!ready.isCompleted) {
            ready.completeError(StateError(L10n.current.sttEngineFailed('$payload')));
          } else if (id != null) {
            engine._pending.remove(id)?.completeError(StateError('$payload'));
          }
      }
    });
    await ready.future.timeout(const Duration(seconds: 30));
    return engine;
  }

  void _onPartial(String text, bool endpoint) {
    _partial = text.trim();
    if (endpoint) {
      if (_partial.isNotEmpty) _committed.addAll(_partial.split(' '));
      _partial = '';
      if (_committed.length > 40) _committed.removeRange(0, _committed.length - 40);
    }
    _heard.add([..._committed, if (_partial.isNotEmpty) _partial].join(' '));
  }

  @override
  Stream<String> get heard => _heard.stream;

  @override
  void accept(Float32List samples) {
    if (_hasStreaming) _send.send(('audio', samples, null));
  }

  @override
  void clear() {
    _committed.clear();
    _partial = '';
    if (_hasStreaming) _send.send(('reset', null, null));
  }

  @override
  Future<String> transcribe(Float32List audio, {String? language, String? prompt}) {
    if (!_hasWhisper) return Future.error(StateError(L10n.current.sttNoModel));
    final id = _nextId++;
    final c = Completer<String>();
    _pending[id] = c;
    _send.send(('transcribe', audio, id));
    return c.future.timeout(const Duration(seconds: 45));
  }

  @override
  Future<void> dispose() async {
    _send.send(('dispose', null, null));
    await _heard.close();
    for (final c in _pending.values) {
      c.completeError(StateError(L10n.current.sttStopped));
    }
    _pending.clear();
    Future<void>.delayed(const Duration(seconds: 2), () => _isolate.kill());
  }
}

// ─────────────────── Segmented recognition over a Transcriber ───────────────────

/// Pseudo-streaming for engines that only transcribe whole clips (Whisper): voice activity cuts the audio into utterances, and the open
/// utterance is re-transcribed about once a second so words keep arriving.
class SegmentedRecognizer implements LiveRecognizer {
  SegmentedRecognizer(
    this.transcriber, {
    required this.language,
    this.prompt,
    this.refresh = const Duration(milliseconds: 1100),
  });

  final Transcriber transcriber;
  final String language;
  final String? prompt;
  final Duration refresh;

  final _vad = EnergyVad();
  final _heard = StreamController<String>.broadcast();
  final _segment = <double>[];

  /// Utterances that ended while a transcription was running.
  final _closed = <Float32List>[];
  final _committed = <String>[];
  String _partial = '';
  bool _busy = false;
  DateTime _lastRun = DateTime.fromMillisecondsSinceEpoch(0);
  int _generation = 0;

  static const _maxSegmentSamples = AudioCapture.sampleRate * 8;

  /// Most audio sent in one catch-up pass (Whisper's window is 30 s).
  static const _maxPassSamples = AudioCapture.sampleRate * 20;
  static const _minSamples = AudioCapture.sampleRate ~/ 4;

  @override
  Stream<String> get heard => _heard.stream;

  @override
  void accept(Float32List samples) {
    _vad.accept(samples);
    if (_vad.speaking || _segment.isNotEmpty) _segment.addAll(samples);

    final ended = !_vad.speaking && _vad.silenceMs >= 450 && _segment.isNotEmpty;
    final tooLong = _segment.length >= _maxSegmentSamples;
    if (ended || tooLong) {
      if (_segment.length >= _minSamples) _closed.add(Float32List.fromList(_segment));
      _segment.clear();
      _pump();
    } else if (_vad.speaking && DateTime.now().difference(_lastRun) >= refresh) {
      _pump();
    }
  }

  /// Runs one transcription at a time. Requests never queue up behind a slow
  /// model: utterances that close meanwhile are transcribed together in the
  /// next pass, and the open one is only refreshed when nothing is pending.
  /// A queue made a slow model (Whisper Turbo on a CPU) fall seconds behind
  /// the presenter and then race through the backlog on the next pause.
  Future<void> _pump() async {
    if (_busy || _heard.isClosed) return;
    final Float32List audio;
    final bool finalize;
    if (_closed.isNotEmpty) {
      var take = 0, length = 0;
      while (take < _closed.length && (take == 0 || length + _closed[take].length <= _maxPassSamples)) {
        length += _closed[take++].length;
      }
      audio = Float32List(length);
      var offset = 0;
      for (final c in _closed.take(take)) {
        audio.setAll(offset, c);
        offset += c.length;
      }
      _closed.removeRange(0, take);
      finalize = true;
    } else if (_segment.length >= _minSamples) {
      audio = Float32List.fromList(_segment);
      finalize = false;
    } else {
      return;
    }

    _busy = true;
    _lastRun = DateTime.now();
    final gen = _generation;
    try {
      final text = await transcriber.transcribe(audio, language: language, prompt: prompt);
      if (gen != _generation || _heard.isClosed) return;
      if (finalize) {
        _committed.addAll(text.split(' ').where((w) => w.isNotEmpty));
        if (_committed.length > 40) _committed.removeRange(0, _committed.length - 40);
        _partial = '';
      } else {
        _partial = text;
      }
      _heard.add([..._committed, if (_partial.isNotEmpty) _partial].join(' '));
    } catch (_) {
      // A dropped segment only costs a little tracking; hotkeys still work.
    } finally {
      _busy = false;
    }
    if (_closed.isNotEmpty) unawaited(_pump());
  }

  @override
  void clear() {
    _generation++;
    _segment.clear();
    _closed.clear();
    _committed.clear();
    _partial = '';
    _vad.reset();
  }

  @override
  Future<void> dispose() async {
    _generation++;
    await _heard.close();
  }
}

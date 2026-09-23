import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
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

// ───────────────────────── Cloud transcription ─────────────────────────

/// OpenAI-compatible `/audio/transcriptions` — the optional cloud fallback.
class CloudTranscriber implements Transcriber {
  CloudTranscriber({required this.apiKey, required this.model, required this.baseUrl});

  final String apiKey;
  final String model;
  final String baseUrl;
  final _http = http.Client();

  @override
  Future<String> transcribe(Float32List audio, {String? language, String? prompt}) async {
    final uri = Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/audio/transcriptions');
    final req = http.MultipartRequest('POST', uri)
      ..headers['authorization'] = 'Bearer $apiKey'
      ..fields['model'] = model
      ..fields['response_format'] = 'json'
      ..files.add(http.MultipartFile.fromBytes('file', encodeWav(audio), filename: 'audio.wav'));
    if (language != null && language.isNotEmpty) req.fields['language'] = isoLanguage(language);
    if (prompt != null && prompt.isNotEmpty) req.fields['prompt'] = prompt;
    final res = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 30)));
    if (res.statusCode != 200) {
      throw StateError(
        res.statusCode == 401
            ? L10n.current.sttBadKey
            : L10n.current.sttCloudFailed(res.statusCode),
      );
    }
    return ((jsonDecode(res.body) as Map)['text'] as String? ?? '').trim();
  }

  @override
  Future<void> dispose() async => _http.close();
}

Uint8List encodeWav(Float32List samples, {int sampleRate = AudioCapture.sampleRate}) {
  final data = ByteData(44 + samples.length * 2);
  void str(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  data.setUint32(4, 36 + samples.length * 2, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  data
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, sampleRate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little);
  str(36, 'data');
  data.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(44 + i * 2, (samples[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}

// ─────────────────── Segmented recognition over a Transcriber ───────────────────

/// Pseudo-streaming for engines that only transcribe whole clips (Whisper,
/// cloud): voice activity cuts the audio into utterances, and the open
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
  final _committed = <String>[];
  String _partial = '';
  bool _busy = false;
  DateTime _lastRun = DateTime.fromMillisecondsSinceEpoch(0);
  int _generation = 0;

  static const _maxSegmentSamples = AudioCapture.sampleRate * 8;

  @override
  Stream<String> get heard => _heard.stream;

  @override
  void accept(Float32List samples) {
    _vad.accept(samples);
    if (_vad.speaking || _segment.isNotEmpty) _segment.addAll(samples);

    final ended = !_vad.speaking && _vad.silenceMs >= 450 && _segment.isNotEmpty;
    final tooLong = _segment.length >= _maxSegmentSamples;
    if (ended || tooLong) {
      _run(finalize: true);
    } else if (_vad.speaking && DateTime.now().difference(_lastRun) >= refresh) {
      _run(finalize: false);
    }
  }

  Future<void> _run({required bool finalize}) async {
    if (_busy && !finalize) return;
    _lastRun = DateTime.now();
    final audio = Float32List.fromList(_segment);
    final gen = _generation;
    if (finalize) _segment.clear();
    if (audio.length < AudioCapture.sampleRate ~/ 4) return;
    _busy = true;
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
  }

  @override
  void clear() {
    _generation++;
    _segment.clear();
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

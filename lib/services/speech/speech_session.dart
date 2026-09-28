import 'dart:async';
import 'dart:typed_data';

import '../../data/models/settings.dart';
import '../../data/storage/secret_store.dart';
import '../../l10n/l10n.dart';
import 'audio_capture.dart';
import 'model_manager.dart';
import 'recognizers.dart';

/// Which engines a session ended up with — shown in pre-flight and in
/// Settings → Voice & following ("Ready · On-device").
class EngineReport {
  const EngineReport({required this.following, required this.questions, required this.canFollow, this.warning});

  /// Human labels, in the interface language.
  final String following;
  final String questions;
  final bool canFollow;
  final String? warning;
}

class QuestionProgress {
  const QuestionProgress({required this.text, required this.silence, required this.elapsed});

  /// Words heard so far.
  final String text;

  /// 0..1 — how full the silence ring is.
  final double silence;
  final Duration elapsed;
}

/// Owns the microphone and recognizers for one live session.
///
/// Following runs whenever the session is live. Room capture — for a
/// question — runs only between the chord and the end of the question.
class SpeechSession {
  SpeechSession._(this._settings, this._mic, this._follower, this._transcriber, this.report, this._disposables);

  final AppSettings _settings;
  final AudioCapture _mic;
  final LiveRecognizer? _follower;
  final Transcriber? _transcriber;
  final EngineReport report;
  final List<Future<void> Function()> _disposables;

  AudioCapture? _questionInput;
  StreamSubscription<Float32List>? _micSub;
  StreamSubscription<Float32List>? _questionSub;

  bool _capturing = false;
  final _questionAudio = <double>[];
  final _vad = EnergyVad();
  LiveRecognizer? _questionRecognizer;
  StreamSubscription<String>? _questionTextSub;
  String _questionText = '';
  DateTime? _captureStart;
  bool _heardSpeech = false;
  final _progress = StreamController<QuestionProgress>.broadcast();
  final _silenceReached = StreamController<void>.broadcast();

  Stream<String> get heard => _follower?.heard ?? const Stream.empty();
  Stream<double> get level => _mic.level;
  Stream<QuestionProgress> get questionProgress => _progress.stream;

  /// Fires once the configured silence has elapsed after speech.
  Stream<void> get questionSilence => _silenceReached.stream;

  bool get isCapturing => _capturing;

  static Future<SpeechSession> start({
    required AppSettings settings,
    required SecretStore secrets,
    required ModelManager models,
    List<String> hints = const [],
  }) async {
    final disposables = <Future<void> Function()>[];
    LiveRecognizer? follower;
    Transcriber? transcriber;
    final l = L10n.current;
    String following = l.engineUnavailable, questions = l.engineUnavailable;
    var canFollow = false, canAnswer = false;
    String? warning;

    final english = settings.language.toLowerCase().startsWith('en');
    final prompt = hints.isEmpty ? null : hints.join(', ');

    Future<CloudTranscriber?> cloud() async {
      final key = await secrets.read(SecretKey.cloudSttApiKey);
      if (key == null) return null;
      final base = settings.cloudSttBaseUrl.isNotEmpty ? settings.cloudSttBaseUrl : 'https://api.openai.com/v1';
      return CloudTranscriber(apiKey: key, model: settings.cloudSttModel, baseUrl: base);
    }

    if (settings.engine == SpeechEngine.onDevice) {
      final streaming = english
          ? (await models.locate(ModelCatalog.streamingEn) ?? await models.locate(ModelCatalog.streamingEnLight))
          : null;
      final whisper = await models.locate(ModelCatalog.whisperTurbo) ?? await models.locate(ModelCatalog.whisperBase);
      if (streaming != null || whisper != null) {
        final engine = await SherpaEngine.start(
          streaming: streaming,
          whisper: whisper,
          language: isoLanguage(settings.language),
        );
        disposables.add(engine.dispose);
        if (engine.canFollow) {
          follower = engine;
          following = l.engineOnDeviceStreaming;
        } else {
          final seg = SegmentedRecognizer(engine, language: settings.language, prompt: prompt);
          disposables.add(seg.dispose);
          follower = seg;
          following = l.engineOnDeviceWhisper;
        }
        if (engine.canTranscribe) {
          transcriber = engine;
          questions = l.engineOnDeviceWhisper;
          canAnswer = true;
        }
      } else {
        warning = l.engineModelsMissing;
      }
    }

    // Cloud: chosen explicitly, or as the fallback when on-device is missing.
    if (follower == null || transcriber == null) {
      final c = await cloud();
      if (c != null) {
        disposables.add(c.dispose);
        if (follower == null) {
          final seg = SegmentedRecognizer(c, language: settings.language, prompt: prompt);
          disposables.add(seg.dispose);
          follower = seg;
          following = l.engineCloud;
        }
        transcriber ??= c;
        if (!canAnswer) questions = l.engineCloud;
        canAnswer = true;
        warning = settings.engine == SpeechEngine.cloud ? null : warning;
      } else if (settings.engine == SpeechEngine.cloud) {
        warning = l.engineCloudKeyMissing;
      }
    }
    // Last resort for questions: the streaming model's own words.
    if (transcriber == null && follower != null) questions = following;
    canFollow = follower != null;

    final mic = AudioCapture();
    disposables.add(mic.dispose);
    await mic.start(deviceId: settings.microphoneId, noiseSuppression: settings.noiseSuppression);

    final session = SpeechSession._(
      settings,
      mic,
      follower,
      transcriber,
      EngineReport(following: following, questions: questions, canFollow: canFollow, warning: warning),
      disposables,
    );
    session._micSub = mic.samples.listen(session._onMic);
    return session;
  }

  void _onMic(Float32List samples) {
    if (_capturing) {
      if (_questionInput == null) _onQuestionAudio(samples);
      return;
    }
    _follower?.accept(samples);
  }

  // ───────────────────────── Question capture ─────────────────────────

  Future<void> beginQuestion() async {
    if (_capturing) return;
    _capturing = true;
    _questionAudio.clear();
    _vad.reset();
    _heardSpeech = false;
    _questionText = '';
    _captureStart = DateTime.now();

    if (_settings.questionInputId != null && _settings.questionInputId != _settings.microphoneId) {
      final input = AudioCapture();
      _questionInput = input;
      try {
        await input.start(deviceId: _settings.questionInputId, noiseSuppression: false);
        _questionSub = input.samples.listen(_onQuestionAudio);
      } catch (_) {
        await input.dispose();
        _questionInput = null; // falls back to the microphone
      }
    }

    // Live words while the question is asked: the streaming model if we
    // have one, otherwise segmented re-transcription.
    final follower = _follower;
    if (follower is SherpaEngine && follower.canFollow) {
      follower.clear();
      _questionRecognizer = follower;
    } else if (_transcriber != null) {
      _questionRecognizer = SegmentedRecognizer(
        _transcriber,
        language: _settings.language,
        refresh: const Duration(milliseconds: 900),
      );
    }
    _questionTextSub = _questionRecognizer?.heard.listen((t) {
      _questionText = t;
      _emitProgress();
    });
    _emitProgress();
  }

  void _onQuestionAudio(Float32List samples) {
    if (!_capturing) return;
    _questionAudio.addAll(samples);
    _questionRecognizer?.accept(samples);
    _vad.accept(samples);
    if (_vad.speaking) _heardSpeech = true;
    _emitProgress();
    final limit = _settings.silenceSeconds * 1000;
    if (_heardSpeech && _vad.silenceMs >= limit) {
      _silenceReached.add(null);
    }
  }

  void _emitProgress() {
    final limit = _settings.silenceSeconds * 1000;
    _progress.add(
      QuestionProgress(
        text: _questionText,
        silence: _heardSpeech && !_vad.speaking ? (_vad.silenceMs / limit).clamp(0, 1) : 0,
        elapsed: DateTime.now().difference(_captureStart ?? DateTime.now()),
      ),
    );
  }

  /// Ends capture and returns the most accurate transcript available.
  Future<String> endQuestion() async {
    if (!_capturing) return '';
    _capturing = false;
    await _stopQuestionInput();
    final audio = Float32List.fromList(_questionAudio);
    _questionAudio.clear();
    final live = _questionText.trim();
    _resetQuestionRecognizer();

    if (_transcriber != null && audio.length > AudioCapture.sampleRate ~/ 2) {
      try {
        final text = await _transcriber.transcribe(audio, language: _settings.language);
        if (text.isNotEmpty) return text;
      } catch (_) {
        // Fall through to the live transcript.
      }
    }
    return live;
  }

  Future<void> cancelQuestion() async {
    _capturing = false;
    _questionAudio.clear();
    await _stopQuestionInput();
    _resetQuestionRecognizer();
  }

  void _resetQuestionRecognizer() {
    _questionTextSub?.cancel();
    _questionTextSub = null;
    final r = _questionRecognizer;
    if (r != null && r != _follower) unawaited(r.dispose());
    _questionRecognizer = null;
    _follower?.clear();
  }

  Future<void> _stopQuestionInput() async {
    await _questionSub?.cancel();
    _questionSub = null;
    await _questionInput?.dispose();
    _questionInput = null;
  }

  Future<void> dispose() async {
    await _micSub?.cancel();
    await cancelQuestion();
    for (final d in _disposables.reversed) {
      try {
        await d();
      } catch (_) {}
    }
    await _progress.close();
    await _silenceReached.close();
  }
}

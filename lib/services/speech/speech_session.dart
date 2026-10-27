import 'dart:async';
import 'dart:typed_data';

import '../../data/models/settings.dart';
import '../../l10n/l10n.dart';
import 'audio_capture.dart';
import 'model_manager.dart';
import 'recognizers.dart';

/// Which engines a session ended up with — shown in pre-flight and in
/// Settings → Voice & following ("Ready · On-device").
class EngineReport {
  const EngineReport({
    required this.following,
    required this.questions,
    required this.canFollow,
    this.warning,
    this.plan,
  });

  /// Human labels, in the interface language.
  final String following;
  final String questions;
  final bool canFollow;
  final String? warning;

  /// Which model follows, and why.
  final FollowingPlan? plan;
}

/// Why following uses the model it does.
enum FollowingWhy {
  /// A streaming model for the language: each word as it is said.
  streaming,

  /// The language has a streaming model, but it isn't installed: Whisper
  /// follows meanwhile, a phrase at a time.
  whisperUntilStreamingInstalled,

  /// No streaming model speaks the language: Whisper, a phrase at a time.
  whisperOnly,

  /// No model at all: following needs a download.
  none,
}

/// Which model follows the voice in [language]. Streaming models hear each
/// word as it is said; Whisper only transcribes whole utterances (voice
/// activity cuts the audio, the open one is re-read about once a second), so
/// it waits for pauses and then moves a phrase at once. Whisper stays the
/// engine for question capture and dictation, where a full transcript
/// matters more than latency.
class FollowingPlan {
  const FollowingPlan({required this.why, this.model, this.recommended});

  final FollowingWhy why;

  /// The model that follows (null: none installed).
  final SpeechModel? model;

  /// The streaming model to download for word-by-word following, when it
  /// isn't installed yet.
  final SpeechModel? recommended;

  bool get streaming => why == FollowingWhy.streaming;
}

/// [installed]: ids of the models on this computer.
FollowingPlan planFollowing(String language, Set<String> installed) {
  final candidates = ModelCatalog.streamingFor(language);
  final streaming = candidates.where((m) => installed.contains(m.id)).firstOrNull;
  if (streaming != null) return FollowingPlan(why: FollowingWhy.streaming, model: streaming);
  // Following re-transcribes the open utterance about once a second, so it
  // takes the fastest Whisper installed.
  final whisper = [
    ModelCatalog.whisperBase,
    ModelCatalog.whisperTurbo,
  ].where((m) => installed.contains(m.id)).firstOrNull;
  final recommended = candidates.firstOrNull;
  if (whisper == null) return FollowingPlan(why: FollowingWhy.none, recommended: recommended);
  return FollowingPlan(
    why: recommended == null ? FollowingWhy.whisperOnly : FollowingWhy.whisperUntilStreamingInstalled,
    model: whisper,
    recommended: recommended,
  );
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
  SpeechSession._(
    this._settings,
    this._mic,
    this._follower,
    this._transcriber,
    this._liveTranscriber,
    this.report,
    this._disposables,
  );

  final AppSettings _settings;
  final AudioCapture _mic;
  final LiveRecognizer? _follower;
  final Transcriber? _transcriber;

  /// The fastest Whisper loaded, for words that have to keep up with speech.
  final Transcriber? _liveTranscriber;
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

  /// What following listens to: committed words apart from the partial.
  Stream<HeardUpdate> get updates => _follower?.updates ?? const Stream.empty();
  Stream<double> get level => _mic.level;
  Stream<QuestionProgress> get questionProgress => _progress.stream;

  /// Fires once the configured silence has elapsed after speech.
  Stream<void> get questionSilence => _silenceReached.stream;

  bool get isCapturing => _capturing;

  static Future<SpeechSession> start({
    required AppSettings settings,
    required ModelManager models,
    List<String> hints = const [],
  }) async {
    final disposables = <Future<void> Function()>[];
    LiveRecognizer? follower;
    Transcriber? transcriber, liveTranscriber;
    final l = L10n.current;
    String following = l.engineUnavailable, questions = l.engineUnavailable;
    var canFollow = false;
    String? warning;

    final prompt = hints.isEmpty ? null : hints.join(', ');
    final files = <String, ModelFiles>{for (final m in ModelCatalog.all) m.id: ?await models.locate(m)};
    final plan = planFollowing(settings.language, files.keys.toSet());

    {
      final streaming = plan.streaming ? files[plan.model!.id] : null;
      final base = files[ModelCatalog.whisperBase.id];
      // The most accurate Whisper transcribes questions.
      final whisper = files[ModelCatalog.whisperTurbo.id] ?? base;
      if (streaming != null || whisper != null) {
        final engine = await SherpaEngine.start(
          streaming: streaming,
          whisper: whisper,
          language: isoLanguage(settings.language),
          streams: plan.streaming ? OffsetStreams.countFor(plan.model!.chunkSeconds) : 1,
        );
        disposables.add(engine.dispose);
        if (engine.canFollow) {
          follower = engine;
          following = l.engineOnDeviceStreamingModel(plan.model!.name);
        } else {
          // Following re-transcribes the open utterance about once a second,
          // so it needs the fastest Whisper. Turbo takes seconds per pass on a
          // CPU: the script lagged behind the voice, then raced ahead on pauses.
          Transcriber fast = engine;
          if (base != null && whisper != base) {
            final baseEngine = await SherpaEngine.start(whisper: base, language: isoLanguage(settings.language));
            disposables.add(baseEngine.dispose);
            fast = baseEngine;
          }
          liveTranscriber = fast;
          final seg = SegmentedRecognizer(
            fast,
            language: settings.language,
            prompt: prompt,
            refresh: SegmentedRecognizer.followingRefresh,
          );
          disposables.add(seg.dispose);
          follower = seg;
          following = l.engineOnDeviceWhisper;
          // Following works, but a phrase at a time: say how to do better.
          if (plan.recommended case final r?) warning = l.engineStreamingRecommended(r.name);
        }
        if (engine.canTranscribe) {
          transcriber = engine;
          questions = l.engineOnDeviceWhisper;
        }
      } else {
        warning = l.engineModelsMissing;
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
      liveTranscriber ?? transcriber,
      EngineReport(following: following, questions: questions, canFollow: canFollow, warning: warning, plan: plan),
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
    } else if (_liveTranscriber case final live?) {
      _questionRecognizer = SegmentedRecognizer(
        live,
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

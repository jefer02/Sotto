import 'dart:async';
import 'dart:typed_data';

import '../../data/models/settings.dart';
import '../../l10n/l10n.dart';
import 'audio_capture.dart';
import 'model_manager.dart';
import 'recognizers.dart';
import 'speech_session.dart';

/// Speech to text for chat messages (push-to-talk, the mic button). Always
/// on this computer: sherpa-onnx Whisper, never a cloud service.
abstract class Dictation {
  Future<void> begin();

  /// Stops listening; the transcript ('' when nothing was heard).
  Future<String> end();
  Future<void> cancel();
  Future<void> dispose();
}

/// Outside a live session: its own microphone and Whisper model, loaded on
/// first use and kept while the chat is open.
class StandaloneDictation implements Dictation {
  StandaloneDictation({required this.settings, required this.models});

  final AppSettings settings;
  final ModelManager models;

  SherpaEngine? _engine;
  AudioCapture? _mic;
  StreamSubscription<Float32List>? _sub;
  final _audio = <double>[];

  @override
  Future<void> begin() async {
    if (_mic != null) return;
    final whisper = await models.locate(ModelCatalog.whisperTurbo) ?? await models.locate(ModelCatalog.whisperBase);
    if (whisper == null) throw StateError(L10n.current.sttNoModel);
    _engine ??= await SherpaEngine.start(whisper: whisper, language: isoLanguage(settings.language));
    _audio.clear();
    final mic = _mic = AudioCapture();
    await mic.start(deviceId: settings.microphoneId, noiseSuppression: settings.noiseSuppression);
    _sub = mic.samples.listen(_audio.addAll);
  }

  Future<void> _stopMic() async {
    await _sub?.cancel();
    _sub = null;
    await _mic?.dispose();
    _mic = null;
  }

  @override
  Future<String> end() async {
    if (_mic == null) return '';
    await _stopMic();
    final audio = Float32List.fromList(_audio);
    _audio.clear();
    // Under a third of a second is a stray tap, not speech.
    if (audio.length < AudioCapture.sampleRate ~/ 3) return '';
    return (await _engine!.transcribe(audio, language: settings.language)).trim();
  }

  @override
  Future<void> cancel() async {
    await _stopMic();
    _audio.clear();
  }

  @override
  Future<void> dispose() async {
    await cancel();
    await _engine?.dispose();
    _engine = null;
  }
}

/// In a live session: the session's own microphone and recognizers (the
/// question-capture path), so nothing opens the microphone twice.
class SessionDictation implements Dictation {
  SessionDictation(this.session);

  final SpeechSession session;

  @override
  Future<void> begin() => session.beginQuestion();

  @override
  Future<String> end() async => (await session.endQuestion()).trim();

  @override
  Future<void> cancel() => session.cancelQuestion();

  @override
  Future<void> dispose() async {}
}

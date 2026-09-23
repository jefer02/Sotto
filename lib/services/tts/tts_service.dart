import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// On-device voices (AVSpeechSynthesizer on macOS, OneCore / SAPI on
/// Windows). Plays through the system output; with "Headphones only" the
/// pre-flight check reminds the presenter to wear them.
class TtsService {
  final _tts = FlutterTts();
  bool _speaking = false;

  bool get isSpeaking => _speaking;

  /// False on platforms without a speech synthesizer plugin (Linux).
  bool available = true;

  Future<void> speak(String text, {String? language, String? voice}) async {
    await stop();
    if (!available) return;
    if (language != null) await _tts.setLanguage(language);
    if (voice != null) {
      await _tts.setVoice({'name': voice, 'locale': language ?? 'en-US'});
    }
    await _tts.setSpeechRate(0.5);
    _speaking = true;
    _tts.setCompletionHandler(() => _speaking = false);
    await _tts.speak(text);
  }

  Future<void> stop() async {
    _speaking = false;
    if (!available) return;
    try {
      await _tts.stop();
    } on MissingPluginException {
      available = false;
    }
  }

  Future<List<String>> voices() async {
    if (!available) return const [];
    final Object? raw;
    try {
      raw = await _tts.getVoices;
    } on MissingPluginException {
      available = false;
      return const [];
    }
    if (raw is! List) return const [];
    return [
      for (final v in raw)
        if (v is Map && v['name'] is String) v['name'] as String,
    ];
  }
}

final ttsProvider = Provider<TtsService>((ref) => TtsService());

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/services/speech/model_manager.dart';

/// Speech recognition is on this computer only: sherpa-onnx models fetched
/// once from GitHub releases, never a paid or cloud speech API.
void main() {
  test('every speech model downloads from the sherpa-onnx GitHub releases', () {
    for (final m in [
      ModelCatalog.streamingEn,
      ModelCatalog.streamingEnLight,
      ModelCatalog.whisperBase,
      ModelCatalog.whisperTurbo,
    ]) {
      expect(m.url, startsWith('https://github.com/k2-fsa/sherpa-onnx/releases/download/'), reason: m.id);
    }
  });

  test('no cloud speech-to-text endpoint anywhere in the app', () {
    final forbidden = RegExp(
      r'audio/transcriptions|api\.openai\.com|whisper-1|deepgram|assemblyai|speech\.googleapis|'
      r'cognitiveservices|stt\.|speech-to-text api|elevenlabs|api\.groq',
      caseSensitive: false,
    );
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.contains('l10n')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (forbidden.hasMatch(lines[i])) hits.add('${f.path}:${i + 1}: ${lines[i].trim()}');
      }
    }
    expect(hits, isEmpty);
  });

  test('the only hosts the app talks to are DeepSeek and GitHub', () {
    final url = RegExp(r'''https?://([a-z0-9.-]+)''', caseSensitive: false);
    final hosts = <String>{};
    for (final f in Directory('lib/services').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      for (final m in url.allMatches(f.readAsStringSync())) {
        hosts.add(m.group(1)!.toLowerCase());
      }
    }
    expect(hosts.difference({'api.deepseek.com', 'github.com', 'api-docs.deepseek.com'}), isEmpty);
  });
}

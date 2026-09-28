import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/l10n/l10n.dart';
import 'package:sotto/services/ai/llm_client.dart';

http.StreamedResponse _sse(List<Object> events, {int status = 200}) => http.StreamedResponse(
  Stream.value(utf8.encode([for (final e in events) 'data: ${e is String ? e : jsonEncode(e)}\n\n'].join())),
  status,
);

Map<String, Object?> _delta(Map<String, Object?> delta, {String? finish}) => {
  'choices': [
    {'index': 0, 'delta': delta, 'finish_reason': finish},
  ],
};

void main() {
  setUpAll(() => L10n.current = lookupAppLocalizations(const Locale('en')));

  test('streams content and ignores reasoning_content', () async {
    late Map<String, dynamic> sent;
    final client = DeepSeekClient(
      apiKey: 'k',
      model: 'deepseek-flash',
      httpClient: MockClient.streaming((req, body) async {
        sent = jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
        expect(req.url.toString(), 'https://api.deepseek.com/chat/completions');
        expect(req.headers['authorization'], 'Bearer k');
        return _sse([
          _delta({'reasoning_content': 'thinking…'}),
          _delta({'reasoning_content': null, 'content': 'Hello'}),
          _delta({'content': ' there'}, finish: 'stop'),
          '[DONE]',
        ]);
      }),
    );
    final out = await client.stream(system: 's', user: 'u').join();
    expect(out, 'Hello there');
    expect(sent['model'], 'deepseek-flash');
    expect(sent['stream'], true);
    expect(sent['thinking'], {'type': 'disabled'});
  });

  test('content_filter is a refusal', () async {
    final client = DeepSeekClient(
      apiKey: 'k',
      model: 'm',
      httpClient: MockClient.streaming((_, _) async => _sse([_delta({}, finish: 'content_filter')])),
    );
    expect(client.stream(system: 's', user: 'u').join(), throwsA(isA<LlmRefusal>()));
  });

  test('HTTP errors are typed', () async {
    final client = DeepSeekClient(
      apiKey: 'k',
      model: 'm',
      httpClient: MockClient((_) async => http.Response('{"error":{"message":"Insufficient Balance"}}', 402)),
    );
    await expectLater(
      client.stream(system: 's', user: 'u').join(),
      throwsA(isA<LlmException>().having((e) => e.statusCode, 'status', 402)),
    );
  });

  test('lists models', () async {
    final client = DeepSeekClient(
      apiKey: 'k',
      model: 'm',
      httpClient: MockClient((req) async {
        expect(req.url.path, '/models');
        return http.Response(
          jsonEncode({
            'object': 'list',
            'data': [
              {'id': 'deepseek-v4-pro', 'object': 'model'},
              {'id': 'deepseek-flash', 'object': 'model'},
            ],
          }),
          200,
        );
      }),
    );
    expect(await client.listModels(), ['deepseek-flash', 'deepseek-v4-pro']);
  });

  test('settings saved with another provider migrate to DeepSeek', () {
    final old = AppSettings.fromJson({
      'aiProvider': 'anthropic',
      'aiModel': 'claude-opus-5',
      'aiBaseUrl': 'https://api.anthropic.com',
    });
    expect(old.aiModel, defaultAiModel);
    expect(AppSettings.fromJson({'aiModel': 'deepseek-v4-pro'}).aiModel, 'deepseek-v4-pro');
    expect(old.toJson().containsKey('aiProvider'), isFalse);
  });
}

import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/l10n/l10n.dart';
import 'package:sotto/services/ai/deepseek_models.dart';
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

  test('images go to the vision model as image_url parts in the user message', () async {
    late Map<String, dynamic> sent;
    final client = DeepSeekClient(
      apiKey: 'k',
      model: 'deepseek-v4-pro',
      visionModel: 'deepseek-flash',
      httpClient: MockClient.streaming((req, body) async {
        sent = jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
        return _sse([
          _delta({'content': 'ok'}),
          '[DONE]',
        ]);
      }),
    );
    await client.stream(system: 's', user: 'what is this?', images: ['data:image/jpeg;base64,AAAA']).join();
    expect(sent['model'], 'deepseek-flash');
    final messages = sent['messages'] as List;
    expect((messages.first as Map)['content'], 's');
    expect((messages.last as Map)['content'], [
      {'type': 'text', 'text': 'what is this?'},
      {
        'type': 'image_url',
        'image_url': {'url': 'data:image/jpeg;base64,AAAA'},
      },
    ]);
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
              {
                'id': 'deepseek-v4-pro',
                'object': 'model',
                'input_modalities': ['text'],
              },
              {
                'id': 'deepseek-flash',
                'object': 'model',
                'input_modalities': ['text', 'image'],
              },
            ],
          }),
          200,
        );
      }),
    );
    final models = await client.listModels();
    expect([for (final m in models) m.id], ['deepseek-flash', 'deepseek-v4-pro']);
    expect([for (final m in models) m.images], [true, false]);
    // Screenshots go to a model that reads them.
    expect(pickVisionModel(models, 'deepseek-v4-pro'), 'deepseek-flash');
    expect(pickVisionModel(models, 'deepseek-flash'), 'deepseek-flash');
    expect(pickVisionModel(const [DeepSeekModel('x')], 'x'), isNull);
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

  test('task profiles decide thinking; JSON mode sets response_format', () async {
    final sent = <Map<String, dynamic>>[];
    final client = DeepSeekClient(
      apiKey: 'k',
      model: 'deepseek-flash',
      httpClient: MockClient.streaming((req, body) async {
        sent.add(jsonDecode(await body.bytesToString()) as Map<String, dynamic>);
        return _sse([
          _delta({'content': '{}'}),
          '[DONE]',
        ]);
      }),
    );
    await client.complete(system: 's', user: 'Return only JSON', profile: DeepSeekTaskProfile.organize, json: true);
    await client.complete(system: 's', user: 'u', profile: DeepSeekTaskProfile.questionnaire);
    await client.streamMessages(messages: [], profile: DeepSeekTaskProfile.chat(thinkDeeper: true)).drain<void>();
    expect(sent[0]['thinking'], {'type': 'disabled'});
    expect(sent[0]['response_format'], {'type': 'json_object'});
    expect(sent[1]['thinking'], {'type': 'enabled', 'reasoning_effort': 'low'});
    expect(sent[1].containsKey('response_format'), isFalse);
    expect(sent[2]['thinking'], {'type': 'enabled', 'reasoning_effort': 'high'});
    expect(DeepSeekTaskProfile.chat().thinking, isFalse);
    expect(DeepSeekTaskProfile.answers.thinking, isFalse);
    expect(DeepSeekTaskProfile.agent.effort, ReasoningEffort.low);
  });

  test('streamMessages surfaces reasoning_content separately', () async {
    final client = DeepSeekClient(
      apiKey: 'k',
      model: 'deepseek-flash',
      httpClient: MockClient.streaming(
        (req, body) async => _sse([
          _delta({'reasoning_content': 'hmm'}),
          _delta({'content': 'Hi'}),
          '[DONE]',
        ]),
      ),
    );
    final deltas = await client.streamMessages(messages: [], profile: DeepSeekTaskProfile.chat()).toList();
    expect(deltas.map((d) => d.reasoning).join(), 'hmm');
    expect(deltas.map((d) => d.content).join(), 'Hi');
  });
}

import 'dart:convert';
import 'dart:ui' show Locale, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sotto/domain/agent/agent_loop.dart';
import 'package:sotto/domain/agent/coordinates.dart';
import 'package:sotto/l10n/l10n.dart';
import 'package:sotto/services/ai/deepseek_agent.dart';
import 'package:sotto/services/ai/llm_client.dart';

const _screen = AgentScreen(
  image: 'data:image/jpeg;base64,AAAA',
  mapper: CoordinateMapper(imageWidth: 1300, imageHeight: 731, screen: Rect.fromLTWH(0, 0, 1920, 1080), scale: 1.25),
);

Map<String, Object?> _reply(Map<String, Object?> message) => {
  'choices': [
    {'index': 0, 'message': message, 'finish_reason': 'tool_calls'},
  ],
};

Map<String, Object?> _call(String id, String name, Map<String, Object?> args) => {
  'id': id,
  'type': 'function',
  'function': {'name': name, 'arguments': jsonEncode(args)},
};

void main() {
  setUpAll(() => L10n.current = lookupAppLocalizations(const Locale('en')));

  test('keeps the conversation valid: tool answers, one live screenshot, reasoning passed back', () async {
    final requests = <Map<String, dynamic>>[];
    final replies = [
      _reply({
        'role': 'assistant',
        'content': '',
        'reasoning_content': 'The email field is at the top.',
        'tool_calls': [
          _call('a', 'click', {'x': 100, 'y': 200, 'target': 'Email'}),
          _call('b', 'type_text', {'text': 'x', 'target': 'Email'}),
        ],
      }),
      _reply({
        'role': 'assistant',
        'content': '',
        'tool_calls': [
          _call('c', 'done', {'summary': 'ok'}),
        ],
      }),
    ];
    final client = DeepSeekClient(
      apiKey: 'k',
      model: 'deepseek-v4-pro',
      httpClient: MockClient((req) async {
        requests.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response(jsonEncode(replies[requests.length - 1]), 200);
      }),
    );
    final model = DeepSeekAgentModel(client: client, model: 'deepseek-flash', userData: 'Name: Ana');

    final first = await model.start('fill the form', _screen);
    expect(first.call!.name, 'click');
    final r0 = requests[0];
    expect(r0['model'], 'deepseek-flash');
    expect(r0['thinking'], {'type': 'enabled', 'reasoning_effort': 'low'});
    expect((r0['tools'] as List).length, 10);
    final messages0 = r0['messages'] as List;
    expect((messages0[0] as Map)['role'], 'system');
    expect((messages0[0] as Map)['content'], contains('Name: Ana'));
    // Images only ever travel in user messages.
    expect(((messages0[1] as Map)['content'] as List).last, {
      'type': 'image_url',
      'image_url': {'url': 'data:image/jpeg;base64,AAAA'},
    });

    final second = await model.next(result: 'ok', screen: _screen);
    expect(second.call!.name, 'done');
    final messages1 = (requests[1]['messages'] as List).cast<Map<String, dynamic>>();
    final assistant = messages1.firstWhere((m) => m['role'] == 'assistant');
    expect(assistant['reasoning_content'], 'The email field is at the top.');
    final tools = messages1.where((m) => m['role'] == 'tool').toList();
    expect([for (final t in tools) t['tool_call_id']], ['a', 'b']);
    expect(tools[0]['content'], 'ok');
    expect(tools[1]['content'], startsWith('skipped'));
    // Only the newest screenshot is still an image.
    final withImages = messages1.where((m) => m['role'] == 'user' && m['content'] is List);
    expect(withImages.length, 1);
    expect(messages1[1]['content'], contains('[earlier screenshot omitted]'));
  });

  test('a prose reply comes back as text without a call', () async {
    final client = DeepSeekClient(
      apiKey: 'k',
      model: 'm',
      httpClient: MockClient(
        (_) async => http.Response(jsonEncode(_reply({'role': 'assistant', 'content': 'I cannot see a form.'})), 200),
      ),
    );
    final turn = await DeepSeekAgentModel(client: client, model: 'm').start('t', _screen);
    expect(turn.call, isNull);
    expect(turn.text, 'I cannot see a form.');
  });
}

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sotto/data/models/chat.dart';
import 'package:sotto/data/repositories.dart';
import 'package:sotto/data/storage/local_store.dart';
import 'package:sotto/domain/chat/chat_context.dart';
import 'package:sotto/domain/chat/markdown.dart';
import 'package:sotto/l10n/l10n.dart';
import 'package:sotto/services/ai/chat_service.dart';
import 'package:sotto/services/ai/llm_client.dart';

ChatMessage _m(ChatRole role, String text, {String reasoning = '', String? error}) =>
    ChatMessage(id: text, role: role, text: text, at: DateTime(2026), reasoning: reasoning, error: error);

void main() {
  setUpAll(() => L10n.current = lookupAppLocalizations(const Locale('en')));

  group('ChatRepository', () {
    late Directory tmp;
    late LocalStore store;
    late ChatRepository repo;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('sotto_chat');
      store = await LocalStore.open(path: tmp.path);
      repo = ChatRepository(store);
    });

    tearDown(() async {
      await store.close();
      await tmp.delete(recursive: true);
    });

    test('saves, lists newest first, renames, deletes', () async {
      final a = Conversation.create('First').copyWith(messages: [ChatMessage.user('hi')]);
      await repo.save(a);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final b = Conversation.create('Second');
      await repo.save(b);
      final all = await repo.watchAll().first;
      expect(all.map((c) => c.title), ['Second', 'First']);
      expect(repo.get(a.id)!.messages.single.text, 'hi');

      await repo.save(repo.get(a.id)!.copyWith(title: 'Renamed', titled: true));
      expect(repo.get(a.id)!.title, 'Renamed');
      await repo.delete(b.id);
      expect(repo.get(b.id), isNull);
    });

    test('retention prunes old conversations; "delete all" clears them', () async {
      final old = Conversation.create('Old').copyWith(updatedAt: DateTime.now().subtract(const Duration(days: 40)));
      final fresh = Conversation.create('Fresh');
      await repo.save(old);
      await repo.save(fresh);
      expect(await repo.prune(30), 1);
      expect(repo.get(fresh.id), isNotNull);
      await store.wipe();
      expect(repo.get(fresh.id), isNull);
    });

    test('fromJson is tolerant of missing and unknown keys', () {
      final c = Conversation.fromJson({
        'id': 'x',
        'messages': [
          {'role': 'assistant', 'text': 'ok', 'extra': 1},
          'garbage',
        ],
        'future': true,
      });
      expect(c.title, '');
      expect(c.thinkDeeper, isFalse);
      expect(c.messages.single.role, ChatRole.assistant);
      final round = Conversation.fromJson(jsonDecode(jsonEncode(c.toJson())) as Map);
      expect(round.messages.single.text, 'ok');
    });
  });

  group('History trimming', () {
    test('keeps the last N messages, starting with the user', () {
      final msgs = [for (var i = 0; i < 30; i++) _m(i.isEven ? ChatRole.user : ChatRole.assistant, 'm$i')];
      final w = ChatContext.window(msgs, maxMessages: 5);
      // The 5 newest would start with an assistant reply: it is dropped.
      expect(w.map((m) => m.text), ['m26', 'm27', 'm28', 'm29']);
      expect(w.first.role, ChatRole.user);
    });

    test('drops the oldest until it fits; the newest always stays', () {
      final msgs = [_m(ChatRole.user, 'a' * 100), _m(ChatRole.assistant, 'b' * 100), _m(ChatRole.user, 'c' * 500)];
      expect(ChatContext.window(msgs, maxChars: 250).map((m) => m.text.length), [500]);
      expect(ChatContext.window(msgs, maxChars: 2000).length, 3);
    });

    test('skips failed and empty replies', () {
      final msgs = [_m(ChatRole.user, 'q1'), _m(ChatRole.assistant, '', error: 'offline'), _m(ChatRole.user, 'q2')];
      expect(ChatContext.window(msgs).map((m) => m.text), ['q1', 'q2']);
    });

    test('build: system first, screenshot on the newest user message, reasoning echoed only when thinking', () {
      final c = Conversation.create('t').copyWith(
        messages: [
          _m(ChatRole.user, 'q1'),
          _m(ChatRole.assistant, 'a1', reasoning: 'because'),
          _m(ChatRole.user, 'q2'),
        ],
      );
      final plain = ChatContext.build(c);
      expect(plain.first['role'], 'system');
      expect(plain[2].containsKey('reasoning_content'), isFalse);
      expect(plain.last['content'], 'q2');

      final deep = ChatContext.build(
        c,
        thinking: true,
        screenshot: 'data:image/jpeg;base64,AA',
        scriptContext: '# Talk',
      );
      expect(deep[2]['reasoning_content'], 'because');
      expect(deep[1]['content'], 'q1');
      expect((deep.last['content'] as List).last, {
        'type': 'image_url',
        'image_url': {'url': 'data:image/jpeg;base64,AA'},
      });
      expect(deep.first['content'] as String, contains('# Talk'));
    });

    test('clip keeps the start and the end', () {
      final s = ChatContext.clip('${'a' * 50}${'b' * 50}', 20);
      expect(s, startsWith('aaaaaaaaaa'));
      expect(s, endsWith('bbbbbbbbbb'));
    });
  });

  group('Voice-to-text insertion', () {
    test('at the end, with a space only when needed', () {
      expect(insertDictation('', 'hello there'), ('hello there', 11));
      expect(insertDictation('Say', 'hello'), ('Say hello', 9));
      expect(insertDictation('Say ', 'hello'), ('Say hello', 9));
    });

    test('at the caret, between words and before punctuation', () {
      expect(insertDictation('Tell me about.', 'the roadmap', caret: 13), ('Tell me about the roadmap.', 25));
      expect(insertDictation('ab', 'X', caret: 1), ('a X b', 3));
      expect(insertDictation('text', '  ', caret: 2), ('text', 2));
    });
  });

  group('Streaming Markdown', () {
    test('blocks: headings, lists, paragraphs, code', () {
      final b = ChatMarkdown.parse(
        '# Plan\n\nFirst **bold** line\ncontinues.\n\n- one\n- two\n  - nested\n1. first\n2) second\n\n```dart\nvoid main() {}\n```\nAfter.',
      );
      expect(b.map((x) => x.type), [
        MdBlockType.heading,
        MdBlockType.paragraph,
        MdBlockType.bullet,
        MdBlockType.bullet,
        MdBlockType.bullet,
        MdBlockType.numbered,
        MdBlockType.numbered,
        MdBlockType.code,
        MdBlockType.paragraph,
      ]);
      expect(b[1].text, 'First **bold** line continues.');
      expect(b[4].level, 1);
      expect(b[6].number, 2);
      expect(b[7].language, 'dart');
      expect(b[7].open, isFalse);
    });

    test('a half-streamed reply parses at every prefix without losing text', () {
      const full = 'Use **ship** `v2` now:\n\n```js\nconst a = 1;\n```\n- done';
      for (var i = 0; i <= full.length; i++) {
        final prefix = full.substring(0, i);
        final blocks = ChatMarkdown.parse(prefix); // never throws
        final shown = blocks.map((b) => ChatMarkdown.inline(b.text).map((s) => s.text).join()).join();
        expect(
          shown.replaceAll(RegExp(r'[\s*`]'), '').length,
          lessThanOrEqualTo(prefix.replaceAll(RegExp(r'[\s*`#-]'), '').length + 3),
        );
      }
      final open = ChatMarkdown.parse('Text\n```py\nprint(1)');
      expect(open.last.type, MdBlockType.code);
      expect(open.last.open, isTrue);
      expect(open.last.text, 'print(1)');
    });

    test('inline styles; unclosed markers stay text; snake_case is not italic', () {
      expect(ChatMarkdown.inline('a **b** *c* `d` e'), const [
        MdSpan('a ', MdStyle.plain),
        MdSpan('b', MdStyle.bold),
        MdSpan(' ', MdStyle.plain),
        MdSpan('c', MdStyle.italic),
        MdSpan(' ', MdStyle.plain),
        MdSpan('d', MdStyle.code),
        MdSpan(' e', MdStyle.plain),
      ]);
      expect(ChatMarkdown.inline('streaming **bol'), const [MdSpan('streaming **bol', MdStyle.plain)]);
      expect(ChatMarkdown.inline('my_var_name'), const [MdSpan('my_var_name', MdStyle.plain)]);
      expect(ChatMarkdown.plainText('- **Hi** there\n1. `x`'), '• Hi there\n1. x');
    });
  });

  test('ChatService streams over SSE: thinking off by default, reasoning kept apart', () async {
    final sent = <Map<String, dynamic>>[];
    final client = DeepSeekClient(
      apiKey: 'k',
      model: 'deepseek-flash',
      visionModel: 'deepseek-flash',
      httpClient: MockClient.streaming((req, body) async {
        sent.add(jsonDecode(await body.bytesToString()) as Map<String, dynamic>);
        final events = [
          {
            'choices': [
              {
                'delta': {'reasoning_content': 'let me see'},
              },
            ],
          },
          {
            'choices': [
              {
                'delta': {'content': 'Hel'},
              },
            ],
          },
          {
            'choices': [
              {
                'delta': {'content': 'lo'},
                'finish_reason': 'stop',
              },
            ],
          },
        ];
        return http.StreamedResponse(
          Stream.value(utf8.encode([for (final e in events) 'data: ${jsonEncode(e)}\n\n', 'data: [DONE]\n\n'].join())),
          200,
        );
      }),
    );
    final c = Conversation.create('t').copyWith(messages: [ChatMessage.user('hi')]);
    final deltas = await ChatService(client).reply(c).toList();
    expect(deltas.map((d) => d.content).join(), 'Hello');
    expect(deltas.map((d) => d.reasoning).join(), 'let me see');
    expect(sent.single['thinking'], {'type': 'disabled'});
    expect(sent.single['stream'], true);

    await ChatService(client).reply(c.copyWith(thinkDeeper: true)).drain<void>();
    expect(sent.last['thinking'], {'type': 'enabled', 'reasoning_effort': 'high'});
  });
}

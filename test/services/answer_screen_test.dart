import 'dart:typed_data';
import 'dart:ui' show Locale, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/data/models/qa_entry.dart';
import 'package:sotto/data/models/script.dart';
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/l10n/l10n.dart';
import 'package:sotto/services/ai/answer_service.dart';
import 'package:sotto/services/ai/llm_client.dart';
import 'package:sotto/services/screen/screen_service.dart';

/// Records what the answer service sends and replies with a fixed draft.
class _FakeLlm extends LlmClient {
  _FakeLlm(this.reply);
  final String reply;
  String? system;
  String? user;
  List<String> images = const [];

  @override
  Stream<String> stream({
    required String system,
    required String user,
    int maxTokens = 4096,
    DeepSeekTaskProfile profile = DeepSeekTaskProfile.answers,
    List<String> images = const [],
    bool json = false,
  }) async* {
    this.system = system;
    this.user = user;
    this.images = images;
    yield reply;
  }

  @override
  void close() {}
}

void main() {
  setUpAll(() => L10n.current = lookupAppLocalizations(const Locale('en')));

  final now = DateTime(2026);
  final script = Script(
    id: 's',
    title: 'Q3',
    createdAt: now,
    updatedAt: now,
    sections: [
      Section(id: 'a', title: 'Revenue', beats: [Beat.create('Revenue landed at 48.2 million.')]),
    ],
  );

  test('"Ask about screen" attaches the screenshot and cites it', () async {
    final llm = _FakeLlm(
      'HEADLINE: The chart shows Q3 revenue.\nPOINT: Up 12% || on Q2.\nSOURCE: Screen\nGENERAL: no\n',
    );
    final drafts = await AnswerService(llm)
        .draft(
          script: script,
          question: 'What is on my screen?',
          settings: const AppSettings(),
          screenshot: 'data:image/jpeg;base64,AAAA',
          aboutScreen: true,
        )
        .toList();
    expect(llm.images, ['data:image/jpeg;base64,AAAA']);
    expect(llm.user, contains('asking about what is on their screen'));
    expect(llm.system, contains('SOURCE: Screen'));
    final done = drafts.last;
    expect(done.complete, isTrue);
    expect(done.sources.first.kind, SourceKind.screen);
    // The screen is shown as a source from the very first event.
    expect(drafts.first.sources.first.kind, SourceKind.screen);
  });

  test('without a screenshot nothing about the screen is sent', () async {
    final llm = _FakeLlm('HEADLINE: 48.2 million.\nSOURCE: §1\nGENERAL: no\n');
    final drafts = await AnswerService(llm)
        .draft(script: script, question: 'What was revenue?', settings: const AppSettings())
        .toList();
    expect(llm.images, isEmpty);
    expect(llm.system, isNot(contains('screenshot')));
    expect(llm.user, contains('Question from the audience'));
    expect(drafts.last.sources.where((s) => s.kind == SourceKind.screen), isEmpty);
  });

  test('native capture results map to image and screen geometry', () {
    final c = ScreenCapture.fromMap({
      'jpeg': Uint8List.fromList([1, 2, 3]),
      'width': 1300,
      'height': 731,
      'left': -1920,
      'top': 0,
      'screenWidth': 1920.0,
      'screenHeight': 1080.0,
      'scale': 1.25,
      'method': 'wgc',
    });
    expect(c.screen, const Rect.fromLTWH(-1920, 0, 1920, 1080));
    expect(c.dataUrl, 'data:image/jpeg;base64,AQID');
    expect(c.scale, 1.25);
  });

  test('screen awareness is off by default and old settings load it off', () {
    expect(const AppSettings().screenAwareness, isFalse);
    expect(const AppSettings().attachSlideToAnswers, isFalse);
    expect(AppSettings.fromJson({'language': 'en-US'}).screenAwareness, isFalse);
  });
}

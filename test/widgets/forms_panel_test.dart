// The forms panel once a fill is over: the answers to fill in by hand when
// Sotto couldn't, with copy buttons; the chat about the form; and a window
// as tall as what it shows — never the screen.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/core/design/icons.dart';
import 'package:sotto/core/design/theme.dart';
import 'package:sotto/core/design/tokens.dart';
import 'package:sotto/core/platform/window_service.dart';
import 'package:sotto/data/models/chat.dart';
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/data/repositories.dart';
import 'package:sotto/domain/chat/chat_context.dart';
import 'package:sotto/domain/forms/manual_answers.dart';
import 'package:sotto/domain/forms/question_types.dart';
import 'package:sotto/domain/overlay/auto_height.dart';
import 'package:sotto/features/forms/autofill_view.dart';
import 'package:sotto/features/forms/form_assist.dart';
import 'package:sotto/features/questionnaire/questionnaire_controller.dart';
import 'package:sotto/features/questionnaire/questionnaire_view.dart';
import 'package:sotto/l10n/l10n.dart';
import 'package:sotto/services/ai/llm_client.dart';

import '../core/overlay_window_test.dart' show FakeWindowHost;

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings(formsEnabled: true);

  @override
  void update(AppSettings Function(AppSettings) change) => state = change(state);
}

class _Form extends QuestionnaireController {
  _Form(this.initial);
  final QuestionnaireState initial;

  @override
  QuestionnaireState build() => initial;

  void set(QuestionnaireState s) => state = s;
}

const _items = [
  FormItem(question: 'Full name', answer: 'Ana Ruiz', status: ItemStatus.filled),
  FormItem(
    question: 'How often do you use the app?',
    answer: 'Weekly',
    letter: 'B',
    type: QuestionType.multipleChoice,
    status: ItemStatus.failed,
    note: 'could not fill — please fill it yourself',
  ),
  FormItem(question: 'Anything else?', answer: 'Faster exports, please.', status: ItemStatus.failed),
  FormItem(
    question: 'Card number',
    answer: '',
    status: ItemStatus.blocked,
    note: 'password or payment field — never filled',
    editable: false,
  ),
];

/// "Could not fill": the run is over, most of it left to the presenter.
const _couldNotFill = QuestionnaireState(phase: FormPhase.finished, outcome: 'ready', items: _items);

/// Answers the chat with [reply] and keeps what it was sent.
class _FakeLlm extends LlmClient {
  _FakeLlm(this.reply);
  final String reply;
  List<Map<String, Object?>> sent = const [];

  @override
  Stream<String> stream({
    required String system,
    required String user,
    int maxTokens = 4096,
    DeepSeekTaskProfile profile = DeepSeekTaskProfile.answers,
    List<String> images = const [],
    bool json = false,
  }) => const Stream.empty();

  @override
  Stream<LlmDelta> streamMessages({
    required List<Map<String, Object?>> messages,
    required DeepSeekTaskProfile profile,
    int maxTokens = 4096,
    bool vision = false,
  }) async* {
    sent = messages;
    yield LlmDelta(content: reply);
  }

  @override
  void close() {}
}

Future<void> _loadFonts() async {
  for (final (family, file) in const [
    ('Geist', 'assets/fonts/Geist-Variable.ttf'),
    ('GeistMono', 'assets/fonts/GeistMono-Variable.ttf'),
  ]) {
    final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(File(file).readAsBytesSync())));
    await loader.load();
  }
}

Widget _host(List<Object> overrides, Widget child) => ProviderScope(
  overrides: [settingsProvider.overrideWith(_Settings.new), ...overrides.cast()],
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildSottoTheme(SottoPalette.stage),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Material(color: const Color(0xFF15181D), child: child),
  ),
);

void main() {
  setUpAll(() => L10n.current = lookupAppLocalizations(const Locale('en')));

  group('manual answers', () {
    final answers = _couldNotFill.manualAnswers;

    test('what is left to fill by hand, numbered like the panel', () {
      expect(ManualAnswers.needed(answers), 2);
      expect(answers.map((a) => a.number), [1, 2, 3, 4]);
      expect(answers[0].done, isTrue);
      expect(answers[1].shown, 'B) Weekly');
      expect(answers[1].copyText, 'Weekly');
    });

    test('"Copy all" leaves out password and payment fields', () {
      final all = ManualAnswers.copyAll(answers);
      expect(all, contains('2. How often do you use the app?\n   B) Weekly'));
      expect(all, contains('3. Anything else?\n   Faster exports, please.'));
      expect(all, isNot(contains('Card number')));
    });

    test('the chat gets the form, never a sensitive value, under the forms rules', () {
      final form = ManualAnswers.context(answers);
      expect(form, contains('4. Card number — password or payment field: never read or answered'));
      expect(form, contains('2. How often do you use the app? [multiple_choice] — suggested: B) Weekly'));
      final messages = ChatContext.build(
        Conversation.create('q').copyWith(messages: [ChatMessage.user('why B?')]),
        formContext: form,
      );
      final system = messages.first['content']! as String;
      expect(system, contains(ChatContext.formRules));
      expect(system, contains('graded test, quiz or exam'));
      expect(system, contains(form));
    });
  });

  group('the panel', () {
    late List<String> clipboard;

    setUp(() {
      clipboard = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') clipboard.add((call.arguments as Map)['text'] as String);
          return null;
        },
      );
    });

    testWidgets('could not fill: the answers to fill by hand, each with a copy button', (tester) async {
      await tester.runAsync(_loadFonts);
      tester.view.physicalSize = const Size(560, 520);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host([questionnaireControllerProvider.overrideWith(() => _Form(_couldNotFill))], const QuestionnaireView()),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      expect(find.text("Couldn't fill 2 answers — fill them in by hand"), findsOneWidget);
      expect(find.text('B) Weekly'), findsOneWidget);
      // Filled: marked done. Card number: no answer, no copy.
      expect(find.byWidgetPredicate((w) => w is SottoIcon && w.icon == SottoIcons.check), findsOneWidget);
      expect(find.byTooltip('Copy answer'), findsNWidgets(3));

      await tester.tap(find.byTooltip('Copy answer').at(1));
      expect(clipboard.last, 'Weekly');
      await tester.tap(find.text('Copy all'));
      expect(clipboard.last, ManualAnswers.copyAll(_couldNotFill.manualAnswers));
      expect(clipboard.last, isNot(contains('Card number')));
    });

    testWidgets('the chat asks about the form and shows the reply', (tester) async {
      await tester.runAsync(_loadFonts);
      tester.view.physicalSize = const Size(560, 520);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final llm = _FakeLlm('Because you said you use it **weekly**.');
      final form = _Form(_couldNotFill);
      await tester.pumpWidget(
        _host(
          [
            questionnaireControllerProvider.overrideWith(() => form),
            formChatClientProvider.overrideWithValue(() async => llm),
          ],
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: QuestionnaireView()),
              FormChat(),
            ],
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Why B on question 2?');
      await tester.tap(find.byTooltip(L10n.current.chatSend));
      await tester.pump();
      await tester.pump();

      expect(find.text('Why B on question 2?'), findsOneWidget);
      expect(find.textContaining('weekly', findRichText: true), findsOneWidget);
      final system = llm.sent.first['content']! as String;
      expect(system, contains('2. How often do you use the app? [multiple_choice] — suggested: B) Weekly'));
      expect(system, contains(ChatContext.formRules));
      expect(llm.sent.last, {'role': 'user', 'content': 'Why B on question 2?'});

      // While Sotto types into the form, the panel never takes the keyboard.
      form.set(const QuestionnaireState(phase: FormPhase.filling, items: _items));
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(find.text(L10n.current.formsChatBusy), findsOneWidget);
    });

    testWidgets('a new fill starts a new conversation', (tester) async {
      final form = _Form(_couldNotFill);
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(_Settings.new),
          questionnaireControllerProvider.overrideWith(() => form),
          formChatClientProvider.overrideWithValue(() async => _FakeLlm('ok')),
        ],
      );
      addTearDown(container.dispose);
      await tester.runAsync(() => container.read(formChatControllerProvider.notifier).send('rephrase 3'));
      expect(container.read(formChatControllerProvider).messages, hasLength(2));

      form.set(const QuestionnaireState(phase: FormPhase.reading));
      expect(container.read(formChatControllerProvider).messages, isEmpty);
    });
  });

  group('the panel window', () {
    testWidgets('is as tall as its content — compact, not the screen — and stays put', (tester) async {
      await tester.runAsync(_loadFonts);
      tester.view.physicalSize = const Size(560, 380);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final host = FakeWindowHost(maximized: true, minimized: true);
      final window = WindowService(host: host, supportedOverride: true);
      const settings = AppSettings(overlaySize: (560, 140), overlayPositions: {'p': (680, 12)});
      await tester.runAsync(() => window.enterOverlay(settings, height: 380));

      const few = QuestionnaireState(
        phase: FormPhase.finished,
        outcome: 'ready',
        items: [FormItem(question: 'Full name', answer: 'Ana Ruiz', status: ItemStatus.filled)],
      );
      await tester.pumpWidget(
        _host([
          windowServiceProvider.overrideWithValue(window),
          questionnaireControllerProvider.overrideWith(() => _Form(few)),
        ], const AutoFillOverlayScreen()),
      );
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump(const Duration(milliseconds: 50));
      }

      final b = await tester.runAsync(window.bounds);
      expect(b!.height, lessThan(380), reason: 'one question needs less than the opening 380 px');
      expect(b.height, greaterThanOrEqualTo(AutoHeight.panelMin));
      expect(b.topLeft, const Offset(680, 12), reason: 'it grows and shrinks from where it is');
      expect(OverlayGeometry.fills(b, const Rect.fromLTWH(0, 0, 1920, 1040)), isFalse);
    });

    test('never taller than 560 px or 60 % of the display', () {
      expect(AutoHeight.panel(2000, screenHeight: 1040), AutoHeight.panelMax);
      expect(AutoHeight.panel(2000, screenHeight: 700), 420);
      expect(AutoHeight.panel(10, screenHeight: 1040), AutoHeight.panelMin);
      expect(AutoHeight.panel(300, screenHeight: 1040), 300);
    });
  });
}

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/core/design/theme.dart';
import 'package:sotto/core/design/tokens.dart';
import 'package:sotto/data/models/session_record.dart';
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/data/repositories.dart';
import 'package:sotto/features/forms/autofill_controller.dart';
import 'package:sotto/features/forms/forms_screen.dart';
import 'package:sotto/features/questionnaire/questionnaire_controller.dart';
import 'package:sotto/features/settings/pages/answers_page.dart';
import 'package:sotto/features/settings/pages/forms_page.dart';
import 'package:sotto/l10n/l10n.dart';

class _Settings extends SettingsNotifier {
  _Settings(this.initial);
  final AppSettings initial;

  @override
  AppSettings build() => initial;

  @override
  void update(AppSettings Function(AppSettings) change) => state = change(state);
}

/// The one controller behind the overlay bar, the Forms page and chord + F.
class _AutoFill extends AutoFillController {
  _AutoFill(this.initial);
  final AutoFillState initial;
  final fills = <bool>[];

  @override
  AutoFillState build() => initial;

  @override
  Future<void> fillNow({bool fromMainWindow = false}) async => fills.add(fromMainWindow);
}

class _Questionnaire extends QuestionnaireController {
  _Questionnaire(this.initial);
  final QuestionnaireState initial;

  @override
  QuestionnaireState build() => initial;
}

final _l = lookupAppLocalizations(const Locale('en'));

SessionRecord _session() => SessionRecord(
  id: 's1',
  scriptId: '',
  scriptTitle: 'Questionnaire',
  startedAt: DateTime(2026, 9, 1, 10),
  endedAt: DateTime(2026, 9, 1, 10, 5),
  rehearsal: false,
  formRuns: [
    FormRunRecord(
      status: 'ready',
      app: 'Geography quiz',
      at: DateTime(2026, 9, 1, 10),
      auto: true,
      fields: const [
        FormFieldRecord(
          question: 'Capital of Spain?',
          answer: 'Madrid',
          status: 'filled',
          type: 'multiple_choice',
          reasoning: 'Madrid is the capital',
        ),
        FormFieldRecord(question: 'Your name', answer: 'Ana', status: 'filled', type: 'text'),
      ],
    ),
    const FormRunRecord(status: 'stopped', app: 'Survey'),
  ],
);

Future<_AutoFill> _pump(
  WidgetTester tester, {
  AutoFillState auto = const AutoFillState(),
  QuestionnaireState form = const QuestionnaireState(),
  AppSettings settings = const AppSettings(formsEnabled: true),
  Widget child = const FormsScreen(),
}) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('window_manager'),
    (_) async => null,
  );
  L10n.current = _l;
  tester.view.physicalSize = const Size(1280, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = _AutoFill(auto);
  await tester.pumpWidget(
    ProviderScope(
      // A fresh scope each time, so the overrides take.
      key: UniqueKey(),
      overrides: [
        settingsProvider.overrideWith(() => _Settings(settings)),
        autoFillControllerProvider.overrideWith(() => controller),
        questionnaireControllerProvider.overrideWith(() => _Questionnaire(form)),
        sessionsProvider.overrideWith((ref) => Stream.value([_session()])),
        ttsVoicesProvider.overrideWith((ref) async => const <String>[]),
      ],
      child: MaterialApp(
        theme: buildSottoTheme(SottoPalette.houseLights),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return controller;
}

String _status(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('formsStatus'))).data!;

void main() {
  test('auto-fill starts cleanly at launch, on or off', () {
    fakeAsync((async) {
      for (final on in [false, true]) {
        final c = ProviderContainer(
          overrides: [
            settingsProvider.overrideWith(() => _Settings(AppSettings(formsEnabled: on, formsAutoFill: on))),
          ],
        );
        expect(() => c.read(autoFillControllerProvider), returnsNormally);
        async.flushMicrotasks();
        expect(c.read(autoFillControllerProvider).status, on ? AutoFillStatus.watching : AutoFillStatus.off);
        c.dispose();
      }
    });
  });

  testWidgets('status card: off, watching, filling N/M and paused', (tester) async {
    await _pump(tester);
    expect(_status(tester), _l.formsStatusOff);
    expect(find.text(_l.autofillPause), findsNothing);

    await _pump(tester, auto: const AutoFillState(status: AutoFillStatus.watching));
    expect(_status(tester), _l.formsStatusWatching);
    expect(find.text(_l.autofillPause), findsOneWidget);
    expect(find.text(_l.autofillStop), findsOneWidget, reason: 'the hold-to-stop button');

    await _pump(
      tester,
      auto: const AutoFillState(status: AutoFillStatus.filling, app: 'Geography quiz'),
      form: QuestionnaireState(
        phase: FormPhase.filling,
        current: 3,
        items: [
          const FormItem(question: 'a', answer: '1', status: ItemStatus.filled),
          const FormItem(question: 'b', answer: '2', status: ItemStatus.filled),
          const FormItem(question: 'c', answer: '3', status: ItemStatus.filled),
          const FormItem(question: 'd', answer: '4', status: ItemStatus.filling),
          for (var i = 0; i < 5; i++) FormItem(question: 'q$i', answer: 'x'),
        ],
      ),
    );
    expect(_status(tester), _l.formsStatusFilling(4, 9));
    expect(find.text(_l.autofillStopNow), findsOneWidget);

    await _pump(tester, auto: const AutoFillState(status: AutoFillStatus.paused));
    expect(_status(tester), _l.autofillPaused);
    expect(find.text(_l.autofillResume), findsOneWidget);
  });

  testWidgets('"Fill what\'s on screen now" goes through the same controller as auto-fill', (tester) async {
    final controller = await _pump(tester, auto: const AutoFillState(status: AutoFillStatus.watching));
    await tester.tap(find.text(_l.formsFillNow));
    await tester.pump();
    expect(controller.fills, [true]);
  });

  testWidgets('recent fills: app, count and outcome; every answer on tap; nothing when history is off', (tester) async {
    await _pump(tester);
    expect(find.text('Geography quiz'), findsOneWidget);
    expect(find.textContaining(_l.formsFieldsFilled(2)), findsOneWidget);
    expect(find.text(_l.formsOutcomeCompleted), findsOneWidget);
    expect(find.text(_l.formsOutcomeStopped), findsOneWidget);
    expect(find.text('→ Madrid'), findsNothing);
    await tester.tap(find.text('Geography quiz'));
    await tester.pump();
    expect(find.text('→ Madrid'), findsOneWidget);
    expect(find.textContaining(_l.qtMultipleChoice), findsOneWidget);

    await _pump(tester, settings: const AppSettings(historyRetentionDays: 0));
    expect(find.byKey(const Key('formsHistoryOff')), findsOneWidget);
    expect(find.text('Geography quiz'), findsNothing);
  });

  testWidgets('Settings → Answers has no form settings; Settings → Forms has them all', (tester) async {
    await _pump(tester, child: const AnswersPage());
    for (final t in [
      _l.formsGroup,
      _l.formsEnable,
      _l.autofillToggle,
      _l.formsMode,
      _l.formsInstructions,
      _l.formsStyle,
    ]) {
      expect(find.text(t), findsNothing, reason: t);
    }
    expect(find.text(_l.chatAutoSend), findsNothing, reason: 'chat settings moved to General');

    await _pump(tester, child: const FormsSettingsPage());
    for (final t in [
      _l.autofillToggle,
      _l.formsEnable,
      _l.formsMode,
      _l.formsScrollTitle,
      _l.formsInstructions,
      _l.formsLanguage,
      _l.formsStyle,
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text(_l.formsPrivacyNote), findsOneWidget);
    expect(find.text(_l.formsClearHistory), findsWidgets);
  });
}

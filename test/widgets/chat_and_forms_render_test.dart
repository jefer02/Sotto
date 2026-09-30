// Renders the new panels (questionnaire, overlay chat, main-window chat)
// at their real sizes: layout overflows fail the test.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/core/design/theme.dart';
import 'package:sotto/core/design/tokens.dart';
import 'package:sotto/data/models/chat.dart';
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/data/repositories.dart';
import 'package:sotto/features/chat/chat_controller.dart';
import 'package:sotto/features/chat/chat_panel.dart';
import 'package:sotto/features/chat/chat_screen.dart';
import 'package:sotto/features/questionnaire/questionnaire_controller.dart';
import 'package:sotto/features/questionnaire/questionnaire_view.dart';
import 'package:sotto/l10n/app_localizations.dart';

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings(formsEnabled: true);
}

class _Filling extends QuestionnaireController {
  _Filling(this.initial);
  final FormPhase initial;

  @override
  QuestionnaireState build() => QuestionnaireState(
    phase: initial,
    page: 2,
    current: 1,
    items: const [
      FormItem(question: 'Full name', answer: 'Ana Ruiz', status: ItemStatus.filled),
      FormItem(question: '¿Con qué frecuencia usas la app?', answer: 'A diario', status: ItemStatus.filling),
      FormItem(question: 'Favourite colours', answer: 'Red, Blue'),
      FormItem(
        question: 'Card number',
        answer: '',
        status: ItemStatus.blocked,
        note: 'password or payment field — never filled',
        editable: false,
      ),
    ],
  );
}

final _conversation = Conversation.create('Roadmap questions').copyWith(
  messages: [
    ChatMessage.user('What are three good follow-up questions about **pricing**?'),
    ChatMessage(
      id: 'a1',
      role: ChatRole.assistant,
      at: DateTime(2026),
      text: 'Here are three:\n\n1. **Tiers** — who is each for?\n2. How do *discounts* work?\n3. What changes in `v2`?\n\n```\nprice = base * seats\n```',
    ),
  ],
);

class _Chat extends ChatController {
  @override
  ChatState build() => ChatState(conversationId: _conversation.id, overlayOpen: true);
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

Widget _host(List<Object> overrides, Widget child, {bool overlay = true}) => ProviderScope(
  overrides: [settingsProvider.overrideWith(_Settings.new), ...overrides.cast()],
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildSottoTheme(SottoPalette.stage),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Material(
      color: overlay
          ? Color.alphaBlend(OverlayPalette.dark.ground, const Color(0xFF15181D))
          : SottoPalette.stage.ground,
      child: child,
    ),
  ),
);

void main() {
  for (final phase in [FormPhase.filling, FormPhase.review, FormPhase.confirmSubmit]) {
    testWidgets('questionnaire panel: ${phase.name}', (tester) async {
      await tester.runAsync(_loadFonts);
      tester.view.physicalSize = const Size(560, 380);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        _host([questionnaireControllerProvider.overrideWith(() => _Filling(phase))], const QuestionnaireView()),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Ana Ruiz'), findsOneWidget);
    });
  }

  testWidgets('overlay chat panel and main-window chat', (tester) async {
    await tester.runAsync(_loadFonts);
    final conversations = conversationsProvider.overrideWith((ref) => Stream.value([_conversation]));

    tester.view.physicalSize = const Size(560, 440);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(_host([chatControllerProvider.overrideWith(_Chat.new), conversations], const ChatPanel()));
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Tiers', findRichText: true), findsOneWidget);

    tester.view.physicalSize = const Size(1100, 760);
    await tester.pumpWidget(
      _host([chatControllerProvider.overrideWith(_Chat.new), conversations], const ChatScreen(), overlay: false),
    );
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Roadmap questions'), findsOneWidget);
  });
}

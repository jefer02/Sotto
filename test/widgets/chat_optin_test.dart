import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sotto/core/design/theme.dart';
import 'package:sotto/core/design/tokens.dart';
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/data/repositories.dart';
import 'package:sotto/data/storage/local_store.dart';
import 'package:sotto/features/chat/chat_controller.dart';
import 'package:sotto/features/library/library_shell.dart';
import 'package:sotto/l10n/app_localizations.dart';

class _Settings extends SettingsNotifier {
  _Settings(this.initial);
  final AppSettings initial;

  @override
  AppSettings build() => initial;

  @override
  void update(AppSettings Function(AppSettings) change) => state = change(state);
}

/// The chat controller, with a way to pretend a reply is streaming in.
class _Chat extends ChatController {
  void streaming(bool on) => state = on ? state.copyWith(streamingId: 'r1') : state.copyWith(clearStreaming: true);
}

ProviderContainer _container(AppSettings s) => ProviderContainer(
  overrides: [settingsProvider.overrideWith(() => _Settings(s)), chatControllerProvider.overrideWith(_Chat.new)],
);

void main() {
  group('overlay chat panel', () {
    test('is hidden by default: chord + C does nothing until the chat is turned on', () {
      final c = _container(const AppSettings());
      addTearDown(c.dispose);
      expect(const AppSettings().showChat, isFalse);
      c.read(chatControllerProvider.notifier).toggleOverlay();
      expect(c.read(chatControllerProvider).overlayOpen, isFalse);

      c.read(settingsProvider.notifier).update((s) => s.copyWith(showChat: true));
      c.read(chatControllerProvider.notifier).toggleOverlay();
      expect(c.read(chatControllerProvider).overlayOpen, isTrue);
    });

    test('closes itself after 60 s of inactivity; activity starts the clock over', () {
      fakeAsync((async) {
        final c = _container(const AppSettings(showChat: true));
        final chat = c.read(chatControllerProvider.notifier);
        chat.toggleOverlay();
        async.elapse(const Duration(seconds: 40));
        chat.touch(); // a click in the panel
        async.elapse(const Duration(seconds: 40));
        expect(c.read(chatControllerProvider).overlayOpen, isTrue, reason: '40 s since the last activity');
        chat.input.text = 'what is our churn'; // typing
        async.elapse(const Duration(seconds: 59));
        expect(c.read(chatControllerProvider).overlayOpen, isTrue);
        async.elapse(const Duration(seconds: 2));
        expect(c.read(chatControllerProvider).overlayOpen, isFalse);
        c.dispose();
      });
    });

    test('never closes while a reply is streaming in; "never" keeps it open', () {
      fakeAsync((async) {
        final c = _container(const AppSettings(showChat: true));
        final chat = c.read(chatControllerProvider.notifier) as _Chat;
        chat.toggleOverlay();
        chat.streaming(true);
        async.elapse(const Duration(minutes: 3));
        expect(c.read(chatControllerProvider).overlayOpen, isTrue);
        chat.streaming(false);
        chat.touch();
        async.elapse(const Duration(seconds: 61));
        expect(c.read(chatControllerProvider).overlayOpen, isFalse);
        c.dispose();

        final never = _container(const AppSettings(showChat: true, chatAutoClose: 0));
        never.read(chatControllerProvider.notifier).toggleOverlay();
        async.elapse(const Duration(hours: 1));
        expect(never.read(chatControllerProvider).overlayOpen, isTrue);
        never.dispose();
      });
    });
  });

  testWidgets('the sidebar shows Chat only when it is turned on', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('sotto_chat_optin');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('window_manager'), (_) async => null);
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);
    final store = (await tester.runAsync(() => LocalStore.open(path: tmp.path)))!;
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<void> pump(bool showChat) async {
      final router = GoRouter(
        routes: [
          ShellRoute(
            builder: (context, state, child) => LibraryShell(child: child),
            routes: [GoRoute(path: '/', builder: (c, s) => const SizedBox())],
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          key: ValueKey(showChat),
          overrides: [
            localStoreProvider.overrideWithValue(store),
            settingsProvider.overrideWith(() => _Settings(AppSettings(showChat: showChat, onboarded: true))),
          ],
          child: MaterialApp.router(
            theme: buildSottoTheme(SottoPalette.houseLights),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            routerConfig: router,
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }

    await pump(false);
    expect(find.text('Chat'), findsNothing);
    await pump(true);
    expect(find.text('Chat'), findsOneWidget);
  });
}

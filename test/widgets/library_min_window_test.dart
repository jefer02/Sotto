// The library lays out without overflow at the main window's minimum size,
// in both interface languages (Spanish strings run longer).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sotto/app/app.dart';
import 'package:sotto/app/router.dart';
import 'package:sotto/core/design/tokens.dart';
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/data/repositories.dart';
import 'package:sotto/data/seed.dart';
import 'package:sotto/data/storage/local_store.dart';
import 'package:sotto/l10n/l10n.dart';

void main() {
  late Directory tmp;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('sotto_library');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);
    for (final name in [
      'com.llfbandit.record/messages',
      'dev.leanflutter.plugins/hotkey_manager',
      'dev.leanflutter.plugins/hotkey_manager_event',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(name),
        (call) async => call.method == 'listInputDevices' ? [] : null,
      );
    }
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'readAll' ? <String, String>{} : null,
    );
  });

  for (final lang in [AppLanguage.en, AppLanguage.es]) {
    testWidgets('the library fits 960×600 (${lang.name})', (tester) async {
      late ProviderContainer container;
      await tester.runAsync(() async {
        await initializeDateFormatting();
        final store = await LocalStore.open(path: '${tmp.path}/${lang.name}');
        container = ProviderContainer(overrides: [localStoreProvider.overrideWithValue(store)]);
        container
            .read(settingsProvider.notifier)
            .update((s) => s.copyWith(uiLanguage: lang, onboarded: true, welcomeDone: true));
        L10n.current = lookupAppLocalizations(Locale(lang.name));
        await seedIfEmpty(container.read(scriptRepositoryProvider));
      });
      addTearDown(container.dispose);
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Layout.windowMin;
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const SottoApp()));
      for (final route in ['/', '/scripts']) {
        container.read(routerProvider).go(route);
        for (var i = 0; i < 8; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(tester.takeException(), isNull, reason: '$route overflows at 960×600');
      }
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    });
  }
}

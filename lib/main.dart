import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/app.dart';
import 'core/platform/window_service.dart';
import 'data/repositories.dart';
import 'data/seed.dart';
import 'data/storage/local_store.dart';
import 'l10n/l10n.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final store = await LocalStore.open();
  final window = WindowService();
  await window.init();

  final container = ProviderContainer(
    overrides: [localStoreProvider.overrideWithValue(store), windowServiceProvider.overrideWithValue(window)],
  );
  await initializeDateFormatting();
  // Seeded content and early messages use the interface language.
  L10n.current = lookupAppLocalizations(appLocale(container.read(settingsProvider).uiLanguage));
  await seedIfEmpty(container.read(scriptRepositoryProvider));

  // First launch: listen for the presenter's own language by default.
  final settings = container.read(settingsProvider.notifier);
  if (!container.read(settingsProvider).onboarded) {
    final device = WidgetsBinding.instance.platformDispatcher.locale;
    settings.update(
      (st) => st.copyWith(
        onboarded: true,
        language: device.languageCode == 'es' ? (device.countryCode == 'ES' ? 'es-ES' : 'es-419') : st.language,
      ),
    );
  }
  unawaited(container.read(qaRepositoryProvider).prune(container.read(settingsProvider).historyRetentionDays));

  runApp(UncontrolledProviderScope(container: container, child: const SottoApp()));
}

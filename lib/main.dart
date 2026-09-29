import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/app.dart';
import 'core/platform/window_service.dart';
import 'data/repositories.dart';
import 'data/seed.dart';
import 'data/models/settings.dart';
import 'data/storage/local_store.dart';
import 'l10n/l10n.dart';
import 'services/ai/deepseek_models.dart';

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
  await container.read(scriptRepositoryProvider).finishInterruptedOrganizing();

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
  unawaited(_checkModel(container));

  runApp(UncontrolledProviderScope(container: container, child: const SottoApp()));
}

/// DeepSeek renames models from time to time: if the saved one is gone, fall
/// back to Flash (or whatever the API offers first), and pick a model that
/// reads screenshots. Offline → keep what is saved.
Future<void> _checkModel(ProviderContainer container) async {
  try {
    final models = await container.read(deepSeekModelsProvider.future);
    if (models.isEmpty) return;
    final ids = [for (final m in models) m.id];
    final current = container.read(settingsProvider).aiModel;
    final next = ids.contains(current) ? current : (ids.contains(defaultAiModel) ? defaultAiModel : ids.first);
    final vision = pickVisionModel(models, next) ?? next;
    container.read(settingsProvider.notifier).update((s) => s.copyWith(aiModel: next, visionModel: vision));
  } catch (_) {}
}

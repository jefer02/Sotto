import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
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
  final startup = StartupTimer();
  WidgetsFlutterBinding.ensureInitialized();

  // Independent: the boxes, the window and the date formats load together.
  final window = WindowService();
  final (store, _, _) = await (
    startup.time('hive', LocalStore.open()),
    startup.time('window', window.init()),
    startup.time('dates', initializeDateFormatting()),
  ).wait;
  // Coalesced writes (sessions, settings) reach disk before the app goes.
  AppLifecycleListener(
    onStateChange: (s) {
      if (s == AppLifecycleState.hidden || s == AppLifecycleState.detached) unawaited(store.flush());
    },
    onExitRequested: () async {
      await store.flush();
      return AppExitResponse.exit;
    },
  );

  final container = ProviderContainer(
    overrides: [localStoreProvider.overrideWithValue(store), windowServiceProvider.overrideWithValue(window)],
  );
  // Seeded content and early messages use the interface language.
  L10n.current = lookupAppLocalizations(appLocale(container.read(settingsProvider).uiLanguage));
  await startup.time('scripts', () async {
    await seedIfEmpty(container.read(scriptRepositoryProvider));
    await container.read(scriptRepositoryProvider).finishInterruptedOrganizing();
  }());

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
  unawaited(container.read(chatRepositoryProvider).prune(container.read(settingsProvider).historyRetentionDays));
  unawaited(_checkModel(container));
  unawaited(container.read(secretStoreProvider).purgeLegacy());

  startup.mark('runApp');
  runApp(UncontrolledProviderScope(container: container, child: const SottoApp()));
  unawaited(WidgetsBinding.instance.waitUntilFirstFrameRasterized.then((_) => startup.report()));
}

/// Debug builds: how long main() takes to the first frame, step by step
/// ("startup 412 ms — hive 38, window 205, …"), flagged over 800 ms.
class StartupTimer {
  static const budget = Duration(milliseconds: 800);

  final _clock = Stopwatch()..start();
  final _steps = <String, int>{};

  Future<T> time<T>(String step, Future<T> work) async {
    if (!kDebugMode) return work;
    final from = _clock.elapsedMilliseconds;
    try {
      return await work;
    } finally {
      _steps[step] = _clock.elapsedMilliseconds - from;
    }
  }

  void mark(String step) {
    if (kDebugMode) _steps[step] = _clock.elapsedMilliseconds;
  }

  void report() {
    if (!kDebugMode) return;
    final total = _clock.elapsedMilliseconds;
    final steps = _steps.entries.map((e) => '${e.key} ${e.value}').join(', ');
    final slow = total > budget.inMilliseconds ? ' — over ${budget.inMilliseconds} ms' : '';
    debugPrint('[startup] first frame at $total ms$slow ($steps; runApp is time since main)');
  }
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

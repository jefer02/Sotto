import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/app.dart';
import 'app/app_session.dart';
import 'app/lock_progress.dart';
import 'app/startup_failure.dart';
import 'app/unlock_screen.dart';
import 'core/platform/biometrics.dart';
import 'core/platform/platform_features.dart';
import 'core/platform/window_service.dart';
import 'core/utils/frame_stats.dart';
import 'data/lock/migration.dart';
import 'data/repositories.dart';
import 'data/seed.dart';
import 'data/models/settings.dart';
import 'data/storage/local_store.dart';
import 'data/storage/secret_store.dart';
import 'data/storage/storage_paths.dart';
import 'l10n/l10n.dart';
import 'services/ai/deepseek_models.dart';
import 'services/screen/browser_bridge.dart';

Future<void> main() async {
  final startup = StartupTimer();
  WidgetsFlutterBinding.ensureInitialized();

  // Independent: the settings, the window and the date formats load together.
  final window = WindowService();
  final (session, _, _) = await (
    startup.time('hive', _openSession(window, startup)),
    startup.time('window', window.init()),
    startup.time('dates', initializeDateFormatting()),
  ).wait;
  // Coalesced writes (sessions, settings) reach disk before the app goes.
  AppLifecycleListener(
    onStateChange: (s) {
      if (s == AppLifecycleState.hidden || s == AppLifecycleState.detached) unawaited(session.flush());
    },
    onExitRequested: () async {
      await session.flush();
      return AppExitResponse.exit;
    },
  );
  // The app — or, with the App Lock on, the unlock screen first.
  await session.start();
}

/// Finishes or undoes an App Lock migration a crash cut short, then opens
/// the settings box — all the unlock screen needs. When that fails (another
/// Sotto has the data locked, a sync app is holding a file) the window says
/// so instead of staying blank, and tries again on Retry.
Future<AppSession> _openSession(WindowService window, StartupTimer startup) async {
  while (true) {
    try {
      final paths = await StoragePaths.resolve();
      final recovered = await LockMigration.recover(paths);
      await LocalStore.init(path: paths.data.path);
      final settings = await LocalStore.openSettings();
      final secrets = SecretStore(null, paths.keychainPrefix);
      if (paths.devRoot != null) debugPrint('[startup] test data in ${paths.devRoot!.path}');
      // Turning the lock off finished just now: its keychain copy goes too.
      if (recovered case (direction: LockDirection.decrypt, rolledBack: false)) {
        await secrets.write(SecretKey.appLockKey, null);
      }
      // The unlock screen and early messages use the interface language.
      final saved = AppSettings.fromJson(settings.writes.get('app') ?? const {});
      L10n.current = lookupAppLocalizations(appLocale(saved.uiLanguage));
      return AppSession(
        paths: paths,
        settings: settings,
        window: window,
        secrets: secrets,
        biometrics: PlatformFeatures.current.biometrics ? Biometrics(os: PlatformFeatures.current.os) : null,
        screens: SessionScreens(
          locked: (session) => UnlockApp(session: session),
          migrating: (progress, direction) =>
              LockProgressApp(settings: settings, progress: progress, direction: direction),
          failure: (error, retry) => StartupFailure(error: error, onRetry: retry),
        ),
        startApp: (container) => _startApp(container, startup),
      );
    } catch (e) {
      debugPrint('[startup] could not open local data: $e');
      final retry = Completer<void>();
      runApp(StartupFailure(error: e, onRetry: () => retry.isCompleted ? null : retry.complete()));
      await retry.future;
    }
  }
}

var _firstSession = true;

/// The startup steps once the data is open — at launch, and again after
/// every unlock — and the app itself.
Future<void> _startApp(ProviderContainer container, StartupTimer startup) async {
  // Seeded content and early messages use the interface language.
  L10n.current = lookupAppLocalizations(appLocale(container.read(settingsProvider).uiLanguage));
  await startup.time('scripts', () async {
    await seedIfEmpty(container.read(scriptRepositoryProvider));
    await container.read(scriptRepositoryProvider).finishInterruptedOrganizing();
    await container.read(scriptRepositoryProvider).assignMissingTones();
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
  // The browser extension's host is registered for this user and Sotto
  // listens for it. It never launches a browser.
  unawaited(container.read(browserBridgeProvider).start());

  startup.mark('runApp');
  runApp(UncontrolledProviderScope(container: container, child: const SottoApp()));
  if (!_firstSession) return;
  _firstSession = false;
  FrameStats.start();
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

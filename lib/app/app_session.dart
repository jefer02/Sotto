import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:hive_ce/hive_ce.dart';

import '../core/platform/biometrics.dart';
import '../core/platform/hotkey_service.dart';
import '../core/platform/window_service.dart';
import '../data/lock/migration.dart';
import '../data/lock/throttle.dart';
import '../data/lock/vault.dart';
import '../data/models/settings.dart';
import '../data/repositories.dart';
import '../data/storage/local_store.dart';
import '../data/storage/secret_store.dart';
import '../data/storage/storage_paths.dart';
import '../features/agent/agent_controller.dart';
import '../features/forms/autofill_controller.dart';
import '../features/library/organize_jobs.dart';
import '../features/live/live_controller.dart';
import '../features/questionnaire/questionnaire_controller.dart';
import '../l10n/l10n.dart';
import 'router.dart';

/// The screens [AppSession] puts up between sessions.
class SessionScreens {
  const SessionScreens({required this.locked, required this.migrating, required this.failure});

  /// The unlock screen.
  final Widget Function(AppSession session) locked;

  /// Encrypting or decrypting the data: [progress] goes from 0 to 1.
  final Widget Function(ValueListenable<double> progress, LockDirection direction) migrating;

  /// The data couldn't be opened (another Sotto, a sync app holding a file).
  final Widget Function(Object error, VoidCallback retry) failure;
}

enum UnlockResult { unlocked, wrong, throttled, damaged }

/// What the unlock screen needs from the session — an interface so the
/// screen can be tested and rendered without real data.
abstract interface class UnlockGate {
  /// Until the next attempt is allowed; zero when it is now.
  Duration get throttleRemaining;

  /// The vault is there but can't be read: only Reset can help.
  bool get vaultDamaged;

  /// "Windows Hello" / "Touch ID" when that unlock is on; null hides it.
  String? get biometricMethod;

  Future<UnlockResult> unlockWithPassword(String password);
  Future<bool> unlockWithBiometrics();
  Future<(UnlockResult, Uint8List?)> checkRecoveryKey(String recoveryKey);
  Future<void> resetPassword(Uint8List dek, String newPassword);
  Future<void> resetEverything();
}

/// Sotto from launch to quit, across locks.
///
/// Each unlock is a fresh **session**: the data boxes are opened (with the
/// cipher, when the lock is on), a new [ProviderContainer] is made over
/// them, and [startApp] runs the usual startup and shows the app. Locking
/// tears the session down whole — hotkeys released, the container
/// disposed (every StreamProvider, controller and the browser bridge
/// closes through its own onDispose), the boxes closed, the key dropped —
/// so no provider has to know about the lock, and nothing can hold a box
/// that is gone. Only the settings box stays open.
class AppSession implements UnlockGate {
  AppSession({
    required this.paths,
    required this.settings,
    required this.window,
    required this.screens,
    required this.startApp,
    SecretStore? secrets,
    this.biometrics,
    @visibleForTesting void Function(Widget app)? show,
    @visibleForTesting Future<void> Function(ProviderContainer session)? releaseHotkeys,
    @visibleForTesting Future<void> Function()? settle,
    @visibleForTesting this.kdf = KdfParams.standard,
    @visibleForTesting this.overrides = const [],
  }) : secrets = secrets ?? SecretStore(),
       throttle = UnlockThrottle(paths.attempts),
       _show = show ?? runApp,
       _releaseHotkeys = releaseHotkeys ?? _releaseSessionHotkeys,
       _settle = settle ?? (() => WidgetsBinding.instance.endOfFrame);

  final StoragePaths paths;
  final SettingsStore settings;
  final WindowService window;
  final SessionScreens screens;
  final SecretStore secrets;

  /// Windows Hello / Touch ID; null where the platform has none.
  final Biometrics? biometrics;
  bool _biometricsReady = false;
  final UnlockThrottle throttle;
  final KdfParams kdf;
  final List<Override> overrides;

  /// The startup steps after the data is open: seeding, pruning, the model
  /// check, the bridge — and showing the app over [container].
  final Future<void> Function(ProviderContainer container) startApp;

  final void Function(Widget app) _show;
  final Future<void> Function(ProviderContainer session) _releaseHotkeys;

  /// Through the session's own HotkeyService — never hotKeyManager's
  /// unregisterAll: the Windows plugin throws (and the process ends) when
  /// asked to unregister a hotkey it no longer has, which is what the
  /// service would then do as the container is disposed.
  static Future<void> _releaseSessionHotkeys(ProviderContainer session) =>
      session.read(hotkeyServiceProvider).unregisterAll();
  final Future<void> Function() _settle;

  LockVault? _vault;
  VaultDamaged? _damaged;
  Uint8List? _dek;
  LocalStore? _store;
  ProviderContainer? _container;

  /// A valid vault on disk (or one that is there but unreadable).
  bool get lockEnabled => _vault != null || _damaged != null;
  bool get unlocked => _container != null;
  @override
  bool get vaultDamaged => _damaged != null;

  /// The open data, while unlocked.
  LocalStore? get store => _store;

  @override
  Duration get throttleRemaining => throttle.remaining;

  AppSettings get _savedSettings => AppSettings.fromJson(settings.writes.get(LocalStore.prefsSettingsKey) ?? const {});

  /// Windows Hello / Touch ID is set up on this computer.
  bool get biometricsAvailable => biometrics != null && _biometricsReady;

  @override
  String? get biometricMethod =>
      biometricsAvailable && _vault != null && _savedSettings.lockBiometrics ? biometrics!.method : null;

  /// The system prompt, then the data key from the keychain — checked
  /// against the vault before anything is opened with it.
  @override
  Future<bool> unlockWithBiometrics() async {
    final b = biometrics;
    if (b == null || _vault == null || unlocked) return false;
    if (!await b.confirm(L10n.current.biometricUnlockReason)) return false;
    final Uint8List dek;
    try {
      final stored = await secrets.read(SecretKey.appLockKey);
      if (stored == null) return false;
      dek = base64Decode(stored);
    } catch (_) {
      return false;
    }
    if (await unlockWithKey(dek)) return true;
    VaultCrypto.forget(dek);
    return false;
  }

  /// Turns on Windows Hello / Touch ID unlock: after the system prompt, a
  /// copy of the data key goes to the keychain (Windows Credential Manager,
  /// the macOS Keychain). Anything running as this user can read it there —
  /// the trade-off the setting explains. The caller saves the setting.
  Future<bool> enableBiometrics() async {
    final b = biometrics;
    final dek = _dek;
    if (b == null || dek == null) return false;
    if (!await b.confirm(L10n.current.biometricEnableReason)) return false;
    await secrets.write(SecretKey.appLockKey, base64Encode(dek));
    return true;
  }

  /// Deletes the keychain copy. The caller saves the setting.
  Future<void> disableBiometrics() => _forgetKeychainKey();

  // ─────────────────────────── Launch ───────────────────────────

  /// Shows the app, or the unlock screen when the lock is on.
  Future<void> start() async {
    await throttle.load();
    _biometricsReady = await biometrics?.available() ?? false;
    try {
      _vault = await VaultFile(paths.vault).read();
    } on VaultDamaged catch (e) {
      _damaged = e;
    }
    if (lockEnabled) {
      _show(screens.locked(this));
    } else {
      await _run(await _openData(), null);
    }
  }

  /// Writes coalesced changes (the app going to the background or quitting).
  Future<void> flush() => Future.wait([settings.writes.flush(), if (_store != null) _store!.flush()]);

  // ─────────────────────────── Unlock ───────────────────────────

  @override
  Future<UnlockResult> unlockWithPassword(String password) async {
    final vault = _vault;
    if (vault == null) return UnlockResult.damaged;
    if (throttle.blocked) return UnlockResult.throttled;
    final clock = Stopwatch()..start();
    final dek = await VaultCrypto.openWithPassword(vault, password);
    // Only how long the key took (debug and profile builds), never what it is.
    if (!kReleaseMode) debugPrint('[lock] password checked in ${clock.elapsedMilliseconds} ms');
    if (dek == null) {
      await throttle.recordFailure();
      return UnlockResult.wrong;
    }
    await throttle.recordSuccess();
    await _unlock(dek);
    return UnlockResult.unlocked;
  }

  /// "Forgot password?": the data key behind [recoveryKey], to set a new
  /// password with ([resetPassword]). Throttled like the password.
  @override
  Future<(UnlockResult, Uint8List?)> checkRecoveryKey(String recoveryKey) async {
    final vault = _vault;
    if (vault == null) return (UnlockResult.damaged, null);
    if (throttle.blocked) return (UnlockResult.throttled, null);
    final dek = await VaultCrypto.openWithRecovery(vault, recoveryKey);
    if (dek == null) {
      await throttle.recordFailure();
      return (UnlockResult.wrong, null);
    }
    await throttle.recordSuccess();
    return (UnlockResult.unlocked, dek);
  }

  /// Re-wraps the data key under [newPassword] and unlocks. The data is
  /// untouched; the recovery key stays the same.
  @override
  Future<void> resetPassword(Uint8List dek, String newPassword) async {
    final next = await VaultCrypto.withPassword(_vault!, dek, newPassword);
    await VaultFile(paths.vault).write(next);
    _vault = next;
    await _unlock(dek);
  }

  /// Unlocks with a data key from elsewhere (the keychain, after Windows
  /// Hello / Touch ID) — only once the vault has confirmed it is the key.
  Future<bool> unlockWithKey(Uint8List dek) async {
    final vault = _vault;
    if (vault == null || !await VaultCrypto.verifyKey(vault, dek)) return false;
    await _unlock(dek);
    return true;
  }

  Future<void> _unlock(Uint8List dek, {String? location}) async {
    final store = await _openData(cipher: HiveAesCipher(dek), organizeKey: await VaultCrypto.subkey(dek, organizeInfo));
    _dek = dek;
    await _run(store, location);
  }

  static const organizeInfo = 'sotto-organize-cache';

  // ─────────────────────────── Lock ───────────────────────────

  /// Locks now. False (and nothing changes) when the lock is off, Sotto is
  /// already locked, or something is running that mustn't be cut short.
  Future<bool> lock() async {
    final c = _container;
    if (c == null || !lockEnabled || c.read(sessionBusyProvider)) return false;
    _show(screens.locked(this));
    await _endSession();
    return true;
  }

  /// Hotkeys released, the app's widgets gone, providers disposed, data
  /// written and closed, the key dropped.
  Future<void> _endSession() async {
    final c = _container!;
    final store = _store!;
    _container = null;
    _store = null;
    try {
      await _releaseHotkeys(c);
    } catch (_) {}
    // The new screen is up and the old tree unmounted before the container
    // goes: a widget still listening to a disposed provider would throw.
    await _settle();
    await store.flush();
    c.dispose();
    await store.closeData();
    VaultCrypto.forget(_dek);
    _dek = null;
  }

  // ─────────────────────────── Turning it on and off ───────────────────────────

  /// Encrypts the data for a new lock (after the recovery key was shown and
  /// saved), then reopens Sotto on Settings → Privacy.
  Future<void> enable(VaultSetup setup) async {
    // Encrypted boxes must never be "encrypted" again as if they were plain.
    if (lockEnabled || !unlocked) throw StateError('the lock is already on, or Sotto is locked');
    final progress = ValueNotifier<double>(0);
    _show(screens.migrating(progress, LockDirection.encrypt));
    await _endSession();
    final dek = setup.dek;
    try {
      await LockMigration(paths).encrypt(dek, setup.vault, onProgress: (d, t) => progress.value = d / t);
    } catch (e) {
      debugPrint('[lock] encrypting stopped: ${e.runtimeType}');
      await LockMigration.recover(paths);
    }
    await _reopenAfterMigration(dek);
  }

  /// Decrypts the data and deletes the vault and the keychain copy of the
  /// key. False when [password] is wrong.
  Future<bool> disable(String password) async {
    final vault = _vault;
    if (vault == null) return false;
    final dek = await VaultCrypto.openWithPassword(vault, password);
    if (dek == null) return false;
    final progress = ValueNotifier<double>(0);
    _show(screens.migrating(progress, LockDirection.decrypt));
    await _endSession();
    try {
      await LockMigration(paths).decrypt(dek, onProgress: (d, t) => progress.value = d / t);
    } catch (e) {
      debugPrint('[lock] decrypting stopped: ${e.runtimeType}');
      await LockMigration.recover(paths);
    }
    await _reopenAfterMigration(dek);
    return true;
  }

  /// Whatever the disk now says — locked or not — opens with [dek] or plain.
  Future<void> _reopenAfterMigration(Uint8List dek) async {
    _vault = await VaultFile(paths.vault).read();
    _damaged = null;
    if (_vault == null) {
      VaultCrypto.forget(dek);
      await _forgetKeychainKey();
      await _run(await _openData(), privacyLocation);
    } else {
      await _unlock(dek, location: privacyLocation);
    }
  }

  static const privacyLocation = '/settings/privacy';

  // ─────────────────────────── While unlocked ───────────────────────────

  /// The data key, after checking [password] — for the settings that need
  /// it again (show the recovery key, turn biometrics on).
  Future<Uint8List?> verifyPassword(String password) async {
    final vault = _vault;
    if (vault == null) return null;
    return VaultCrypto.openWithPassword(vault, password);
  }

  Future<bool> changePassword(String current, String next) async {
    final dek = await verifyPassword(current);
    if (dek == null) return false;
    final vault = await VaultCrypto.withPassword(_vault!, dek, next);
    await VaultFile(paths.vault).write(vault);
    _vault = vault;
    VaultCrypto.forget(dek);
    return true;
  }

  Future<String?> recoveryKey(String password) async {
    final dek = await verifyPassword(password);
    if (dek == null) return null;
    final key = await VaultCrypto.recoveryKeyOf(_vault!, dek);
    VaultCrypto.forget(dek);
    return key;
  }

  /// A new recovery key; the old one stops working at once.
  Future<String?> regenerateRecoveryKey(String password) async {
    final dek = await verifyPassword(password);
    if (dek == null) return null;
    final (vault, key) = await VaultCrypto.withNewRecoveryKey(_vault!, dek);
    await VaultFile(paths.vault).write(vault);
    _vault = vault;
    VaultCrypto.forget(dek);
    return key;
  }

  /// A new vault for turning the lock on, at this session's KDF cost.
  Future<VaultSetup> createVault(String password) => VaultCrypto.create(password, params: kdf);

  // ─────────────────────────── Reset ───────────────────────────

  /// "Reset Sotto" from the unlock screen, when the password and the
  /// recovery key are both lost: deletes every data box, the vault, the
  /// failed-attempt count, any half-done migration and the keychain copy
  /// of the key. The settings and the DeepSeek key stay. Starts afresh.
  @override
  Future<void> resetEverything() async {
    if (unlocked) throw StateError('reset only from the unlock screen');
    for (final name in LocalStore.dataBoxes) {
      for (final n in [name, '${name}_migrating']) {
        if (Hive.isBoxOpen(n)) await Hive.box<Map>(n).close();
        await Hive.deleteBoxFromDisk(n);
      }
    }
    for (final f in [paths.vault, paths.pendingVault, paths.attempts, paths.migrationMarker]) {
      if (await f.exists()) await f.delete();
    }
    await throttle.recordSuccess();
    await _forgetKeychainKey();
    _vault = null;
    _damaged = null;
    await _run(await _openData(), null);
  }

  /// The keychain copy goes, and the setting with it (written before a new
  /// session reads the settings).
  Future<void> _forgetKeychainKey() async {
    try {
      await secrets.write(SecretKey.appLockKey, null);
    } catch (_) {}
    final raw = settings.writes.get(LocalStore.prefsSettingsKey);
    if (raw != null && raw['lockBiometrics'] == true) {
      await settings.writes.put(LocalStore.prefsSettingsKey, {...raw, 'lockBiometrics': false});
    }
  }

  // ─────────────────────────── Sessions ───────────────────────────

  /// The data boxes; on failure the window says why and tries again on Retry.
  Future<LocalStore> _openData({HiveCipher? cipher, Uint8List? organizeKey}) async {
    while (true) {
      try {
        return await LocalStore.openData(settings, cipher: cipher, organizeKey: organizeKey);
      } catch (e) {
        debugPrint('[startup] could not open local data: $e');
        final retry = Completer<void>();
        _show(screens.failure(e, () => retry.isCompleted ? null : retry.complete()));
        await retry.future;
      }
    }
  }

  Future<void> _run(LocalStore store, String? location) async {
    _store = store;
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        windowServiceProvider.overrideWithValue(window),
        appSessionProvider.overrideWithValue(this),
        // One keychain for the session and the settings (and the lock's own entry name).
        secretStoreProvider.overrideWithValue(secrets),
        if (location != null) initialLocationProvider.overrideWithValue(location),
        ...overrides,
      ],
    );
    _container = container;
    await startApp(container);
  }
}

/// Overridden in each session's container.
final appSessionProvider = Provider<AppSession?>((ref) => null);

/// Whether the App Lock is on. Turning it on or off starts a new session,
/// so within one session it never changes.
final lockEnabledProvider = Provider<bool>((ref) => ref.watch(appSessionProvider)?.lockEnabled ?? false);

/// Something is running that locking must not interrupt: a live session or
/// rehearsal, an agent run, a questionnaire, a fill, an organize job.
final sessionBusyProvider = Provider<bool>((ref) {
  final fill = ref.watch(autoFillControllerProvider);
  return ref.watch(liveControllerProvider.select((s) => s.isLive)) ||
      ref.watch(agentControllerProvider.select((a) => a.active)) ||
      ref.watch(questionnaireControllerProvider.select((q) => q.active)) ||
      fill.overlay ||
      fill.status == AutoFillStatus.filling ||
      ref.watch(organizeJobsProvider.select((jobs) => jobs.values.any((j) => !j.finished)));
});

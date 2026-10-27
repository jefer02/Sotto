import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:sotto/app/app_session.dart';
import 'package:sotto/app/router.dart';
import 'package:sotto/core/platform/biometrics.dart';
import 'package:sotto/core/platform/window_service.dart';
import 'package:sotto/data/lock/vault.dart';
import 'package:sotto/data/repositories.dart';
import 'package:sotto/data/storage/local_store.dart';
import 'package:sotto/data/storage/secret_store.dart';
import 'package:sotto/data/storage/storage_paths.dart';

const _fast = KdfParams(memoryKiB: 64, iterations: 1, parallelism: 1);

class _Window implements WindowService {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// A keychain that remembers what was deleted.
class _Keychain implements FlutterSecureStorage {
  final values = <String, String>{};
  final deleted = <String>[];

  @override
  dynamic noSuchMethod(Invocation i) {
    final key = i.namedArguments[#key] as String?;
    switch (i.memberName) {
      case #write:
        values[key!] = i.namedArguments[#value] as String;
        return Future<void>.value();
      case #delete:
        deleted.add(key!);
        values.remove(key);
        return Future<void>.value();
      case #read:
        return Future<String?>.value(values[key]);
    }
    throw UnimplementedError('${i.memberName}');
  }
}

/// Windows Hello that says yes (or no) without asking anyone.
class _Bio extends Biometrics {
  _Bio() : super(os: 'windows');
  bool ok = true;
  int prompts = 0;

  @override
  Future<bool> available() async => true;

  @override
  Future<bool> confirm(String reason) async {
    prompts++;
    return ok;
  }
}

class _Busy extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) => state = v;
}

final _busy = NotifierProvider<_Busy, bool>(_Busy.new);

void main() {
  late Directory dir;
  late StoragePaths paths;
  late List<String> shown;
  late List<ProviderContainer> sessions;
  late _Keychain keychain;
  late AppSession session;
  late _Bio bio;

  Future<AppSession> launch() async {
    await LocalStore.init(path: dir.path);
    final settings = await LocalStore.openSettings();
    final s = AppSession(
      paths: paths,
      settings: settings,
      window: _Window(),
      secrets: SecretStore(keychain),
      biometrics: bio,
      screens: SessionScreens(
        locked: (_) => const Text('locked'),
        migrating: (_, d) => Text('migrating ${d.name}'),
        failure: (e, _) => Text('failure $e'),
      ),
      startApp: (c) async => sessions.add(c),
      show: (w) => shown.add((w as Text).data!),
      releaseHotkeys: (_) async {},
      settle: () async {},
      kdf: _fast,
      overrides: [sessionBusyProvider.overrideWith((ref) => ref.watch(_busy))],
    );
    await s.start();
    return s;
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sotto_session');
    paths = StoragePaths.inside(dir);
    shown = [];
    sessions = [];
    keychain = _Keychain();
    bio = _Bio();
    session = await launch();
    await sessions.last.read(localStoreProvider).scripts.put('s1', {'id': 's1', 'title': 'Keynote'});
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Future<VaultSetup> turnOn([String password = 'password1']) async {
    final setup = await session.createVault(password);
    await session.enable(setup);
    return setup;
  }

  test('without a vault the app starts as before', () async {
    expect(sessions, hasLength(1));
    expect(shown, isEmpty);
    expect(session.lockEnabled, isFalse);
    expect(sessions.last.read(lockEnabledProvider), isFalse);
    expect(await session.lock(), isFalse, reason: 'nothing to lock with');
  });

  test('turning the lock on encrypts the data and reopens on Privacy', () async {
    final first = sessions.last;
    await turnOn();
    expect(shown, ['migrating encrypt']);
    expect(sessions, hasLength(2));
    expect(() => first.read(localStoreProvider), throwsStateError, reason: 'the old session is disposed');
    expect(paths.vault.existsSync(), isTrue);
    expect(sessions.last.read(lockEnabledProvider), isTrue);
    expect(sessions.last.read(initialLocationProvider), AppSession.privacyLocation);
    expect(sessions.last.read(localStoreProvider).scripts.get('s1')!['title'], 'Keynote');
    expect(sessions.last.read(localStoreProvider).organizeKey, hasLength(32));
  });

  test('turning the lock on twice is refused before anything is touched', () async {
    await turnOn();
    await expectLater(turnOn(), throwsStateError);
    expect(shown, ['migrating encrypt'], reason: 'no second migration started');
    expect(sessions.last.read(localStoreProvider).scripts.get('s1')!['title'], 'Keynote');
  });

  test('lock closes the data and the session; the password opens them again', () async {
    await turnOn();
    final open = sessions.last;
    expect(await session.lock(), isTrue);
    expect(shown.last, 'locked');
    expect(session.unlocked, isFalse);
    expect(Hive.isBoxOpen('scripts'), isFalse);
    expect(Hive.isBoxOpen('settings'), isTrue);
    expect(() => open.read(localStoreProvider), throwsStateError);

    expect(await session.unlockWithPassword('wrong'), UnlockResult.wrong);
    expect(sessions, hasLength(2));
    expect(await session.unlockWithPassword('password1'), UnlockResult.unlocked);
    expect(sessions, hasLength(3));
    expect(sessions.last.read(initialLocationProvider), '/');
    expect(sessions.last.read(localStoreProvider).scripts.get('s1')!['title'], 'Keynote');
  });

  test('a restart with the lock on shows the unlock screen first', () async {
    await turnOn();
    await Hive.close();
    shown.clear();
    session = await launch();
    expect(shown, ['locked']);
    expect(session.lockEnabled, isTrue);
    expect(session.unlocked, isFalse);
    expect(Hive.isBoxOpen('scripts'), isFalse, reason: 'nothing is opened before the password');
    expect(await session.unlockWithPassword('password1'), UnlockResult.unlocked);
  });

  test('five wrong passwords throttle the next try, across a restart', () async {
    await turnOn();
    await session.lock();
    for (var i = 0; i < 5; i++) {
      expect(await session.unlockWithPassword('nope $i'), UnlockResult.wrong);
    }
    expect(await session.unlockWithPassword('password1'), UnlockResult.throttled);
    await Hive.close();
    session = await launch();
    expect(session.throttle.blocked, isTrue);
    expect(await session.unlockWithPassword('password1'), UnlockResult.throttled);
  });

  test('it never locks in the middle of something', () async {
    await turnOn();
    sessions.last.read(_busy.notifier).set(true);
    expect(await session.lock(), isFalse);
    expect(session.unlocked, isTrue);
    sessions.last.read(_busy.notifier).set(false);
    expect(await session.lock(), isTrue);
  });

  test('forgot password: the recovery key sets a new one', () async {
    final setup = await turnOn('forgotten');
    await session.lock();
    final (bad, none) = await session.checkRecoveryKey('0000-0000-0000-0000-0000-0000-0000');
    expect((bad, none), (UnlockResult.wrong, null));
    final (ok, dek) = await session.checkRecoveryKey(setup.recoveryKey);
    expect(ok, UnlockResult.unlocked);
    await session.resetPassword(dek!, 'remembered');
    expect(session.unlocked, isTrue);
    await session.lock();
    expect(await session.unlockWithPassword('forgotten'), UnlockResult.wrong);
    expect(await session.unlockWithPassword('remembered'), UnlockResult.unlocked);
    expect(sessions.last.read(localStoreProvider).scripts.get('s1')!['title'], 'Keynote');
  });

  test('change password, show and regenerate the recovery key', () async {
    final setup = await turnOn();
    expect(await session.changePassword('wrong', 'x'), isFalse);
    expect(await session.changePassword('password1', 'password2'), isTrue);
    expect(await session.recoveryKey('password1'), isNull);
    expect(await session.recoveryKey('password2'), setup.recoveryKey);

    final fresh = await session.regenerateRecoveryKey('password2');
    expect(fresh, isNot(setup.recoveryKey));
    await session.lock();
    expect((await session.checkRecoveryKey(setup.recoveryKey)).$1, UnlockResult.wrong);
    expect((await session.checkRecoveryKey(fresh!)).$1, UnlockResult.unlocked);
  });

  test('a key from the keychain unlocks only if the vault confirms it', () async {
    final setup = await session.createVault('password1');
    // Locking zero-fills the session's key: keep a copy, as the keychain would.
    final saved = Uint8List.fromList(setup.dek);
    await session.enable(setup);
    await session.lock();
    expect(setup.dek, everyElement(0), reason: 'the dropped key was wiped');
    expect(await session.unlockWithKey(Uint8List(32)), isFalse);
    expect(session.unlocked, isFalse);
    expect(await session.unlockWithKey(saved), isTrue);
    expect(session.unlocked, isTrue);
  });

  test('turning the lock off needs the password and leaves plain data', () async {
    await turnOn();
    keychain.values['sotto.${SecretKey.appLockKey.name}'] = 'key';
    expect(await session.disable('wrong'), isFalse);
    expect(paths.vault.existsSync(), isTrue);
    expect(await session.disable('password1'), isTrue);
    expect(shown.last, 'migrating decrypt');
    expect(paths.vault.existsSync(), isFalse);
    expect(keychain.deleted, contains('sotto.${SecretKey.appLockKey.name}'));
    expect(sessions.last.read(lockEnabledProvider), isFalse);
    expect(sessions.last.read(localStoreProvider).scripts.get('s1')!['title'], 'Keynote');
    await Hive.close();
    session = await launch();
    expect(session.unlocked, isTrue, reason: 'opens straight away again');
  });

  test('Reset Sotto deletes the data and the lock, keeps the settings', () async {
    await turnOn();
    sessions.last.read(settingsProvider.notifier).update((s) => s.copyWith(historyRetentionDays: 7));
    await session.flush();
    keychain.values['sotto.${SecretKey.deepseekApiKey.name}'] = 'sk-kept';
    await session.lock();
    await session.unlockWithPassword('bad');
    await session.resetEverything();
    expect(session.unlocked, isTrue);

    expect(session.lockEnabled, isFalse);
    for (final f in [paths.vault, paths.attempts, paths.migrationMarker, paths.pendingVault]) {
      expect(f.existsSync(), isFalse, reason: f.path);
    }
    expect(sessions.last.read(localStoreProvider).scripts.get('s1'), isNull);
    expect(sessions.last.read(settingsProvider).historyRetentionDays, 7);
    expect(keychain.deleted, contains('sotto.${SecretKey.appLockKey.name}'));
    expect(keychain.values['sotto.${SecretKey.deepseekApiKey.name}'], 'sk-kept');
  });

  test('a damaged vault stays locked, and Reset still works', () async {
    await turnOn();
    await Hive.close();
    paths.vault.writeAsStringSync('{"format": 1');
    session = await launch();
    expect(shown.last, 'locked');
    expect(session.vaultDamaged, isTrue);
    expect(await session.unlockWithPassword('password1'), UnlockResult.damaged);
    await session.resetEverything();
    expect(session.unlocked, isTrue);
    expect(session.lockEnabled, isFalse);
  });

  test('a test-data run has its own lock key in the keychain', () async {
    final k = _Keychain();
    final dev = SecretStore(k, 'sotto.dev.');
    await dev.write(SecretKey.appLockKey, 'test-key');
    await dev.write(SecretKey.deepseekApiKey, 'sk-shared');
    expect(k.values.keys, unorderedEquals(['sotto.dev.appLockKey', 'sotto.deepseekApiKey']));
    await SecretStore(k).write(SecretKey.appLockKey, null);
    expect(k.values['sotto.dev.appLockKey'], 'test-key', reason: 'the real entry is a different one');
  });

  group('Windows Hello', () {
    const entry = 'sotto.appLockKey';

    Future<void> turnOnHello() async {
      await turnOn();
      expect(await session.enableBiometrics(), isTrue);
      sessions.last.read(settingsProvider.notifier).update((s) => s.copyWith(lockBiometrics: true));
      await session.flush();
    }

    test('off until turned on; then the keychain holds the data key', () async {
      await turnOn();
      expect(session.biometricMethod, isNull);
      expect(await session.enableBiometrics(), isTrue);
      sessions.last.read(settingsProvider.notifier).update((s) => s.copyWith(lockBiometrics: true));
      await session.flush();
      expect(keychain.values[entry], isNotNull);
      expect(session.biometricMethod, 'Windows Hello');
    });

    test('unlocks after the prompt, and not when it is cancelled', () async {
      await turnOnHello();
      await session.lock();
      bio.ok = false;
      expect(await session.unlockWithBiometrics(), isFalse);
      expect(session.unlocked, isFalse);
      bio.ok = true;
      expect(await session.unlockWithBiometrics(), isTrue);
      expect(sessions.last.read(localStoreProvider).scripts.get('s1')!['title'], 'Keynote');
    });

    test("a keychain key that is not this vault's is refused", () async {
      await turnOnHello();
      await session.lock();
      keychain.values[entry] = base64Encode(List.filled(32, 9));
      expect(await session.unlockWithBiometrics(), isFalse);
      expect(session.unlocked, isFalse);
    });

    test('turning it off deletes the keychain copy', () async {
      await turnOnHello();
      await session.disableBiometrics();
      expect(keychain.values.containsKey(entry), isFalse);
      expect(session.biometricMethod, isNull);
    });

    test('turning the lock off, or Reset, clears it too', () async {
      await turnOnHello();
      await session.disable('password1');
      expect(keychain.values.containsKey(entry), isFalse);
      expect(sessions.last.read(settingsProvider).lockBiometrics, isFalse);
    });

    test('the key is never kept in the keychain cache', () async {
      await turnOnHello();
      keychain.values.remove(entry);
      await session.lock();
      expect(await session.unlockWithBiometrics(), isFalse, reason: 'read fresh, not from memory');
    });
  });
}

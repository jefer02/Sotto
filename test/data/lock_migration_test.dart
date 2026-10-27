import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:sotto/data/lock/migration.dart';
import 'package:sotto/data/lock/vault.dart';
import 'package:sotto/data/storage/local_store.dart';
import 'package:sotto/data/storage/organize_cache.dart';
import 'package:sotto/data/storage/storage_paths.dart';

const _fast = KdfParams(memoryKiB: 64, iterations: 1, parallelism: 1);
const _secret = 'SECRET-SCRIPT-TEXT-4711';

class _Crash implements Exception {}

void main() {
  late Directory dir;
  late StoragePaths paths;
  late VaultSetup setup;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sotto_migration');
    paths = StoragePaths.inside(dir);
    setup = await VaultCrypto.create('password1', params: _fast);
    final store = await LocalStore.open(path: dir.path);
    await store.scripts.put('s1', {'id': 's1', 'title': _secret});
    await store.scripts.put('s2', {'id': 's2', 'title': 'Second'});
    await store.collections.put('c1', {'id': 'c1', 'name': 'Talks'});
    await store.qa.put('q1', {'id': 'q1', 'question': 'Why?'});
    await store.sessions.put('x1', {'id': 'x1'});
    await store.chats.put('t1', {'id': 't1'});
    await store.organizeCache.put('h1', {'at': 'now', 'sections': []});
    await store.prefs.put('app', {'formsInstructions': 'My name is Ana'});
    await store.close();
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  /// Opens every data box with [cipher] and returns its records.
  Future<Map<String, Map<dynamic, Map>>> read({HiveCipher? cipher}) async {
    final out = <String, Map<dynamic, Map>>{};
    for (final name in LocalStore.dataBoxes) {
      final box = await Hive.openBox<Map>(name, encryptionCipher: cipher);
      out[name] = box.toMap();
      await box.close();
    }
    return out;
  }

  Set<String> files() => {for (final f in dir.listSync()) f.uri.pathSegments.last};

  bool onDiskContains(String text) => LocalStore.dataBoxes.any(
    (n) => paths.box(n).existsSync() && latin1.decode(paths.box(n).readAsBytesSync()).contains(text),
  );

  Future<void> crashAt(String step, Future<void> Function(LockMigration m) run) async {
    final m = LockMigration(paths, onStep: (s) async => s == step ? throw _Crash() : null);
    await expectLater(run(m), throwsA(isA<_Crash>()));
    await Hive.close(); // the process died: nothing stays open
    Hive.init(dir.path);
  }

  void expectData(Map<String, Map<dynamic, Map>> data, {bool cacheKept = true}) {
    expect(data['scripts']!.keys, unorderedEquals(['s1', 's2']));
    expect(data['scripts']!['s1']!['title'], _secret);
    expect(data['collections']!['c1']!['name'], 'Talks');
    expect(data['qa_history']!.keys, ['q1']);
    expect(data['sessions']!.keys, ['x1']);
    expect(data['chats']!.keys, ['t1']);
    expect(data['prefs']!['app']!['formsInstructions'], 'My name is Ana');
    expect(data['organize_cache']!.length, cacheKept ? 1 : 0);
  }

  test('plain → encrypted → plain keeps every record', () async {
    Hive.init(dir.path);
    expect(onDiskContains(_secret), isTrue);
    final progress = <int>[];

    await LockMigration(paths).encrypt(setup.dek, setup.vault, onProgress: (done, _) => progress.add(done));
    expect(progress, [0, 1, 2, 3, 4, 5, 6, 7]);
    expect(paths.vault.existsSync(), isTrue);
    expect(files().where((f) => f.contains('_migrating') || f.contains('pending') || f.contains('migration')), isEmpty);
    expect(onDiskContains(_secret), isFalse, reason: 'values are encrypted on disk');
    expectData(await read(cipher: HiveAesCipher(setup.dek)), cacheKept: false);

    await LockMigration(paths).decrypt(setup.dek);
    expect(paths.vault.existsSync(), isFalse);
    expect(onDiskContains(_secret), isTrue);
    expectData(await read(), cacheKept: false);
  });

  test('the store opens encrypted data through a cipher', () async {
    Hive.init(dir.path);
    await LockMigration(paths).encrypt(setup.dek, setup.vault);
    final store = await LocalStore.openData(await LocalStore.openSettings(), cipher: HiveAesCipher(setup.dek));
    expect(store.scripts.get('s1')!['title'], _secret);
    await store.closeData();
    expect(Hive.isBoxOpen('scripts'), isFalse);
    expect(Hive.isBoxOpen('settings'), isTrue, reason: 'settings stay open while locked');
  });

  test('turning on, interrupted while copying, rolls back on the next start', () async {
    Hive.init(dir.path);
    await crashAt('copied:sessions', (m) => m.encrypt(setup.dek, setup.vault));
    expect(files(), contains('lock_migration.json'));

    final outcome = await LockMigration.recover(paths);
    expect(outcome, (direction: LockDirection.encrypt, rolledBack: true));
    expect(paths.vault.existsSync(), isFalse);
    expect(files().where((f) => f.contains('_migrating') || f.startsWith('lock_')), isEmpty);
    expectData(await read());
  });

  test('turning on, interrupted while swapping, finishes on the next start', () async {
    Hive.init(dir.path);
    await crashAt('swapped:qa_history', (m) => m.encrypt(setup.dek, setup.vault));
    expect(paths.vault.existsSync(), isFalse, reason: 'not yet promoted');

    final outcome = await LockMigration.recover(paths);
    expect(outcome, (direction: LockDirection.encrypt, rolledBack: false));
    final vault = (await VaultFile(paths.vault).read())!;
    final dek = (await VaultCrypto.openWithPassword(vault, 'password1'))!;
    expectData(await read(cipher: HiveAesCipher(dek)), cacheKept: false);
    expect(files().where((f) => f.contains('_migrating') || f.contains('pending') || f.contains('migration')), isEmpty);
  });

  test('turning off, interrupted while copying, stays locked with the data intact', () async {
    Hive.init(dir.path);
    await LockMigration(paths).encrypt(setup.dek, setup.vault);
    await crashAt('copied:chats', (m) => m.decrypt(setup.dek));

    expect(await LockMigration.recover(paths), (direction: LockDirection.decrypt, rolledBack: true));
    expect(paths.vault.existsSync(), isTrue);
    expectData(await read(cipher: HiveAesCipher(setup.dek)), cacheKept: false);
  });

  test('turning off, interrupted while swapping, finishes and deletes the vault', () async {
    Hive.init(dir.path);
    await LockMigration(paths).encrypt(setup.dek, setup.vault);
    await crashAt('swapping', (m) => m.decrypt(setup.dek));

    expect(await LockMigration.recover(paths), (direction: LockDirection.decrypt, rolledBack: false));
    expect(paths.vault.existsSync(), isFalse);
    expectData(await read(), cacheKept: false);
  });

  test('nothing to recover is a no-op that clears stray copies', () async {
    File('${dir.path}/scripts_migrating.hive').writeAsStringSync('half');
    expect(await LockMigration.recover(paths), isNull);
    expect(files(), isNot(contains('scripts_migrating.hive')));
    Hive.init(dir.path);
    expectData(await read());
  });

  test('an unreadable marker stops startup instead of guessing', () async {
    paths.migrationMarker.writeAsStringSync('{');
    await expectLater(LockMigration.recover(paths), throwsA(isA<MigrationFailed>()));
  });

  test('a box left open is refused', () async {
    Hive.init(dir.path);
    await Hive.openBox<Map>('scripts');
    await expectLater(LockMigration(paths).encrypt(setup.dek, setup.vault), throwsStateError);
  });

  group('prefs', () {
    const text = 'I am Ana Ruiz from Acme';

    Future<void> oldSettings() async {
      Hive.init(dir.path);
      final prefs = await Hive.openBox<Map>('prefs');
      await prefs.clear();
      await prefs.close();
      final settings = await Hive.openBox<Map>('settings');
      await settings.put('app', {'appTheme': 'light', 'formsInstructions': text});
      await settings.close();
    }

    bool settingsFileHas(String s) => latin1.decode(paths.box('settings').readAsBytesSync()).contains(s);

    test('lock off: copied into prefs, and a copy stays in settings for older builds', () async {
      await oldSettings();
      final store = await LocalStore.openData(await LocalStore.openSettings());
      expect(store.prefs.get('app')!['formsInstructions'], text);
      await store.settingsWrites.flush();
      expect(store.settings.get('app')!['formsInstructions'], text);
      expect(store.settings.get('app')!['appTheme'], 'light');
      await store.close();
    });

    test('lock on: gone from settings, the file compacted; lock off: written back', () async {
      await oldSettings();
      final plain = await LocalStore.openData(await LocalStore.openSettings());
      await plain.closeData();
      await LockMigration(paths).encrypt(setup.dek, setup.vault);

      final locked = await LocalStore.openData(
        SettingsStore(Hive.box<Map>('settings')),
        cipher: HiveAesCipher(setup.dek),
      );
      expect(locked.encrypted, isTrue);
      expect(locked.prefs.get('app')!['formsInstructions'], text);
      expect(locked.settings.get('app')!.containsKey('formsInstructions'), isFalse);
      expect(settingsFileHas('Ana Ruiz'), isFalse, reason: 'no old copy left in the file');
      await locked.closeData();

      await LockMigration(paths).decrypt(setup.dek);
      final unlocked = await LocalStore.openData(SettingsStore(Hive.box<Map>('settings')));
      await unlocked.settingsWrites.flush();
      expect(unlocked.settings.get('app')!['formsInstructions'], text);
      await unlocked.close();
    });
  });

  test('organize cache keys are HMACs with the lock on', () {
    final box = _NullBox();
    final plain = OrganizeCache(box).keyFor('text', 'model');
    final keyed = OrganizeCache(box, hmacKey: List.filled(32, 1)).keyFor('text', 'model');
    expect(plain, hasLength(64));
    expect(keyed, hasLength(64));
    expect(keyed, isNot(plain));
    expect(OrganizeCache(box, hmacKey: List.filled(32, 2)).keyFor('text', 'model'), isNot(keyed));
  });
}

class _NullBox implements Box<Map> {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

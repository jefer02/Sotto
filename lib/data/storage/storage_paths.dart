import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where Sotto keeps things on disk, decided in one place so the data
/// folder can move later without touching the code that uses it.
///
/// [data] holds the Hive boxes (Documents\Sotto, where Hive.initFlutter
/// put them). [support] holds the App Lock's small files, kept out of
/// Documents and the sync apps that watch it.
///
/// Development: `--dart-define=SOTTO_DATA_ROOT=C:\SottoTest` moves both
/// into that folder (`<root>\data`, `<root>\support`) and gives the
/// keychain entry of the lock its own name, so a test run never touches the
/// real data or the real lock. Ignored in release builds. The speech models
/// stay where they are, shared.
class StoragePaths {
  const StoragePaths({required this.data, required this.support, this.devRoot});

  final Directory data;
  final Directory support;

  /// The SOTTO_DATA_ROOT folder in use, or null.
  final Directory? devRoot;

  static const _devRoot = String.fromEnvironment('SOTTO_DATA_ROOT');

  static Future<StoragePaths> resolve() async {
    if (!kReleaseMode && _devRoot.isNotEmpty) {
      final root = Directory(_devRoot);
      return StoragePaths(
        data: Directory(p.join(root.path, 'data')),
        support: Directory(p.join(root.path, 'support')),
        devRoot: root,
      );
    }
    return StoragePaths(
      data: Directory(p.join((await getApplicationDocumentsDirectory()).path, 'Sotto')),
      support: await getApplicationSupportDirectory(),
    );
  }

  /// Keychain names start with this: `sotto.` normally, `sotto.dev.` with a
  /// SOTTO_DATA_ROOT, so the test run's lock key can't replace the real one.
  String get keychainPrefix => devRoot == null ? 'sotto.' : 'sotto.dev.';

  /// One folder for both, for tests.
  factory StoragePaths.inside(Directory dir) => StoragePaths(data: dir, support: dir);

  /// Present and valid = the lock is on.
  File get vault => File(p.join(support.path, 'lock_vault.json'));

  /// A vault written during "turn the lock on", before the boxes are swapped.
  File get pendingVault => File(p.join(support.path, 'lock_vault.pending.json'));

  File get attempts => File(p.join(support.path, 'lock_attempts.json'));

  /// Present while boxes are being encrypted or decrypted.
  File get migrationMarker => File(p.join(support.path, 'lock_migration.json'));

  /// A Hive box's file.
  File box(String name, [String ext = 'hive']) => File(p.join(data.path, '${name.toLowerCase()}.$ext'));
}

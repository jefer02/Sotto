import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';

import '../storage/local_store.dart';
import '../storage/storage_paths.dart';
import 'atomic_file.dart';
import 'throttle.dart';
import 'vault.dart';

enum LockDirection { encrypt, decrypt }

/// What [LockMigration.recover] found at startup.
typedef RecoveryOutcome = ({LockDirection direction, bool rolledBack});

/// Turns the App Lock on (encrypting every data box) or off (decrypting
/// them), so that a crash or power cut at any moment leaves the data
/// readable on the next start:
///
/// 1. **copy** — each box is copied into `<name>_migrating` with the new
///    cipher, then reopened from disk and its records counted. The
///    originals aren't touched; a crash here rolls back.
/// 2. The new vault is written as `lock_vault.pending.json` (turning on).
/// 3. **swap** — the marker says so first; then each original is deleted
///    and its copy renamed in its place. Only renames are left, so a crash
///    here rolls forward without needing the key.
/// 4. The pending vault becomes `lock_vault.json` (on), or the vault is
///    deleted (off); then the marker goes.
///
/// [recover] runs before any box is opened: opening an encrypted box
/// without its key would read as damaged records.
class LockMigration {
  LockMigration(this.paths, {@visibleForTesting this.onStep});

  final StoragePaths paths;

  /// Tests interrupt here ("copied:scripts", "swapping", "swapped:chats"…).
  final Future<void> Function(String step)? onStep;

  static const _suffix = '_migrating';
  static List<String> get boxes => LocalStore.dataBoxes;

  /// Encrypts the data boxes with [dek] and saves [vault]. Hive must point
  /// at [StoragePaths.data] and the data boxes must be closed (flushed).
  Future<void> encrypt(List<int> dek, LockVault vault, {void Function(int done, int total)? onProgress}) async {
    await _writeMarker(LockDirection.encrypt, 'copy');
    await _copyAll(from: null, to: HiveAesCipher(dek), onProgress: onProgress);
    await VaultFile(paths.pendingVault).write(vault);
    await _swapAndFinish(LockDirection.encrypt);
  }

  /// Decrypts the data boxes back to plain files and deletes the vault.
  Future<void> decrypt(List<int> dek, {void Function(int done, int total)? onProgress}) async {
    await _writeMarker(LockDirection.decrypt, 'copy');
    await _copyAll(from: HiveAesCipher(dek), to: null, onProgress: onProgress);
    await _swapAndFinish(LockDirection.decrypt);
  }

  /// Finishes or undoes a migration a crash interrupted. Null when there
  /// was none. Throws [MigrationFailed] if the marker can't be read.
  static Future<RecoveryOutcome?> recover(StoragePaths paths) async {
    final m = LockMigration(paths);
    final marker = paths.migrationMarker;
    if (!await marker.exists()) {
      // Leftovers from a run whose marker was already gone: nothing uses them.
      await m._deleteTemps();
      if (await paths.pendingVault.exists()) await paths.pendingVault.delete();
      return null;
    }
    final LockDirection direction;
    final String phase;
    try {
      final j = jsonDecode(await marker.readAsString()) as Map;
      direction = LockDirection.values.byName(j['direction'] as String);
      phase = j['phase'] as String;
    } catch (e) {
      throw MigrationFailed('unreadable migration marker (${e.runtimeType})');
    }
    if (phase == 'copy') {
      await m._deleteTemps();
      if (await paths.pendingVault.exists()) await paths.pendingVault.delete();
      await marker.delete();
      return (direction: direction, rolledBack: true);
    }
    if (phase != 'swap') throw MigrationFailed('unknown migration phase');
    await m._swapAndFinish(direction, resume: true);
    return (direction: direction, rolledBack: false);
  }

  // ─────────────────────────── Steps ───────────────────────────

  Future<void> _copyAll({
    required HiveCipher? from,
    required HiveCipher? to,
    void Function(int done, int total)? onProgress,
  }) async {
    await _deleteTemps();
    onProgress?.call(0, boxes.length);
    for (final (i, name) in boxes.indexed) {
      await _copy(name, from, to);
      await onStep?.call('copied:$name');
      onProgress?.call(i + 1, boxes.length);
    }
  }

  Future<void> _copy(String name, HiveCipher? from, HiveCipher? to) async {
    if (Hive.isBoxOpen(name)) throw StateError('$name must be closed before it is migrated');
    final temp = '$name$_suffix';
    final source = await Hive.openBox<Map>(name, encryptionCipher: from);
    final target = await Hive.openBox<Map>(temp, encryptionCipher: to);
    final Set<Object?> keys;
    try {
      // The organize cache is rebuilt on demand: it starts empty.
      final records = LocalStore.derivedBoxes.contains(name) ? <dynamic, Map>{} : source.toMap();
      keys = records.keys.toSet();
      await target.putAll(records);
      await target.flush();
    } finally {
      await target.close();
      await source.close();
    }
    // Counted again from disk, through the new cipher.
    final check = await Hive.openBox<Map>(temp, encryptionCipher: to);
    try {
      final same = check.length == keys.length && check.keys.every(keys.contains) && check.values.length == keys.length;
      if (!same) throw MigrationFailed('$name: ${check.length} of ${keys.length} records copied');
    } finally {
      await check.close();
    }
  }

  Future<void> _swapAndFinish(LockDirection direction, {bool resume = false}) async {
    if (!resume) await _writeMarker(direction, 'swap');
    await onStep?.call('swapping');
    for (final name in boxes) {
      final copy = paths.box('$name$_suffix');
      if (await copy.exists()) {
        await _deleteBoxFiles(name);
        await copy.rename(paths.box(name).path);
        await _deleteBoxFiles('$name$_suffix');
      }
      await onStep?.call('swapped:$name');
    }
    switch (direction) {
      case LockDirection.encrypt:
        if (await paths.pendingVault.exists()) await paths.pendingVault.rename(paths.vault.path);
      case LockDirection.decrypt:
        await VaultFile(paths.vault).delete();
    }
    await UnlockThrottle.clear(paths.attempts);
    await paths.migrationMarker.delete();
  }

  Future<void> _writeMarker(LockDirection direction, String phase) => writeFileAtomic(
    paths.migrationMarker,
    jsonEncode({'direction': direction.name, 'phase': phase, 'at': DateTime.now().toUtc().toIso8601String()}),
  );

  Future<void> _deleteTemps() async {
    for (final name in boxes) {
      await _deleteBoxFiles('$name$_suffix');
    }
  }

  Future<void> _deleteBoxFiles(String name) async {
    for (final ext in const ['hive', 'hivec', 'lock']) {
      final f = paths.box(name, ext);
      if (await f.exists()) await f.delete();
    }
  }
}

class MigrationFailed implements Exception {
  const MigrationFailed(this.reason);
  final String reason;

  @override
  String toString() => 'Encrypting or decrypting the local data failed: $reason';
}

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import 'write_buffer.dart';

/// All app data lives in Hive boxes in the data folder (`StoragePaths.data`).
/// Records are stored as plain JSON maps so the schema can evolve
/// without generated adapters: unknown keys are ignored, missing ones fall
/// back to defaults in each model's `fromJson`.
///
/// Two parts: the `settings` box, which opens first and stays open (the
/// unlock screen needs the theme and language), and the data boxes
/// ([dataBoxes]), which the App Lock encrypts and closes when it locks.
class LocalStore {
  LocalStore._(
    this.scripts,
    this.collections,
    this.settings,
    this.qa,
    this.sessions,
    this.organizeCache,
    this.chats,
    this.prefs, {
    required this.settingsWrites,
    this.organizeKey,
    this.encrypted = false,
  }) : sessionWrites = BoxWriteBuffer(sessions);

  /// Every box the lock encrypts, by its name on disk.
  static const dataBoxes = ['scripts', 'collections', 'qa_history', 'sessions', 'organize_cache', 'chats', 'prefs'];

  /// Rebuilt from scripts on demand, so encrypting or decrypting starts it
  /// empty instead of copying it.
  static const derivedBoxes = {'organize_cache'};

  final Box<Map> scripts;
  final Box<Map> collections;
  final Box<Map> settings;
  final Box<Map> qa;
  final Box<Map> sessions;

  /// AI organizing results by a hash of the text, so re-importing the same
  /// file is instant. Derived from scripts, so "delete all" clears it too.
  final Box<Map> organizeCache;

  /// Assistant chat conversations.
  final Box<Map> chats;

  /// Preferences that can hold personal text (the forms instructions):
  /// kept out of `settings`, so the lock encrypts them with the data.
  final Box<Map> prefs;

  /// With the lock on, the organize cache's keys are HMACs under this key
  /// (derived from the data key) rather than plain hashes of the text.
  final Uint8List? organizeKey;

  /// The data boxes are encrypted (the App Lock is on).
  final bool encrypted;

  /// Session records (and the fill log inside them) and settings change in
  /// bursts — a fill cycle, a slider drag: their writes are coalesced.
  final BoxWriteBuffer sessionWrites;
  final BoxWriteBuffer settingsWrites;

  /// Writes every coalesced change now (on exit).
  Future<void> flush() => Future.wait([sessionWrites.flush(), settingsWrites.flush()]);

  /// Points Hive at the data folder. [path] is for tests; the app uses
  /// Documents\Sotto (`StoragePaths.data`).
  static Future<void> init({String? path}) async {
    if (path != null) {
      await Directory(path).create(recursive: true);
      Hive.init(path);
    } else {
      await Hive.initFlutter('Sotto');
    }
  }

  /// The settings box alone, before the data (and before unlocking).
  static Future<SettingsStore> openSettings() async => SettingsStore(await Hive.openBox<Map>('settings'));

  /// Everything, unencrypted — the app without the lock, and tests.
  static Future<LocalStore> open({String? path}) async {
    await init(path: path);
    return openData(await openSettings());
  }

  /// The data boxes, encrypted with [cipher] when the lock is on. Hive
  /// doesn't check a cipher's key: callers pass only a key the vault has
  /// verified, or a wrong one would read as damaged records.
  static Future<LocalStore> openData(SettingsStore settings, {HiveCipher? cipher, Uint8List? organizeKey}) async {
    final boxes = await Future.wait([for (final name in dataBoxes) Hive.openBox<Map>(name, encryptionCipher: cipher)]);
    final store = LocalStore._(
      boxes[0],
      boxes[1],
      settings.box,
      boxes[2],
      boxes[3],
      boxes[4],
      boxes[5],
      boxes[6],
      organizeKey: organizeKey,
      encrypted: cipher != null,
      settingsWrites: settings.writes,
    );
    await store._syncPrivatePrefs();
    return store;
  }

  /// The forms instructions live in [prefs]. Older versions kept them in
  /// `settings`, so a copy stays there while the lock is off (an older
  /// build still finds them). With the lock on, that copy is removed and
  /// the settings file compacted, so no plain copy lingers in it; turning
  /// the lock off writes it back.
  Future<void> _syncPrivatePrefs() async {
    final raw = settingsWrites.get(prefsSettingsKey);
    final inSettings = raw?[privatePrefsKey];
    final inPrefs = prefs.get(prefsSettingsKey)?[privatePrefsKey];
    // Once, from an older version.
    if (inPrefs == null && inSettings is String && inSettings.isNotEmpty) {
      await prefs.put(prefsSettingsKey, {...?prefs.get(prefsSettingsKey), privatePrefsKey: inSettings});
    }
    final value = inPrefs ?? inSettings;
    if (encrypted) {
      if (raw == null || !raw.containsKey(privatePrefsKey)) return;
      await settingsWrites.put(prefsSettingsKey, Map.of(raw)..remove(privatePrefsKey));
      await settingsWrites.flush();
      await settings.compact();
    } else if (value is String && inSettings != value) {
      await settingsWrites.put(prefsSettingsKey, {...?raw, privatePrefsKey: value});
    }
  }

  /// The settings record's key, in both `settings` and [prefs].
  static const prefsSettingsKey = 'app';

  /// The one setting kept in [prefs] (and mirrored in `settings` only while
  /// the lock is off).
  static const privatePrefsKey = 'formsInstructions';

  /// Emits the box's values now and after every change.
  static Stream<List<Map>> watchAll(Box<Map> box) async* {
    yield box.values.toList();
    await for (final _ in box.watch()) {
      yield box.values.toList();
    }
  }

  /// Flushes and closes the data boxes; `settings` stays open (locking).
  Future<void> closeData() async {
    await sessionWrites.flush();
    await Future.wait([
      for (final b in [scripts, collections, qa, sessions, organizeCache, chats, prefs]) b.close(),
    ]);
  }

  Future<void> close() async {
    await flush();
    await Hive.close();
  }

  /// "Delete all local data" in Privacy & data.
  Future<void> wipe() async {
    sessionWrites.discard();
    await Future.wait([
      scripts.clear(),
      collections.clear(),
      qa.clear(),
      sessions.clear(),
      organizeCache.clear(),
      chats.clear(),
      prefs.clear(),
    ]);
  }
}

/// The settings box and its write buffer: open from launch to quit,
/// across locks.
class SettingsStore {
  SettingsStore(this.box) : writes = BoxWriteBuffer(box);

  final Box<Map> box;
  final BoxWriteBuffer writes;
}

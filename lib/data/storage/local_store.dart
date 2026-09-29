import 'dart:async';

import 'package:hive_ce_flutter/hive_ce_flutter.dart';

/// All app data lives in Hive boxes under the platform's application-support
/// directory. Records are stored as plain JSON maps so the schema can evolve
/// without generated adapters: unknown keys are ignored, missing ones fall
/// back to defaults in each model's `fromJson`.
class LocalStore {
  LocalStore._(this.scripts, this.collections, this.settings, this.qa, this.sessions, this.organizeCache, this.chats);

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

  /// [path] is for tests; the app uses the application-support directory.
  static Future<LocalStore> open({String? path}) async {
    if (path != null) {
      Hive.init(path);
    } else {
      await Hive.initFlutter('Sotto');
    }
    final boxes = await Future.wait([
      Hive.openBox<Map>('scripts'),
      Hive.openBox<Map>('collections'),
      Hive.openBox<Map>('settings'),
      Hive.openBox<Map>('qa_history'),
      Hive.openBox<Map>('sessions'),
      Hive.openBox<Map>('organize_cache'),
      Hive.openBox<Map>('chats'),
    ]);
    return LocalStore._(boxes[0], boxes[1], boxes[2], boxes[3], boxes[4], boxes[5], boxes[6]);
  }

  /// Emits the box's values now and after every change.
  static Stream<List<Map>> watchAll(Box<Map> box) async* {
    yield box.values.toList();
    await for (final _ in box.watch()) {
      yield box.values.toList();
    }
  }

  Future<void> close() => Hive.close();

  /// "Delete all local data" in Privacy & data.
  Future<void> wipe() async {
    await Future.wait([
      scripts.clear(),
      collections.clear(),
      qa.clear(),
      sessions.clear(),
      organizeCache.clear(),
      chats.clear(),
    ]);
  }
}

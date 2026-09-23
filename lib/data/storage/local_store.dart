import 'dart:async';

import 'package:hive_ce_flutter/hive_ce_flutter.dart';

/// All app data lives in Hive boxes under the platform's application-support
/// directory. Records are stored as plain JSON maps so the schema can evolve
/// without generated adapters: unknown keys are ignored, missing ones fall
/// back to defaults in each model's `fromJson`.
class LocalStore {
  LocalStore._(this.scripts, this.collections, this.settings, this.qa, this.sessions);

  final Box<Map> scripts;
  final Box<Map> collections;
  final Box<Map> settings;
  final Box<Map> qa;
  final Box<Map> sessions;

  static Future<LocalStore> open() async {
    await Hive.initFlutter('Sotto');
    final boxes = await Future.wait([
      Hive.openBox<Map>('scripts'),
      Hive.openBox<Map>('collections'),
      Hive.openBox<Map>('settings'),
      Hive.openBox<Map>('qa_history'),
      Hive.openBox<Map>('sessions'),
    ]);
    return LocalStore._(boxes[0], boxes[1], boxes[2], boxes[3], boxes[4]);
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
    await Future.wait([scripts.clear(), collections.clear(), qa.clear(), sessions.clear()]);
  }
}

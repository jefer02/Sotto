import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import 'models/chat.dart';
import 'models/qa_entry.dart';
import 'models/script.dart';
import 'models/session_record.dart';
import 'models/settings.dart';
import 'storage/local_store.dart';
import 'storage/secret_store.dart';

/// Overridden in `main()` with the opened store.
final localStoreProvider = Provider<LocalStore>((ref) => throw StateError('LocalStore not initialised'));

final secretStoreProvider = Provider<SecretStore>((ref) => SecretStore());

// ───────────────────────────── Scripts ─────────────────────────────

class ScriptRepository {
  ScriptRepository(this._store);

  final LocalStore _store;

  Stream<List<Script>> watchAll() =>
      LocalStore.watchAll(_store.scripts)
          .map((maps) => maps.map(Script.fromJson).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)));

  Script? get(String id) {
    final raw = _store.scripts.get(id);
    return raw == null ? null : Script.fromJson(raw);
  }

  Future<void> save(Script script) => _store.scripts.put(script.id, script.toJson());

  Future<void> delete(String id) async {
    await _store.scripts.delete(id);
    final qaKeys = _store.qa.keys.where((k) => _store.qa.get(k)?['scriptId'] == id).toList();
    await _store.qa.deleteAll(qaKeys);
  }

  Future<Script> duplicate(Script s) async {
    final copy = Script.fromJson({
      ...s.toJson(),
      'id': Script.blank().id,
      'title': L10n.current.copyTitle(s.title),
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
      'rehearsalCount': 0,
    });
    await save(copy);
    return copy;
  }

  Stream<List<Collection>> watchCollections() =>
      LocalStore.watchAll(_store.collections)
          .map((maps) => maps.map(Collection.fromJson).sortedBy((c) => c.name.toLowerCase()));

  Future<void> saveCollection(Collection c) => _store.collections.put(c.id, c.toJson());

  Future<void> deleteCollection(String id) async {
    await _store.collections.delete(id);
    for (final key in _store.scripts.keys.toList()) {
      final raw = _store.scripts.get(key);
      if (raw != null && raw['collectionId'] == id) {
        await _store.scripts.put(key, {...raw, 'collectionId': null});
      }
    }
  }

  /// Collections from before colors existed get one each, in name order.
  Future<void> assignMissingTones() async {
    final all = _store.collections.values.map(Collection.fromJson).sortedBy((c) => c.name.toLowerCase()).toList();
    final placed = all.where((c) => c.tone != null).toList();
    for (final c in all.where((c) => c.tone == null)) {
      final toned = c.withTone(Collection.nextTone(placed));
      placed.add(toned);
      await saveCollection(toned);
    }
  }

  bool get isEmpty => _store.scripts.isEmpty;

  /// Refinement that was cut short by quitting leaves the quick, rule-based
  /// organization — which is complete, so the script is simply structured.
  Future<void> finishInterruptedOrganizing() async {
    for (final key in _store.scripts.keys.toList()) {
      final raw = _store.scripts.get(key);
      if (raw != null && raw['status'] == ScriptStatus.organizing.name) {
        await _store.scripts.put(key, {...raw, 'status': ScriptStatus.structured.name});
      }
    }
  }
}

final scriptRepositoryProvider = Provider<ScriptRepository>((ref) => ScriptRepository(ref.watch(localStoreProvider)));

final scriptsProvider = StreamProvider<List<Script>>((ref) => ref.watch(scriptRepositoryProvider).watchAll());

final collectionsProvider = StreamProvider<List<Collection>>(
  (ref) => ref.watch(scriptRepositoryProvider).watchCollections(),
);

final scriptByIdProvider = Provider.family<Script?, String>((ref, id) {
  final scripts = ref.watch(scriptsProvider).value;
  return scripts?.firstWhereOrNull((s) => s.id == id) ?? ref.read(scriptRepositoryProvider).get(id);
});

// ───────────────────────────── Settings ─────────────────────────────

class SettingsNotifier extends Notifier<AppSettings> {
  static const _key = 'app';

  @override
  AppSettings build() {
    final raw = ref.watch(localStoreProvider).settingsWrites.get(_key);
    return raw == null ? const AppSettings() : AppSettings.fromJson(raw);
  }

  void update(AppSettings Function(AppSettings s) change) {
    state = change(state);
    unawaited(ref.read(localStoreProvider).settingsWrites.put(_key, state.toJson()));
  }

  void reset(AppSettings Function(AppSettings current, AppSettings defaults) pick) =>
      update((s) => pick(s, const AppSettings()));
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

// ───────────────────────────── Q&A history ─────────────────────────────

class QaRepository {
  QaRepository(this._store);

  final LocalStore _store;

  Stream<List<QaEntry>> watchForScript(String scriptId) => LocalStore.watchAll(_store.qa).map(
    (maps) =>
        maps.where((m) => m['scriptId'] == scriptId).map(QaEntry.fromJson).sortedBy((e) => e.askedAt).reversed.toList(),
  );

  Stream<List<QaEntry>> watchForSession(String sessionId) => LocalStore.watchAll(_store.qa).map(
    (maps) => maps
        .where((m) => m['sessionId'] == sessionId)
        .map(QaEntry.fromJson)
        .sortedBy((e) => e.askedAt)
        .reversed
        .toList(),
  );

  Future<void> save(QaEntry e) => _store.qa.put(e.id, e.toJson());

  Future<void> clear() => _store.qa.clear();

  /// Enforces "transcripts kept locally for N days".
  Future<int> prune(int retentionDays) async {
    final cutoff = DateTime.now().subtract(Duration(days: retentionDays));
    final stale = _store.qa.keys.where((k) {
      final at = _store.qa.get(k)?['askedAt'] as String?;
      return at != null && DateTime.parse(at).isBefore(cutoff);
    }).toList();
    await _store.qa.deleteAll(stale);
    return stale.length;
  }
}

final qaRepositoryProvider = Provider<QaRepository>((ref) => QaRepository(ref.watch(localStoreProvider)));

final qaForScriptProvider = StreamProvider.family<List<QaEntry>, String>(
  (ref, scriptId) => ref.watch(qaRepositoryProvider).watchForScript(scriptId),
);

final qaForSessionProvider = StreamProvider.family<List<QaEntry>, String>(
  (ref, sessionId) => ref.watch(qaRepositoryProvider).watchForSession(sessionId),
);

// ───────────────────────────── Sessions ─────────────────────────────

class SessionRepository {
  SessionRepository(this._store);

  final LocalStore _store;

  Stream<List<SessionRecord>> watchAll() =>
      LocalStore.watchAll(_store.sessions)
          .map((maps) => maps.map(SessionRecord.fromJson).sortedBy((s) => s.startedAt).reversed.toList());

  /// Coalesced: writes within 200 ms reach disk together.
  Future<void> save(SessionRecord r) => _store.sessionWrites.put(r.id, r.toJson());

  Future<void> delete(String id) => _store.sessionWrites.delete(id);

  /// "Clear fill history": questionnaire records go; sessions that were
  /// only a questionnaire go with them, live sessions keep the rest.
  Future<void> clearFormRuns() async {
    await _store.sessionWrites.flush();
    final writes = <Future<void>>[];
    for (final raw in _store.sessions.values.toList()) {
      final r = SessionRecord.fromJson(raw);
      if (r.formRuns.isEmpty) continue;
      final onlyForms = r.agentRuns.isEmpty && r.wordsSpoken == 0 && r.sectionSeconds.isEmpty;
      writes.add(onlyForms ? delete(r.id) : save(r.withoutFormRuns()));
    }
    await Future.wait(writes);
  }
}

final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => SessionRepository(ref.watch(localStoreProvider)),
);

final sessionsProvider = StreamProvider<List<SessionRecord>>((ref) => ref.watch(sessionRepositoryProvider).watchAll());

// ───────────────────────────── Chats ─────────────────────────────

class ChatRepository {
  ChatRepository(this._store);

  final LocalStore _store;

  /// Newest first.
  Stream<List<Conversation>> watchAll() =>
      LocalStore.watchAll(_store.chats)
          .map((maps) => maps.map(Conversation.fromJson).sortedBy((c) => c.updatedAt).reversed.toList());

  Conversation? get(String id) {
    final raw = _store.chats.get(id);
    return raw == null ? null : Conversation.fromJson(raw);
  }

  Future<void> save(Conversation c) => _store.chats.put(c.id, c.toJson());

  Future<void> delete(String id) => _store.chats.delete(id);

  Future<void> clear() => _store.chats.clear();

  /// Privacy → Keep history: conversations untouched for longer go.
  Future<int> prune(int retentionDays) async {
    final cutoff = DateTime.now().subtract(Duration(days: retentionDays));
    final stale = _store.chats.keys.where((k) {
      final at = DateTime.tryParse(_store.chats.get(k)?['updatedAt'] as String? ?? '');
      return at != null && at.isBefore(cutoff);
    }).toList();
    await _store.chats.deleteAll(stale);
    return stale.length;
  }
}

final chatRepositoryProvider = Provider<ChatRepository>((ref) => ChatRepository(ref.watch(localStoreProvider)));

final conversationsProvider = StreamProvider<List<Conversation>>((ref) => ref.watch(chatRepositoryProvider).watchAll());

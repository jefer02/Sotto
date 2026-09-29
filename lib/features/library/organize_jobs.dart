import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/script.dart';
import '../../data/repositories.dart';
import '../../data/storage/organize_cache.dart';
import '../../domain/structuring/organize_plan.dart';
import '../../domain/structuring/script_structurer.dart';
import '../../services/ai/llm_client.dart';
import '../../services/ai/script_organizer.dart';

/// Where AI refinements land: the open editor's working copy when there is
/// one (so unsaved typing is never overwritten), otherwise storage.
abstract interface class ScriptWorkingCopy {
  /// [patch] gets the working copy and the beat holding the caret.
  void applyExternal(Script Function(Script script, String? caretBeat) patch);
}

class WorkingCopies {
  final _open = <String, ScriptWorkingCopy>{};

  void register(String scriptId, ScriptWorkingCopy copy) => _open[scriptId] = copy;

  void unregister(String scriptId, ScriptWorkingCopy copy) {
    if (identical(_open[scriptId], copy)) _open.remove(scriptId);
  }

  ScriptWorkingCopy? of(String scriptId) => _open[scriptId];
}

final workingCopiesProvider = Provider<WorkingCopies>((ref) => WorkingCopies());

final organizeCacheProvider = Provider<OrganizeCache>(
  (ref) => OrganizeCache(ref.watch(localStoreProvider).organizeCache),
);

/// A running (or just finished) refinement, for the progress bar.
class OrganizeProgress {
  const OrganizeProgress({required this.done, required this.total, this.kept = 0, this.finished = false, this.error});

  final int done;
  final int total;

  /// Parts left as the presenter edited them.
  final int kept;
  final bool finished;

  /// Why refining stopped early (bad key, no balance…); the rule-based
  /// result stays.
  final String? error;

  double get fraction => total == 0 ? 1 : done / total;

  OrganizeProgress copyWith({int? done, int? kept, bool? finished, String? error}) => OrganizeProgress(
    done: done ?? this.done,
    total: total,
    kept: kept ?? this.kept,
    finished: finished ?? this.finished,
    error: error ?? this.error,
  );
}

/// Background AI refinement of imported scripts, one job per script.
class OrganizeJobs extends Notifier<Map<String, OrganizeProgress>> {
  final _running = <String, ScriptOrganizer>{};

  @override
  Map<String, OrganizeProgress> build() => const {};

  bool isRunning(String scriptId) => _running.containsKey(scriptId);

  void _set(String id, OrganizeProgress p) => state = {...state, id: p};

  /// Refines [prep]'s chunks with [llm] (closed when done) and applies
  /// each to the script as it arrives. [budgets] keeps section time
  /// budgets by title when organizing again.
  Future<void> start(
    String scriptId,
    OrganizePrep prep,
    LlmClient llm, {
    String? cacheKey,
    Map<String, int?> budgets = const {},
  }) async {
    if (_running.containsKey(scriptId)) {
      llm.close();
      return;
    }
    final merger = RegionMerger(prep.regions);
    final organizer = _running[scriptId] = ScriptOrganizer(llm, labels: StructurerLabels.current());
    _set(scriptId, OrganizeProgress(done: 0, total: prep.chunks.length));
    final watch = Stopwatch()..start();
    List<ChunkOutcome> outcomes = const [];
    try {
      outcomes = await organizer.run(
        prep.parsed,
        prep.chunks,
        onChunk: (o) {
          final refined = o.sections;
          if (refined != null) {
            final withBudgets = ChunkSections([
              for (final s in refined.sections)
                budgets[s.title] == null ? s : s.copyWith(budgetSeconds: budgets[s.title]),
            ], continues: refined.continues);
            _patch(scriptId, organizer, (s, caret) => merger.apply(s, o.index, withBudgets, focusedBeat: caret).$1);
          }
          final p = state[scriptId];
          if (p != null) _set(scriptId, p.copyWith(done: p.done + 1, kept: merger.keptCount));
        },
      );
    } finally {
      llm.close();
      _running.remove(scriptId);
    }
    debugPrint(
      'organize: ${prep.parsed.wordCount} words, ${prep.chunks.length} chunks in ${watch.elapsedMilliseconds} ms',
    );

    _patch(scriptId, null, (s, caret) {
      final seamed = merger.fixSeams(s, focusedBeat: caret);
      return seamed.copyWith(
        status: ScriptStatus.structured,
        hintWords: ScriptStructurer.hintWordsFor(seamed.sections),
        updatedAt: seamed.updatedAt,
      );
    });

    final merged = ScriptOrganizer.mergedResult(outcomes);
    if (cacheKey != null && merged != null) unawaited(ref.read(organizeCacheProvider).put(cacheKey, merged));

    final fatal = outcomes.map((o) => o.error).whereType<LlmException>().firstOrNull;
    final p = state[scriptId];
    if (p != null) _set(scriptId, p.copyWith(finished: true, kept: merger.keptCount, error: fatal?.message));
    // The "kept your edits" note lingers a little, then the bar goes away.
    Timer(const Duration(seconds: 12), () {
      if (state[scriptId]?.finished ?? false) state = {...state}..remove(scriptId);
    });
  }

  void _patch(String scriptId, ScriptOrganizer? organizer, Script Function(Script, String?) patch) {
    final copy = ref.read(workingCopiesProvider).of(scriptId);
    if (copy != null) {
      copy.applyExternal(patch);
      return;
    }
    final repo = ref.read(scriptRepositoryProvider);
    final current = repo.get(scriptId);
    if (current == null) {
      organizer?.cancel(); // deleted meanwhile
      return;
    }
    final next = patch(current, null);
    if (!identical(next, current)) unawaited(repo.save(next));
  }
}

final organizeJobsProvider = NotifierProvider<OrganizeJobs, Map<String, OrganizeProgress>>(OrganizeJobs.new);

final organizeProgressProvider = Provider.family<OrganizeProgress?, String>(
  (ref, id) => ref.watch(organizeJobsProvider.select((m) => m[id])),
);

import 'dart:async';
import 'dart:isolate';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../core/utils/ids.dart';
import '../../data/import/script_importer.dart';
import '../../data/models/script.dart';
import '../../data/repositories.dart';
import '../../data/storage/organize_cache.dart';
import '../../domain/structuring/organize_plan.dart';
import '../../domain/structuring/script_structurer.dart';
import '../../services/ai/llm_client.dart';
import 'organize_jobs.dart';
import '../../l10n/l10n.dart';

Future<Script> createScriptAndOpen(WidgetRef ref, {String? collectionId}) async {
  final script = Script.blank(collectionId: collectionId);
  await ref.read(scriptRepositoryProvider).save(script);
  ref.read(routerProvider).go('/script/${script.id}');
  return script;
}

/// The rule-based first pass, on a background isolate. Top-level so the
/// closure sent to the isolate captures only the text and the labels.
Future<OrganizePrep> _prepare(String text) {
  final labels = StructurerLabels.current();
  return Isolate.run(() => OrganizePrep.build(text, labels));
}

Future<LlmClient?> _llmFor(WidgetRef ref) async {
  return LlmClient.forSettings(ref.read(settingsProvider), ref.read(secretStoreProvider));
}

/// Usable at once, refined in the background:
/// 1. the same text organized before → the cached result, instantly;
/// 2. otherwise the rule-based pass runs on a background isolate and the
///    script opens with it ("Refining…"), editable right away;
/// 3. with a DeepSeek key, [OrganizeJobs] refines it chunk by chunk.
Future<Script> importText(WidgetRef ref, ImportResult result, {String? collectionId, bool useAi = true}) async {
  final repo = ref.read(scriptRepositoryProvider);
  final settings = ref.read(settingsProvider);
  final llm = useAi ? await _llmFor(ref) : null;
  final cacheKey = OrganizeCache.keyFor(result.text, settings.aiModel);
  final now = DateTime.now();

  Script scriptWith(List<Section> sections, ScriptStatus status) => Script(
    id: newId(),
    title: result.title,
    sections: sections,
    createdAt: now,
    updatedAt: now,
    collectionId: collectionId,
    status: status,
    sourceName: result.sourceName,
    hintWords: ScriptStructurer.hintWordsFor(sections),
  );

  final cached = llm == null ? null : ref.read(organizeCacheProvider).get(cacheKey);
  if (cached != null) {
    llm?.close();
    final script = scriptWith(cached, ScriptStatus.structured);
    await repo.save(script);
    return script;
  }

  final prep = await _prepare(result.text);
  final script = scriptWith(prep.sections, llm == null ? ScriptStatus.structured : ScriptStatus.organizing);
  await repo.save(script);
  if (llm != null) {
    unawaited(ref.read(organizeJobsProvider.notifier).start(script.id, prep, llm, cacheKey: cacheKey));
  }
  return script;
}

Future<void> importFiles(WidgetRef ref, BuildContext context, {List<String>? paths, String? collectionId}) async {
  var files = paths;
  if (files == null) {
    final picked = await FilePicker.pickFiles(
      dialogTitle: L10n.current.dialogImportScript,
      type: FileType.custom,
      allowedExtensions: ScriptImporter.supportedExtensions,
    );
    files = [
      for (final f in picked)
        if (f.path != null) f.path!,
    ];
  }
  for (final path in files) {
    try {
      final result = await ScriptImporter.fromFile(path);
      await importText(ref, result, collectionId: collectionId);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}

Future<void> importFromClipboard(WidgetRef ref, {String? collectionId}) async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  final text = data?.text?.trim();
  if (text == null || text.isEmpty) return;
  final script = await importText(ref, ScriptImporter.fromPaste(text), collectionId: collectionId);
  ref.read(routerProvider).go('/script/${script.id}');
}

/// Re-runs organizing on an existing script's text, keeping section
/// budgets where titles survive.
Future<void> reorganize(WidgetRef ref, Script script, {bool useAi = true}) async {
  final raw = [
    for (final s in script.sections) ...[
      '## ${s.title}',
      for (final k in s.keyPoints) '- $k',
      '',
      for (final b in s.beats) '${b.cue?.token ?? ''} ${b.text}'.trim(),
      '',
    ],
  ].join('\n');
  final budgets = {for (final s in script.sections) s.title: s.budgetSeconds};
  final llm = useAi ? await _llmFor(ref) : null;
  final prep = await _prepare(raw);
  if (llm == null) {
    final sections = [for (final s in prep.sections) s.copyWith(budgetSeconds: budgets[s.title])];
    final copy = ref.read(workingCopiesProvider).of(script.id);
    if (copy != null) {
      copy.applyExternal((s, _) => s.copyWith(sections: sections, status: ScriptStatus.structured));
    } else {
      await ref
          .read(scriptRepositoryProvider)
          .save(script.copyWith(sections: sections, status: ScriptStatus.structured));
    }
    return;
  }
  // The rule-based pass first, so the regions the refinement replaces are
  // exactly what is on screen.
  final start = [for (final s in prep.sections) s.copyWith(budgetSeconds: budgets[s.title])];
  final regions = <List<Section>>[];
  var i = 0;
  for (final r in prep.regions) {
    regions.add(start.sublist(i, i + r.length));
    i += r.length;
  }
  final seeded = OrganizePrep(parsed: prep.parsed, chunks: prep.chunks, regions: regions);
  Script apply(Script s) => s.copyWith(sections: start, status: ScriptStatus.organizing);
  final copy = ref.read(workingCopiesProvider).of(script.id);
  if (copy != null) {
    copy.applyExternal((s, _) => apply(s));
  } else {
    await ref.read(scriptRepositoryProvider).save(apply(script));
  }
  unawaited(ref.read(organizeJobsProvider.notifier).start(script.id, seeded, llm, budgets: budgets));
}

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../core/utils/ids.dart';
import '../../data/import/script_importer.dart';
import '../../data/models/script.dart';
import '../../data/models/settings.dart';
import '../../data/repositories.dart';
import '../../data/storage/secret_store.dart';
import '../../domain/structuring/script_structurer.dart';
import '../../services/ai/answer_service.dart';
import '../../services/ai/llm_client.dart';
import '../../l10n/l10n.dart';

Future<Script> createScriptAndOpen(WidgetRef ref, {String? collectionId}) async {
  final script = Script.blank(collectionId: collectionId);
  await ref.read(scriptRepositoryProvider).save(script);
  ref.read(routerProvider).go('/script/${script.id}');
  return script;
}

Future<LlmClient?> _llmFor(WidgetRef ref) async {
  final s = ref.read(settingsProvider);
  final secrets = ref.read(secretStoreProvider);
  final key = await secrets.read(switch (s.aiProvider) {
    AiProvider.anthropic => SecretKey.anthropicApiKey,
    AiProvider.openai => SecretKey.openaiApiKey,
    AiProvider.openaiCompatible => SecretKey.compatibleApiKey,
  });
  if (key == null && s.aiProvider != AiProvider.openaiCompatible) return null;
  return LlmClient.create(s, key ?? '');
}

/// Creates the script immediately (status "Organizing…" in the library),
/// then structures it: with the model when a key is set, otherwise — or if
/// the model fails — with the offline rule-based structurer.
Future<Script> importText(WidgetRef ref, ImportResult result, {String? collectionId, bool useAi = true}) async {
  final repo = ref.read(scriptRepositoryProvider);
  final now = DateTime.now();
  final placeholder = Script(
    id: newId(),
    title: result.title,
    sections: [Section.create(L10n.current.sectionOpening)],
    createdAt: now,
    updatedAt: now,
    collectionId: collectionId,
    status: ScriptStatus.organizing,
    sourceName: result.sourceName,
  );
  // Everything the background task needs is captured now: the widget that
  // started the import may be gone by the time organizing finishes.
  final llmFuture = useAi ? _llmFor(ref) : Future<LlmClient?>.value();
  await repo.save(placeholder);

  unawaited(() async {
    const structurer = ScriptStructurer();
    List<Section>? sections;
    if (useAi) {
      final llm = await llmFuture;
      if (llm != null) {
        try {
          final md = await AnswerService(llm).organize(result.text);
          final parsed = structurer.structure(md, linePerBeat: true);
          if (parsed.fold<int>(0, (a, s) => a + s.wordCount) > 0) sections = parsed;
        } catch (_) {
          // Offline or rejected: the rule-based pass below still works.
        } finally {
          llm.close();
        }
      }
    }
    sections ??= structurer.structure(result.text);
    final current = repo.get(placeholder.id) ?? placeholder;
    await repo.save(
      current.copyWith(
        sections: sections,
        status: ScriptStatus.structured,
        hintWords: ScriptStructurer.hintWordsFor(sections),
      ),
    );
  }());
  return placeholder;
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

/// Re-runs organizing on an existing script's text.
Future<void> reorganize(WidgetRef ref, Script script, {bool useAi = true}) async {
  final raw = [
    for (final s in script.sections) ...[
      '## ${s.title}',
      for (final k in s.keyPoints) '- $k',
      for (final b in s.beats) '${b.cue?.token ?? ''} ${b.text}'.trim(),
      '',
    ],
  ].join('\n');
  final repo = ref.read(scriptRepositoryProvider);
  await repo.save(script.copyWith(status: ScriptStatus.organizing));
  const structurer = ScriptStructurer();
  List<Section>? sections;
  if (useAi) {
    final llm = await _llmFor(ref);
    if (llm != null) {
      try {
        sections = structurer.structure(await AnswerService(llm).organize(raw), linePerBeat: true);
      } catch (_) {
      } finally {
        llm.close();
      }
    }
  }
  sections ??= structurer.structure(raw);
  // Keep the presenter's budgets where section titles survived.
  final budgets = {for (final s in script.sections) s.title: s.budgetSeconds};
  sections = [for (final s in sections) s.copyWith(budgetSeconds: budgets[s.title])];
  await repo.save(script.copyWith(sections: sections, status: ScriptStatus.structured));
}

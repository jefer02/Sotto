import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/utils/ids.dart';
import '../../data/import/material_reader.dart';
import '../../data/import/source_material.dart';
import '../../data/models/script.dart';
import '../../data/models/settings.dart';
import '../../data/repositories.dart';
import '../../domain/structuring/script_structurer.dart';
import '../../l10n/l10n.dart';
import '../../services/ai/llm_client.dart';
import '../../services/ai/script_generator.dart';
import '../../services/screen/screen_service.dart';
import 'organize_jobs.dart';

/// Reads the files added to "Generate with AI". Tests swap it.
final materialReaderProvider = Provider<MaterialReader>(
  (ref) => MaterialReader(ocr: NativeImageOcr(ref.watch(screenServiceProvider))),
);

final generationCacheProvider = Provider<GenerationCache>(
  (ref) => GenerationCache(ref.watch(localStoreProvider).organizeCache),
);

/// The presenter's pace for a word budget: the mean of their measured
/// rehearsals, else the pace in Settings (148 wpm until they rehearse).
({int wpm, bool measured}) paceFor(AppSettings s) {
  final samples = s.paceSamples.where((x) => x > 0).toList();
  if (samples.isEmpty) return (wpm: s.wordsPerMinute, measured: false);
  final mean = samples.reduce((a, b) => a + b) / samples.length;
  return (wpm: mean.round().clamp(80, 240), measured: true);
}

/// A file added as material: being read, read, or not readable.
class MaterialEntry {
  const MaterialEntry({required this.id, required this.name, this.material, this.error});

  final String id;
  final String name;
  final SourceMaterial? material;

  /// Why it couldn't be read, in the interface language.
  final String? error;

  bool get reading => material == null && error == null;
}

enum GeneratePhase { form, generating, failed }

/// "Generate with AI": the material, then the run — progress per stage and
/// the script as it streams. Nothing is saved until a run succeeds; a
/// cancelled or failed run leaves no script behind.
class GenerateScriptController extends ChangeNotifier {
  GenerateScriptController({
    required this.reader,
    required this.llm,
    required this.cache,
    required this.save,
    required this.model,
  });

  final MaterialReader reader;

  /// A DeepSeek client, or null without a key.
  final Future<LlmClient?> Function() llm;
  final GenerationCache cache;
  final Future<void> Function(Script script) save;

  /// The DeepSeek model, part of the cache key.
  final String model;

  final List<MaterialEntry> materials = [];
  GeneratePhase phase = GeneratePhase.form;
  GenerationProgress? progress;
  String preview = '';
  String? error;
  ScriptGenerator? _generator;
  bool _stopped = false;
  bool _disposed = false;

  List<SourceMaterial> get ready => [
    for (final m in materials)
      if (m.material != null) m.material!,
  ];

  bool get reading => materials.any((m) => m.reading);
  bool get canGenerate => ready.isNotEmpty && !reading && phase != GeneratePhase.generating;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// Reads each file off the UI thread; each shows in the list at once
  /// and fills in when read.
  Future<void> addFiles(List<String> paths) async {
    final added = [for (final path in paths) (path, MaterialEntry(id: newId(), name: p.basename(path)))];
    materials.addAll(added.map((a) => a.$2));
    _changed();
    await Future.wait([
      for (final (path, entry) in added)
        () async {
          MaterialEntry next;
          try {
            next = MaterialEntry(id: entry.id, name: entry.name, material: await reader.read(path));
          } on MaterialException catch (e) {
            next = MaterialEntry(id: entry.id, name: entry.name, error: MaterialReader.describe(e));
          } catch (_) {
            next = MaterialEntry(
              id: entry.id,
              name: entry.name,
              error: MaterialReader.describe(const MaterialException(MaterialProblem.corrupted)),
            );
          }
          final i = materials.indexWhere((m) => m.id == entry.id);
          if (i >= 0) materials[i] = next;
          _changed();
        }(),
    ]);
  }

  void remove(String id) {
    materials.removeWhere((m) => m.id == id);
    _changed();
  }

  /// Generates and saves the script (status draft), or returns null when
  /// cancelled or failed ([error] says why).
  Future<Script?> generate(GenerationOptions options, {String? collectionId}) async {
    if (!canGenerate) return null;
    final materials = ready;
    _stopped = false;
    phase = GeneratePhase.generating;
    error = null;
    preview = '';
    progress = null;
    _changed();

    final key = GenerationCache.keyFor(materials, options, model);
    var generated = cache.get(key);
    if (generated == null) {
      final client = await llm();
      if (client == null) return _fail(L10n.current.genNeedsKey);
      if (_stopped) {
        client.close();
        return null;
      }
      final generator = _generator = ScriptGenerator(client);
      try {
        generated = await generator.run(
          materials,
          options,
          onProgress: (p) {
            progress = p;
            _changed();
          },
          onPreview: (text) {
            preview = text;
            _changed();
          },
        );
      } on GenerationCancelled {
        phase = GeneratePhase.form;
        progress = null;
        _changed();
        return null;
      } on GenerationException catch (e) {
        return _fail(e.message);
      } catch (e) {
        if (generator.cancelled) {
          phase = GeneratePhase.form;
          _changed();
          return null;
        }
        // Not DeepSeek's: logged for a report, worded for the presenter.
        if (kDebugMode) debugPrint('generate: unexpected error: $e');
        return _fail(L10n.current.llmGenericError('DeepSeek'));
      } finally {
        _generator = null;
        client.close();
      }
      unawaited(cache.put(key, generated));
    }

    if (_stopped) return null;
    final now = DateTime.now();
    final script = Script(
      id: newId(),
      title: materials.first.title,
      sections: generated.sections,
      createdAt: now,
      updatedAt: now,
      collectionId: collectionId,
      status: ScriptStatus.draft,
      prepQuestions: generated.questions,
      hintWords: ScriptStructurer.hintWordsFor(generated.sections),
      targetSeconds: options.minutes * 60,
      sourceName: materials.map((m) => m.name).join(', '),
    );
    await save(script);
    return script;
  }

  Script? _fail(String message) {
    phase = GeneratePhase.failed;
    error = message;
    _changed();
    return null;
  }

  /// Stops at once; nothing is saved.
  void cancel() {
    _stopped = true;
    _generator?.cancel();
    if (phase != GeneratePhase.form) {
      phase = GeneratePhase.form;
      progress = null;
      _changed();
    }
  }

  void back() {
    phase = GeneratePhase.form;
    error = null;
    _changed();
  }

  @override
  void dispose() {
    _generator?.cancel();
    _disposed = true;
    super.dispose();
  }
}

/// A controller wired to the app's providers.
GenerateScriptController generateControllerFor(WidgetRef ref) => GenerateScriptController(
  reader: ref.read(materialReaderProvider),
  llm: ref.read(organizerLlmProvider),
  cache: ref.read(generationCacheProvider),
  save: ref.read(scriptRepositoryProvider).save,
  model: ref.read(settingsProvider).aiModel,
);

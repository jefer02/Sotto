import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:http/http.dart' as http;

import '../../core/utils/ids.dart';
import '../../core/utils/parallel.dart';
import '../../data/import/source_material.dart';
import '../../data/models/script.dart';
import '../../domain/structuring/check_markers.dart';
import '../../domain/structuring/generation_plan.dart';
import '../../domain/structuring/script_structurer.dart';
import '../../l10n/l10n.dart';
import 'llm_client.dart';

export '../../domain/structuring/generation_plan.dart' show GenerationOptions;

/// Where a generation is.
enum GenerationStage { understanding, writing, checking, questions }

class GenerationProgress {
  const GenerationProgress(this.stage, {this.done = 0, this.total = 0});

  final GenerationStage stage;

  /// Groups of slides read so far, during [GenerationStage.understanding].
  final int done;
  final int total;
}

/// A generated script, before it becomes a [Script].
class GeneratedScript {
  const GeneratedScript({
    required this.title,
    required this.sections,
    this.questions = const [],
    this.checks = 0,
    this.fromCache = false,
  });

  final String title;
  final List<Section> sections;
  final List<PrepQuestion> questions;

  /// Markers left where the material lacked something ("[CHECK: …]").
  final int checks;
  final bool fromCache;

  int get wordCount => sections.fold(0, (a, s) => a + s.wordCount);

  Map<String, Object?> toJson() => {
    'title': title,
    'sections': [for (final s in sections) s.toJson()],
    'questions': [for (final q in questions) q.toJson()],
    'checks': checks,
  };

  /// From the cache, with fresh ids (it becomes a new script).
  factory GeneratedScript.fromJson(Map<dynamic, dynamic> j) => GeneratedScript(
    title: j['title'] as String,
    sections: [
      for (final m in j['sections'] as List)
        () {
          final s = Section.fromJson(m as Map);
          return Section(
            id: newId(),
            title: s.title,
            keyPoints: s.keyPoints,
            beats: [for (final b in s.beats) Beat(id: newId(), text: b.text, cue: b.cue)],
          );
        }(),
    ],
    questions: [
      for (final q in (j['questions'] as List? ?? const []))
        () {
          final p = PrepQuestion.fromJson(q as Map);
          return PrepQuestion(id: newId(), question: p.question, answer: p.answer);
        }(),
    ],
    checks: (j['checks'] as num?)?.toInt() ?? 0,
    fromCache: true,
  );
}

/// The model's replies couldn't be made into a script, or DeepSeek failed.
class GenerationException implements Exception {
  const GenerationException(this.message, {this.cause});
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

/// Cancelled by the presenter; nothing was saved.
class GenerationCancelled implements Exception {
  const GenerationCancelled();
}

/// Generated scripts keyed by a hash of the material, the options and the
/// model, like [OrganizeCache] — the same request again opens at once.
/// Shares the organize box and its 40-entry age limit.
class GenerationCache {
  GenerationCache(this._box, {this.maxEntries = 40});

  final Box<Map> _box;
  final int maxEntries;

  /// Bump when the prompts or the parsing change what a result means.
  static const version = 1;

  static String keyFor(List<SourceMaterial> materials, GenerationOptions options, String model) => sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'v': version,
            'kind': 'generate',
            'model': model,
            'options': options.toJson(),
            'materials': [for (final m in materials) m.toJson()],
          }),
        ),
      )
      .toString();

  GeneratedScript? get(String key) {
    final raw = _box.get(key)?['generated'];
    if (raw is! Map) return null;
    try {
      return GeneratedScript.fromJson(raw);
    } catch (_) {
      return null; // an old or damaged entry: generate again
    }
  }

  Future<void> put(String key, GeneratedScript script) async {
    await _box.put(key, {'at': DateTime.now().toIso8601String(), 'generated': script.toJson()});
    if (_box.length > maxEntries) {
      final byAge = _box.keys.toList()..sort((a, b) => '${_box.get(a)?['at']}'.compareTo('${_box.get(b)?['at']}'));
      await _box.deleteAll(byAge.take(_box.length - maxEntries));
    }
  }
}

/// Writes a script from slides, pages and documents with DeepSeek, in
/// map-reduce:
///
/// 1. **map** — groups of ≤ 6 slides (≤ 1,200 words) → each slide's purpose,
///    key ideas and verbatim facts; 4 requests in flight, retried with
///    backoff on 429 / 5xx / timeouts, JSON mode, thinking off. A group
///    whose reply is unusable twice falls back to its slides' own words.
/// 2. **reduce** — one streamed request writes the whole script from the
///    digests: introduction, sections, spoken beats, slide cues and a
///    closing, within the word budget (minutes × pace, ±10 %). Thinking on
///    ([DeepSeekTaskProfile.generate]) — this is the call quality rests on.
/// 3. **check** — the reply is parsed and repaired locally ([ScriptDraft]);
///    unusable JSON is asked for once more, a length outside the budget is
///    sent back once to be resized. Long beats are then split at natural
///    pauses by the rule-based organizer ([ScriptStructurer.splitLong]).
/// 4. **questions** (optional) — likely audience questions with answers
///    grounded in the same digests.
///
/// File content is always delimited data in the prompts, never
/// instructions ([GenerationPrompt]). [cancel] closes the client, so a
/// request in flight stops at once.
///
/// Cost, for U slides of T words in all and a budget of W words: map is
/// ⌈U/6⌉ requests, ≈ ⌈U/24⌉ round trips at 4 in flight, O(T) tokens in;
/// reduce is one request of O(U) digest tokens in and O(W) out (twice at
/// most when resized); local work is O(T + W) time and memory.
class ScriptGenerator {
  ScriptGenerator(this.client, {this.concurrency = 4, this.retry = const RetryPolicy(), this.sleep, this.labels});

  final LlmClient client;
  final int concurrency;
  final RetryPolicy retry;

  /// Injectable for tests.
  final Future<void> Function(Duration)? sleep;

  /// For splitting long beats; null: [StructurerLabels.current].
  final StructurerLabels? labels;

  bool _cancelled = false;
  bool get cancelled => _cancelled;

  /// Stops now: the request in flight is dropped and [run] throws
  /// [GenerationCancelled].
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    client.close();
  }

  void _check() {
    if (_cancelled) throw const GenerationCancelled();
  }

  Future<T> _request<T>(Future<T> Function() fn) async {
    _check();
    try {
      return await withRetry(
        fn,
        retryIf: (e) => !_cancelled && e is LlmException && e.retryable,
        policy: retry,
        sleep: sleep,
      );
    } catch (e) {
      _check();
      if (e is GenerationException || e is GenerationCancelled) rethrow;
      // DeepSeek's own errors are already worded (bad key, no balance,
      // busy, timed out); a dropped connection or a garbled stream gets
      // the closest message there is.
      final l = L10n.current;
      final message = switch (e) {
        LlmException() => e.message,
        SocketException() => l.llmOffline('DeepSeek'),
        http.ClientException(:final message) => l.llmUnreachable('DeepSeek', message),
        HttpException(:final message) => l.llmUnreachable('DeepSeek', message),
        _ => l.llmGenericError('DeepSeek'),
      };
      _log('request failed: $e');
      throw GenerationException(message, cause: e);
    }
  }

  /// Debug builds only: what each stage took, for reports from real use.
  static void _log(String message) {
    if (kDebugMode) debugPrint('generate: $message');
  }

  /// Tokens the requests of the current stage used, when the client
  /// reports them (DeepSeek, with `stream_options`).
  LlmUsage _usage = const LlmUsage();

  LlmUsage _takeUsage() {
    final u = _usage;
    _usage = const LlmUsage();
    return u;
  }

  /// Slides whose map reply was unusable twice, so their own words stood in.
  var _fallbacks = 0;

  Future<GeneratedScript> run(
    List<SourceMaterial> materials,
    GenerationOptions options, {
    void Function(GenerationProgress progress)? onProgress,
    void Function(String preview)? onPreview,
  }) async {
    final refs = unitRefs(materials);
    if (refs.isEmpty) throw GenerationException(L10n.current.genFailedNoText);
    final total = Stopwatch()..start();
    final previousOnUsage = client.onUsage;
    client.onUsage = (u) => _usage += u;
    var stage = 'map';
    try {
      final script = await _run(refs, materials, options, onProgress, onPreview, (s) => stage = s);
      _log(
        'done in ${total.elapsedMilliseconds} ms: ${script.wordCount} words, ${script.sections.length} sections, '
        '${script.questions.length} questions, ${script.checks} markers',
      );
      return script;
    } on GenerationCancelled {
      _log('cancelled during $stage after ${total.elapsedMilliseconds} ms');
      rethrow;
    } catch (e) {
      _log('failed during $stage after ${total.elapsedMilliseconds} ms: $e');
      rethrow;
    } finally {
      client.onUsage = previousOnUsage;
    }
  }

  Future<GeneratedScript> _run(
    List<UnitRef> refs,
    List<SourceMaterial> materials,
    GenerationOptions options,
    void Function(GenerationProgress progress)? onProgress,
    void Function(String preview)? onPreview,
    void Function(String stage) at,
  ) async {
    final fallbackTitle = materials.first.title;
    final wordsIn = materials.fold(0, (a, m) => a + m.wordCount + (options.useNotes ? m.notesWords : 0));
    _log(
      '${materials.length} file(s), ${refs.length} slides/pages, $wordsIn words in; '
      'budget ${options.wordBudget} words (${options.minWords}-${options.maxWords})',
    );

    // 1. map
    final groups = mapGroups(refs);
    final digests = <String, SlideDigest>{};
    var done = 0;
    var watch = Stopwatch()..start();
    onProgress?.call(GenerationProgress(GenerationStage.understanding, total: groups.length));
    await forEachParallel(groups, concurrency, (group) async {
      _check();
      final groupWatch = Stopwatch()..start();
      digests.addAll(await _map(group, options));
      _log(
        'map group ${groups.indexOf(group) + 1}/${groups.length}: ${group.length} slides in '
        '${groupWatch.elapsedMilliseconds} ms',
      );
      onProgress?.call(GenerationProgress(GenerationStage.understanding, done: ++done, total: groups.length));
    });
    _check();
    _log(
      'map: ${groups.length} requests in ${watch.elapsedMilliseconds} ms, ${_takeUsage()}, '
      '$_fallbacks slides fell back to their own words',
    );
    at('write');

    // 2–3. reduce, check
    onProgress?.call(const GenerationProgress(GenerationStage.writing));
    final allowed = {for (final r in refs) ?r.cue};
    final request = GenerationPrompt.reduceUser(refs, digests, options);
    final maxTokens = (options.wordBudget * 4 + 4096).clamp(8192, 32768);
    watch = Stopwatch()..start();
    var draft = await _reduce(request, allowed, fallbackTitle, maxTokens, onPreview);
    _log(
      'write: ${draft.wordCount} words, ${draft.sections.length} sections, cues ${draft.cues} in '
      '${watch.elapsedMilliseconds} ms, ${_takeUsage()}, ${draft.repairs} local repairs',
    );
    at('check');
    onProgress?.call(const GenerationProgress(GenerationStage.checking));
    if (!options.fits(draft.wordCount)) {
      watch = Stopwatch()..start();
      final previous = jsonEncode({
        'title': draft.title,
        'sections': [
          for (final s in draft.sections)
            {
              'title': s.title,
              'beats': [
                for (final b in s.beats) {'text': b.text, if (b.cue?.label != null) 'slide': int.parse(b.cue!.label!)},
              ],
            },
        ],
      });
      try {
        final resized = await _reduce(
          GenerationPrompt.resizeUser(previous, draft.wordCount, options),
          allowed,
          fallbackTitle,
          maxTokens,
          onPreview,
        );
        _log(
          'resize: ${draft.wordCount} -> ${resized.wordCount} words in ${watch.elapsedMilliseconds} ms, ${_takeUsage()}',
        );
        // The closer of the two to the target.
        if ((resized.wordCount - options.wordBudget).abs() < (draft.wordCount - options.wordBudget).abs()) {
          draft = resized;
        }
      } on GenerationException catch (e) {
        // Keep the first draft: the right shape, just off in length.
        _log('resize failed, keeping ${draft.wordCount} words: $e');
      }
    }
    final sections = _splitLong(draft.sections);

    // 4. questions
    var questions = const <PrepQuestion>[];
    if (options.prepQuestions) {
      at('questions');
      onProgress?.call(const GenerationProgress(GenerationStage.questions));
      watch = Stopwatch()..start();
      questions = await _questions(refs, digests, options);
      _log('questions: ${questions.length} in ${watch.elapsedMilliseconds} ms, ${_takeUsage()}');
    }
    _check();
    return GeneratedScript(
      title: draft.title,
      sections: sections,
      questions: questions,
      checks: CheckMarkers.countIn(sections),
    );
  }

  Future<Map<String, SlideDigest>> _map(List<UnitRef> group, GenerationOptions options) async {
    final user = GenerationPrompt.mapUser(group, options);
    final refs = {for (final r in group) r.ref};
    final maxTokens = (group.length * 400 + 512).clamp(1024, 4096);
    for (var attempt = 0; attempt < 2; attempt++) {
      final raw = await _request(
        () => client.complete(
          system: GenerationPrompt.mapSystem,
          user: user,
          maxTokens: maxTokens,
          profile: DeepSeekTaskProfile.digest,
          json: true,
        ),
      );
      try {
        final parsed = parseDigests(raw, refs);
        return {for (final r in group) r.ref: parsed[r.ref] ?? fallbackDigest(r)};
      } on FormatException {
        continue;
      }
    }
    _fallbacks += group.length;
    return {for (final r in group) r.ref: fallbackDigest(r)};
  }

  /// One reduce request, streamed for the preview; an unusable reply is
  /// asked for once more with what was wrong.
  Future<ScriptDraft> _reduce(
    String request,
    Set<int> allowed,
    String fallbackTitle,
    int maxTokens,
    void Function(String preview)? onPreview,
  ) async {
    var user = request;
    FormatException? problem;
    for (var attempt = 0; attempt < 2; attempt++) {
      final raw = await _request(() async {
        final buf = StringBuffer();
        await for (final chunk in client.stream(
          system: GenerationPrompt.reduceSystem,
          user: user,
          maxTokens: maxTokens,
          profile: DeepSeekTaskProfile.generate,
          json: true,
        )) {
          _check();
          buf.write(chunk);
          onPreview?.call(streamPreview(buf.toString()));
        }
        return buf.toString();
      });
      try {
        return ScriptDraft.parse(raw, allowedCues: allowed, fallbackTitle: fallbackTitle);
      } on FormatException catch (e) {
        problem = e;
        user = GenerationPrompt.repairUser(request, e.message);
      }
    }
    _log('reply unusable twice: ${problem?.message}');
    throw GenerationException(L10n.current.genFailedInvalidReply, cause: problem);
  }

  Future<List<PrepQuestion>> _questions(
    List<UnitRef> refs,
    Map<String, SlideDigest> digests,
    GenerationOptions options,
  ) async {
    final user = GenerationPrompt.questionsUser(refs, digests, options);
    for (var attempt = 0; attempt < 2; attempt++) {
      final raw = await _request(
        () => client.complete(
          system: GenerationPrompt.questionsSystem,
          user: user,
          maxTokens: 4096,
          profile: DeepSeekTaskProfile.digest,
          json: true,
        ),
      );
      try {
        return parseQuestions(raw);
      } on FormatException {
        continue;
      }
    }
    return const []; // optional: the script stands without them
  }

  /// Beats over one breath split where the organizer would split them;
  /// a cue stays on the first part.
  List<Section> _splitLong(List<Section> sections) {
    final structurer = ScriptStructurer(labels: labels ?? StructurerLabels.current());
    return [
      for (final s in sections)
        s.copyWith(
          beats: [
            for (final b in s.beats)
              ...() {
                final parts = structurer.splitLong(b.text);
                return [
                  for (var i = 0; i < parts.length; i++)
                    i == 0 ? Beat(id: b.id, text: parts[i], cue: b.cue) : Beat(id: newId(), text: parts[i]),
                ];
              }(),
          ],
        ),
    ];
  }
}

import 'dart:async';

import '../../core/utils/parallel.dart';
import '../../data/models/script.dart';
import '../../domain/structuring/organize_plan.dart';
import '../../domain/structuring/script_structurer.dart';
import '../../domain/structuring/sentence_splitter.dart';
import 'llm_client.dart';

/// How one chunk went.
class ChunkOutcome {
  const ChunkOutcome(this.index, {this.sections, this.repairs = 0, this.error, this.elapsed = Duration.zero});

  final int index;

  /// Null: the chunk keeps its rule-based sections.
  final ChunkSections? sections;
  final int repairs;
  final Object? error;
  final Duration elapsed;
}

/// The AI refinement: every chunk is sent at once (at most [concurrency] in
/// flight), each reply is validated and rebuilt locally from the original
/// sentences. The system prompt is identical and first in every request so
/// DeepSeek's automatic prefix cache applies. Thinking is off
/// ([DeepSeekTaskProfile.organize]).
class ScriptOrganizer {
  ScriptOrganizer(
    this.client, {
    required this.labels,
    this.concurrency = 4,
    this.retry = const RetryPolicy(),
    this.sleep,
  });

  final LlmClient client;
  final StructurerLabels labels;
  final int concurrency;
  final RetryPolicy retry;

  /// Injectable for tests.
  final Future<void> Function(Duration)? sleep;

  bool _stopped = false;

  /// Stops sending chunks that haven't started; running ones still finish.
  void cancel() => _stopped = true;

  /// [onChunk] fires as each chunk finishes, in completion order. After a
  /// final error (bad key, no balance) the chunks not yet sent are skipped.
  Future<List<ChunkOutcome>> run(
    ParsedScript script,
    List<OrganizeChunk> chunks, {
    void Function(ChunkOutcome outcome)? onChunk,
  }) async {
    final outcomes = List<ChunkOutcome?>.filled(chunks.length, null);
    final structurer = ScriptStructurer(labels: labels);
    Object? fatal;

    await forEachParallel(chunks, concurrency, (chunk) async {
      final started = DateTime.now();
      ChunkOutcome outcome;
      if (_stopped || fatal != null) {
        outcome = ChunkOutcome(chunk.index, error: fatal ?? 'cancelled');
      } else {
        try {
          final (sections, repairs) = await _organize(script, chunk, chunks.length, structurer);
          outcome = ChunkOutcome(
            chunk.index,
            sections: sections,
            repairs: repairs,
            elapsed: DateTime.now().difference(started),
          );
        } catch (e) {
          if (e is LlmException && !e.retryable) fatal ??= e;
          outcome = ChunkOutcome(chunk.index, error: e, elapsed: DateTime.now().difference(started));
        }
      }
      outcomes[chunk.index] = outcome;
      onChunk?.call(outcome);
    });
    return [for (final o in outcomes) o!];
  }

  /// One chunk: request (retrying 429 / 5xx / timeouts with backoff), parse,
  /// validate and repair. An unusable reply is asked for once more; after
  /// that the chunk keeps its rule-based result.
  Future<(ChunkSections?, int)> _organize(
    ParsedScript script,
    OrganizeChunk chunk,
    int count,
    ScriptStructurer structurer,
  ) async {
    final user = OrganizePrompt.user(script, chunk, count);
    // IDs plus a little structure: ~1 output token per 2 input words.
    final maxTokens =
        (script.sentences.sublist(chunk.first - 1, chunk.last).fold<int>(0, (a, s) => a + s.words) ~/ 2 + 1024).clamp(
          2048,
          8192,
        );
    for (var attempt = 0; attempt < 2; attempt++) {
      final raw = await withRetry(
        () => client.complete(
          system: OrganizePrompt.system,
          user: user,
          maxTokens: maxTokens,
          profile: DeepSeekTaskProfile.organize,
          json: true,
        ),
        retryIf: (e) => e is LlmException && e.retryable,
        policy: retry,
        sleep: sleep,
      );
      final OrganizePlan plan;
      try {
        plan = OrganizePlan.parse(raw);
      } on FormatException {
        continue;
      }
      final check = PlanValidator.check(plan, chunk.first, chunk.last);
      if (!check.ok) continue;
      return (
        PlanRebuilder.rebuild(script, check.plan!, structurer: structurer, labels: labels, first: chunk.isFirst),
        check.repairs,
      );
    }
    return (null, 0);
  }

  /// All chunks merged — the full AI result, for the cache. Null when any
  /// chunk fell back to rule-based.
  static List<Section>? mergedResult(List<ChunkOutcome> outcomes) {
    if (outcomes.any((o) => o.sections == null)) return null;
    return PlanRebuilder.merge([for (final o in outcomes) o.sections!]);
  }
}

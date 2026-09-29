import 'dart:convert';

import '../../core/utils/ids.dart';
import '../../data/models/script.dart';
import 'script_structurer.dart';
import 'sentence_splitter.dart';

// The AI organizer never writes script text. It gets numbered sentences and
// returns boundaries as sentence IDs:
//
//   {"sections":[{"title":"…","beats":[[1,2],[3],[4,5,6]],
//                 "cues":[{"after":6,"type":"slide","label":"3"}]}]}
//
// Everything here is local and deterministic: chunking the script, the
// prompt, validating and repairing the reply, and rebuilding sections from
// the original sentences — so the wording is guaranteed unchanged.

// ─────────────────────────────── Chunks ───────────────────────────────

/// A contiguous run of sentences sent in one request.
class OrganizeChunk {
  const OrganizeChunk({required this.index, required this.first, required this.last, this.context = ''});

  final int index;

  /// Sentence ids, inclusive.
  final int first;
  final int last;

  /// The end of the previous chunk, for context only (it carries no IDs).
  final String context;

  bool get isFirst => index == 0;
}

abstract final class ScriptChunker {
  /// Splits at author headings once a chunk has [minWords], and at the
  /// first paragraph boundary after [targetWords]; a paragraph longer than
  /// 1.5 × [targetWords] is cut between sentences. Each chunk after the
  /// first carries the previous paragraph (≤ [contextWords]) as context.
  static List<OrganizeChunk> chunk(
    ParsedScript script, {
    int targetWords = 1500,
    int minWords = 600,
    int contextWords = 150,
  }) {
    if (script.length == 0) return const [];
    final chunks = <OrganizeChunk>[];
    var start = 1;
    var words = 0;

    void close(int last) {
      chunks.add(
        OrganizeChunk(
          index: chunks.length,
          first: start,
          last: last,
          context: start == 1 ? '' : _context(script, start, contextWords),
        ),
      );
    }

    for (final s in script.sentences) {
      if (s.id > start) {
        final para = script.paragraphs[s.paragraph];
        final paraStart = para.first == s.id;
        final cut = paraStart
            ? words >= targetWords || (para.heading != null && words >= minWords)
            : words >= targetWords * 1.5;
        if (cut) {
          close(s.id - 1);
          start = s.id;
          words = 0;
        }
      }
      words += s.words;
    }
    close(script.length);
    return chunks;
  }

  /// The paragraph before sentence [start] (or its part before [start]),
  /// trimmed to its last [maxWords] words.
  static String _context(ParsedScript script, int start, int maxWords) {
    final prev = script.sentence(start - 1);
    final para = script.paragraphs[prev.paragraph];
    final words = [for (var id = para.first; id < start && id <= para.last; id++) script.sentence(id).text]
        .join(' ')
        .split(' ');
    return words.length <= maxWords ? words.join(' ') : '… ${words.sublist(words.length - maxWords).join(' ')}';
  }

  /// The chunk as plain Markdown — the rule-based first pass reads this.
  static String sourceText(ParsedScript script, OrganizeChunk chunk) {
    final out = StringBuffer();
    int? paragraph;
    for (var id = chunk.first; id <= chunk.last; id++) {
      final s = script.sentence(id);
      if (s.paragraph != paragraph) {
        if (paragraph != null) out.write('\n\n');
        paragraph = s.paragraph;
        final para = script.paragraphs[s.paragraph];
        if (para.first == id && para.heading != null) {
          out.write('## ${para.heading}\n');
          for (final k in para.keyPoints) {
            out.write('- $k\n');
          }
          out.write('\n');
        }
      } else {
        out.write(' ');
      }
      out.write(s.text);
    }
    return out.toString();
  }
}

// ─────────────────────────────── Prompt ───────────────────────────────

abstract final class OrganizePrompt {
  /// Identical for every chunk and first in the request, so DeepSeek's
  /// automatic prefix cache serves it after the first call.
  static const system = '''
You organize a presenter's script for a teleprompter. The script is split into numbered sentences like [12]. You never write, change or repeat script text: you only group sentence IDs.

Return only JSON, exactly this shape:
{"sections":[{"title":"Short title","keyPoints":["short phrase"],"beats":[[1,2],[3],[4,5,6]],"cues":[{"after":6,"type":"slide","label":"3"}]}]}

Rules:
- Use every sentence ID of the script part exactly once, in ascending order. The context has no IDs: never use it.
- A beat is one breath, about 8–25 words: group short consecutive sentences; a long sentence is a beat on its own.
- A section is one topic, usually 120–400 words. An author heading (## …) always starts a new section and is its title.
- Titles have 2–6 words, in the script's language. If the part begins by continuing the context's topic without a heading, set "title": null on its first section.
- keyPoints: 0–3 phrases of at most 8 words that summarize the section, in the script's language.
- cues: only where the script clearly implies one. type is "slide" (label: the slide number if known), "pause", "demo" or "note" (label: a 1–4 word note). "after" is the ID of the sentence the cue follows. Directions already in brackets such as [SLIDE 3] stay in the text; do not repeat them as cues.
- JSON only: no prose, no markdown, no code fences.''';

  static String user(ParsedScript script, OrganizeChunk chunk, int chunkCount) {
    final out = StringBuffer()
      ..writeln('Part ${chunk.index + 1} of $chunkCount. Sentence IDs ${chunk.first}–${chunk.last}.');
    if (chunk.context.isNotEmpty) {
      out
        ..writeln()
        ..writeln('Context — the end of the previous part (no IDs, do not organize):')
        ..writeln('"""')
        ..writeln(chunk.context)
        ..writeln('"""');
    }
    out
      ..writeln()
      ..writeln('Script part:');
    int? paragraph;
    for (var id = chunk.first; id <= chunk.last; id++) {
      final s = script.sentence(id);
      if (s.paragraph != paragraph) {
        final para = script.paragraphs[s.paragraph];
        if (paragraph != null) out.writeln();
        paragraph = s.paragraph;
        if (para.first == id && para.heading != null) out.writeln('## ${para.heading}');
      }
      out.writeln('[$id] ${s.text}');
    }
    return out.toString();
  }
}

// ─────────────────────────────── Plan ───────────────────────────────

class PlanCue {
  const PlanCue({required this.after, required this.type, this.label});

  final int after;
  final CueType type;
  final String? label;
}

class PlanSection {
  const PlanSection({this.title, this.keyPoints = const [], required this.beats, this.cues = const []});

  /// Null: continues the previous part's last section.
  final String? title;
  final List<String> keyPoints;
  final List<List<int>> beats;
  final List<PlanCue> cues;

  PlanSection withBeats(List<List<int>> beats) =>
      PlanSection(title: title, keyPoints: keyPoints, beats: beats, cues: cues);
}

class OrganizePlan {
  const OrganizePlan(this.sections);

  final List<PlanSection> sections;

  Iterable<int> get ids => sections.expand((s) => s.beats.expand((b) => b));

  /// Tolerant: code fences and prose around the object are ignored, IDs
  /// may arrive as numbers or numeric strings, a bare ID counts as a
  /// one-sentence beat. Throws [FormatException] when there is no plan.
  static OrganizePlan parse(String raw) {
    final from = raw.indexOf('{');
    final to = raw.lastIndexOf('}');
    if (from < 0 || to <= from) throw const FormatException('No JSON object');
    final j = jsonDecode(raw.substring(from, to + 1));
    if (j is! Map || j['sections'] is! List) throw const FormatException('No "sections" list');

    int? id(Object? v) => switch (v) {
      final int i => i,
      final double d when d == d.roundToDouble() => d.toInt(),
      final String s => int.tryParse(s.trim().replaceAll(RegExp(r'[\[\]]'), '')),
      _ => null,
    };

    final sections = <PlanSection>[];
    for (final s in (j['sections'] as List).whereType<Map<Object?, Object?>>()) {
      final beats = <List<int>>[];
      for (final b in (s['beats'] as List?) ?? const []) {
        final group = b is List ? [for (final v in b) ?id(v)] : [?id(b)];
        if (group.isNotEmpty) beats.add(group);
      }
      final title = s['title'];
      sections.add(
        PlanSection(
          title: title is String && title.trim().isNotEmpty && title.trim().toLowerCase() != 'null'
              ? title.trim()
              : null,
          keyPoints: [
            for (final k in (s['keyPoints'] as List?) ?? const [])
              if (k is String && k.trim().isNotEmpty) k.trim(),
          ].take(3).toList(),
          beats: beats,
          cues: [
            for (final c in ((s['cues'] as List?) ?? const []).whereType<Map<Object?, Object?>>())
              if (id(c['after']) != null)
                PlanCue(
                  after: id(c['after'])!,
                  type: switch ('${c['type']}'.toLowerCase()) {
                    'slide' => CueType.slide,
                    'pause' => CueType.pause,
                    'demo' => CueType.demo,
                    _ => CueType.note,
                  },
                  label: switch (c['label']) {
                    final String l when l.trim().isNotEmpty => l.trim(),
                    final num n => '${n.toInt()}',
                    _ => null,
                  },
                ),
          ],
        ),
      );
    }
    return OrganizePlan(sections);
  }
}

/// What validation found. [plan] is null when the reply can't be trusted
/// and the chunk keeps its rule-based result.
class PlanCheck {
  const PlanCheck({this.plan, this.repairs = 0, this.problem});

  final OrganizePlan? plan;

  /// IDs dropped (duplicate, out of range) or re-inserted (missing).
  final int repairs;
  final String? problem;

  bool get ok => plan != null;
}

abstract final class PlanValidator {
  /// Every ID in [first]..[last] must be used exactly once, in order.
  /// Repairs locally: drops duplicates and out-of-range IDs, and merges
  /// missing IDs into the beat of the sentence before them. IDs out of
  /// order, or more than [maxMissingShare] of them missing, make the plan
  /// unusable.
  static PlanCheck check(OrganizePlan plan, int first, int last, {double maxMissingShare = 0.34}) {
    final seen = <int>{};
    var repairs = 0;
    var previous = first - 1;
    final sections = <PlanSection>[];
    for (final s in plan.sections) {
      final beats = <List<int>>[];
      for (final b in s.beats) {
        final kept = <int>[];
        for (final id in b) {
          if (id < first || id > last || seen.contains(id)) {
            repairs++;
            continue;
          }
          if (id < previous) return PlanCheck(problem: 'IDs out of order at $id');
          seen.add(id);
          previous = id;
          kept.add(id);
        }
        if (kept.isNotEmpty) beats.add(kept);
      }
      if (beats.isNotEmpty) sections.add(s.withBeats(beats));
    }
    final total = last - first + 1;
    final missing = [
      for (var id = first; id <= last; id++)
        if (!seen.contains(id)) id,
    ];
    if (sections.isEmpty || missing.length > total * maxMissingShare) {
      return PlanCheck(problem: '${missing.length} of $total IDs missing');
    }

    // Orphans join the beat of the nearest earlier sentence (or, before
    // the first used ID, the very first beat).
    for (final id in missing) {
      var placed = false;
      for (var si = sections.length - 1; si >= 0 && !placed; si--) {
        final beats = sections[si].beats;
        for (var bi = beats.length - 1; bi >= 0 && !placed; bi--) {
          final at = beats[bi].lastIndexWhere((x) => x < id);
          if (at >= 0) {
            beats[bi].insert(at + 1, id);
            placed = true;
          }
        }
      }
      if (!placed) sections.first.beats.first.insert(0, id);
      repairs++;
    }
    return PlanCheck(plan: OrganizePlan(sections), repairs: repairs);
  }
}

// ─────────────────────────────── Rebuild ───────────────────────────────

/// One chunk's sections. [continues]: its first section carries on the
/// previous chunk's last section (the model gave it no title).
class ChunkSections {
  const ChunkSections(this.sections, {this.continues = false});

  final List<Section> sections;
  final bool continues;
}

abstract final class PlanRebuilder {
  /// Sections from the original sentences, grouped as [plan] says. Inline
  /// cues in the text become chips as usual; the model's cues attach to
  /// the beat after the sentence they follow. Beats longer than one breath
  /// are split at a pause.
  static ChunkSections rebuild(
    ParsedScript script,
    OrganizePlan plan, {
    required ScriptStructurer structurer,
    required StructurerLabels labels,
    bool first = true,
    int slideStart = 0,
  }) {
    var slide = slideStart;
    Cue? pending;
    final sections = <Section>[];
    var continues = false;

    for (var si = 0; si < plan.sections.length; si++) {
      final ps = plan.sections[si];
      final cues = {for (final c in ps.cues) c.after: c};
      final beats = <Beat>[];
      for (final group in ps.beats) {
        final text = group.map((id) => script.sentence(id).text).join(' ');
        final (built, next) = structurer.beatsFor(text, slide, whole: true);
        slide = next;
        if (pending != null && built.isNotEmpty) {
          if (built.first.cue == null) built[0] = built.first.copyWith(cue: pending);
          pending = null;
        }
        beats.addAll(built);
        for (final id in group) {
          final c = cues[id];
          if (c == null) continue;
          if (c.type == CueType.slide) {
            final n = int.tryParse(c.label ?? '');
            slide = n ?? slide + 1;
            pending = Cue(CueType.slide, n == null && c.label != null ? c.label : '$slide');
          } else {
            pending = Cue(c.type, c.label);
          }
        }
      }
      if (beats.isEmpty) continue;

      // The author's own bullets beat the model's summary.
      final authored = <String>[];
      for (final group in ps.beats) {
        for (final id in group) {
          final para = script.paragraphs[script.sentence(id).paragraph];
          if (para.first == id) authored.addAll(para.keyPoints);
        }
      }

      String title;
      if (ps.title != null) {
        title = ps.title!;
      } else if (sections.isEmpty && first) {
        title = labels.opening;
      } else {
        title = ScriptStructurer.titleFrom(beats.first.text, labels.fallback);
        if (sections.isEmpty) continues = true;
      }
      sections.add(
        Section(id: newId(), title: title, beats: beats, keyPoints: authored.isNotEmpty ? authored : ps.keyPoints),
      );
    }
    if (pending != null && sections.isNotEmpty) {
      final last = sections.removeLast();
      sections.add(
        last.copyWith(
          beats: [
            ...last.beats,
            Beat.create('', cue: pending),
          ],
        ),
      );
    }
    return ChunkSections(sections, continues: continues);
  }

  /// Joins chunks in order; a chunk that [ChunkSections.continues] merges
  /// its first section into the previous chunk's last one.
  static List<Section> merge(List<ChunkSections> parts) {
    final out = <Section>[];
    for (final part in parts) {
      var sections = part.sections;
      if (part.continues && out.isNotEmpty && sections.isNotEmpty) {
        out.add(joinSections(out.removeLast(), sections.first));
        sections = sections.sublist(1);
      }
      out.addAll(sections);
    }
    return out;
  }

  static Section joinSections(Section a, Section b) =>
      a.copyWith(beats: [...a.beats, ...b.beats], keyPoints: {...a.keyPoints, ...b.keyPoints}.take(3).toList());
}

// ─────────────────────────── Progressive merge ───────────────────────────

enum PatchResult {
  /// The refined sections replaced the region.
  applied,

  /// The presenter changed the region (or is typing in it): left alone.
  kept,

  /// Nothing to do.
  unchanged,
}

/// Applies refined chunks, as they arrive, to a script the presenter may
/// be editing. Each chunk owns a "region" — the sections Sotto last wrote
/// for it. A region is replaced only while it still matches what Sotto
/// wrote and the caret isn't in it; otherwise the presenter's edits win.
class RegionMerger {
  RegionMerger(List<List<Section>> regions)
    : _regions = [
        for (final r in regions) _Region([for (final s in r) s.id], _snapshot(r)),
      ];

  final List<_Region> _regions;

  int get length => _regions.length;

  int get keptCount => _regions.where((r) => r.kept).length;

  static String _snapshot(List<Section> sections) => jsonEncode([for (final s in sections) s.toJson()]);

  /// Index of region [k]'s sections in [sections], or null when the
  /// region is no longer there exactly as Sotto wrote it.
  int? _locate(List<Section> sections, int k, String? focusedBeat) {
    final r = _regions[k];
    if (r.ids.isEmpty) return null;
    final start = sections.indexWhere((s) => s.id == r.ids.first);
    if (start < 0 || start + r.ids.length > sections.length) return null;
    final current = sections.sublist(start, start + r.ids.length);
    for (var i = 0; i < r.ids.length; i++) {
      if (current[i].id != r.ids[i]) return null;
    }
    if (_snapshot(current) != r.snapshot) return null;
    if (focusedBeat != null && current.any((s) => s.beats.any((b) => b.id == focusedBeat))) return null;
    return start;
  }

  (Script, PatchResult) apply(Script script, int k, ChunkSections refined, {String? focusedBeat}) {
    final r = _regions[k];
    if (refined.sections.isEmpty) return (script, PatchResult.unchanged);
    final at = _locate(script.sections, k, focusedBeat);
    if (at == null) {
      r.kept = true;
      return (script, PatchResult.kept);
    }
    final sections = [...script.sections]..replaceRange(at, at + r.ids.length, refined.sections);
    r
      ..ids = [for (final s in refined.sections) s.id]
      ..snapshot = _snapshot(refined.sections)
      ..continues = refined.continues;
    return (script.copyWith(sections: sections), PatchResult.applied);
  }

  /// After the last chunk: a refined chunk that continues the previous one
  /// merges its first section into the previous region's last section —
  /// when both are still exactly as Sotto wrote them.
  Script fixSeams(Script script, {String? focusedBeat}) {
    var sections = script.sections;
    for (var k = _regions.length - 1; k > 0; k--) {
      if (!_regions[k].continues) continue;
      final at = _locate(sections, k, focusedBeat);
      final prev = _locate(sections, k - 1, focusedBeat);
      if (at == null || prev == null || at != prev + _regions[k - 1].ids.length) continue;
      final joined = PlanRebuilder.joinSections(sections[at - 1], sections[at]);
      sections = [...sections]
        ..removeAt(at)
        ..[at - 1] = joined;
      final r = _regions[k - 1];
      r.ids = [...r.ids.sublist(0, r.ids.length - 1), joined.id];
      r.snapshot = _snapshot(sections.sublist(prev, prev + r.ids.length));
      _regions[k].ids = _regions[k].ids.sublist(1);
      _regions[k].snapshot = _snapshot(sections.sublist(at, at + _regions[k].ids.length));
      _regions[k].continues = false;
    }
    return identical(sections, script.sections) ? script : script.copyWith(sections: sections);
  }
}

class _Region {
  _Region(this.ids, this.snapshot);

  List<String> ids;
  String snapshot;
  bool continues = false;
  bool kept = false;
}

// ─────────────────────────────── Prep ───────────────────────────────

/// Everything the import needs before any network call: numbered
/// sentences, chunks, and each chunk's rule-based sections (the instant
/// first pass the presenter can read and edit right away). Pure, so it
/// runs on a background isolate (`Isolate.run`).
class OrganizePrep {
  const OrganizePrep({required this.parsed, required this.chunks, required this.regions});

  final ParsedScript parsed;
  final List<OrganizeChunk> chunks;

  /// Rule-based sections per chunk.
  final List<List<Section>> regions;

  List<Section> get sections => [for (final r in regions) ...r];

  static OrganizePrep build(String text, StructurerLabels labels, {int targetWords = 1500}) {
    final parsed = ParsedScript.parse(text);
    final chunks = ScriptChunker.chunk(parsed, targetWords: targetWords);
    final structurer = ScriptStructurer(labels: labels);
    final regions = chunks.isEmpty
        ? [structurer.structure(text)]
        : [for (final c in chunks) structurer.structure(ScriptChunker.sourceText(parsed, c), first: c.isFirst)];
    return OrganizePrep(parsed: parsed, chunks: chunks, regions: regions);
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/core/utils/parallel.dart';
import 'package:sotto/data/models/script.dart';
import 'package:sotto/domain/structuring/organize_plan.dart';
import 'package:sotto/domain/structuring/script_structurer.dart';
import 'package:sotto/domain/structuring/sentence_splitter.dart';
import 'package:sotto/l10n/l10n.dart';
import 'package:sotto/services/ai/llm_client.dart';
import 'package:sotto/services/ai/script_organizer.dart';

const _labels = StructurerLabels(opening: 'Opening', fallback: 'Section');
const _structurer = ScriptStructurer(labels: _labels);

/// Answers organize prompts like DeepSeek would: every ID of the part, two
/// sentences per beat, a new section every 12 sentences.
class FakeOrganizerLlm extends LlmClient {
  FakeOrganizerLlm({this.latency = Duration.zero, this.failFirst = 0, this.reply});

  final Duration latency;

  /// This many calls throw a retryable 429 first.
  int failFirst;

  /// Overrides the reply (e.g. broken JSON).
  final String Function(String user)? reply;

  int calls = 0;
  int inFlight = 0;
  int maxInFlight = 0;
  final systems = <String>{};
  final profiles = <DeepSeekTaskProfile>[];
  final jsonFlags = <bool>[];

  static String planFor(String user) {
    final ids = [for (final m in RegExp(r'^\[(\d+)\] ', multiLine: true).allMatches(user)) int.parse(m.group(1)!)];
    final sections = <Map<String, Object?>>[];
    for (var i = 0; i < ids.length; i += 12) {
      final part = ids.sublist(i, (i + 12).clamp(0, ids.length));
      sections.add({
        'title': i == 0 && user.contains('Context —') ? null : 'Topic ${ids[i]}',
        'keyPoints': ['point'],
        'beats': [for (var j = 0; j < part.length; j += 2) part.sublist(j, (j + 2).clamp(0, part.length))],
        'cues': [
          {'after': part.first, 'type': 'pause'},
        ],
      });
    }
    return jsonEncode({'sections': sections});
  }

  @override
  Stream<String> stream({
    required String system,
    required String user,
    int maxTokens = 4096,
    DeepSeekTaskProfile profile = DeepSeekTaskProfile.answers,
    List<String> images = const [],
    bool json = false,
  }) async* {
    calls++;
    systems.add(system);
    profiles.add(profile);
    jsonFlags.add(json);
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      if (latency > Duration.zero) await Future<void>.delayed(latency);
      if (failFirst > 0) {
        failFirst--;
        throw LlmException('rate limited', statusCode: 429, retryable: true);
      }
      yield (reply ?? planFor)(user);
    } finally {
      inFlight--;
    }
  }

  @override
  void close() {}
}

String _longScript(int words, {int headingEvery = 900}) {
  const vocab = [
    'revenue',
    'grew',
    'across',
    'every',
    'region',
    'while',
    'margins',
    'held',
    'steady',
    'and',
    'our',
    'team',
    'shipped',
    'faster',
    'than',
    'planned',
    'customers',
    'noticed',
    'the',
    'difference',
    'in',
    'support',
    'quality',
  ];
  final out = StringBuffer('# Quarterly review\n\n');
  var n = 0;
  var section = 1;
  var sinceHeading = 0;
  var sentence = 0;
  while (n < words) {
    if (sinceHeading >= headingEvery) {
      section++;
      out.write('\n\n## Part $section\n\n');
      sinceHeading = 0;
    }
    final len = 8 + (sentence * 7) % 14;
    final w = [for (var i = 0; i < len; i++) vocab[(sentence * 3 + i) % vocab.length]];
    w[0] = '${w[0][0].toUpperCase()}${w[0].substring(1)}';
    out.write('${w.join(' ')}${sentence % 9 == 4 ? ' by 48,2 %' : ''}. ');
    if (sentence % 6 == 5) out.write('\n\n');
    n += len;
    sinceHeading += len;
    sentence++;
  }
  return out.toString();
}

void main() {
  setUpAll(() => L10n.current = lookupAppLocalizations(const Locale('en')));

  group('SentenceSplitter', () {
    test('English: abbreviations, initials, decimals, ellipses', () {
      expect(SentenceSplitter.split('Dr. Smith arrived at 9 a.m. today. He sat down.'), [
        'Dr. Smith arrived at 9 a.m. today.',
        'He sat down.',
      ]);
      expect(SentenceSplitter.split('J. K. Rowling wrote it. Then e.g. Tolkien did too.'), [
        'J. K. Rowling wrote it.',
        'Then e.g. Tolkien did too.',
      ]);
      expect(SentenceSplitter.split('Revenue grew 3.5 percent. Margin hit 48,2 %. Next year is 2027.'), [
        'Revenue grew 3.5 percent.',
        'Margin hit 48,2 %.',
        'Next year is 2027.',
      ]);
      expect(SentenceSplitter.split('Well... maybe not. "Really?" she asked. OK!'), [
        'Well... maybe not.',
        '"Really?" she asked.',
        'OK!',
      ]);
    });

    test('Spanish: abbreviations, opening marks, decimal commas', () {
      expect(SentenceSplitter.split('La Sra. García llegó tarde. ¿Qué pasó? ¡Nada! Creció un 48,2 % este año.'), [
        'La Sra. García llegó tarde.',
        '¿Qué pasó?',
        '¡Nada!',
        'Creció un 48,2 % este año.',
      ]);
      expect(SentenceSplitter.split('Vendimos en EE. UU. y en México. Ver pág. 12 del informe.'), [
        'Vendimos en EE. UU. y en México.',
        'Ver pág. 12 del informe.',
      ]);
    });

    test('never changes a character', () {
      const text = 'First one. [SLIDE 3] Second (with a note). Third… Fourth!';
      expect(SentenceSplitter.split(text).join(' '), text);
    });
  });

  test('ParsedScript: headings, author bullets as key points, bullets elsewhere as sentences', () {
    final p = ParsedScript.parse(
      '# Intro\n- Why now\n- What changed\n\nHello there. Welcome all.\n\n- A list item\nAfter.',
    );
    expect(p.sentences.map((s) => s.text), ['Hello there.', 'Welcome all.', 'A list item', 'After.']);
    expect(p.paragraphs.first.heading, 'Intro');
    expect(p.paragraphs.first.keyPoints, ['Why now', 'What changed']);
    expect(p.paragraphs.length, 3);
  });

  group('OrganizePlan', () {
    test('parses tolerant JSON: fences, strings, bare IDs', () {
      final plan = OrganizePlan.parse(
        '```json\n{"sections":[{"title":"A","beats":[["1",2],3],"cues":[{"after":"2","type":"slide","label":4}]}]}\n```',
      );
      expect(plan.sections.single.beats, [
        [1, 2],
        [3],
      ]);
      expect(plan.sections.single.cues.single.label, '4');
      expect(() => OrganizePlan.parse('no json here'), throwsFormatException);
    });

    test('valid plan passes untouched', () {
      final check = PlanValidator.check(OrganizePlan.parse('{"sections":[{"title":"A","beats":[[1,2],[3]]}]}'), 1, 3);
      expect(check.ok, isTrue);
      expect(check.repairs, 0);
    });

    test('repairs duplicates, out-of-range and orphans into the nearest beat', () {
      final check = PlanValidator.check(
        OrganizePlan.parse('{"sections":[{"title":"A","beats":[[10,11],[11,13],[99]]},{"title":"B","beats":[[15]]}]}'),
        10,
        15,
      );
      expect(check.ok, isTrue);
      expect(check.plan!.ids.toList(), [10, 11, 12, 13, 14, 15]);
      // 12 joins the beat of 11 (the sentence before it), 14 the beat of 13.
      expect(check.plan!.sections.first.beats, [
        [10, 11, 12],
        [13, 14],
      ]);
      expect(check.repairs, 4); // duplicate 11, 99, missing 12 and 14
    });

    test('an orphan before the first ID joins the first beat', () {
      final check = PlanValidator.check(OrganizePlan.parse('{"sections":[{"title":"A","beats":[[2],[3]]}]}'), 1, 3);
      expect(check.plan!.sections.first.beats.first, [1, 2]);
    });

    test('out of order or mostly missing is unusable', () {
      expect(PlanValidator.check(OrganizePlan.parse('{"sections":[{"beats":[[2],[1],[3]]}]}'), 1, 3).ok, isFalse);
      expect(PlanValidator.check(OrganizePlan.parse('{"sections":[{"beats":[[1]]}]}'), 1, 10).ok, isFalse);
    });
  });

  group('PlanRebuilder', () {
    final parsed = ParsedScript.parse(
      'We start here today. It is short. [SLIDE 7] The chart shows growth. Then we pause for questions.',
    );

    test('rebuilds from the original sentences, cues included', () {
      final plan = OrganizePlan.parse(
        '{"sections":[{"title":"Start","beats":[[1,2],[3]]},{"title":"Close","beats":[[4]],"cues":[]}],'
        '"x":1}',
      );
      final withCue = OrganizePlan([
        plan.sections.first,
        PlanSection(title: 'Close', beats: plan.sections.last.beats, cues: const []),
      ]);
      final built = PlanRebuilder.rebuild(parsed, withCue, structurer: _structurer, labels: _labels);
      final beats = built.sections.expand((s) => s.beats).toList();
      expect(beats.map((b) => b.text), [
        'We start here today. It is short.',
        'The chart shows growth.',
        'Then we pause for questions.',
      ]);
      // The inline [SLIDE 7] becomes the chip on the beat after it.
      expect(beats[1].cue, const Cue(CueType.slide, '7'));
      expect(built.continues, isFalse);
    });

    test('model cues attach to the next beat; a null title on a later part continues', () {
      final plan = OrganizePlan([
        const PlanSection(
          beats: [
            [1],
            [2],
            [3, 4],
          ],
          cues: [PlanCue(after: 1, type: CueType.pause)],
        ),
      ]);
      final built = PlanRebuilder.rebuild(parsed, plan, structurer: _structurer, labels: _labels, first: false);
      expect(built.continues, isTrue);
      expect(built.sections.single.beats[1].cue, const Cue(CueType.pause));
    });

    test('merge joins a continuing part into the previous section', () {
      final a = ChunkSections([
        Section.create('A', beats: [Beat.create('one')]),
      ]);
      final b = ChunkSections([
        Section.create('x', beats: [Beat.create('two')]),
        Section.create('B', beats: [Beat.create('three')]),
      ], continues: true);
      final merged = PlanRebuilder.merge([a, b]);
      expect(merged.map((s) => s.title), ['A', 'B']);
      expect(merged.first.beats.map((b) => b.text), ['one', 'two']);
    });
  });

  test('ScriptChunker covers every sentence once, cuts at headings, carries context', () {
    final parsed = ParsedScript.parse(_longScript(6000, headingEvery: 700));
    final chunks = ScriptChunker.chunk(parsed, targetWords: 1500);
    expect(chunks.length, greaterThan(3));
    expect(chunks.first.first, 1);
    expect(chunks.last.last, parsed.length);
    for (var i = 1; i < chunks.length; i++) {
      expect(chunks[i].first, chunks[i - 1].last + 1);
      expect(chunks[i].context, isNotEmpty);
    }
    expect(chunks.first.context, isEmpty);
    // Cuts after the minimum land on author headings when one is near.
    final atHeading = chunks
        .skip(1)
        .where((c) => parsed.paragraphs[parsed.sentence(c.first).paragraph].heading != null);
    expect(atHeading, isNotEmpty);
  });

  group('RegionMerger', () {
    Script scriptOf(List<Section> sections) {
      final now = DateTime(2026);
      return Script(id: 's', title: 't', sections: sections, createdAt: now, updatedAt: now);
    }

    List<Section> region(String title) => [
      Section.create(title, beats: [Beat.create('$title one'), Beat.create('$title two')]),
    ];

    test('replaces untouched regions, keeps edited ones and the one with the caret', () {
      final r0 = region('A'), r1 = region('B'), r2 = region('C');
      final merger = RegionMerger([r0, r1, r2]);
      var script = scriptOf([...r0, ...r1, ...r2]);

      // The presenter edits part B.
      final edited = r1.first.copyWith(
        beats: [
          r1.first.beats.first.copyWith(text: 'mine'),
          r1.first.beats.last,
        ],
      );
      script = script.copyWith(sections: [...r0, edited, ...r2]);

      final refined = ChunkSections([
        Section.create('New', beats: [Beat.create('x')]),
      ]);
      final (s0, a) = merger.apply(script, 0, refined);
      expect(a, PatchResult.applied);
      final (s1, b) = merger.apply(s0, 1, refined);
      expect(b, PatchResult.kept);
      expect(identical(s1, s0), isTrue);
      final (s2, c) = merger.apply(s1, 2, refined, focusedBeat: r2.first.beats.first.id);
      expect(c, PatchResult.kept);
      expect(s2.sections.map((s) => s.title), ['New', 'B', 'C']);
      expect(s2.sections[1].beats.first.text, 'mine');
      expect(merger.keptCount, 2);
    });

    test('fixSeams merges a continuing part into the untouched section before it', () {
      final r0 = region('A'), r1 = region('B');
      final merger = RegionMerger([r0, r1]);
      var script = scriptOf([...r0, ...r1]);
      (script, _) = merger.apply(
        script,
        0,
        ChunkSections([
          Section.create('A2', beats: [Beat.create('a')]),
        ]),
      );
      (script, _) = merger.apply(
        script,
        1,
        ChunkSections([
          Section.create('cont', beats: [Beat.create('b')]),
          Section.create('B2', beats: [Beat.create('c')]),
        ], continues: true),
      );
      script = merger.fixSeams(script);
      expect(script.sections.map((s) => s.title), ['A2', 'B2']);
      expect(script.sections.first.beats.map((b) => b.text), ['a', 'b']);
    });
  });

  group('ScriptOrganizer', () {
    test('sends chunks in parallel (max 4) with one cacheable system prompt, JSON and no thinking', () async {
      final prep = OrganizePrep.build(_longScript(9000), _labels);
      final llm = FakeOrganizerLlm(latency: const Duration(milliseconds: 20));
      final outcomes = await ScriptOrganizer(llm, labels: _labels).run(prep.parsed, prep.chunks);
      expect(outcomes.every((o) => o.sections != null), isTrue);
      expect(llm.maxInFlight, 4);
      expect(llm.systems, {OrganizePrompt.system});
      expect(llm.profiles.every((p) => p == DeepSeekTaskProfile.organize && !p.thinking), isTrue);
      expect(llm.jsonFlags.every((j) => j), isTrue);
      expect(DeepSeekTaskProfile.organize.requestFields, {
        'thinking': {'type': 'disabled'},
      });

      // The wording is exactly the source's.
      final merged = ScriptOrganizer.mergedResult(outcomes)!;
      final rebuilt = merged.expand((s) => s.beats).map((b) => b.text).where((t) => t.isNotEmpty).join(' ');
      expect(rebuilt, prep.parsed.sentences.map((s) => s.text).join(' '));
    });

    test('retries 429 with backoff, then succeeds', () async {
      final prep = OrganizePrep.build(_longScript(800), _labels);
      final llm = FakeOrganizerLlm(failFirst: 2);
      final delays = <Duration>[];
      final outcomes = await ScriptOrganizer(
        llm,
        labels: _labels,
        sleep: (d) async => delays.add(d),
      ).run(prep.parsed, prep.chunks);
      expect(outcomes.single.sections, isNotNull);
      expect(delays.length, 2);
      expect(delays[1], greaterThan(delays[0]));
    });

    test('an unusable reply keeps the rule-based result for that chunk', () async {
      final prep = OrganizePrep.build(_longScript(800), _labels);
      final llm = FakeOrganizerLlm(reply: (_) => '{"sections":[{"beats":[[3],[1]]}]}');
      final outcomes = await ScriptOrganizer(llm, labels: _labels).run(prep.parsed, prep.chunks);
      expect(outcomes.single.sections, isNull);
      expect(llm.calls, 2); // asked once more, then gave up
      expect(ScriptOrganizer.mergedResult(outcomes), isNull);
    });
  });

  test('withRetry stops on a final error', () async {
    var calls = 0;
    await expectLater(
      withRetry<void>(() async {
        calls++;
        throw LlmException('bad key', statusCode: 401);
      }, retryIf: (e) => e is LlmException && e.retryable),
      throwsA(isA<LlmException>()),
    );
    expect(calls, 1);
  });

  test('benchmark: 15,000-word script', () async {
    final text = _longScript(15000);
    final clock = Stopwatch()..start();
    final prep = OrganizePrep.build(text, _labels);
    final firstPass = clock.elapsedMilliseconds;

    // ~1.2 s per request: roughly DeepSeek's latency for a short JSON reply.
    const latency = Duration(milliseconds: 1200);
    final llm = FakeOrganizerLlm(latency: latency);
    final organizing = Stopwatch()..start();
    final outcomes = await ScriptOrganizer(llm, labels: _labels).run(prep.parsed, prep.chunks);
    final refine = organizing.elapsedMilliseconds;

    final sequential = latency.inMilliseconds * prep.chunks.length;
    // ignore: avoid_print
    print(
      'benchmark: ${prep.parsed.wordCount} words, ${prep.parsed.length} sentences, '
      '${prep.chunks.length} chunks · first pass ${firstPass}ms · '
      'refined in ${refine}ms (sequential would be ~${sequential}ms)',
    );
    expect(firstPass, lessThan(2000));
    expect(outcomes.every((o) => o.sections != null), isTrue);
    expect(refine, lessThan(sequential * 0.6));
  });
}

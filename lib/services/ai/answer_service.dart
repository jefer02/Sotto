import 'dart:async';
import 'dart:math' as math;

import '../../data/models/qa_entry.dart';
import '../../data/models/script.dart';
import '../../data/models/settings.dart';
import '../../domain/following/text_normalizer.dart';
import '../../l10n/l10n.dart';
import 'llm_client.dart';

/// A retrievable excerpt of the presenter's material.
class Excerpt {
  const Excerpt({required this.source, required this.text});

  final SourceRef source;
  final String text;
}

/// The answer as it streams in. `complete` flips when the stream ends —
/// only then may Send / Read aloud / Dismiss appear.
class AnswerDraft {
  const AnswerDraft({
    required this.sources,
    this.headline = '',
    this.points = const [],
    this.grounded = true,
    this.notInNotes = false,
    this.complete = false,
    this.predrafted = false,
  });

  final List<SourceRef> sources;
  final String headline;
  final List<AnswerPoint> points;
  final bool grounded;
  final bool notInNotes;
  final bool complete;
  final bool predrafted;

  AnswerDraft copyWith({
    List<SourceRef>? sources,
    String? headline,
    List<AnswerPoint>? points,
    bool? grounded,
    bool? notInNotes,
    bool? complete,
  }) => AnswerDraft(
    sources: sources ?? this.sources,
    headline: headline ?? this.headline,
    points: points ?? this.points,
    grounded: grounded ?? this.grounded,
    notInNotes: notInNotes ?? this.notInNotes,
    complete: complete ?? this.complete,
    predrafted: predrafted,
  );
}

/// Grounded answer drafting. Only the question text and the excerpts used
/// to answer it leave the machine.
class AnswerService {
  AnswerService(this.client);

  final LlmClient client;

  // ─────────────────────────── Retrieval ───────────────────────────

  /// Chunks the script (per section) and prep documents (per paragraph).
  static List<Excerpt> corpus(Script script) {
    final out = <Excerpt>[];
    for (var i = 0; i < script.sections.length; i++) {
      final s = script.sections[i];
      final body = [
        if (s.keyPoints.isNotEmpty) 'Key points: ${s.keyPoints.join('; ')}',
        for (final b in s.beats)
          if (b.plainText.trim().isNotEmpty) b.plainText.trim(),
      ].join(' ');
      out.add(
        Excerpt(
          source: SourceRef(kind: SourceKind.section, label: s.title, code: '§${i + 1}'),
          text: body,
        ),
      );
    }
    for (final d in script.prepDocs) {
      final paras = d.text.split(RegExp(r'\n\s*\n')).map((p) => p.trim()).where((p) => p.isNotEmpty);
      final buf = StringBuffer();
      for (final p in paras) {
        buf.write('$p\n');
        if (buf.length > 900) {
          out.add(
            Excerpt(
              source: SourceRef(kind: SourceKind.prep, label: d.name, code: 'Prep'),
              text: buf.toString(),
            ),
          );
          buf.clear();
        }
      }
      if (buf.isNotEmpty) {
        out.add(
          Excerpt(
            source: SourceRef(kind: SourceKind.prep, label: d.name, code: 'Prep'),
            text: buf.toString(),
          ),
        );
      }
    }
    for (final q in script.prepQuestions) {
      out.add(
        Excerpt(
          source: SourceRef(kind: SourceKind.prep, label: L10n.current.sourceQaPrep, code: 'Prep'),
          text: 'Q: ${q.question}\nA: ${q.answer}',
        ),
      );
    }
    return out;
  }

  static Set<String> _terms(String text) => {
    for (final t in TextNormalizer.normalizeHeard(text))
      if (!TextNormalizer.stopWords.contains(t) && t.length > 2) t,
  };

  /// BM25-style keyword scoring — fast, offline, good enough for a
  /// presenter's own material. The current section always gets a boost.
  static List<Excerpt> retrieve(List<Excerpt> corpus, String question, {int? currentSection, int k = 4}) {
    final q = _terms(question);
    if (q.isEmpty) return corpus.take(math.min(k, corpus.length)).toList();
    final docs = [for (final e in corpus) _terms(e.text)];
    final avg = docs.fold<int>(0, (a, d) => a + d.length) / math.max(1, docs.length);
    final df = <String, int>{};
    for (final d in docs) {
      for (final t in d) {
        df[t] = (df[t] ?? 0) + 1;
      }
    }
    final scored = <(double, Excerpt)>[];
    for (var i = 0; i < corpus.length; i++) {
      var score = 0.0;
      for (final t in q) {
        if (!docs[i].contains(t)) continue;
        final idf = math.log(1 + (corpus.length - df[t]! + 0.5) / (df[t]! + 0.5));
        score += idf * 2.2 / (1 + 1.2 * (0.25 + 0.75 * docs[i].length / math.max(1, avg)));
      }
      final e = corpus[i];
      if (currentSection != null && e.source.code == '§${currentSection + 1}') score += 0.6;
      scored.add((score, e));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return scored.where((s) => s.$1 > 0).take(k).map((s) => s.$2).toList();
  }

  // ─────────────────────── Pre-drafted answers ───────────────────────

  /// Q&A-prep answers that match the question well enough are shown
  /// instantly, without a model call.
  static AnswerDraft? matchPredrafted(Script script, String question) {
    final q = _terms(question);
    if (q.length < 2) return null;
    PrepQuestion? best;
    var bestScore = 0.0;
    for (final p in script.prepQuestions) {
      final t = _terms(p.question);
      if (t.isEmpty) continue;
      final inter = q.intersection(t).length;
      final score = inter / q.union(t).length;
      if (score > bestScore) {
        bestScore = score;
        best = p;
      }
    }
    if (best == null || bestScore < 0.5) return null;

    final sentences = best.answer
        .split(RegExp(r'(?<=[.!?])\s+|\n+'))
        .map((s) => s.trim().replaceFirst(RegExp(r'^[-•*]\s*'), ''))
        .where((s) => s.isNotEmpty)
        .toList();
    return AnswerDraft(
      sources: [SourceRef(kind: SourceKind.prep, label: L10n.current.sourceQaPrep, code: 'Prep')],
      headline: sentences.isEmpty ? best.answer : sentences.first,
      points: [for (final s in sentences.skip(1).take(4)) _splitLead(s)],
      complete: true,
      predrafted: true,
    );
  }

  // ─────────────────────────── Drafting ───────────────────────────

  static String _system(AppSettings s, {bool screenshot = false}) {
    final grounding = switch (s.grounding) {
      Grounding.scriptOnly =>
        'Answer ONLY from the excerpts. If they do not contain the answer, write exactly '
            'HEADLINE: NOT_IN_NOTES and one POINT, in the language of the answer, suggesting how to defer gracefully.',
      Grounding.scriptFirst =>
        'Prefer the excerpts. If you must use general knowledge, still answer, and write GENERAL: yes.',
    };
    final length = switch (s.answerLength) {
      AnswerLength.headline => 'Write only the headline, no points.',
      AnswerLength.headlinePlus3 => 'Write the headline and exactly 3 points.',
      AnswerLength.detailed => 'Write the headline and 4–5 points.',
    };
    final tone = switch (s.tone) {
      AnswerTone.matchScript => "Match the voice of the presenter's script.",
      AnswerTone.conversational => 'Use a warm, conversational voice.',
      AnswerTone.formal => 'Use a precise, formal voice.',
    };
    final lang = s.answerLanguage == AnswerLanguage.sameAsQuestion
        ? 'Answer in the language of the question.'
        : 'Answer in the language of the script.';

    return '''
You help a presenter answer a live question from their audience. They will glance at your answer while speaking, so it must be sayable out loud and readable in one glance.

$grounding
$length
$tone
$lang

Output format — plain lines, nothing else, no markdown:
HEADLINE: <one sentence the presenter can say first, at most 22 words>
POINT: <2–5 word bold lead> || <rest of the talking point, at most 20 words>
SOURCE: <the code of each excerpt you used, e.g. §3 or Prep:filename>
GENERAL: yes|no

Write numbers the way they are said in the script. Never invent figures that are not in the excerpts unless GENERAL is yes.${screenshot ? '''

A screenshot of the presenter's screen is attached. What is visible on it counts as source material: cite it as SOURCE: Screen. Describe only what is actually visible; never guess at text you cannot read.''' : ''}''';
  }

  /// [screen]: null without a screenshot; true when the question is about
  /// the screen itself, false when the screenshot is extra context.
  static String _user(Script script, String question, List<Excerpt> excerpts, List<String> covered, {bool? screen}) {
    final ex = excerpts
        .map(
          (e) => '[${e.source.code == 'Prep' ? 'Prep:${e.source.label}' : e.source.code}] ${e.source.label}\n${e.text}',
        )
        .join('\n\n');
    return '''
Talk: ${script.title}
Sections already covered: ${covered.isEmpty ? 'none yet' : covered.join(', ')}

Excerpts:
$ex

${switch (screen) {
      true => 'The presenter is asking about what is on their screen right now (screenshot attached):',
      false => 'The screenshot shows the slide on screen right now. Question from the audience:',
      null => 'Question from the audience:',
    }}
"$question"''';
  }

  /// Streams progressive drafts. The first event carries only the sources,
  /// which the overlay shows before any words arrive.
  ///
  /// [screenshot] (a JPEG data URL) is attached to the request; with
  /// [aboutScreen] the question is about the screen itself ("Ask about
  /// screen"), otherwise it is extra context for an audience question.
  Stream<AnswerDraft> draft({
    required Script script,
    required String question,
    required AppSettings settings,
    int? currentSection,
    String? screenshot,
    bool aboutScreen = false,
  }) async* {
    final excerpts = retrieve(corpus(script), question, currentSection: currentSection);
    final screen = screenshot == null
        ? null
        : SourceRef(kind: SourceKind.screen, label: L10n.current.sourceScreen, code: 'Screen');
    var d = AnswerDraft(sources: [?screen, for (final e in excerpts) e.source]);
    yield d;

    final covered = [
      for (var i = 0; i <= (currentSection ?? -1) && i < script.sections.length; i++) script.sections[i].title,
    ];

    final buf = StringBuffer();
    await for (final chunk in client.stream(
      system: _system(settings, screenshot: screenshot != null),
      user: _user(script, question, excerpts, covered, screen: screenshot == null ? null : aboutScreen),
      maxTokens: 1024,
      images: [?screenshot],
    )) {
      buf.write(chunk);
      final parsed = _parse(buf.toString(), excerpts, partial: true, screen: screen);
      d = parsed.copyWith(sources: parsed.sources.isEmpty ? d.sources : parsed.sources);
      yield d;
    }
    final done = _parse(buf.toString(), excerpts, partial: false, screen: screen);
    yield done.copyWith(sources: done.sources.isEmpty ? d.sources : done.sources, complete: true);
  }

  static AnswerDraft _parse(String text, List<Excerpt> excerpts, {required bool partial, SourceRef? screen}) {
    var headline = '';
    final points = <AnswerPoint>[];
    final sources = <SourceRef>[];
    var general = false;
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      final isLast = i == lines.length - 1;
      if (line.startsWith('HEADLINE:')) {
        headline = line.substring(9).trim();
      } else if (line.startsWith('POINT:')) {
        // A half-streamed point would pop in mid-word; wait for its line.
        if (partial && isLast) continue;
        final body = line.substring(6).trim();
        final parts = body.split('||');
        points.add(
          parts.length > 1
              ? AnswerPoint(lead: parts[0].trim(), rest: parts.sublist(1).join('||').trim())
              : _splitLead(body),
        );
      } else if (line.startsWith('SOURCE:')) {
        final code = line.substring(7).trim();
        if (screen != null && code.toLowerCase() == 'screen') {
          if (!sources.contains(screen)) sources.add(screen);
          continue;
        }
        final match = excerpts.where((e) {
          final c = e.source.code == 'Prep' ? 'Prep:${e.source.label}' : e.source.code;
          return c?.toLowerCase() == code.toLowerCase() || e.source.code == code;
        });
        for (final e in match.take(1)) {
          if (!sources.any((s) => s.label == e.source.label && s.code == e.source.code)) sources.add(e.source);
        }
      } else if (line.startsWith('GENERAL:')) {
        general = line.toLowerCase().contains('yes');
      }
    }
    // A language-neutral token, rendered in the interface language.
    final notInNotes = headline.toUpperCase().startsWith('NOT_IN_NOTES');
    if (notInNotes) headline = L10n.current.notInYourNotes;
    return AnswerDraft(
      sources: [
        ...sources,
        if (general) SourceRef(kind: SourceKind.general, label: L10n.current.sourceGeneral),
      ],
      headline: headline,
      points: points,
      grounded: !general,
      notInNotes: notInNotes,
    );
  }

  static AnswerPoint _splitLead(String s) {
    final words = s.split(' ');
    if (words.length <= 4) return AnswerPoint(lead: s, rest: '');
    return AnswerPoint(lead: words.take(3).join(' '), rest: words.skip(3).join(' '));
  }

  // ─────────────────────────── Structuring ───────────────────────────

  /// Asks the model to organize raw text into Markdown the rule-based
  /// structurer can read with one beat per line.
  Future<String> organize(String raw) => client.complete(
    system: '''
You organize a presenter's script for a teleprompter. Keep their words exactly; do not rewrite, summarize or add content.
Output Markdown only:
## <Section title>            (3–7 sections for a typical talk)
- <key point>                  (2–3 short key points per section, optional)
<one beat per line>            (a beat is one breath: 8–25 words, split long sentences at natural pauses)
Put stage directions on their own beat line prefix: [SLIDE n], [PAUSE] or [DEMO].''',
    user: raw,
    maxTokens: 32000,
  );
}

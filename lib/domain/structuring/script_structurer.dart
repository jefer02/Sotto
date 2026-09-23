import '../../data/models/script.dart';
import '../../core/utils/ids.dart';
import '../../l10n/l10n.dart';

/// Offline, rule-based organizer: raw text → sections, beats and cues.
/// The AI organizer produces the same shape when a key is configured; this
/// one always works and is what runs while you are offline.
class ScriptStructurer {
  const ScriptStructurer({this.minBeatWords = 6, this.maxBeatWords = 28});

  /// Shorter sentences merge into the next one.
  final int minBeatWords;

  /// Longer sentences split at a natural pause ("one breath").
  final int maxBeatWords;

  static final _heading = RegExp(r'^\s{0,3}#{1,6}\s+(.+?)\s*#*\s*$');
  static final _sectionLabel = RegExp(r'^\s*(?:section|part|chapter|secci[oó]n|parte|cap[ií]tulo)\s+\d+\s*[:.\-–—]\s*(.+)$', caseSensitive: false);
  static final _bullet = RegExp(r'^\s*(?:[-*•]|\d+[.)])\s+(.+)$');
  static final _rule = RegExp(r'^\s*(?:-{3,}|\*{3,}|_{3,})\s*$');
  static final _inlineCue = RegExp(
    // English and Spanish stage directions: [SLIDE 7] / [DIAPOSITIVA 7], [PAUSE] / [PAUSA]…
    r'\[(?:(slide|diapositiva|diapo)\s*(\d+)?|(next slide|siguiente diapositiva)|(pause|pausa)|(demo)|(note|nota)[:\s]*([^\]]*))\]'
    r'|\((pause|pausa|next slide|siguiente diapositiva)\)',
    caseSensitive: false,
  );
  static final _sentenceEnd = RegExp(r'(?<=[.!?…])["”’)]?\s+(?=["“‘(]?[A-Z0-9$€£])');

  /// [linePerBeat] trusts the input's line breaks as beat boundaries — used
  /// for the AI organizer's output, which already splits by breath.
  List<Section> structure(String raw, {bool linePerBeat = false}) {
    final lines = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final drafts = <_DraftSection>[];
    _DraftSection? current;
    final paragraph = StringBuffer();

    void flushParagraph() {
      final text = paragraph.toString().trim();
      paragraph.clear();
      if (text.isEmpty) return;
      current ??= _DraftSection(null);
      if (drafts.isEmpty || drafts.last != current) drafts.add(current!);
      current!.paragraphs.add(text);
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      String? title;
      final h = _heading.firstMatch(line);
      final label = _sectionLabel.firstMatch(line);
      if (h != null) {
        title = h.group(1);
      } else if (label != null) {
        title = label.group(1);
      } else if (_looksLikeTitle(trimmed, lines, i)) {
        title = trimmed;
      }

      if (title != null) {
        flushParagraph();
        current = _DraftSection(_cleanTitle(title));
        drafts.add(current!);
        continue;
      }
      if (_rule.hasMatch(line)) {
        flushParagraph();
        current = _DraftSection(null);
        continue;
      }
      if (trimmed.isEmpty) {
        flushParagraph();
        continue;
      }
      final bullet = _bullet.firstMatch(line);
      if (bullet != null && current != null && current!.paragraphs.isEmpty && paragraph.isEmpty) {
        current!.keyPoints.add(bullet.group(1)!.trim());
        continue;
      }
      if (paragraph.isNotEmpty) paragraph.write(' ');
      paragraph.write(trimmed);
      if (linePerBeat) flushParagraph();
    }
    flushParagraph();

    final nonEmpty = drafts.where((d) => d.paragraphs.isNotEmpty || d.keyPoints.isNotEmpty).toList();
    if (nonEmpty.isEmpty) return [Section.create(L10n.current.sectionOpening)];

    // No headings at all: chunk long scripts into ~200-word parts.
    if (!linePerBeat && nonEmpty.length == 1 && nonEmpty.first.title == null) {
      return _chunkUntitled(nonEmpty.first.paragraphs);
    }

    var slide = 0;
    return [
      for (var i = 0; i < nonEmpty.length; i++)
        Section(
          id: newId(),
          title: nonEmpty[i].title ?? (i == 0 ? L10n.current.sectionOpening : _titleFrom(nonEmpty[i].paragraphs)),
          keyPoints: nonEmpty[i].keyPoints,
          beats: () {
            final beats = <Beat>[];
            for (final p in nonEmpty[i].paragraphs) {
              final (b, s) = _beatsFor(p, slide, whole: linePerBeat);
              beats.addAll(b);
              slide = s;
            }
            return beats.isEmpty ? [Beat.create('')] : beats;
          }(),
        ),
    ];
  }

  /// Returns the beats of a paragraph and the running slide counter.
  (List<Beat>, int) _beatsFor(String paragraph, int slideCounter, {bool whole = false}) {
    var slide = slideCounter;
    final beats = <Beat>[];
    Cue? pending;

    // Pull cues out, remembering where they were so they attach to the
    // sentence that follows them.
    final pieces = <(Cue?, String)>[];
    var last = 0;
    for (final m in _inlineCue.allMatches(paragraph)) {
      pieces.add((null, paragraph.substring(last, m.start)));
      Cue cue;
      if (m.group(1) != null || m.group(3) != null || (m.group(8)?.toLowerCase().endsWith('diapositiva') ?? false) || m.group(8)?.toLowerCase() == 'next slide') {
        final n = int.tryParse(m.group(2) ?? '');
        slide = n ?? slide + 1;
        cue = Cue(CueType.slide, '$slide');
      } else if (m.group(4) != null || (m.group(8)?.toLowerCase().startsWith('paus') ?? false)) {
        cue = const Cue(CueType.pause);
      } else if (m.group(5) != null) {
        cue = const Cue(CueType.demo);
      } else {
        cue = Cue(CueType.note, (m.group(7) ?? '').trim().isEmpty ? null : m.group(7)!.trim());
      }
      pieces.add((cue, ''));
      last = m.end;
    }
    pieces.add((null, paragraph.substring(last)));

    for (final (cue, text) in pieces) {
      if (cue != null) {
        pending = cue;
        continue;
      }
      final trimmed = text.trim().replaceAll(RegExp(r'\s+'), ' ');
      for (final sentence in whole ? [if (trimmed.isNotEmpty) trimmed] : _sentences(text)) {
        beats.add(Beat.create(sentence, cue: pending));
        pending = null;
      }
    }
    if (pending != null) beats.add(Beat.create('', cue: pending));
    return (beats, slide);
  }

  List<String> _sentences(String text) {
    final raw = text
        .split(_sentenceEnd)
        .map((s) => s.trim().replaceAll(RegExp(r'\s+'), ' '))
        .where((s) => s.isNotEmpty)
        .toList();

    // Merge fragments shorter than a breath into the following sentence.
    final merged = <String>[];
    for (final s in raw) {
      if (merged.isNotEmpty && _words(merged.last) < minBeatWords) {
        merged[merged.length - 1] = '${merged.last} $s';
      } else {
        merged.add(s);
      }
    }
    return [for (final s in merged) ..._splitLong(s)];
  }

  /// Splits at the pause nearest the middle: ";", ":", "—", then ",".
  List<String> _splitLong(String s) {
    if (_words(s) <= maxBeatWords) return [s];
    final mid = s.length ~/ 2;
    int? best;
    for (final mark in const [';', ':', ' — ', ' – ', ',']) {
      var idx = s.indexOf(mark);
      while (idx != -1) {
        final left = _words(s.substring(0, idx));
        final right = _words(s.substring(idx + mark.length));
        if (left >= minBeatWords && right >= minBeatWords) {
          if (best == null || (idx - mid).abs() < (best - mid).abs()) best = idx + mark.trimRight().length;
        }
        idx = s.indexOf(mark, idx + 1);
      }
      if (best != null) break;
    }
    if (best == null) return [s];
    return [..._splitLong(s.substring(0, best).trim()), ..._splitLong(s.substring(best).trim())];
  }

  List<Section> _chunkUntitled(List<String> paragraphs) {
    const target = 220;
    final sections = <Section>[];
    var buffer = <String>[];
    var words = 0;
    var slide = 0;
    void emit() {
      if (buffer.isEmpty) return;
      final beats = <Beat>[];
      for (final p in buffer) {
        final (b, s) = _beatsFor(p, slide);
        beats.addAll(b);
        slide = s;
      }
      sections.add(Section(id: newId(), title: sections.isEmpty ? L10n.current.sectionOpening : _titleFrom(buffer), beats: beats));
      buffer = [];
      words = 0;
    }

    for (final p in paragraphs) {
      buffer.add(p);
      words += _words(p);
      if (words >= target) emit();
    }
    emit();
    return sections;
  }

  bool _looksLikeTitle(String line, List<String> lines, int i) {
    if (line.isEmpty || line.length > 60) return false;
    if (RegExp(r'[.,;:!?…"”]$').hasMatch(line)) return false;
    if (_bullet.hasMatch(line) || _inlineCue.hasMatch(line)) return false;
    final prevBlank = i == 0 || lines[i - 1].trim().isEmpty;
    final nextBlank = i + 1 >= lines.length || lines[i + 1].trim().isEmpty;
    final words = _words(line);
    return prevBlank && nextBlank && words <= 7 && RegExp(r'^[A-Z0-9]').hasMatch(line);
  }

  String _cleanTitle(String t) => t.replaceAll(RegExp(r'[*_`]'), '').trim();

  String _titleFrom(List<String> paragraphs) {
    final words = paragraphs.first.replaceAll(_inlineCue, '').trim().split(RegExp(r'\s+'));
    final t = words.take(4).join(' ').replaceAll(RegExp(r'[.,;:!?]+$'), '');
    return t.isEmpty ? L10n.current.sectionFallback : t;
  }

  static int _words(String s) => s.trim().isEmpty ? 0 : s.trim().split(RegExp(r'\s+')).length;

  /// Names and numbers worth sending to the recognizer as hints.
  static List<String> hintWordsFor(List<Section> sections, {int limit = 12}) {
    final counts = <String, int>{};
    final number = RegExp(r'[$€£]?\d[\d,.]*\s?(?:%|million|billion|thousand|millones|mil|k|m|bn)?', caseSensitive: false);
    final proper = RegExp(r'(?<=[a-z,;:]\s)([A-Z][a-zA-Z]{2,}(?:\s[A-Z][a-zA-Z]+)*)');
    for (final s in sections) {
      for (final b in s.beats) {
        final text = b.plainText;
        for (final m in number.allMatches(text)) {
          final v = m.group(0)!.trim().replaceAll(RegExp(r'[.,]$'), '');
          if (v.length > 1) counts[v] = (counts[v] ?? 0) + 2;
        }
        for (final m in proper.allMatches(text)) {
          counts[m.group(1)!] = (counts[m.group(1)!] ?? 0) + 1;
        }
      }
    }
    final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).map((e) => e.key).toList();
  }
}

class _DraftSection {
  _DraftSection(this.title);

  final String? title;
  final List<String> paragraphs = [];
  final List<String> keyPoints = [];
}

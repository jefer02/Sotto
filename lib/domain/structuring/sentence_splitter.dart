import 'script_structurer.dart';

/// Splits prose into sentences without touching a character of it: the AI
/// organizer refers to sentences by number and never rewrites them, so the
/// split must be exact and deterministic.
///
/// English and Spanish aware: abbreviations ("Dr.", "e.g.", "Sra.",
/// "EE. UU."), initials ("J. K. Rowling"), decimals ("3.5", "48,2"),
/// ellipses followed by lowercase, and Spanish opening marks (¿ ¡).
abstract final class SentenceSplitter {
  /// Lowercased, without the final dot.
  static const abbreviations = {
    // English
    'mr', 'mrs', 'ms', 'dr', 'prof', 'sr', 'jr', 'st', 'vs', 'etc', 'e.g', 'i.e', 'eg', 'ie', 'inc', 'ltd', 'co',
    'corp', 'no', 'fig', 'figs', 'approx', 'dept', 'est', 'vol', 'p', 'pp', 'ch', 'cf', 'al', 'u.s', 'u.k', 'a.m',
    'p.m', 'jan', 'feb', 'mar', 'apr', 'jun', 'jul', 'aug', 'sep', 'sept', 'oct', 'nov', 'dec', 'mt', 'ft', 'lb',
    'oz', 'gen', 'gov', 'rep', 'sen', 'rev', 'ave', 'blvd',
    // Spanish
    'sra', 'srta', 'sres', 'dra', 'lic', 'ing', 'arq', 'ud', 'uds', 'vd', 'vds', 'pág', 'págs', 'núm', 'nº', 'art',
    'aprox', 'tel', 'av', 'avda', 'dña', 'd', 'da', 'ee.uu', 'uu', 'ee', 'p.ej', 'ej', 'cía', 'admón', 'depto',
    'dpto', 'máx', 'mín', 'izq', 'dcha', 'aa.vv', 'op', 'cit', 'ibid', 'ene', 'abr', 'ago', 'dic',
  };

  // Candidate ends: terminal punctuation, optional closing quotes or
  // brackets, then whitespace.
  static final _end = RegExp(r'[.!?…]+["”’»)\]]*(?=\s)');
  static final _startOk = RegExp(r'[A-ZÁÉÍÓÚÜÑ0-9"“‘«(\[¿¡$€£]');

  static List<String> split(String text) {
    final out = <String>[];
    var start = 0;
    for (final m in _end.allMatches(text)) {
      final end = m.end;
      // The next non-space character must look like a sentence start.
      var next = end;
      while (next < text.length && _isSpace(text.codeUnitAt(next))) {
        next++;
      }
      if (next >= text.length) break;
      if (!_startOk.hasMatch(text[next])) continue;
      if (_isAbbreviation(text, m.start, m.group(0)!)) continue;
      final s = text.substring(start, end).trim();
      if (s.isNotEmpty) out.add(s);
      start = next;
    }
    final tail = text.substring(start).trim();
    if (tail.isNotEmpty) out.add(tail);
    return out;
  }

  static bool _isSpace(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0xA0;

  /// Whether the dot at [at] ends an abbreviation or an initial rather
  /// than a sentence.
  static bool _isAbbreviation(String text, int at, String mark) {
    if (!mark.startsWith('.') || mark.startsWith('..')) return false;
    var i = at;
    while (i > 0 && !_isSpace(text.codeUnitAt(i - 1)) && !'(["“‘«¿¡'.contains(text[i - 1])) {
      i--;
    }
    final word = text.substring(i, at);
    if (word.isEmpty) return false;
    final lower = word.toLowerCase();
    if (abbreviations.contains(lower)) return true;
    // Initials: "J." in "J. K. Rowling"; also "U.S." style chains.
    if (RegExp(r'^[A-ZÁÉÍÓÚÑ]$').hasMatch(word)) return true;
    if (RegExp(r'^(?:[A-Za-z]\.)+[A-Za-z]$').hasMatch(word)) return true;
    return false;
  }
}

/// A sentence of the source, numbered from 1 across the whole script.
class NumberedSentence {
  const NumberedSentence(this.id, this.text, this.paragraph);

  final int id;

  /// Exactly as written (whitespace collapsed), inline cues included.
  final String text;

  /// Index into [ParsedScript.paragraphs].
  final int paragraph;

  int get words => text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;
}

/// A paragraph, and the heading that opens it (if one does).
class ParsedParagraph {
  const ParsedParagraph({required this.first, required this.last, this.heading, this.keyPoints = const []});

  /// Sentence ids, inclusive.
  final int first;
  final int last;

  /// Title of a heading line right before this paragraph.
  final String? heading;

  /// Bullets right under that heading: the author's own key points.
  final List<String> keyPoints;
}

/// The script as numbered sentences in paragraphs — what the AI organizer
/// sees and what it refers back to.
class ParsedScript {
  const ParsedScript({required this.sentences, required this.paragraphs});

  final List<NumberedSentence> sentences;
  final List<ParsedParagraph> paragraphs;

  int get length => sentences.length;

  NumberedSentence sentence(int id) => sentences[id - 1];

  int get wordCount => sentences.fold(0, (a, s) => a + s.words);

  /// Headings become paragraph titles and the bullets right under them key
  /// points; other bullets are sentences of their own; everything else
  /// splits with [SentenceSplitter].
  static ParsedScript parse(String raw) {
    final lines = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final sentences = <NumberedSentence>[];
    final paragraphs = <ParsedParagraph>[];
    final buffer = StringBuffer();
    String? heading;
    var keyPoints = <String>[];

    void addParagraph(List<String> parts) {
      final texts = [
        for (final p in parts)
          if (p.trim().isNotEmpty) p.trim().replaceAll(RegExp(r'\s+'), ' '),
      ];
      if (texts.isEmpty) return;
      final first = sentences.length + 1;
      for (final t in texts) {
        sentences.add(NumberedSentence(sentences.length + 1, t, paragraphs.length));
      }
      paragraphs.add(ParsedParagraph(first: first, last: sentences.length, heading: heading, keyPoints: keyPoints));
      heading = null;
      keyPoints = [];
    }

    void flush() {
      final text = buffer.toString();
      buffer.clear();
      if (text.trim().isNotEmpty) addParagraph(SentenceSplitter.split(text));
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final title = ScriptStructurer.titleAt(lines, i);
      if (title != null) {
        flush();
        // Two headings in a row: keep the later, more specific one.
        heading = title;
        keyPoints = [];
        continue;
      }
      if (line.trim().isEmpty || ScriptStructurer.isRule(line)) {
        flush();
        continue;
      }
      final bullet = ScriptStructurer.bulletAt(line);
      if (bullet != null) {
        flush();
        if (heading != null) {
          keyPoints.add(bullet);
          continue;
        }
        addParagraph([bullet]);
        continue;
      }
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(line.trim());
    }
    flush();
    return ParsedScript(sentences: sentences, paragraphs: paragraphs);
  }
}

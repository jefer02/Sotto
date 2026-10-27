import '../../data/models/script.dart';

/// A marker in a script: where it is and what it says.
class MarkerRef {
  const MarkerRef({
    required this.section,
    required this.beatId,
    required this.start,
    required this.end,
    required this.text,
  });

  /// Index of the section holding it.
  final int section;
  final String beatId;

  /// Its characters in the beat's text, end exclusive.
  final int start;
  final int end;

  /// The marker as written: "[CHECK: Q3 revenue]".
  final String text;

  /// What it says is missing: "Q3 revenue".
  String get note {
    final colon = text.indexOf(':');
    return text.substring(colon + 1, text.length - 1).trim();
  }
}

/// The visible markers a generated script carries where its material lacked
/// something — "[CHECK: Q3 revenue]", "[REVISAR: fecha de lanzamiento]".
/// They are notes to the presenter, never meant to be said: voice following
/// skips them, the overlay shows them apart (or hides them), the editor walks
/// through them and pre-flight counts what is left. O(n) in the text.
abstract final class CheckMarkers {
  /// The marker words, in every interface language: a script keeps the
  /// markers it was generated with when the language changes.
  static final pattern = RegExp(r'\[\s*(?:CHECK|REVISAR|VERIFY|VERIFICAR)\s*:[^\]\n]*\]', caseSensitive: false);

  static bool has(String text) => pattern.hasMatch(text);

  static int count(String text) => pattern.allMatches(text).length;

  static int countIn(Iterable<Section> sections) =>
      sections.expand((s) => s.beats).fold(0, (a, b) => a + count(b.text));

  /// Every marker in [script], in reading order.
  static List<MarkerRef> inScript(Script script) => [
    for (var s = 0; s < script.sections.length; s++)
      for (final beat in script.sections[s].beats)
        for (final m in pattern.allMatches(beat.text))
          MarkerRef(section: s, beatId: beat.id, start: m.start, end: m.end, text: m[0]!),
  ];

  /// [text] without its markers, spaces tidied: "We grew [CHECK: x] fast."
  /// → "We grew fast.".
  static String strip(String text) => has(text) ? _tidy(text.replaceAll(pattern, ' ')) : text;

  /// [text] with the marker at [start]–[end] taken out, spaces tidied.
  static String removeAt(String text, int start, int end) =>
      _tidy('${text.substring(0, start)} ${text.substring(end)}');

  static String _tidy(String text) =>
      text.replaceAll(RegExp(r'[ \t]{2,}'), ' ').replaceAllMapped(RegExp(r' +([.,;:!?)])'), (m) => m[1]!).trim();

  /// The script as the live view shows it with markers hidden: markers gone,
  /// beats left empty dropped, then sections left empty. Ids are kept.
  static Script stripScript(Script script) {
    if (countIn(script.sections) == 0) return script;
    final sections = [
      for (final s in script.sections)
        s.copyWith(
          beats: [
            for (final b in s.beats)
              if (!has(b.text)) b else if (strip(b.text).isNotEmpty) b.copyWith(text: strip(b.text)),
          ],
        ),
    ].where((s) => s.beats.isNotEmpty).toList();
    return sections.isEmpty ? script : script.copyWith(sections: sections, updatedAt: script.updatedAt);
  }

  /// For each of [text]'s display words (split on whitespace, `**` removed —
  /// the words the overlay lays out and the aligner indexes), whether it is
  /// part of a marker.
  static List<bool> wordMask(String text) {
    final clean = text.replaceAll('**', '');
    final words = RegExp(r'\S+').allMatches(clean).toList();
    if (!has(clean)) return List.filled(words.length, false);
    final spans = pattern.allMatches(clean).toList();
    return [for (final w in words) spans.any((m) => w.start < m.end && w.end > m.start)];
  }
}

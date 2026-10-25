import '../../data/models/script.dart';

/// Text the presenter pasted into a beat, as opposed to typed: a change that
/// inserts a substantial amount of script text at once.
class PastedText {
  const PastedText({required this.before, required this.pasted, required this.after});

  /// The beat's text around the paste.
  final String before;
  final String pasted;
  final String after;

  /// At least this much text, in at least two sentences (or two lines),
  /// arriving in one change. Typing never inserts that much at once.
  static const minLength = 60;
  static const minSentences = 2;

  static final _sentenceEnd = RegExp(r'[.!?…](?=\s|$)');

  /// The paste in the change from [old] to [now], or null when the change
  /// looks like typing (or a short paste: a word, a phrase).
  static PastedText? detect(String old, String now) {
    if (now.length - old.length < minLength) return null;
    var p = 0;
    while (p < old.length && p < now.length && old.codeUnitAt(p) == now.codeUnitAt(p)) {
      p++;
    }
    var s = 0;
    while (s < old.length - p &&
        s < now.length - p &&
        old.codeUnitAt(old.length - 1 - s) == now.codeUnitAt(now.length - 1 - s)) {
      s++;
    }
    final pasted = now.substring(p, now.length - s);
    if (pasted.trim().length < minLength) return null;
    final lines = pasted.split('\n').where((l) => l.trim().isNotEmpty).length;
    final sentences = _sentenceEnd.allMatches(pasted.trim()).length;
    if (lines < 2 && sentences < minSentences) return null;
    return PastedText(before: now.substring(0, p), pasted: pasted, after: now.substring(now.length - s));
  }
}

/// Where organized sections go when text is pasted into beat [beatIndex] of
/// section [sectionIndex].
///
/// * Into a script with nothing else in it (a new script): the organized
///   sections are the script.
/// * Into a script with content: they go in at the paste — the section
///   keeps what came before it, and what came after continues in a section
///   of the same title after the pasted ones. Nothing typed moves or merges,
///   and the inserted sections are exactly [organized] (so refinement can
///   find and replace them).
abstract final class PastePlacement {
  static bool isOnly(Script script, int sectionIndex, int beatIndex, PastedText paste) {
    if (paste.before.trim().isNotEmpty || paste.after.trim().isNotEmpty) return false;
    for (var si = 0; si < script.sections.length; si++) {
      final sec = script.sections[si];
      if (si != sectionIndex && sec.keyPoints.isNotEmpty) return false;
      for (var bi = 0; bi < sec.beats.length; bi++) {
        if (si == sectionIndex && bi == beatIndex) continue;
        if (sec.beats[bi].text.trim().isNotEmpty) return false;
      }
    }
    return true;
  }

  static List<Section> place(
    Script script,
    int sectionIndex,
    int beatIndex,
    PastedText paste,
    List<Section> organized,
  ) {
    if (isOnly(script, sectionIndex, beatIndex, paste)) return organized;
    final sec = script.sections[sectionIndex];
    final beat = sec.beats[beatIndex];
    final head = [
      ...sec.beats.take(beatIndex),
      if (paste.before.trim().isNotEmpty) beat.copyWith(text: paste.before.trimRight()),
    ];
    final tail = [
      if (paste.after.trim().isNotEmpty) Beat.create(paste.after.trimLeft()),
      ...sec.beats.skip(beatIndex + 1),
    ];
    return [
      ...script.sections.take(sectionIndex),
      if (head.isNotEmpty) sec.copyWith(beats: head),
      ...organized,
      if (tail.isNotEmpty) head.isEmpty ? sec.copyWith(beats: tail) : Section.create(sec.title).copyWith(beats: tail),
      ...script.sections.skip(sectionIndex + 1),
    ];
  }
}

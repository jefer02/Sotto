import 'dart:async';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';

import '../../data/import/script_importer.dart';
import '../../data/models/script.dart';
import '../../data/repositories.dart';
import '../../domain/structuring/organize_plan.dart';
import '../../domain/structuring/paste_placement.dart';
import '../../domain/structuring/script_structurer.dart';
import '../library/organize_jobs.dart';

enum SaveState { saved, saving, dirty }

class EditorState {
  const EditorState({
    required this.script,
    this.section = 0,
    this.focusedBeat,
    this.save = SaveState.saved,
    this.dismissedHints = const {},
    this.pastesOrganized = 0,
  });

  final Script? script;
  final int section;
  final String? focusedBeat;
  final SaveState save;

  /// Long-beat suggestions the presenter chose to ignore.
  final Set<String> dismissedHints;

  /// Counts pastes organized in place, so the Write tab can offer to undo
  /// each one.
  final int pastesOrganized;

  EditorState copyWith({
    Script? script,
    int? section,
    String? focusedBeat,
    SaveState? save,
    Set<String>? dismissedHints,
    int? pastesOrganized,
  }) => EditorState(
    script: script ?? this.script,
    section: section ?? this.section,
    focusedBeat: focusedBeat ?? this.focusedBeat,
    save: save ?? this.save,
    dismissedHints: dismissedHints ?? this.dismissedHints,
    pastesOrganized: pastesOrganized ?? this.pastesOrganized,
  );
}

/// The editor's working copy. Edits apply instantly here and are written to
/// disk 400 ms after typing stops, so fields never fight a round-trip.
class EditorController extends Notifier<EditorState> implements ScriptWorkingCopy {
  EditorController(this.scriptId);

  final String scriptId;
  Timer? _saveTimer;
  late ScriptRepository _repo;

  // Plain copies of the unsaved work: `state` can't be read from onDispose.
  Script? _pending;

  /// The beat whose text field has keyboard focus — AI refinement never
  /// replaces the part it is in.
  String? _caretBeat;

  /// A paste waiting to be organized, and the script as it was before the
  /// last organized paste (one step of undo; gone at the next edit).
  Timer? _pasteTimer;
  Script? _beforeOrganize;

  /// A paste is organized this long after it lands: one paste arriving in
  /// several changes (an input method, a slow clipboard) organizes once.
  static const pasteDebounce = Duration(milliseconds: 250);

  @override
  EditorState build() {
    // Captured now: providers can't be read from onDispose.
    _repo = ref.read(scriptRepositoryProvider);
    final copies = ref.read(workingCopiesProvider)..register(scriptId, this);
    ref.onDispose(() {
      copies.unregister(scriptId, this);
      _saveTimer?.cancel();
      _pasteTimer?.cancel();
      _flush(disposing: true);
    });
    // Pick up changes made elsewhere (e.g. organizing finished) only while
    // the working copy has no unsaved edits.
    ref.listen(scriptByIdProvider(scriptId), (_, next) {
      if (next != null && state.save == SaveState.saved && !identical(next, state.script)) {
        state = state.copyWith(script: next);
      }
    });
    return EditorState(script: _repo.get(scriptId));
  }

  Script? get script => state.script;

  /// [keepUndo]: a change that isn't the presenter's own edit (refinement
  /// landing) leaves the last organized paste undoable.
  void update(Script Function(Script s) change, {bool keepUndo = false}) {
    final s = state.script;
    if (s == null) return;
    if (!keepUndo) _beforeOrganize = null;
    final next = change(s).copyWith(updatedAt: DateTime.now());
    _pending = next;
    state = state.copyWith(script: next, save: SaveState.dirty);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _flush);
  }

  void _flush({bool disposing = false}) {
    final s = _pending;
    if (s == null) return;
    _pending = null;
    final status = s.status == ScriptStatus.draft && s.wordCount > 20 ? ScriptStatus.structured : s.status;
    unawaited(_repo.save(s.copyWith(status: status, updatedAt: s.updatedAt)));
    if (!disposing) state = state.copyWith(save: SaveState.saved);
  }

  /// Applies a background change (AI refinement) to the working copy: the
  /// selected section stays selected and the caret's beat is untouched.
  @override
  void applyExternal(Script Function(Script script, String? caretBeat) patch) {
    final s = state.script;
    if (s == null) return;
    final next = patch(s, _caretBeat);
    if (identical(next, s)) return;
    final selected = s.sections.elementAtOrNull(state.section)?.id;
    update((_) => next, keepUndo: true);
    final i = next.sections.indexWhere((x) => x.id == selected);
    state = state.copyWith(section: i >= 0 ? i : state.section.clamp(0, next.sections.length - 1));
  }

  void caretIn(String beatId, {required bool focused}) {
    if (focused) {
      _caretBeat = beatId;
    } else if (_caretBeat == beatId) {
      _caretBeat = null;
    }
  }

  void selectSection(int i) =>
      state = state.copyWith(section: i, focusedBeat: state.script?.sections.elementAtOrNull(i)?.beats.firstOrNull?.id);

  void focusBeat(String id) {
    final s = state.script;
    if (s == null) return;
    final si = s.sections.indexWhere((sec) => sec.beats.any((b) => b.id == id));
    state = state.copyWith(focusedBeat: id, section: si < 0 ? state.section : si);
  }

  void dismissHint(String beatId) => state = state.copyWith(dismissedHints: {...state.dismissedHints, beatId});

  // ─────────────────────────── Sections ───────────────────────────

  void updateSection(int i, Section Function(Section s) change) => update((s) {
    final sections = [...s.sections];
    sections[i] = change(sections[i]);
    return s.copyWith(sections: sections);
  });

  void addSection({int? after}) {
    final at = (after ?? state.section) + 1;
    update(
      (s) => s.copyWith(
        sections: [...s.sections]..insert(at.clamp(0, s.sections.length), Section.create(L10n.current.newSectionTitle)),
      ),
    );
    selectSection(at);
  }

  void deleteSection(int i) {
    final s = state.script;
    if (s == null || s.sections.length <= 1) return;
    update((s) => s.copyWith(sections: [...s.sections]..removeAt(i)));
    selectSection((i - 1).clamp(0, s.sections.length - 2));
  }

  /// [to] is the index after removal (ReorderableListView.onReorderItem).
  void moveSection(int from, int to) => update((s) {
    final list = [...s.sections];
    final item = list.removeAt(from);
    list.insert(to.clamp(0, list.length), item);
    return s.copyWith(sections: list);
  });

  // ─────────────────────────── Beats ───────────────────────────

  (int, int)? _locate(String beatId) {
    final s = state.script;
    if (s == null) return null;
    for (var si = 0; si < s.sections.length; si++) {
      final bi = s.sections[si].beats.indexWhere((b) => b.id == beatId);
      if (bi >= 0) return (si, bi);
    }
    return null;
  }

  void setBeatText(String beatId, String text) {
    final loc = _locate(beatId);
    if (loc == null) return;
    final (si, bi) = loc;
    // Several sentences arriving at once are a paste of script text: it is
    // organized right away, like an import. Typing never triggers it.
    final paste = PastedText.detect(state.script!.sections[si].beats[bi].text, text);
    if (paste != null) {
      _pasteTimer?.cancel();
      _pasteTimer = Timer(pasteDebounce, () => unawaited(_organizePaste(beatId, paste.pasted)));
    }
    // A typed leading "[SLIDE 7] " becomes a cue chip.
    final (cue, rest) = Cue.parseLeading(text);
    updateSection(si, (sec) {
      final beats = [...sec.beats];
      final old = beats[bi];
      beats[bi] = cue != null ? old.copyWith(text: rest, cue: cue) : old.copyWith(text: text);
      return sec.copyWith(beats: beats);
    });
  }

  /// Organizes [pasted], now in beat [beatId]: the rule-based pass at once
  /// (on a background isolate), then DeepSeek refinement in the background
  /// as for an import — without a key, the rule-based pass alone. The
  /// wording never changes. Undo puts the pasted text back as it was.
  Future<void> _organizePaste(String beatId, String pasted) async {
    // Only the text and the labels go to the isolate, not this controller.
    final labels = StructurerLabels.current();
    final prep = await Isolate.run(() => OrganizePrep.build(pasted, labels));
    if (!ref.mounted) return;
    // Typing meanwhile moved or removed the pasted text: leave it be.
    final loc = _locate(beatId);
    if (loc == null) return;
    final (si, bi) = loc;
    final before = state.script!;
    final text = before.sections[si].beats[bi].text;
    final at = text.indexOf(pasted);
    if (at < 0 || prep.sections.isEmpty) return;
    final paste = PastedText(before: text.substring(0, at), pasted: pasted, after: text.substring(at + pasted.length));
    final whole = PastePlacement.isOnly(before, si, bi, paste);
    final sections = PastePlacement.place(before, si, bi, paste, prep.sections);
    final llm = await ref.read(organizerLlmProvider)();
    if (!ref.mounted || !identical(state.script, before)) {
      llm?.close();
      return;
    }
    _pasteTimer?.cancel();
    final untitled = before.title == L10n.current.untitledScript;
    update(
      (s) => s.copyWith(
        title: whole && untitled ? ScriptImporter.fromPaste(pasted).title : null,
        sections: sections,
        status: llm == null ? ScriptStatus.structured : ScriptStatus.organizing,
        hintWords: ScriptStructurer.hintWordsFor(sections),
      ),
      keepUndo: true,
    );
    _beforeOrganize = before;
    final first = sections.indexWhere((s) => identical(s, prep.sections.first));
    state = state.copyWith(pastesOrganized: state.pastesOrganized + 1, section: first < 0 ? null : first);
    if (llm != null) unawaited(ref.read(organizeJobsProvider.notifier).start(scriptId, prep, llm));
  }

  /// The last organized paste can still be undone.
  bool get canUndoOrganize => _beforeOrganize != null;

  /// Puts the script back as it was with the paste in it, unorganized, and
  /// stops refining it.
  void undoOrganize() {
    final before = _beforeOrganize;
    if (before == null) return;
    ref.read(organizeJobsProvider.notifier).cancel(scriptId);
    update((_) => before);
    final i = state.section.clamp(0, before.sections.length - 1);
    state = state.copyWith(section: i);
  }

  /// Enter splits a beat at the cursor; returns the new beat's id.
  String? splitBeat(String beatId, int offset) {
    final loc = _locate(beatId);
    if (loc == null) return null;
    final (si, bi) = loc;
    final beat = state.script!.sections[si].beats[bi];
    final at = offset.clamp(0, beat.text.length);
    final next = Beat.create(beat.text.substring(at).trimLeft());
    updateSection(si, (sec) {
      final beats = [...sec.beats];
      beats[bi] = beat.copyWith(text: beat.text.substring(0, at).trimRight());
      beats.insert(bi + 1, next);
      return sec.copyWith(beats: beats);
    });
    state = state.copyWith(focusedBeat: next.id);
    return next.id;
  }

  /// Backspace at the start merges into the previous beat; returns
  /// (previous beat id, caret offset) or null at the section's first beat.
  (String, int)? mergeWithPrevious(String beatId) {
    final loc = _locate(beatId);
    if (loc == null) return null;
    final (si, bi) = loc;
    if (bi == 0) return null;
    final beats = state.script!.sections[si].beats;
    final prev = beats[bi - 1];
    final cur = beats[bi];
    final joiner = prev.text.isEmpty || cur.text.isEmpty ? '' : ' ';
    updateSection(si, (sec) {
      final list = [...sec.beats];
      list[bi - 1] = prev.copyWith(text: '${prev.text}$joiner${cur.text}', cue: prev.cue ?? cur.cue);
      list.removeAt(bi);
      return sec.copyWith(beats: list);
    });
    state = state.copyWith(focusedBeat: prev.id);
    return (prev.id, prev.text.length + joiner.length);
  }

  void setCue(String beatId, Cue? cue) {
    final loc = _locate(beatId);
    if (loc == null) return;
    final (si, bi) = loc;
    updateSection(si, (sec) {
      final beats = [...sec.beats];
      beats[bi] = cue == null ? beats[bi].copyWith(clearCue: true) : beats[bi].copyWith(cue: cue);
      return sec.copyWith(beats: beats);
    });
  }

  /// Splits a long beat after the sentence-ending or clause punctuation
  /// nearest its middle.
  void splitAtBreath(String beatId) {
    final loc = _locate(beatId);
    if (loc == null) return;
    final (si, bi) = loc;
    final text = state.script!.sections[si].beats[bi].text;
    final at = breathSplitOffset(text);
    if (at != null) splitBeat(beatId, at);
  }

  static int? breathSplitOffset(String text) {
    final mid = text.length ~/ 2;
    int? best;
    for (final m in RegExp(r'[.;:—–,](\s)').allMatches(text)) {
      final at = m.start + 1;
      if (at < 12 || text.length - at < 12) continue;
      if (best == null || (at - mid).abs() < (best - mid).abs()) best = at;
    }
    return best;
  }

  static String? breathSplitWord(String text) {
    final at = breathSplitOffset(text);
    if (at == null) return null;
    final before = text.substring(0, at).trim().split(RegExp(r'\s+'));
    return before.isEmpty ? null : before.last;
  }
}

final editorProvider = NotifierProvider.autoDispose.family<EditorController, EditorState, String>(EditorController.new);

/// Seconds from the talk's start to each beat, and each section's start.
class Timeline {
  Timeline(Script s, int wpm) {
    var t = 0.0;
    for (final sec in s.sections) {
      sectionStart.add(t.round());
      final words = sec.wordCount;
      final perWord = sec.budgetSeconds != null && words > 0 ? sec.budgetSeconds! / words : 60 / wpm;
      for (final b in sec.beats) {
        beatStart[b.id] = t.round();
        t += b.wordCount * perWord;
      }
      if (sec.budgetSeconds != null) t = sectionStart.last + sec.budgetSeconds!.toDouble();
    }
    total = t.round();
  }

  final sectionStart = <int>[];
  final beatStart = <String, int>{};
  late final int total;
}

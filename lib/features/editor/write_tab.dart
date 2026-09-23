import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/l10n.dart';

import '../../core/design/icons.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/display.dart';
import '../../core/widgets/interactive.dart';
import '../../data/models/script.dart';
import '../../data/repositories.dart';
import 'editor_controller.dart';
import 'emphasis_controller.dart';

/// Where the caret should land after a split or merge.
typedef FocusRequest = ({String beatId, int offset});

class WriteTab extends ConsumerStatefulWidget {
  const WriteTab({super.key, required this.scriptId});
  final String scriptId;

  @override
  ConsumerState<WriteTab> createState() => _WriteTabState();
}

class _WriteTabState extends ConsumerState<WriteTab> {
  final _focusRequest = ValueNotifier<FocusRequest?>(null);
  final _scroll = ScrollController();

  @override
  void dispose() {
    _focusRequest.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final e = ref.watch(editorProvider(widget.scriptId));
    final c = ref.read(editorProvider(widget.scriptId).notifier);
    final wpm = ref.watch(settingsProvider.select((s) => s.wordsPerMinute));
    final script = e.script;
    if (script == null) return const SizedBox.shrink();
    final si = e.section.clamp(0, script.sections.length - 1);
    final section = script.sections[si];
    final timeline = Timeline(script, wpm);
    final start = timeline.sectionStart[si];
    final next = si + 1 < script.sections.length ? script.sections[si + 1] : null;

    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(40, 36, 40, 80),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 60),
                  child: Text(
                    context.l10n.sectionHeader(si + 1, script.sections.length, formatDuration(section.estimatedSeconds(wpm)), formatDuration(start)),
                    style: TypeScale.monoSmall.copyWith(color: p.inkTertiary),
                  ),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 60),
                  child: _InlineField(
                    key: ValueKey('title-${section.id}'),
                    text: section.title,
                    style: TypeScale.display.copyWith(fontSize: 28, height: 34 / 28, color: p.inkPrimary),
                    placeholder: context.l10n.sectionTitle,
                    onChanged: (t) => c.updateSection(si, (s) => s.copyWith(title: t)),
                  ),
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.only(left: 60),
                  child: _KeyPoints(
                    key: ValueKey('kp-${section.id}'),
                    points: section.keyPoints,
                    onChanged: (k) => c.updateSection(si, (s) => s.copyWith(keyPoints: k)),
                  ),
                ),
                const SizedBox(height: 22),
                for (final beat in section.beats) ...[
                  BeatRow(
                    key: ValueKey(beat.id),
                    scriptId: widget.scriptId,
                    beat: beat,
                    timestamp: timeline.beatStart[beat.id] ?? 0,
                    focused: e.focusedBeat == beat.id,
                    focusRequest: _focusRequest,
                    allBeatIds: [for (final b in section.beats) b.id],
                  ),
                  if (beat.wordCount > 28 && !e.dismissedHints.contains(beat.id))
                    _LongBeatHint(
                      beat: beat,
                      onIgnore: () => c.dismissHint(beat.id),
                      onSplit: () => c.splitAtBreath(beat.id),
                    ),
                ],
                Padding(
                  padding: const EdgeInsets.only(left: 60, top: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextLink(
                      context.l10n.addBeat,
                      muted: true,
                      onTap: () {
                        final last = section.beats.lastOrNull;
                        if (last == null) return;
                        final id = c.splitBeat(last.id, last.text.length);
                        if (id != null) _focusRequest.value = (beatId: id, offset: 0);
                      },
                    ),
                  ),
                ),
                if (next != null) ...[
                  const SizedBox(height: 28),
                  Padding(
                    padding: const EdgeInsets.only(left: 60),
                    child: Row(
                      children: [
                        Expanded(child: Divider(color: p.hairline)),
                        const SizedBox(width: 12),
                        Interactive(
                          onTap: () => c.selectSection(si + 1),
                          builder: (context, st) => Text.rich(
                            TextSpan(
                              style: TypeScale.caption.copyWith(color: p.inkTertiary),
                              children: [
                                TextSpan(text: context.l10n.transitionTo),
                                TextSpan(
                                  text: next.title,
                                  style: TypeScale.captionStrong.copyWith(
                                    color: st.hovered ? p.inkPrimary : p.inkSecondary,
                                  ),
                                ),
                                TextSpan(text: '  ·  ${formatDuration(next.estimatedSeconds(wpm))}'),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Divider(color: p.hairline)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class BeatRow extends ConsumerStatefulWidget {
  const BeatRow({
    super.key,
    required this.scriptId,
    required this.beat,
    required this.timestamp,
    required this.focused,
    required this.focusRequest,
    required this.allBeatIds,
  });

  final String scriptId;
  final Beat beat;
  final int timestamp;
  final bool focused;
  final ValueNotifier<FocusRequest?> focusRequest;
  final List<String> allBeatIds;

  @override
  ConsumerState<BeatRow> createState() => _BeatRowState();
}

class _BeatRowState extends ConsumerState<BeatRow> {
  late final EmphasisController _text;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _text = EmphasisController(text: widget.beat.text, markerColor: const Color(0x55928D86));
    _focus
      ..addListener(_onFocus)
      ..onKeyEvent = _onKey;
    widget.focusRequest.addListener(_onRequest);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onRequest());
  }

  @override
  void didUpdateWidget(BeatRow old) {
    super.didUpdateWidget(old);
    // Accept outside changes (split, merge, cue parsing) unless mid-typing
    // produced the same text already.
    if (widget.beat.text != _text.text) {
      final sel = _text.selection;
      _text.text = widget.beat.text;
      if (_focus.hasFocus && sel.isValid) {
        final at = sel.baseOffset.clamp(0, widget.beat.text.length);
        _text.selection = TextSelection.collapsed(offset: at);
      }
    }
  }

  @override
  void dispose() {
    widget.focusRequest.removeListener(_onRequest);
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (_focus.hasFocus) ref.read(editorProvider(widget.scriptId).notifier).focusBeat(widget.beat.id);
    setState(() {});
  }

  void _onRequest() {
    final r = widget.focusRequest.value;
    if (r == null || r.beatId != widget.beat.id || !mounted) return;
    widget.focusRequest.value = null;
    _focus.requestFocus();
    _text.selection = TextSelection.collapsed(offset: r.offset.clamp(0, _text.text.length));
  }

  void _moveTo(int delta, {bool toEnd = false}) {
    final ids = widget.allBeatIds;
    final i = ids.indexOf(widget.beat.id) + delta;
    if (i < 0 || i >= ids.length) return;
    final target = ref.read(editorProvider(widget.scriptId)).script?.allBeats.where((b) => b.id == ids[i]).firstOrNull;
    widget.focusRequest.value = (beatId: ids[i], offset: toEnd ? (target?.text.length ?? 0) : 0);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final c = ref.read(editorProvider(widget.scriptId).notifier);
    final sel = _text.selection;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (e.logicalKey == LogicalKeyboardKey.enter && !shift) {
      // Enter ends a breath: split the beat at the caret.
      final id = c.splitBeat(widget.beat.id, sel.baseOffset < 0 ? _text.text.length : sel.baseOffset);
      if (id != null) widget.focusRequest.value = (beatId: id, offset: 0);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.backspace && sel.isCollapsed && sel.baseOffset == 0) {
      if (widget.beat.cue != null) {
        c.setCue(widget.beat.id, null);
        return KeyEventResult.handled;
      }
      final r = c.mergeWithPrevious(widget.beat.id);
      if (r != null) widget.focusRequest.value = (beatId: r.$1, offset: r.$2);
      return r == null ? KeyEventResult.ignored : KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowUp && sel.isCollapsed && sel.baseOffset == 0) {
      _moveTo(-1, toEnd: true);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowDown && sel.isCollapsed && sel.baseOffset == _text.text.length) {
      _moveTo(1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final focused = _focus.hasFocus || widget.focused;
    _text.markerColor = p.inkDisabled;
    final c = ref.read(editorProvider(widget.scriptId).notifier);
    var nextSlide = 1;
    for (final b in ref.read(editorProvider(widget.scriptId)).script?.allBeats ?? const <Beat>[]) {
      if (b.id == widget.beat.id) break;
      if (b.cue?.type == CueType.slide) nextSlide = (int.tryParse(b.cue!.label ?? '') ?? nextSlide - 1) + 1;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                formatDuration(widget.timestamp),
                style: TypeScale.monoSmall.copyWith(color: focused ? p.cueText : p.inkTertiary),
              ),
            ),
          ),
          Expanded(
            child: Transform.translate(
              offset: const Offset(-14, 0),
              child: AnimatedContainer(
                duration: Motion.quick,
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                decoration: BoxDecoration(
                  color: focused ? p.raised : Colors.transparent,
                  borderRadius: Radii.rM,
                  border: Border.all(color: focused ? p.control : Colors.transparent),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.beat.cue != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, right: 10),
                        child: _CueMenu(
                          cue: widget.beat.cue!,
                          nextSlide: nextSlide,
                          onChanged: (cue) => c.setCue(widget.beat.id, cue),
                        ),
                      ),
                    Expanded(
                      child: TextField(
                        controller: _text,
                        focusNode: _focus,
                        maxLines: null,
                        style: ReadingType.editor.copyWith(color: p.inkPrimary),
                        cursorWidth: 2,
                        decoration: InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          // A hidden hint still takes layout space, so only set it when empty.
                          hintText: _text.text.isEmpty
                              ? context.l10n.beatHint
                              : null,
                          hintStyle: ReadingType.editor.copyWith(color: p.inkDisabled),
                        ),
                        onChanged: (t) => c.setBeatText(widget.beat.id, t),
                      ),
                    ),
                    if (focused && widget.beat.cue == null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8, top: 2),
                        child: _CueMenu(nextSlide: nextSlide, onChanged: (cue) => c.setCue(widget.beat.id, cue)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cue chip that opens a menu; without a cue, a small "add cue" button.
class _CueMenu extends StatelessWidget {
  const _CueMenu({this.cue, required this.onChanged, this.nextSlide = 1});
  final Cue? cue;
  final ValueChanged<Cue?> onChanged;

  /// The slide number that follows the previous slide cue in the script.
  final int nextSlide;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(p.float),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: Radii.rM,
            side: BorderSide(color: p.control),
          ),
        ),
      ),
      menuChildren: [
        MenuItemButton(
          onPressed: () => onChanged(Cue(CueType.slide, cue?.type == CueType.slide ? cue!.label : '$nextSlide')),
          child: Text(context.l10n.cueMenuSlide, style: TypeScale.body.copyWith(color: p.inkPrimary)),
        ),
        if (cue?.type == CueType.slide) ...[
          MenuItemButton(
            onPressed: () => onChanged(Cue(CueType.slide, '${(int.tryParse(cue!.label ?? '') ?? 1) + 1}')),
            child: Text(context.l10n.cueMenuSlideNext, style: TypeScale.body.copyWith(color: p.inkPrimary)),
          ),
          MenuItemButton(
            onPressed: () =>
                onChanged(Cue(CueType.slide, '${((int.tryParse(cue!.label ?? '') ?? 2) - 1).clamp(1, 999)}')),
            child: Text(context.l10n.cueMenuSlidePrev, style: TypeScale.body.copyWith(color: p.inkPrimary)),
          ),
        ],
        MenuItemButton(
          onPressed: () => onChanged(const Cue(CueType.pause)),
          child: Text(context.l10n.cueMenuPause, style: TypeScale.body.copyWith(color: p.inkPrimary)),
        ),
        MenuItemButton(
          onPressed: () => onChanged(const Cue(CueType.demo)),
          child: Text(context.l10n.cueMenuDemo, style: TypeScale.body.copyWith(color: p.inkPrimary)),
        ),
        if (cue != null)
          MenuItemButton(
            onPressed: () => onChanged(null),
            child: Text(context.l10n.cueMenuRemove, style: TypeScale.body.copyWith(color: p.liveCapture)),
          ),
      ],
      builder: (context, controller, _) => GestureDetector(
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: cue != null
              ? CueChip(cue!)
              : Tooltip(
                  message: context.l10n.addCue,
                  child: SottoIcon(SottoIcons.slide, size: 14, color: p.inkTertiary),
                ),
        ),
      ),
    );
  }
}

class _LongBeatHint extends StatelessWidget {
  const _LongBeatHint({required this.beat, required this.onIgnore, required this.onSplit});
  final Beat beat;
  final VoidCallback onIgnore;
  final VoidCallback onSplit;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final word = EditorController.breathSplitWord(beat.text);
    return Padding(
      padding: const EdgeInsets.only(left: 60, bottom: 10, top: 2),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        decoration: BoxDecoration(
          color: p.panel,
          borderRadius: Radii.rM,
          border: Border.all(color: p.control),
        ),
        child: Row(
          children: [
            SottoIcon(SottoIcons.structure, size: 14, color: p.cueText),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: context.l10n.longBeat(beat.wordCount),
                      style: TypeScale.bodyStrong.copyWith(color: p.inkPrimary),
                    ),
                    TextSpan(
                      text: word == null
                          ? context.l10n.longBeatPause
                          : context.l10n.longBeatSplitAfter(word),
                      style: TypeScale.body.copyWith(color: p.inkSecondary),
                    ),
                  ],
                ),
              ),
            ),
            SottoButton.ghost(label: context.l10n.ignore, size: ButtonSize.small, onPressed: onIgnore),
            if (word != null) ...[
              const SizedBox(width: 4),
              SottoButton(label: context.l10n.split, size: ButtonSize.small, onPressed: onSplit),
            ],
          ],
        ),
      ),
    );
  }
}

/// A borderless single-line field that looks like plain text until focused.
class _InlineField extends StatefulWidget {
  const _InlineField({super.key, required this.text, required this.style, required this.onChanged, this.placeholder});
  final String text;
  final TextStyle style;
  final ValueChanged<String> onChanged;
  final String? placeholder;

  @override
  State<_InlineField> createState() => _InlineFieldState();
}

class _InlineFieldState extends State<_InlineField> {
  late final _c = TextEditingController(text: widget.text);
  final _f = FocusNode();

  @override
  void didUpdateWidget(_InlineField old) {
    super.didUpdateWidget(old);
    if (!_f.hasFocus && widget.text != _c.text) _c.text = widget.text;
  }

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _c,
    focusNode: _f,
    style: widget.style,
    onChanged: widget.onChanged,
    decoration: InputDecoration(
      isCollapsed: true,
      border: InputBorder.none,
      hintText: widget.placeholder,
      hintStyle: widget.style.copyWith(color: context.palette.inkDisabled),
    ),
  );
}

/// "Key points — shown in Column layout and rehearsal".
class _KeyPoints extends StatefulWidget {
  const _KeyPoints({super.key, required this.points, required this.onChanged});
  final List<String> points;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_KeyPoints> createState() => _KeyPointsState();
}

class _KeyPointsState extends State<_KeyPoints> {
  late final _c = TextEditingController(text: widget.points.join('\n'));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: Radii.rM,
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(context.l10n.keyPoints, style: TypeScale.bodyStrong.copyWith(color: p.inkSecondary)),
              const Spacer(),
              Text(context.l10n.keyPointsNote, style: TypeScale.caption.copyWith(color: p.inkTertiary)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  for (var i = 0; i < _c.text.split('\n').length; i++)
                    SizedBox(
                      width: 14,
                      height: 24,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: 3,
                          height: 3,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: p.inkTertiary),
                        ),
                      ),
                    ),
                ],
              ),
              Expanded(
                child: TextField(
                  controller: _c,
                  maxLines: null,
                  style: TypeScale.body.copyWith(color: p.inkPrimary, height: 24 / 13),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: context.l10n.keyPointsHint,
                    hintStyle: TypeScale.body.copyWith(color: p.inkDisabled, height: 24 / 13),
                  ),
                  onChanged: (t) {
                    setState(() {});
                    widget.onChanged(t.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList());
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

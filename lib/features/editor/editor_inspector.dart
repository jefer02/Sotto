import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/l10n.dart';

import '../../core/design/icons.dart';
import '../../core/design/theme.dart';
import '../../core/design/typography.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/controls.dart';
import '../../core/widgets/display.dart';
import '../../data/models/script.dart';
import '../../data/repositories.dart';
import '../../domain/structuring/script_structurer.dart';
import '../live/overlay/overlay_preview.dart';
import '../live/overlay/reading_view.dart';
import 'editor_controller.dart';

class EditorInspector extends ConsumerStatefulWidget {
  const EditorInspector({super.key, required this.scriptId});
  final String scriptId;

  @override
  ConsumerState<EditorInspector> createState() => _EditorInspectorState();
}

class _EditorInspectorState extends ConsumerState<EditorInspector> {
  bool _follow = true;
  ResolvedLayout _layout = ResolvedLayout.standard;
  int _pinnedBeat = 0;
  bool _addingHint = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final e = ref.watch(editorProvider(widget.scriptId));
    final c = ref.read(editorProvider(widget.scriptId).notifier);
    final wpm = ref.watch(settingsProvider.select((s) => s.wordsPerMinute));
    final script = e.script!;
    final beats = script.allBeats.toList();
    final focusedIndex = beats.indexWhere((b) => b.id == e.focusedBeat);
    if (_follow && focusedIndex >= 0) _pinnedBeat = focusedIndex;
    final beatIndex = _pinnedBeat.clamp(0, beats.isEmpty ? 0 : beats.length - 1);

    // "Beat 3.2 · 0:06" and "Next cue: Slide 7 in 2 beats".
    var sectionNo = 0, beatNo = 0, counted = 0;
    for (var si = 0; si < script.sections.length; si++) {
      final n = script.sections[si].beats.length;
      if (beatIndex < counted + n) {
        sectionNo = si + 1;
        beatNo = beatIndex - counted + 1;
        break;
      }
      counted += n;
    }
    final beat = beats.isEmpty ? null : beats[beatIndex];
    final beatSecs = beat == null ? 0 : (beat.wordCount * 60 / wpm).round();
    int? cueIn;
    Cue? nextCue;
    for (var i = beatIndex + 1; i < beats.length; i++) {
      if (beats[i].cue != null) {
        cueIn = i - beatIndex;
        nextCue = beats[i].cue;
        break;
      }
    }

    final checks = _deliveryChecks(script);
    final hints = script.hintWords.isNotEmpty ? script.hintWords : ScriptStructurer.hintWordsFor(script.sections);

    return Container(
      width: 390,
      decoration: BoxDecoration(
        color: p.panel,
        border: Border(left: BorderSide(color: p.hairline)),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 24),
        children: [
          Row(
            children: [
              Text(context.l10n.overlayPreview, style: TypeScale.bodyStrong.copyWith(color: p.inkPrimary)),
              const Spacer(),
              Text(context.l10n.followCursor, style: TypeScale.caption.copyWith(color: p.inkTertiary)),
              const SizedBox(width: 10),
              SottoToggle(value: _follow, onChanged: (v) => setState(() => _follow = v)),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedControl<ResolvedLayout>(
            width: double.infinity,
            segments: [
              Segment(ResolvedLayout.ticker, context.l10n.layoutTicker),
              Segment(ResolvedLayout.standard, context.l10n.layoutStandard),
              Segment(ResolvedLayout.column, context.l10n.layoutColumn),
            ],
            value: _layout,
            onChanged: (v) => setState(() => _layout = v),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: _layout == ResolvedLayout.column ? 420 : 240,
            child: beats.isEmpty
                ? const SizedBox.shrink()
                : OverlayPreview(script: script, beat: beatIndex, layout: _layout),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(
                context.l10n.beatPosition(sectionNo, beatNo, formatDuration(beatSecs)),
                style: TypeScale.monoSmall.copyWith(color: p.inkTertiary),
              ),
              Text(
                nextCue == null
                    ? context.l10n.noMoreCues
                    : context.l10n.nextCueIn(cueIn!, '${nextCue.display[0]}${nextCue.display.substring(1).toLowerCase()}'),
                style: TypeScale.monoSmall.copyWith(color: p.inkTertiary),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Divider(color: p.hairline, height: 1),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(context.l10n.listenForWords, style: TypeScale.bodyStrong.copyWith(color: p.inkPrimary)),
              ),
              TextLink(context.l10n.add, onTap: () => setState(() => _addingHint = true)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.hintWordsExplain,
            style: TypeScale.caption.copyWith(color: p.inkTertiary),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final h in hints)
                GestureDetector(
                  onTap: () => c.update((s) => s.copyWith(hintWords: [...hints]..remove(h))),
                  child: Tooltip(message: context.l10n.remove, child: StatusChip(h)),
                ),
            ],
          ),
          if (_addingHint) ...[
            const SizedBox(height: 10),
            SottoTextField(
              autofocus: true,
              placeholder: context.l10n.hintWordPlaceholder,
              onSubmitted: (v) {
                final t = v.trim();
                if (t.isNotEmpty && !hints.contains(t)) c.update((s) => s.copyWith(hintWords: [...hints, t]));
                setState(() => _addingHint = false);
              },
            ),
          ],
          const SizedBox(height: 20),
          Divider(color: p.hairline, height: 1),
          const SizedBox(height: 18),
          Text(context.l10n.deliveryCheck, style: TypeScale.bodyStrong.copyWith(color: p.inkPrimary)),
          const SizedBox(height: 10),
          for (final (ok, text) in checks)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SottoIcon(ok ? SottoIcons.check : SottoIcons.alert, size: 14, color: ok ? p.confirmed : p.cueText),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(text, style: TypeScale.body.copyWith(color: p.inkSecondary)),
                  ),
                ],
              ),
            ),
          if (script.status == ScriptStatus.draft && script.wordCount > 40) ...[
            const SizedBox(height: 8),
            SottoButton(
              label: context.l10n.markAsReady,
              size: ButtonSize.small,
              icon: SottoIcons.check,
              onPressed: () => c.update((s) => s.copyWith(status: ScriptStatus.ready)),
            ),
          ],
        ],
      ),
    );
  }

  static final _abbrev = RegExp(r'[$€£]?\d+(?:\.\d+)?[MBKmbk]\b');

  List<(bool, String)> _deliveryChecks(Script s) {
    final out = <(bool, String)>[];
    var lastSlide = 0;
    var ordered = true;
    for (final b in s.allBeats) {
      if (b.cue?.type == CueType.slide) {
        final n = int.tryParse(b.cue!.label ?? '');
        if (n != null) {
          if (n < lastSlide) ordered = false;
          lastSlide = n;
        }
      }
    }
    final l = context.l10n;
    out.add((ordered, ordered ? l.checkCuesOrdered : l.checkCuesBackwards));
    final long = s.allBeats.where((b) => b.wordCount > 28).length;
    out.add((
      long == 0,
      long == 0 ? l.checkBeatsFit : l.checkLongBeats(long),
    ));
    final abbreviated = s.allBeats.where((b) => _abbrev.hasMatch(b.plainText)).length;
    out.add((
      abbreviated == 0,
      abbreviated == 0
          ? l.checkNumbersSpoken
          : l.checkNumbersAbbreviated(abbreviated),
    ));
    final empty = s.allBeats.where((b) => b.plainText.trim().isEmpty && b.cue == null).length;
    if (empty > 0) out.add((false, l.checkEmptyBeats(empty)));
    return out;
  }
}

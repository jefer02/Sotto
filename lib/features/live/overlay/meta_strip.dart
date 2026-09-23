import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';

import '../../../core/design/theme.dart';
import '../../../core/design/typography.dart';
import '../../../core/widgets/display.dart';
import '../../../data/repositories.dart';
import '../live_controller.dart';
import '../live_state.dart';

enum MetaDensity { ticker, compact, full }

/// Section · voice · pace · time. Collapses long before the script text
/// drops below 18 px.
class MetaStrip extends ConsumerWidget {
  const MetaStrip({super.key, this.density = MetaDensity.full, this.onDragStart, this.state});

  final MetaDensity density;
  final VoidCallback? onDragStart;

  /// Overrides the live session — used by previews in Settings and the editor.
  final LiveState? state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = context.overlayPalette;
    final LiveState s = state ?? ref.watch(liveControllerProvider);
    final wpm = ref.watch(settingsProvider.select((x) => x.wordsPerMinute));
    final script = s.script;
    if (script == null) return const SizedBox(height: 36);
    final section = s.section;
    final pace = s.pace(wpm);
    final planned = s.plannedSeconds(wpm);

    final label = TypeScale.captionStrong.copyWith(color: o.inkAt(0.78));
    final timer = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: formatClock(s.elapsed.inSeconds)),
          if (density != MetaDensity.ticker)
            TextSpan(
              text: ' / ${formatClock(planned)}',
              style: TextStyle(color: o.inkAt(0.5)),
            ),
        ],
      ),
      style: TypeScale.mono.copyWith(
        color: density == MetaDensity.compact && pace == PaceStatus.onPace ? o.confirmed : o.inkAt(0.8),
      ),
    );

    final noticeOrPace = s.notice != null
        ? Flexible(
            child: Text(
              s.notice!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TypeScale.captionStrong.copyWith(color: o.inkAt(0.7)),
            ),
          )
        : _PaceLabel(state: s, pace: pace);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: onDragStart == null ? null : (_) => onDragStart!(),
      child: SizedBox(
        height: 36,
        child: Padding(
          padding: const EdgeInsets.only(left: 16, right: 14),
          child: Row(
            children: [
              if (density == MetaDensity.ticker) ...[
                Text(
                  '${s.sectionIndex + 1}/${script.sections.length}',
                  style: TypeScale.mono.copyWith(fontSize: 11, color: o.inkAt(0.6)),
                ),
                const SizedBox(width: 8),
              ] else ...[
                SectionProgress(state: s),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(section?.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: label),
              ),
              if (density == MetaDensity.full) ...[
                VoiceGlyph(state: s),
                const SizedBox(width: 12),
                noticeOrPace,
                const SizedBox(width: 12),
              ] else if (density == MetaDensity.compact) ...[
                VoiceGlyph(state: s),
                const SizedBox(width: 10),
              ],
              timer,
            ],
          ),
        ),
      ),
    );
  }
}

/// Seven 10 × 3 hairlines: done sections bright, the current one with a
/// tungsten fill for how far into it you are.
class SectionProgress extends StatelessWidget {
  const SectionProgress({super.key, required this.state, this.vertical = false});

  final LiveState state;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final o = context.overlayPalette;
    final flat = state.flat;
    final script = state.script;
    if (flat == null || script == null) return const SizedBox.shrink();
    final current = state.sectionIndex;
    final first = flat.sectionFirstBeat[current];
    final count = script.sections[current].beats.length;
    final within = count == 0 ? 0.0 : ((state.position.beat - first) / count).clamp(0.0, 1.0);

    Widget seg(int i) {
      final done = i < current;
      final bar = Container(
        width: vertical ? 3 : 10,
        height: vertical ? 22 : 3,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: o.inkAt(done ? 0.62 : 0.16)),
        child: i == current
            ? Align(
                alignment: vertical ? Alignment.topCenter : Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: vertical ? 1 : (0.15 + within * 0.85),
                  heightFactor: vertical ? (0.15 + within * 0.85) : 1,
                  child: Container(
                    decoration: BoxDecoration(color: o.cue, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
              )
            : null,
      );
      return Padding(
        padding: vertical ? const EdgeInsets.only(bottom: 4) : const EdgeInsets.only(right: 3),
        child: bar,
      );
    }

    final children = [for (var i = 0; i < script.sections.length && i < 12; i++) seg(i)];
    return vertical
        ? Column(mainAxisSize: MainAxisSize.min, children: children)
        : Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

/// Three small bars that move with the presenter's voice; two bars when
/// paused. Never colored — it's status, not a signal.
class VoiceGlyph extends StatelessWidget {
  const VoiceGlyph({super.key, required this.state});
  final LiveState state;

  @override
  Widget build(BuildContext context) {
    final o = context.overlayPalette;
    final paused = state.phase == LivePhase.paused;
    final l = state.following && !state.manualMode ? state.voiceLevel : 0.0;
    final heights = paused ? [9.0, 9.0] : [4 + 4 * l, 5 + 7 * l, 4 + 5 * l];
    return Tooltip(
      message: paused
          ? context.l10n.paused
          : state.manualMode
          ? context.l10n.hotkeysOnly
          : context.l10n.followingYourVoice,
      child: SizedBox(
        height: 12,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (final h in heights)
              AnimatedContainer(
                duration: const Duration(milliseconds: 90),
                width: 2,
                height: h.clamp(2.0, 12.0),
                margin: EdgeInsets.only(right: paused ? 3 : 2),
                decoration: BoxDecoration(color: o.inkAt(0.6), borderRadius: BorderRadius.circular(1)),
              ),
          ],
        ),
      ),
    );
  }
}

class _PaceLabel extends StatelessWidget {
  const _PaceLabel({required this.state, required this.pace});
  final LiveState state;
  final PaceStatus pace;

  @override
  Widget build(BuildContext context) {
    final o = context.overlayPalette;
    final style = TypeScale.captionStrong.copyWith(color: o.inkAt(0.62));
    if (state.phase == LivePhase.standby) return Text(context.l10n.standby, style: style);
    if (state.phase == LivePhase.paused) return Text(context.l10n.paused, style: style);
    return switch (pace) {
      PaceStatus.onPace => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(shape: BoxShape.circle, color: o.confirmed),
          ),
          const SizedBox(width: 6),
          Text(context.l10n.onPace, style: style),
        ],
      ),
      PaceStatus.ahead => Text(context.l10n.ahead, style: style),
      PaceStatus.behind => Text(context.l10n.behind, style: style),
      PaceStatus.holding => Text(context.l10n.holding, style: style),
    };
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../core/widgets/display.dart';
import '../../data/models/session_record.dart';
import '../../l10n/l10n.dart';

/// What happened on one calendar day.
class PracticeDay {
  PracticeDay(this.date);

  /// Local midnight.
  final DateTime date;
  int rehearsals = 0;
  int live = 0;
  int seconds = 0;

  bool get empty => rehearsals == 0 && live == 0;
}

/// [sessions] bucketed into the [days] local calendar days ending on [now]'s
/// day, oldest first. Agent-only records aren't practice and are left out.
List<PracticeDay> practiceDays(List<SessionRecord> sessions, {required int days, required DateTime now}) {
  final out = [for (var i = days - 1; i >= 0; i--) PracticeDay(DateTime(now.year, now.month, now.day - i))];
  // Count days in UTC so a daylight-saving change can't make one 23 hours long.
  final first = DateTime.utc(out.first.date.year, out.first.date.month, out.first.date.day);
  for (final s in sessions) {
    if (s.agentOnly) continue;
    final t = s.startedAt.toLocal();
    final i = DateTime.utc(t.year, t.month, t.day).difference(first).inDays;
    if (i < 0 || i >= days) continue;
    final day = out[i];
    if (s.rehearsal) {
      day.rehearsals++;
    } else {
      day.live++;
    }
    day.seconds += s.durationSeconds;
  }
  return out;
}

/// One bar per day for the last [days] days, lit on the days you rehearsed
/// or ran the talk live. Hover a bar, or focus the strip and use the arrow
/// keys, to see that day. Adapted from ObsidianUI's Status Bars (MIT,
/// obsidianui.dev).
class PracticeBars extends StatefulWidget {
  const PracticeBars({super.key, required this.sessions, this.days = 30, this.now});

  final List<SessionRecord> sessions;
  final int days;

  /// Overrides the clock — for tests.
  final DateTime? now;

  @override
  State<PracticeBars> createState() => _PracticeBarsState();
}

class _PracticeBarsState extends State<PracticeBars> with SingleTickerProviderStateMixin {
  static const _barHeight = 32.0;
  static const _tipWidth = 184.0;

  // The bars rise left to right once, when the strip first appears.
  late final _enter = AnimationController(vsync: this, duration: Motion.settle);
  final _focus = FocusNode(debugLabel: 'PracticeBars');

  int? _selected;

  // The last day shown, so the tooltip can fade out in place.
  int _tip = 0;
  bool _focused = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _enter.value = 1;
    } else if (_enter.isDismissed) {
      _enter.forward();
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _select(int? i) {
    if (i == _selected) return;
    setState(() {
      _selected = i;
      if (i != null) _tip = i;
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final last = widget.days - 1;
    final at = _selected ?? last;
    final next = switch (e.logicalKey) {
      LogicalKeyboardKey.arrowLeft => (at - 1).clamp(0, last),
      LogicalKeyboardKey.arrowRight => (at + 1).clamp(0, last),
      LogicalKeyboardKey.home => 0,
      LogicalKeyboardKey.end => last,
      _ => null,
    };
    if (next == null) {
      if (e.logicalKey != LogicalKeyboardKey.escape || _selected == null) return KeyEventResult.ignored;
      _select(null);
      return KeyEventResult.handled;
    }
    _select(next);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    final days = practiceDays(widget.sessions, days: widget.days, now: widget.now ?? DateTime.now());
    final practiced = days.where((d) => !d.empty).length;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    Color colorOf(PracticeDay d) => d.live > 0
        ? p.cueFill
        : d.rehearsals > 0
        ? p.confirmed
        : p.inkPrimary.withValues(alpha: p.isDark ? 0.08 : 0.07);

    Widget legend(Color c, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 6),
        Text(label, style: TypeScale.caption.copyWith(color: p.inkTertiary)),
      ],
    );

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        // Counts up from the old value whenever the range changes.
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: practiced.toDouble()),
          duration: still ? Duration.zero : Motion.settle,
          curve: Motion.glideEnter,
          builder: (context, v, _) =>
              Text(l.practiceDaysCount(v.round()), style: TypeScale.bodyStrong.copyWith(color: p.inkPrimary)),
        ),
        const SizedBox(width: 8),
        Text(l.practiceBarsTitle(widget.days), style: TypeScale.caption.copyWith(color: p.inkTertiary)),
      ],
    );

    final strip = LayoutBuilder(
      builder: (context, box) {
        final slot = box.maxWidth / widget.days;
        final tipLeft = (slot * (_tip + 0.5) - _tipWidth / 2).clamp(
          0.0,
          (box.maxWidth - _tipWidth).clamp(0.0, double.infinity),
        );
        return Stack(
          clipBehavior: Clip.none,
          children: [
            MouseRegion(
              onExit: (_) {
                if (!_focused) _select(null);
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (e) => _select((e.localPosition.dx / slot).floor().clamp(0, widget.days - 1)),
                child: SizedBox(
                  height: _barHeight,
                  child: AnimatedBuilder(
                    animation: _enter,
                    builder: (context, _) => Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < days.length; i++)
                          Expanded(
                            child: MouseRegion(
                              onEnter: (_) => _select(i),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 1),
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: FractionallySizedBox(
                                    widthFactor: 1,
                                    heightFactor: Interval(
                                      0.5 * i / days.length,
                                      0.5 + 0.5 * i / days.length,
                                      curve: Motion.glideEnter,
                                    ).transform(_enter.value),
                                    child: AnimatedOpacity(
                                      duration: Motion.quick,
                                      opacity: _selected == null || _selected == i ? 1 : 0.62,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: colorOf(days[i]),
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            AnimatedPositioned(
              duration: still ? Duration.zero : Motion.smooth,
              curve: Motion.glideEnter,
              left: tipLeft,
              bottom: _barHeight + 8,
              width: _tipWidth,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  duration: still ? Duration.zero : Motion.snappy,
                  opacity: _selected == null ? 0 : 1,
                  child: _DayTip(day: days[_tip.clamp(0, days.length - 1)]),
                ),
              ),
            ),
          ],
        );
      },
    );

    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f && _selected == null) _select(widget.days - 1);
        if (!f) _select(null);
      },
      child: Semantics(
        label: '${l.practiceBarsTitle(widget.days)}: ${l.practiceDaysCount(practiced)}',
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          decoration: BoxDecoration(
            color: p.panel,
            borderRadius: Radii.rL,
            border: Border.all(color: _focused ? p.focusRing : p.hairline, width: _focused ? 2 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: 12),
              strip,
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(l.practiceRangeStart(widget.days - 1), style: TypeScale.caption.copyWith(color: p.inkTertiary)),
                  const Spacer(),
                  legend(p.confirmed, l.practiceLegendRehearsal),
                  const SizedBox(width: 14),
                  legend(p.cueFill, l.practiceLegendLive),
                  const Spacer(),
                  Text(l.practiceToday, style: TypeScale.caption.copyWith(color: p.inkTertiary)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayTip extends StatelessWidget {
  const _DayTip({required this.day});
  final PracticeDay day;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    final line = TypeScale.caption.copyWith(color: p.inkSecondary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: p.float,
        borderRadius: Radii.rM,
        border: Border.all(color: p.control),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: p.isDark ? 0.4 : 0.12),
            blurRadius: 14,
            spreadRadius: -4,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat.MMMEd(l.localeName).format(day.date),
            style: TypeScale.captionStrong.copyWith(color: p.inkPrimary),
          ),
          const SizedBox(height: 4),
          if (day.empty)
            Text(l.practiceDayEmpty, style: line.copyWith(color: p.inkTertiary))
          else ...[
            if (day.rehearsals > 0) Text(l.practiceDayRehearsals(day.rehearsals), style: line),
            if (day.live > 0) Text(l.practiceDayLive(day.live), style: line),
            const SizedBox(height: 2),
            Text(formatDuration(day.seconds), style: TypeScale.monoSmall.copyWith(color: p.inkTertiary)),
          ],
        ],
      ),
    );
  }
}

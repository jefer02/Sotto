import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../l10n/l10n.dart';

import '../../../core/design/icons.dart';
import '../../../core/design/theme.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/typography.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/display.dart';
import '../../../core/widgets/keycap.dart';
import '../../../data/models/qa_entry.dart';
import '../../../data/models/shortcut.dart';
import '../../../data/repositories.dart';
import '../live_controller.dart';
import '../live_state.dart';

// ─────────────────────────── Listening ───────────────────────────

/// Red means the mic is capturing the room — and only then.
class ListeningView extends ConsumerWidget {
  const ListeningView({super.key, required this.state});
  final LiveState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = context.overlayPalette;
    final settings = ref.watch(settingsProvider);
    final q = state.question;
    final elapsed = q?.elapsed.inSeconds ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 20,
            child: Row(
              children: [
                _TallyDot(silence: q?.silence ?? 0),
                const SizedBox(width: 10),
                Text(
                  context.l10n.listening,
                  style: withWeight(TypeScale.caption, 600).copyWith(color: o.capture, letterSpacing: 0.12),
                ),
                const SizedBox(width: 10),
                Text(
                  '${elapsed ~/ 60}:${(elapsed % 60).toString().padLeft(2, '0')}',
                  style: TypeScale.mono.copyWith(fontWeight: FontWeight.w400, color: o.inkAt(0.6)),
                ),
                const Spacer(),
                _KeyAction(
                  shortcut: settings.shortcutFor(LiveAction.ask),
                  label: context.l10n.done,
                  onTap: () => ref.read(liveControllerProvider.notifier).finishQuestion(),
                ),
                const SizedBox(width: 12),
                _KeyAction(
                  shortcut: settings.shortcutFor(LiveAction.dismiss),
                  label: context.l10n.cancel,
                  onTap: () => ref.read(liveControllerProvider.notifier).cancelQuestion(),
                ),
              ],
            ),
          ),
          if (state.screenAttached) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                SottoIcon(SottoIcons.display, size: 12, color: o.inkAt(0.6)),
                const SizedBox(width: 6),
                Text(context.l10n.screenshotAttached, style: TypeScale.caption.copyWith(color: o.inkAt(0.6))),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Expanded(child: _StreamedQuestion(text: q?.text ?? '')),
          SizedBox(
            height: 28,
            child: _Waveform(level: state.voiceLevel, color: o.capture),
          ),
        ],
      ),
    );
  }
}

class _KeyAction extends StatelessWidget {
  const _KeyAction({required this.shortcut, required this.label, required this.onTap});
  final Shortcut shortcut;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final o = context.overlayPalette;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            KeyCombo(shortcut, tone: KeycapTone.overlay, merged: true),
            const SizedBox(width: 6),
            Text(
              label,
              style: TypeScale.micro.copyWith(fontWeight: FontWeight.w400, color: o.inkAt(0.6)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tally dot with the silence ring: after speech stops, a ring fills around
/// the dot; talking again resets it.
class _TallyDot extends StatelessWidget {
  const _TallyDot({required this.silence});
  final double silence;

  @override
  Widget build(BuildContext context) {
    final o = context.overlayPalette;
    return SizedBox(
      width: 16,
      height: 16,
      child: CustomPaint(
        painter: _RingPainter(progress: silence, color: o.capture, track: o.capture.withValues(alpha: 0.18)),
        child: Center(
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: o.capture,
              boxShadow: [BoxShadow(color: o.capture.withValues(alpha: 0.14), spreadRadius: 3)],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.color, required this.track});
  final double progress;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect.deflate(1), 0, math.pi * 2, false, paint..color = track);
    canvas.drawArc(rect.deflate(1), -math.pi / 2, math.pi * 2 * progress, false, paint..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.color != color;
}

/// Question words stream in, each with a 120 ms fade and a 4 px rise; the
/// newest words — still being recognized — stay a step dimmer.
class _StreamedQuestion extends StatelessWidget {
  const _StreamedQuestion({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final o = context.overlayPalette;
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final style = ReadingType.question.copyWith(color: o.ink, shadows: o.textShadows());
    if (words.isEmpty) {
      return Text(context.l10n.askAway, style: style.copyWith(color: o.inkAt(0.36)));
    }
    return SingleChildScrollView(
      reverse: true,
      child: Wrap(
        children: [
          for (var i = 0; i < words.length; i++)
            _WordIn(
              key: ValueKey(i),
              child: Text('${words[i]} ', style: style.copyWith(color: i >= words.length - 2 ? o.inkAt(0.55) : o.ink)),
            ),
        ],
      ),
    );
  }
}

class _WordIn extends StatelessWidget {
  const _WordIn({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 120),
    curve: Motion.glideEnter,
    builder: (context, t, child) => Opacity(
      opacity: t,
      child: Transform.translate(offset: Offset(0, 4 * (1 - t)), child: child),
    ),
    child: child,
  );
}

/// Question level: a scrolling history of the room's level in tally red.
class _Waveform extends StatefulWidget {
  const _Waveform({required this.level, required this.color});
  final double level;
  final Color color;

  @override
  State<_Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<_Waveform> with SingleTickerProviderStateMixin {
  final _history = List<double>.filled(96, 0);
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      if (elapsed - _last < const Duration(milliseconds: 40)) return;
      _last = elapsed;
      setState(() {
        _history.removeAt(0);
        // A little jitter keeps quiet passages from looking frozen.
        _history.add((widget.level + math.Random().nextDouble() * 0.08 * widget.level).clamp(0, 1));
      });
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.infinite, painter: _WavePainter(List.of(_history), widget.color));
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.levels, this.color);
  final List<double> levels;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final step = size.width / levels.length;
    final paint = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final mid = size.height / 2;
    for (var i = 0; i < levels.length; i++) {
      final l = levels[i];
      final h = math.max(1.0, l * l * size.height);
      final age = i / levels.length;
      paint.color = color.withValues(alpha: 0.2 + 0.8 * age);
      final x = i * step + step / 2;
      canvas.drawLine(Offset(x, mid - h / 2), Offset(x, mid + h / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => true;
}

// ─────────────────────────── Drafting ───────────────────────────

/// Sources before sentences: which sections and documents are being used
/// appears before any words, so trust is built before the answer is read.
class DraftingView extends StatelessWidget {
  const DraftingView({super.key, required this.state});
  final LiveState state;

  @override
  Widget build(BuildContext context) {
    final o = context.overlayPalette;
    final sources = state.draft?.sources ?? const <SourceRef>[];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _DraftingDots(color: o.cue),
              const SizedBox(width: 8),
              Text(
                sources.isEmpty ? context.l10n.transcribingQuestion : context.l10n.draftingFrom,
                style: TypeScale.captionStrong.copyWith(color: o.inkAt(0.7)),
              ),
            ],
          ),
          if ((state.questionText ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '“${state.questionText}”',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: ReadingType.answerQuote.copyWith(color: o.inkAt(0.62)),
            ),
          ],
          if (sources.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < sources.length; i++)
                  _StaggerIn(index: i, child: SourceChip(sources[i], overlay: true)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DraftingDots extends StatefulWidget {
  const _DraftingDots({required this.color});
  final Color color;

  @override
  State<_DraftingDots> createState() => _DraftingDotsState();
}

class _DraftingDotsState extends State<_DraftingDots> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) => Row(
      children: [
        for (var i = 0; i < 3; i++)
          Container(
            width: 4,
            height: 4,
            margin: const EdgeInsets.only(right: 3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withValues(
                alpha: 0.3 + 0.7 * (0.5 + 0.5 * math.sin((_c.value - i / 3) * math.pi * 2)),
              ),
            ),
          ),
      ],
    ),
  );
}

// ─────────────────────────── Answer ───────────────────────────

/// Headline first, points after. Actions appear only when streaming ends,
/// so a mid-stream key press can never send half an answer.
class AnswerView extends ConsumerWidget {
  const AnswerView({super.key, required this.state, this.onMeasured});

  final LiveState state;

  /// Reports the content's natural height so the window can grow to fit.
  final ValueChanged<double>? onMeasured;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = context.overlayPalette;
    final d = state.draft;
    final error = state.answerError;
    final showSources = ref.watch(settingsProvider.select((s) => s.showSources));

    final body = Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (error != null) ...[
            Row(
              children: [
                SottoIcon(SottoIcons.alert, size: 13, color: o.inkAt(0.7)),
                const SizedBox(width: 6),
                Text(context.l10n.noAnswerDrafted, style: TypeScale.captionStrong.copyWith(color: o.inkAt(0.7))),
              ],
            ),
            const SizedBox(height: 10),
            Text(error, style: ReadingType.answerPoint.copyWith(color: o.inkAt(0.85))),
          ] else if (d != null) ...[
            Row(
              children: [
                if (d.notInNotes)
                  _Provenance(icon: SottoIcons.info, label: context.l10n.provNotInNotes, color: o.inkAt(0.7))
                else if (d.grounded)
                  _Provenance(
                    icon: SottoIcons.check,
                    label: d.predrafted ? context.l10n.provFromPrep : context.l10n.provFromScript,
                    color: o.confirmed,
                  )
                else
                  _Provenance(icon: SottoIcons.globe, label: context.l10n.provGeneral, color: o.inkAt(0.7)),
                const Spacer(),
                if (d.complete)
                  Text(
                    d.predrafted
                        ? context.l10n.predraftedInstant
                        : context.l10n.draftedIn(
                            NumberFormat('0.0', context.l10n.localeName).format((state.draftMillis ?? 0) / 1000),
                          ),
                    style: TypeScale.mono.copyWith(fontSize: 11, fontWeight: FontWeight.w400, color: o.inkAt(0.55)),
                  ),
              ],
            ),
            if ((state.questionText ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '“${state.questionText}”',
                style: ReadingType.answerQuote.copyWith(color: o.inkAt(0.62), shadows: o.textShadows(0.62)),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              d.headline,
              style: ReadingType.answerHeadline.copyWith(color: o.ink, shadows: o.textShadows()),
            ),
            if (d.points.isNotEmpty) const SizedBox(height: 12),
            for (var i = 0; i < d.points.length; i++)
              _StaggerIn(
                index: i,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 10, right: 12),
                        child: Container(
                          width: 8,
                          height: 2,
                          decoration: BoxDecoration(
                            color: o.cue.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: d.points[i].lead,
                                style: withWeight(
                                  ReadingType.answerPoint,
                                  600,
                                ).copyWith(color: o.ink, shadows: o.textShadows()),
                              ),
                              if (d.points[i].rest.isNotEmpty) TextSpan(text: ' ${d.points[i].rest}'),
                            ],
                          ),
                          style: ReadingType.answerPoint.copyWith(color: o.inkAt(0.74), shadows: o.textShadows(0.74)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (showSources && d.sources.isNotEmpty && d.complete) ...[
              const SizedBox(height: 7),
              Wrap(spacing: 6, runSpacing: 6, children: [for (final s in d.sources) SourceChip(s, overlay: true)]),
            ],
          ],
        ],
      ),
    );

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: onMeasured == null ? body : _MeasureSize(onChange: onMeasured!, child: body),
          ),
        ),
        AnimatedSwitcher(
          duration: Motion.smooth,
          child: (d?.complete ?? false) || error != null
              ? _AnswerActions(key: const ValueKey('actions'), state: state)
              : const SizedBox(key: ValueKey('none'), height: 0),
        ),
      ],
    );
  }
}

class _Provenance extends StatelessWidget {
  const _Provenance({required this.icon, required this.label, required this.color});
  final SottoIcons icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SottoIcon(icon, size: 13, color: color),
      const SizedBox(width: 6),
      Text(label, style: TypeScale.captionStrong.copyWith(color: color)),
    ],
  );
}

class _AnswerActions extends ConsumerWidget {
  const _AnswerActions({super.key, required this.state});
  final LiveState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = context.overlayPalette;
    final c = ref.read(liveControllerProvider.notifier);
    final settings = ref.watch(settingsProvider);
    final hasAnswer = state.currentQa != null;
    final sent = state.currentQa?.outcome == AnswerOutcome.sentToChat;

    // Narrow overlays keep the keycap only on Send, where the hold matters.
    final wide = MediaQuery.sizeOf(context).width >= 640;
    return Container(
      height: 50,
      padding: const EdgeInsets.only(left: 11, right: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: o.inkAt(0.08))),
      ),
      child: Row(
        children: [
          if (hasAnswer)
            // Hold to send: posting to the audience is irreversible.
            GestureDetector(
              onTapDown: (_) => c.sendDown(),
              onTapUp: (_) => c.sendUp(),
              onTapCancel: c.sendUp,
              child: Stack(
                children: [
                  IgnorePointer(
                    child: SottoButton(
                      label: sent ? context.l10n.outcomeCopied : context.l10n.copyForChat,
                      icon: sent ? SottoIcons.check : SottoIcons.send,
                      variant: ButtonVariant.overlay,
                      shortcut: settings.shortcutFor(LiveAction.sendToChat),
                      onPressed: () {},
                    ),
                  ),
                  if (state.sendHold > 0)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: state.sendHold,
                            child: Container(
                              decoration: BoxDecoration(
                                color: o.cue.withValues(alpha: 0.18),
                                borderRadius: Radii.rControl,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(width: 2),
          if (hasAnswer)
            _GhostOverlayButton(
              icon: SottoIcons.speaker,
              label: context.l10n.readAloud,
              shortcut: wide ? settings.shortcutFor(LiveAction.readAloud) : null,
              onTap: () => c.readAloud(),
            ),
          _GhostOverlayButton(
            icon: SottoIcons.close,
            label: context.l10n.dismiss,
            shortcut: wide ? settings.shortcutFor(LiveAction.dismiss) : null,
            onTap: c.dismiss,
          ),
          const Spacer(),
          if (hasAnswer) ...[
            SottoIconButton(
              icon: SottoIcons.refresh,
              tooltip: context.l10n.draftAgain,
              overlay: true,
              iconSize: 13,
              size: 26,
              onPressed: () => c.redraft(),
            ),
            SottoIconButton(
              icon: SottoIcons.copy,
              tooltip: context.l10n.copyAnswer,
              overlay: true,
              iconSize: 13,
              size: 26,
              onPressed: () => c.copyCurrent(),
            ),
          ],
        ],
      ),
    );
  }
}

class _GhostOverlayButton extends StatelessWidget {
  const _GhostOverlayButton({required this.icon, required this.label, required this.onTap, this.shortcut});
  final SottoIcons icon;
  final String label;
  final Shortcut? shortcut;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final o = context.overlayPalette;
    return TextButton(
      onPressed: onTap,
      style: ButtonStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 9)),
        minimumSize: const WidgetStatePropertyAll(Size(0, 30)),
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: Radii.rM)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.hovered) ? o.inkAt(0.06) : Colors.transparent,
        ),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SottoIcon(icon, size: 14, color: o.inkAt(0.88)),
          const SizedBox(width: 8),
          Text(label, style: TypeScale.captionStrong.copyWith(color: o.inkAt(0.88))),
          if (shortcut != null) ...[
            const SizedBox(width: 8),
            KeyCombo(shortcut!, tone: KeycapTone.overlay, merged: true),
          ],
        ],
      ),
    );
  }
}

/// Points stagger in 120 ms apart.
class _StaggerIn extends StatefulWidget {
  const _StaggerIn({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<_StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends State<_StaggerIn> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: Motion.smooth);

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(Motion.answerPointStagger * widget.index, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, child) {
      final t = Motion.glideEnter.transform(_c.value);
      return Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 4 * (1 - t)), child: child),
      );
    },
    child: widget.child,
  );
}

class _MeasureSize extends StatefulWidget {
  const _MeasureSize({required this.onChange, required this.child});
  final ValueChanged<double> onChange;
  final Widget child;

  @override
  State<_MeasureSize> createState() => _MeasureSizeState();
}

class _MeasureSizeState extends State<_MeasureSize> {
  double? _last;

  @override
  Widget build(BuildContext context) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final box = context.findRenderObject() as RenderBox?;
      if (!mounted || box == null || !box.hasSize) return;
      final h = box.size.height;
      if (_last == null || (h - _last!).abs() > 4) {
        _last = h;
        widget.onChange(h);
      }
    });
    return widget.child;
  }
}

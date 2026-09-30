import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/icons.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../core/platform/window_service.dart';
import '../../core/widgets/buttons.dart';
import '../../data/models/shortcut.dart';
import '../../data/repositories.dart';
import '../../domain/forms/autofill_watcher.dart' show HoldToConfirm;
import '../../domain/forms/question_types.dart';
import '../../l10n/l10n.dart';
import '../agent/agent_view.dart';
import '../questionnaire/questionnaire_controller.dart';
import '../questionnaire/questionnaire_view.dart';
import 'autofill_controller.dart';

/// A question type in words.
String questionTypeLabel(AppLocalizations l, QuestionType t) => switch (t) {
  QuestionType.text => l.qtText,
  QuestionType.longText => l.qtLongText,
  QuestionType.multipleChoice => l.qtMultipleChoice,
  QuestionType.trueFalse => l.qtTrueFalse,
  QuestionType.checkboxes => l.qtCheckboxes,
  QuestionType.dropdown => l.qtDropdown,
  QuestionType.scale => l.qtScale,
  QuestionType.matching => l.qtMatching,
  QuestionType.ordering => l.qtOrdering,
  QuestionType.imageChoice => l.qtImageChoice,
  QuestionType.readOnly => l.qtReadOnly,
};

/// The overlay's persistent auto-fill status bar:
/// "● Auto-fill ON  [Pause] [Stop]", "⏸ Paused  [Resume]", or while a
/// cycle runs "Filling… 4/9 — question  [Stop now]". The log of answers
/// opens below it.
class AutoFillBar extends ConsumerStatefulWidget {
  const AutoFillBar({super.key, this.standalone = false});

  /// Outside a live session: offers "Open Sotto".
  final bool standalone;

  @override
  ConsumerState<AutoFillBar> createState() => _AutoFillBarState();
}

class _AutoFillBarState extends ConsumerState<AutoFillBar> {
  bool _logOpen = false;

  @override
  Widget build(BuildContext context) {
    final o = context.overlayPalette;
    final l = context.l10n;
    final a = ref.watch(autoFillControllerProvider);
    final c = ref.read(autoFillControllerProvider.notifier);
    final q = ref.watch(questionnaireControllerProvider);
    final stopKeys = ref.watch(settingsProvider).shortcutFor(LiveAction.agentStop);
    final amber = AgentView.controlColor;
    final filling = a.status == AutoFillStatus.filling || q.inControl;

    String label;
    Color dot;
    if (a.countdown > 0) {
      label = l.autofillCountdown(a.countdown);
      dot = amber;
    } else if (filling) {
      final done = q.items.where((i) => i.status == ItemStatus.filled || i.status == ItemStatus.failed).length;
      final current = q.current != null && q.current! < q.items.length ? q.items[q.current!].question : '';
      label = l.autofillFilling(
        math.min(done + 1, math.max(1, q.fillableCount)),
        q.fillableCount,
        _truncate(current, 40),
      );
      dot = amber;
    } else if (a.status == AutoFillStatus.paused) {
      label = '⏸ ${l.autofillPaused}';
      dot = o.inkAt(0.5);
    } else if (a.on) {
      label = l.autofillOn;
      dot = o.confirmed;
    } else {
      label = a.message ?? '';
      dot = o.inkAt(0.4);
    }

    final bar = Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: o.textOnly ? o.chromeGround : o.inkAt(0.06),
        borderRadius: BorderRadius.circular(9),
        // The "Sotto is filling" indicator: an amber frame while a cycle runs.
        border: Border.all(color: filling ? amber : o.inkAt(0.12), width: filling ? 1.5 : 1),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TypeScale.caption.copyWith(color: o.ink, fontWeight: FontWeight.w600, shadows: const []),
            ),
          ),
          if (filling)
            SottoButton(
              label: l.autofillStopNow,
              icon: SottoIcons.stop,
              variant: ButtonVariant.overlay,
              size: ButtonSize.small,
              shortcut: stopKeys,
              onPressed: c.emergencyStop,
            )
          else if (a.status == AutoFillStatus.paused)
            SottoButton(
              label: l.autofillResume,
              icon: SottoIcons.play,
              variant: ButtonVariant.overlay,
              size: ButtonSize.small,
              onPressed: c.resume,
            )
          else if (a.on)
            SottoButton(
              label: l.autofillPause,
              icon: SottoIcons.pause,
              variant: ButtonVariant.overlay,
              size: ButtonSize.small,
              onPressed: c.pause,
            ),
          if (a.on) ...[const SizedBox(width: 6), HoldToStopButton(onConfirmed: c.stop)],
          const SizedBox(width: 4),
          _IconToggle(
            icon: SottoIcons.history,
            tooltip: l.autofillLog,
            active: _logOpen,
            onTap: () => setState(() => _logOpen = !_logOpen),
          ),
          if (widget.standalone)
            _IconToggle(
              icon: SottoIcons.display,
              tooltip: l.autofillOpenSotto,
              onTap: () => unawaited(c.openMainWindow()),
            ),
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        bar,
        if (a.message != null && !filling && a.on) ...[
          const SizedBox(height: 4),
          Text(
            a.message!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TypeScale.caption.copyWith(color: o.inkAt(0.8)),
          ),
        ],
        if (_logOpen) ...[const SizedBox(height: 6), const SizedBox(height: 160, child: AutoFillLog())],
      ],
    );
  }

  static String _truncate(String s, int n) => s.length <= n ? s : '${s.substring(0, n - 1)}…';
}

class _IconToggle extends StatelessWidget {
  const _IconToggle({required this.icon, required this.tooltip, required this.onTap, this.active = false});
  final SottoIcons icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final o = context.overlayPalette;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 16,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: SottoIcon(icon, size: 14, color: active ? o.cue : o.inkAt(0.7)),
        ),
      ),
    );
  }
}

/// "Stop" that only stops after a one-second hold ([HoldToConfirm]), with
/// the countdown drawn as a ring filling round the button.
class HoldToStopButton extends StatefulWidget {
  const HoldToStopButton({super.key, required this.onConfirmed});
  final VoidCallback onConfirmed;

  @override
  State<HoldToStopButton> createState() => _HoldToStopButtonState();
}

class _HoldToStopButtonState extends State<HoldToStopButton> with SingleTickerProviderStateMixin {
  final _hold = HoldToConfirm();

  // The hold is timed on the ticker's clock (frame time, fake in tests).
  static final _base = DateTime(2000);
  Duration _elapsed = Duration.zero;
  late final Ticker _ticker = createTicker((elapsed) {
    _elapsed = elapsed;
    _tick();
  });
  double _progress = 0;

  DateTime get _now => _base.add(_elapsed);

  void _tick() {
    final p = _hold.progress(_now);
    setState(() => _progress = p);
    if (p >= 1) {
      _ticker.stop();
      _hold.cancel();
      setState(() => _progress = 0);
      widget.onConfirmed();
    }
  }

  void _down() {
    _elapsed = Duration.zero;
    _hold.press(_base);
    if (!_ticker.isActive) unawaited(_ticker.start());
  }

  void _up() {
    if (_hold.holding && _hold.release(_now)) widget.onConfirmed();
    _ticker.stop();
    setState(() => _progress = 0);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final o = context.overlayPalette;
    final l = context.l10n;
    return Tooltip(
      message: l.autofillHoldToStop,
      child: Listener(
        onPointerDown: (_) => _down(),
        onPointerUp: (_) => _up(),
        onPointerCancel: (_) => _up(),
        child: CustomPaint(
          foregroundPainter: _RingPainter(_progress, o.capture),
          child: Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: o.capture.withValues(alpha: 0.12 + 0.3 * _progress),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: o.capture.withValues(alpha: 0.6)),
            ),
            child: Text(
              _progress > 0 ? '${(1 - _progress).toStringAsFixed(1)} s' : l.autofillStop,
              style: TypeScale.micro.copyWith(color: o.capture, fontWeight: FontWeight.w700, shadows: const []),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.color);
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(7));
    final path = Path()..addRRect(r);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final m in path.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * progress), paint);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.color != color;
}

/// Every completed answer: question → answer, and the one-line why.
class AutoFillLog extends ConsumerWidget {
  const AutoFillLog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = context.overlayPalette;
    final l = context.l10n;
    final log = ref.watch(autoFillControllerProvider.select((a) => a.log));
    if (log.isEmpty) {
      return Center(
        child: Text(l.autofillLogEmpty, style: TypeScale.caption.copyWith(color: o.inkAt(0.55))),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: o.textOnly ? o.chromeGround : o.inkAt(0.04),
        borderRadius: BorderRadius.circular(9),
      ),
      child: ListView.separated(
        reverse: true,
        padding: const EdgeInsets.all(8),
        itemCount: log.length,
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (context, i) {
          final e = log[log.length - 1 - i];
          final failed = e.status == ItemStatus.failed || e.status == ItemStatus.blocked;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                e.question.length > 70 ? '${e.question.substring(0, 69)}…' : e.question,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TypeScale.micro.copyWith(color: o.inkAt(0.6), shadows: const []),
              ),
              Text(
                '→ ${e.answer}${failed && e.note.isNotEmpty ? ' · ${e.note}' : ''}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TypeScale.caption.copyWith(color: failed ? o.capture : o.ink, shadows: const []),
              ),
              if (e.reasoning.isNotEmpty)
                Text(
                  '${questionTypeLabel(l, e.type)} · ${e.reasoning}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TypeScale.micro.copyWith(color: o.inkAt(0.5), shadows: const []),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Outside a live session, while auto-fill (or a manual fill) runs: the
/// status bar, the questionnaire panel when a cycle is on, else the log.
class AutoFillOverlayScreen extends ConsumerWidget {
  const AutoFillOverlayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = context.overlayPalette;
    final formActive = ref.watch(questionnaireControllerProvider.select((q) => q.active));
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) => unawaited(ref.read(windowServiceProvider).startDragging()),
        child: ClipRRect(
          borderRadius: Radii.rXl,
          child: ColoredBox(
            color: o.textOnly ? o.chromeGround : o.ground,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AutoFillBar(standalone: true),
                  const SizedBox(height: 8),
                  Expanded(child: formActive ? const QuestionnaireView() : const AutoFillLog()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/icons.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../core/platform/platform_keys.dart';
import '../../core/platform/window_service.dart';
import '../../core/widgets/buttons.dart';
import '../../data/models/shortcut.dart';
import '../../data/repositories.dart';
import '../../domain/agent/agent_loop.dart';
import '../../l10n/l10n.dart';
import 'agent_controller.dart';

/// The agent's panel inside the overlay: who is in control, the step, the
/// action waiting for Enter / Esc, and the log so far.
class AgentView extends ConsumerWidget {
  const AgentView({super.key});

  /// Amber, the "someone else has the controls" colour.
  static const controlColor = Color(0xFFFFA928);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = context.overlayPalette;
    final l = context.l10n;
    final a = ref.watch(agentControllerProvider);
    final c = ref.read(agentControllerProvider.notifier);
    final settings = ref.watch(settingsProvider);
    final stopKeys = settings.shortcutFor(LiveAction.agentStop);
    final finished = a.phase == AgentPhase.finished;

    final status = switch (a.phase) {
      AgentPhase.starting => l.agentStarting,
      AgentPhase.thinking => l.agentThinking,
      AgentPhase.confirming => l.agentWaiting,
      AgentPhase.acting => l.agentActing,
      AgentPhase.finished => _resultLabel(l, a),
      AgentPhase.idle => '',
    };

    return Container(
      // The indicator: an amber frame whenever the agent has the controls.
      decoration: BoxDecoration(
        borderRadius: Radii.rXl,
        border: Border.all(color: a.inControl ? controlColor : o.inkAt(0.1), width: a.inControl ? 2 : 1),
      ),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (a.inControl) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: controlColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: controlColor.withValues(alpha: 0.7)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SottoIcon(SottoIcons.cursor, size: 11, color: controlColor),
                      const SizedBox(width: 5),
                      Text(
                        l.agentInControl,
                        style: TypeScale.micro.copyWith(color: controlColor, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Text(
                l.agentStep(a.step, AgentController.maxSteps),
                style: TypeScale.mono.copyWith(fontSize: 11, color: o.inkAt(0.6)),
              ),
              const Spacer(),
              if (a.inControl)
                SottoButton(
                  label: l.agentStop,
                  icon: SottoIcons.close,
                  variant: ButtonVariant.overlay,
                  size: ButtonSize.small,
                  shortcut: stopKeys,
                  onPressed: c.stop,
                )
              else if (finished)
                SottoButton(
                  label: l.close,
                  variant: ButtonVariant.overlay,
                  size: ButtonSize.small,
                  onPressed: () => unawaited(c.close()),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            a.task,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TypeScale.bodyStrong.copyWith(color: o.ink),
          ),
          const SizedBox(height: 6),
          Text(status, style: TypeScale.caption.copyWith(color: o.inkAt(0.7))),
          if (a.pending case final p?) ...[
            const SizedBox(height: 12),
            _Pending(pending: p, onRun: c.approve, onStop: c.reject),
          ],
          if (finished && (a.result?.summary.isNotEmpty ?? false)) ...[
            const SizedBox(height: 10),
            Text(a.result!.summary, style: TypeScale.body.copyWith(color: o.inkAt(0.9))),
          ],
          if (a.error != null) ...[
            const SizedBox(height: 10),
            Text(a.error!, style: TypeScale.body.copyWith(color: o.capture)),
          ],
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              reverse: true,
              padding: EdgeInsets.zero,
              children: [
                for (final e in a.log.reversed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: SottoIcon(
                            switch (e.outcome) {
                              AgentOutcome.done => SottoIcons.check,
                              AgentOutcome.blocked => SottoIcons.lock,
                              _ => SottoIcons.close,
                            },
                            size: 11,
                            color: e.outcome == AgentOutcome.done ? o.confirmed : o.capture,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            e.note.isEmpty ? e.action : '${e.action} — ${e.note}',
                            style: TypeScale.caption.copyWith(color: o.inkAt(0.62)),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (a.inControl)
            Text(
              l.agentStopHint(PlatformKeys.describe(stopKeys)),
              style: TypeScale.micro.copyWith(color: o.inkAt(0.5), fontWeight: FontWeight.w400),
            ),
        ],
      ),
    );
  }

  static String _resultLabel(AppLocalizations l, AgentState a) {
    if (a.error != null) return l.agentCouldNotStart;
    return switch (a.result?.status) {
      AgentStatus.completed => l.agentCompleted,
      AgentStatus.stopped => l.agentStopped,
      AgentStatus.declined => l.agentDeclined,
      AgentStatus.limit => l.agentLimit(AgentController.maxSteps),
      AgentStatus.failed => l.agentFailed,
      null => '',
    };
  }
}

class _Pending extends StatelessWidget {
  const _Pending({required this.pending, required this.onRun, required this.onStop});
  final PendingAction pending;
  final VoidCallback onRun;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final o = context.overlayPalette;
    final l = context.l10n;
    final p = pending;
    const text = LocalizedAgentText();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: o.textOnly ? o.chromeGround : o.inkAt(0.06),
        borderRadius: Radii.rM,
        border: Border.all(color: p.sensitive ? o.capture : AgentView.controlColor.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            p.sensitive && p.reason != null ? l.agentConfirmSensitive(text.reason(p.reason!)) : l.agentNext,
            style: TypeScale.micro.copyWith(
              color: p.sensitive ? o.capture : AgentView.controlColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(text.describe(p.action), style: TypeScale.bodyStrong.copyWith(color: o.ink)),
          const SizedBox(height: 8),
          Row(
            children: [
              SottoButton(
                label: l.agentRun,
                variant: ButtonVariant.overlay,
                size: ButtonSize.small,
                shortcutText: '↵',
                onPressed: onRun,
              ),
              const SizedBox(width: 8),
              SottoButton(
                label: l.agentStopTask,
                variant: ButtonVariant.overlay,
                size: ButtonSize.small,
                shortcutText: 'Esc',
                onPressed: onStop,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The overlay for an agent task started from the main window (no live
/// session): just the agent panel, draggable, on the overlay palette.
class AgentOverlayScreen extends ConsumerWidget {
  const AgentOverlayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = context.overlayPalette;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) => unawaited(ref.read(windowServiceProvider).startDragging()),
        child: ClipRRect(
          borderRadius: Radii.rXl,
          child: ColoredBox(
            // Text-only overlays still need a surface here: this is a panel
            // of controls, not a line to read over slides.
            color: o.textOnly ? o.chromeGround : o.ground,
            child: const AgentView(),
          ),
        ),
      ),
    );
  }
}

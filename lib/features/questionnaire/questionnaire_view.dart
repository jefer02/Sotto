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
import '../../l10n/l10n.dart';
import '../agent/agent_view.dart';
import 'questionnaire_controller.dart';

/// The questionnaire panel in the overlay: "Answering 7/12…", the current
/// question and answer, the list so far, and — when it's the presenter's
/// turn — Enter to fill / go on / submit.
class QuestionnaireView extends ConsumerWidget {
  const QuestionnaireView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = context.overlayPalette;
    final l = context.l10n;
    final q = ref.watch(questionnaireControllerProvider);
    final c = ref.read(questionnaireControllerProvider.notifier);
    final stopKeys = ref.watch(settingsProvider).shortcutFor(LiveAction.agentStop);
    final finished = q.phase == FormPhase.finished;
    final amber = AgentView.controlColor;

    final done = q.items.where((i) => i.status == ItemStatus.filled || i.status == ItemStatus.failed).length;
    final status = switch (q.phase) {
      FormPhase.reading => l.formsReading,
      FormPhase.thinking => l.formsThinking,
      FormPhase.review => l.formsReview,
      FormPhase.filling => l.formsAnswering(done + 1, q.fillableCount),
      FormPhase.verifying => l.formsVerifying,
      FormPhase.nextPage => l.formsNextPage(q.submitLabel ?? ''),
      FormPhase.confirmSubmit => l.formsDoneSubmit,
      FormPhase.finished => switch (q.outcome) {
        'submitted' => l.formsSubmitted,
        'stopped' => l.formsStopped,
        'failed' => l.formsFailed,
        _ => l.formsReady(q.filledCount),
      },
      FormPhase.idle => '',
    };
    final current = q.current != null && q.current! < q.items.length ? q.items[q.current!] : null;
    final waiting = q.phase == FormPhase.review || q.phase == FormPhase.nextPage || q.phase == FormPhase.confirmSubmit;

    return Container(
      // Amber frame while Sotto is filling: nothing happens silently.
      decoration: BoxDecoration(
        borderRadius: Radii.rXl,
        border: Border.all(color: q.inControl ? amber : o.inkAt(0.1), width: q.inControl ? 2 : 1),
      ),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (q.inControl) ...[_Chip(label: l.formsFilling, color: amber), const SizedBox(width: 10)],
              Text(l.formsPage(q.page), style: TypeScale.mono.copyWith(fontSize: 11, color: o.inkAt(0.6))),
              const Spacer(),
              if (!finished)
                SottoButton(
                  label: l.agentStop,
                  icon: SottoIcons.close,
                  variant: ButtonVariant.overlay,
                  size: ButtonSize.small,
                  shortcut: stopKeys,
                  onPressed: c.stop,
                )
              else
                SottoButton(
                  label: l.close,
                  variant: ButtonVariant.overlay,
                  size: ButtonSize.small,
                  onPressed: () => unawaited(c.close()),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(status, style: TypeScale.bodyStrong.copyWith(color: o.ink)),
          if (current != null && q.phase == FormPhase.filling) ...[
            const SizedBox(height: 6),
            Text(
              current.question,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TypeScale.caption.copyWith(color: o.inkAt(0.7)),
            ),
            Text(
              '→ ${current.answer}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TypeScale.body.copyWith(color: o.ink),
            ),
          ],
          if (q.error != null) ...[
            const SizedBox(height: 8),
            Text(q.error!, style: TypeScale.body.copyWith(color: o.capture)),
          ],
          if (waiting) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                SottoButton(
                  label: switch (q.phase) {
                    FormPhase.review => l.formsFillThese,
                    FormPhase.nextPage => l.formsGoNext,
                    _ => l.formsSubmit(q.submitLabel ?? ''),
                  },
                  variant: ButtonVariant.overlay,
                  size: ButtonSize.small,
                  shortcutText: '↵',
                  onPressed: c.approve,
                ),
                const SizedBox(width: 8),
                SottoButton(
                  label: q.phase == FormPhase.confirmSubmit ? l.formsIllSubmit : l.agentStopTask,
                  variant: ButtonVariant.overlay,
                  size: ButtonSize.small,
                  shortcutText: 'Esc',
                  onPressed: c.reject,
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: q.items.length,
              itemBuilder: (context, i) => _ItemRow(
                item: q.items[i],
                current: i == q.current,
                editable: q.phase == FormPhase.review && q.items[i].editable,
                onEdit: (t) => c.editAnswer(i, t),
              ),
            ),
          ),
          if (!finished)
            Text(
              l.agentStopHint(PlatformKeys.describe(stopKeys)),
              style: TypeScale.micro.copyWith(color: o.inkAt(0.5), fontWeight: FontWeight.w400),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.7)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SottoIcon(SottoIcons.form, size: 11, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TypeScale.micro.copyWith(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _ItemRow extends StatefulWidget {
  const _ItemRow({required this.item, required this.current, required this.editable, required this.onEdit});
  final FormItem item;
  final bool current;
  final bool editable;
  final ValueChanged<String> onEdit;

  @override
  State<_ItemRow> createState() => _ItemRowState();
}

class _ItemRowState extends State<_ItemRow> {
  late final _text = TextEditingController(text: widget.item.answer);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // The overlay takes the keyboard only while an answer is being edited.
    _focus.addListener(() => unawaited(setOverlayKeyboard(_focus.hasFocus)));
  }

  @override
  void didUpdateWidget(_ItemRow old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && widget.item.answer != _text.text) _text.text = widget.item.answer;
  }

  @override
  void dispose() {
    if (_focus.hasFocus) unawaited(setOverlayKeyboard(false));
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final o = context.overlayPalette;
    final item = widget.item;
    final (icon, color) = switch (item.status) {
      ItemStatus.filled => (SottoIcons.check, o.confirmed),
      ItemStatus.failed => (SottoIcons.alert, o.capture),
      ItemStatus.blocked => (SottoIcons.lock, o.capture),
      ItemStatus.skipped => (SottoIcons.close, o.inkAt(0.4)),
      ItemStatus.filling => (SottoIcons.cursor, AgentView.controlColor),
      ItemStatus.pending => (SottoIcons.form, o.inkAt(0.4)),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: SottoIcon(icon, size: 11, color: color),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.question,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TypeScale.caption.copyWith(color: o.inkAt(widget.current ? 0.9 : 0.62)),
                ),
                if (widget.editable)
                  TextField(
                    controller: _text,
                    focusNode: _focus,
                    onChanged: widget.onEdit,
                    style: TypeScale.body.copyWith(color: o.ink),
                    cursorColor: o.cue,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      filled: true,
                      fillColor: o.inkAt(0.06),
                      border: OutlineInputBorder(
                        borderRadius: Radii.rS,
                        borderSide: BorderSide(color: o.inkAt(0.14)),
                      ),
                    ),
                  )
                else
                  Text(
                    item.note.isEmpty
                        ? item.answer
                        : (item.answer.isEmpty ? item.note : '${item.answer} — ${item.note}'),
                    style: TypeScale.body.copyWith(color: item.status == ItemStatus.skipped ? o.inkAt(0.5) : o.ink),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A questionnaire started from the main window: just the panel.
class QuestionnaireOverlayScreen extends ConsumerWidget {
  const QuestionnaireOverlayScreen({super.key});

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
          child: ColoredBox(color: o.textOnly ? o.chromeGround : o.ground, child: const QuestionnaireView()),
        ),
      ),
    );
  }
}

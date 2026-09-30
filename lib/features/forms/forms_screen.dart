import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/icons.dart';
import '../../core/design/theme.dart';
import '../../core/design/typography.dart';
import '../../core/platform/platform_keys.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/controls.dart';
import '../../core/widgets/display.dart';
import '../../core/widgets/interactive.dart';
import '../../data/models/session_record.dart';
import '../../data/models/shortcut.dart';
import '../../data/repositories.dart';
import '../../domain/forms/question_types.dart';
import '../../l10n/l10n.dart';
import '../library/library_shell.dart';
import '../questionnaire/questionnaire_controller.dart';
import 'autofill_controller.dart';
import 'autofill_view.dart';

/// The Forms page (/forms): auto-fill's master switch, what it's doing now
/// (the same controller as the overlay's status bar), a one-off "fill what's
/// on screen", and the recent fills with every answer.
class FormsScreen extends ConsumerWidget {
  const FormsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return Column(
      children: [
        LibraryHeader(
          title: l.navForms,
          actions: [
            SottoIconButton(
              icon: SottoIcons.sliders,
              tooltip: l.formsOpenSettings,
              onPressed: () => context.go('/settings/forms'),
            ),
          ],
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(40, 28, 40, 40),
            children: const [
              _MasterToggle(),
              SizedBox(height: 14),
              FormsStatusCard(),
              SizedBox(height: 28),
              _RecentFills(),
            ],
          ),
        ),
      ],
    );
  }
}

class _MasterToggle extends ConsumerWidget {
  const _MasterToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final l = context.l10n;
    final on = ref.watch(settingsProvider.select((s) => s.formsEnabled && s.formsAutoFill));
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Row(
        children: [
          SottoIcon(SottoIcons.form, size: 20, color: on ? p.cueText : p.inkTertiary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.autofillToggle, style: TypeScale.title3.copyWith(color: p.inkPrimary)),
                const SizedBox(height: 4),
                Text(l.autofillToggleSub, style: TypeScale.caption.copyWith(color: p.inkTertiary)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SottoToggle(value: on, onChanged: ref.read(autoFillControllerProvider.notifier).setEnabled),
        ],
      ),
    );
  }
}

/// Off / Watching / Filling… N/M / Paused, with the overlay's controls.
class FormsStatusCard extends ConsumerWidget {
  const FormsStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final l = context.l10n;
    final a = ref.watch(autoFillControllerProvider);
    final c = ref.read(autoFillControllerProvider.notifier);
    final q = ref.watch(questionnaireControllerProvider);
    final keys = PlatformKeys.describe(ref.watch(settingsProvider).shortcutFor(LiveAction.fillForm));

    final filling = a.status == AutoFillStatus.filling || q.inControl;
    final done = q.items.where((i) => i.status == ItemStatus.filled || i.status == ItemStatus.failed).length;
    final (title, sub, dot) = filling
        ? (l.formsStatusFilling(math.min(done + 1, math.max(1, q.fillableCount)), q.fillableCount), a.app, p.cueText)
        : switch (a.status) {
            AutoFillStatus.paused => (l.autofillPaused, l.formsStatusPausedSub, p.inkTertiary),
            AutoFillStatus.watching => (l.formsStatusWatching, l.formsStatusWatchingSub, p.confirmed),
            _ => (l.formsStatusOff, l.formsStatusOffSub, p.inkTertiary),
          };

    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  key: const Key('formsStatus'),
                  style: TypeScale.bodyStrong.copyWith(color: p.inkPrimary),
                ),
              ),
              if (filling)
                SottoButton(
                  label: l.autofillStopNow,
                  icon: SottoIcons.stop,
                  size: ButtonSize.small,
                  onPressed: c.emergencyStop,
                )
              else if (a.status == AutoFillStatus.paused)
                SottoButton(label: l.autofillResume, icon: SottoIcons.play, size: ButtonSize.small, onPressed: c.resume)
              else if (a.on)
                SottoButton(label: l.autofillPause, icon: SottoIcons.pause, size: ButtonSize.small, onPressed: c.pause),
              if (a.on) ...[const SizedBox(width: 8), HoldToStopButton(onConfirmed: c.stop, color: p.inkPrimary)],
            ],
          ),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(sub, style: TypeScale.caption.copyWith(color: p.inkTertiary)),
          ],
          if (a.message != null && !filling) ...[
            const SizedBox(height: 6),
            Text(a.message!, style: TypeScale.caption.copyWith(color: p.inkSecondary)),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              SottoButton.primary(
                label: l.formsFillNow,
                icon: SottoIcons.form,
                onPressed: filling ? null : () => unawaited(c.fillNow(fromMainWindow: true)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(l.formsFillNowSub(keys), style: TypeScale.caption.copyWith(color: p.inkTertiary)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentFills extends ConsumerWidget {
  const _RecentFills();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final l = context.l10n;
    final keep = ref.watch(settingsProvider.select((s) => s.historyRetentionDays != 0));
    final sessions = ref.watch(sessionsProvider).value ?? const <SessionRecord>[];
    final fills = keep ? FormFill.recent(sessions).take(50).toList() : const <FormFill>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.formsRecent, style: TypeScale.bodyStrong.copyWith(color: p.inkPrimary)),
        const SizedBox(height: 10),
        if (!keep)
          Text(
            l.formsHistoryOff,
            key: const Key('formsHistoryOff'),
            style: TypeScale.caption.copyWith(color: p.inkTertiary),
          )
        else if (fills.isEmpty)
          Text(l.formsRecentEmpty, style: TypeScale.caption.copyWith(color: p.inkTertiary))
        else
          for (final f in fills) ...[FormFillTile(fill: f), const SizedBox(height: 8)],
      ],
    );
  }
}

/// One fill: when, where, how many fields, how it ended — tap for every
/// answer with its question type.
class FormFillTile extends StatefulWidget {
  const FormFillTile({super.key, required this.fill});
  final FormFill fill;

  @override
  State<FormFillTile> createState() => _FormFillTileState();
}

class _FormFillTileState extends State<FormFillTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    final f = widget.fill;
    final (outcome, color) = switch (f.outcome) {
      'completed' => (l.formsOutcomeCompleted, p.confirmed),
      'stopped' => (l.formsOutcomeStopped, p.inkTertiary),
      _ => (l.formsOutcomeError, p.cueText),
    };
    final where = f.run.app.isNotEmpty ? f.run.app : l.formsSessionTitle;
    return Interactive(
      onTap: () => setState(() => _open = !_open),
      builder: (context, s) => SurfaceCard(
        hovered: s.hovered,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SottoIcon(f.run.auto ? SottoIcons.auto : SottoIcons.form, size: 14, color: p.inkTertiary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        where,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TypeScale.bodyStrong.copyWith(color: p.inkPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${shortDateTime(f.at)} · ${l.formsFieldsFilled(f.run.filledCount)}',
                        style: TypeScale.caption.copyWith(color: p.inkTertiary),
                      ),
                    ],
                  ),
                ),
                Text(
                  outcome,
                  style: TypeScale.caption.copyWith(color: color, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                SottoIcon(_open ? SottoIcons.up : SottoIcons.down, size: 12, color: p.inkTertiary),
              ],
            ),
            if (_open) ...[
              const SizedBox(height: 10),
              for (final field in f.run.fields)
                Padding(
                  padding: const EdgeInsets.only(left: 26, bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(field.question, style: TypeScale.caption.copyWith(color: p.inkSecondary)),
                      Text(
                        '→ ${field.answer.isEmpty ? '—' : field.answer}',
                        style: TypeScale.body.copyWith(color: p.inkPrimary),
                      ),
                      Text(
                        [
                          if (QuestionTypes.parse(field.type) case final t?) questionTypeLabel(l, t),
                          field.status,
                          if (field.reasoning.isNotEmpty) field.reasoning,
                        ].join(' · '),
                        style: TypeScale.micro.copyWith(color: p.inkTertiary),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

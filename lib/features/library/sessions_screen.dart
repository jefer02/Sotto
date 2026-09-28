import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../l10n/l10n.dart';

import '../../core/design/icons.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/display.dart';
import '../../core/widgets/interactive.dart';
import '../../data/models/session_record.dart';
import '../../data/repositories.dart';
import 'library_shell.dart';

class SessionsScreen extends ConsumerWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionsProvider).value ?? const <SessionRecord>[];
    return Column(
      children: [
        LibraryHeader(title: context.l10n.navSessions),
        Expanded(
          child: sessions.isEmpty
              ? emptyState(
                  context,
                  icon: SottoIcons.sessions,
                  title: context.l10n.emptyNoSessions,
                  body: context.l10n.emptyNoSessionsHint,
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(40, 28, 40, 40),
                  itemCount: sessions.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => SessionTile(record: sessions[i]),
                ),
        ),
      ],
    );
  }
}

class SessionTile extends ConsumerWidget {
  const SessionTile({super.key, required this.record, this.showTitle = true});

  final SessionRecord record;
  final bool showTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final r = record;
    final delta = r.plannedSeconds == null ? null : r.durationSeconds - r.plannedSeconds!;
    final d = r.startedAt;
    final date =
        shortDateTime(d);

    return Interactive(
      onTap: () => context.go('/script/${r.scriptId}?tab=rehearsals'),
      builder: (context, s) => SurfaceCard(
        hovered: s.hovered,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            SottoIcon(
              r.agentOnly ? SottoIcons.cursor : (r.rehearsal ? SottoIcons.rehearse : SottoIcons.play),
              size: 15,
              color: p.inkTertiary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    showTitle ? r.scriptTitle : (r.rehearsal ? context.l10n.rehearsal : context.l10n.liveSession),
                    style: TypeScale.bodyStrong.copyWith(color: p.inkPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(date, style: TypeScale.caption.copyWith(color: p.inkTertiary)),
                  // Every agent action is kept for review.
                  for (final run in r.agentRuns)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Interactive(
                        onTap: () => unawaited(showAgentLog(context, run)),
                        builder: (context, s) => Text(
                          '${context.l10n.sessionAgentTask(run.task)} · ${context.l10n.sessionAgentActions(run.log.length)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TypeScale.caption.copyWith(
                            color: s.hovered ? p.cueText : p.inkSecondary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (showTitle) ...[
              StatusChip(r.rehearsal ? context.l10n.rehearsal : context.l10n.liveChip, tone: r.rehearsal ? ChipTone.neutral : ChipTone.cue),
              const SizedBox(width: 20),
            ],
            SizedBox(
              width: 110,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: formatDuration(r.durationSeconds),
                      style: TypeScale.mono.copyWith(color: p.inkPrimary),
                    ),
                    if (delta != null)
                      TextSpan(
                        text: '  ${delta >= 0 ? '+' : '−'}${formatDuration(delta.abs())}',
                        style: TypeScale.mono.copyWith(color: p.inkTertiary),
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 90,
              child: Text(
                r.wordsPerMinute == null ? '—' : context.l10n.wpmValue(r.wordsPerMinute!),
                style: TypeScale.monoSmall.copyWith(color: p.inkTertiary),
              ),
            ),
            SizedBox(
              width: 100,
              child: Text(
                context.l10n.questionsCount(r.questionCount),
                style: TypeScale.caption.copyWith(color: p.inkTertiary),
              ),
            ),
            SottoIconButton(
              icon: SottoIcons.close,
              tooltip: context.l10n.deleteSession,
              onPressed: () => unawaited(ref.read(sessionRepositoryProvider).delete(r.id)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Every action an agent task took, for review after the fact.
Future<void> showAgentLog(BuildContext context, AgentRunRecord run) => showDialog<void>(
  context: context,
  builder: (context) {
    final p = context.palette;
    return AlertDialog(
      backgroundColor: p.float,
      shape: RoundedRectangleBorder(borderRadius: Radii.rL, side: BorderSide(color: p.control)),
      title: Text(context.l10n.sessionAgentTask(run.task), style: TypeScale.title3.copyWith(color: p.inkPrimary)),
      content: SizedBox(
        width: 520,
        child: ListView(
          shrinkWrap: true,
          children: [
            if (run.summary.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(run.summary, style: TypeScale.body.copyWith(color: p.inkSecondary)),
              ),
            for (final e in run.log)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 64,
                      child: Text(clockTime(e.at), style: TypeScale.monoSmall.copyWith(color: p.inkTertiary)),
                    ),
                    SizedBox(
                      width: 72,
                      child: Text(e.outcome, style: TypeScale.caption.copyWith(color: p.inkTertiary)),
                    ),
                    Expanded(
                      child: Text(
                        e.note.isEmpty ? e.action : '${e.action} — ${e.note}',
                        style: TypeScale.body.copyWith(color: p.inkPrimary),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [SottoButton(label: context.l10n.close, onPressed: () => Navigator.pop(context))],
    );
  },
);

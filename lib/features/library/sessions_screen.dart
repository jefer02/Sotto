import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../l10n/l10n.dart';

import '../../core/design/icons.dart';
import '../../core/design/theme.dart';
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
            SottoIcon(r.rehearsal ? SottoIcons.rehearse : SottoIcons.play, size: 15, color: p.inkTertiary),
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

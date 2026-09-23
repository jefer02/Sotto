import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/l10n.dart';

import '../../core/design/icons.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/display.dart';
import '../../data/models/qa_entry.dart';
import '../../data/models/session_record.dart';
import '../../data/repositories.dart';
import '../library/sessions_screen.dart';
import '../preflight/preflight_dialog.dart';
import 'editor_controller.dart';

/// Timing by section for the latest run, every past run, and the questions
/// asked across sessions. This is where a session report opens.
class RehearsalsTab extends ConsumerWidget {
  const RehearsalsTab({super.key, required this.scriptId});
  final String scriptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final script = ref.watch(editorProvider(scriptId)).script!;
    final wpm = ref.watch(settingsProvider.select((s) => s.wordsPerMinute));
    final sessions = (ref.watch(sessionsProvider).value ?? const <SessionRecord>[])
        .where((s) => s.scriptId == scriptId)
        .toList();
    final questions = ref.watch(qaForScriptProvider(scriptId)).value ?? const <QaEntry>[];
    final latest = sessions.firstOrNull;

    if (sessions.isEmpty && questions.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SottoIcon(SottoIcons.rehearse, size: 20, color: p.inkTertiary),
              const SizedBox(height: 12),
              Text(context.l10n.noRehearsalsYet, style: TypeScale.title3.copyWith(color: p.inkPrimary)),
              const SizedBox(height: 6),
              Text(
                context.l10n.noRehearsalsHint,
                textAlign: TextAlign.center,
                style: TypeScale.body.copyWith(color: p.inkTertiary),
              ),
              const SizedBox(height: 16),
              SottoButton.primary(
                label: context.l10n.rehearseNow,
                icon: SottoIcons.rehearse,
                onPressed: () => unawaited(showPreflight(context, ref, scriptId, rehearsal: true)),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(40, 32, 40, 48),
      children: [
        if (latest != null) ...[
          Row(
            children: [
              Text(
                latest.rehearsal ? context.l10n.latestRehearsal : context.l10n.latestSession,
                style: TypeScale.title3.copyWith(color: p.inkPrimary),
              ),
              const Spacer(),
              Text(
                '${formatDuration(latest.durationSeconds)}'
                '${latest.plannedSeconds == null ? '' : context.l10n.ofPlanned(formatDuration(latest.plannedSeconds!))}'
                '${latest.wordsPerMinute == null ? '' : ' · ${context.l10n.wpmValue(latest.wordsPerMinute!)}'}',
                style: TypeScale.mono.copyWith(color: p.inkSecondary, fontWeight: FontWeight.w400),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: p.panel,
              borderRadius: Radii.rL,
              border: Border.all(color: p.hairline),
            ),
            child: Column(
              children: [
                for (var i = 0; i < script.sections.length; i++)
                  _SectionTiming(
                    index: i,
                    title: script.sections[i].title,
                    planned: script.sections[i].estimatedSeconds(wpm),
                    actual: latest.sectionSeconds[script.sections[i].id],
                    last: i == script.sections.length - 1,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
        Text(context.l10n.allRuns, style: TypeScale.title3.copyWith(color: p.inkPrimary)),
        const SizedBox(height: 12),
        for (final s in sessions) ...[SessionTile(record: s, showTitle: false), const SizedBox(height: 8)],
        if (questions.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(context.l10n.questionsAsked, style: TypeScale.title3.copyWith(color: p.inkPrimary)),
          const SizedBox(height: 12),
          for (final q in questions)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: p.panel,
                borderRadius: Radii.rL,
                border: Border.all(color: p.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(q.question, style: TypeScale.bodyStrong.copyWith(color: p.inkPrimary)),
                      ),
                      Text(
                        relativeTime(q.askedAt),
                        style: TypeScale.caption.copyWith(color: p.inkTertiary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(q.headline, style: TypeScale.body.copyWith(color: p.inkSecondary)),
                  if (q.sources.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(spacing: 6, runSpacing: 6, children: [for (final s in q.sources) SourceChip(s)]),
                  ],
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _SectionTiming extends StatelessWidget {
  const _SectionTiming({
    required this.index,
    required this.title,
    required this.planned,
    this.actual,
    required this.last,
  });
  final int index;
  final String title;
  final int planned;
  final int? actual;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final delta = actual == null ? null : actual! - planned;
    final ratio = actual == null || planned == 0 ? 0.0 : (actual! / planned).clamp(0.0, 1.6) / 1.6;
    // Over by more than 15 %: tungsten marks where to look. Never red.
    final over = delta != null && delta > planned * 0.15;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: p.hairline)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              (index + 1).toString().padLeft(2, '0'),
              style: TypeScale.monoSmall.copyWith(color: p.inkTertiary),
            ),
          ),
          SizedBox(
            width: 200,
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: TypeScale.body.copyWith(color: p.inkPrimary),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Container(
                  height: 4,
                  decoration: BoxDecoration(color: p.float, borderRadius: BorderRadius.circular(2)),
                ),
                FractionallySizedBox(
                  widthFactor: ratio,
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: over ? p.cueFill : p.inkTertiary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Planned mark.
                FractionallySizedBox(
                  widthFactor: 1 / 1.6,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Container(width: 1, height: 8, color: p.emphasis),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          SizedBox(
            width: 130,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: actual == null ? '—' : formatDuration(actual!),
                    style: TextStyle(color: p.inkPrimary),
                  ),
                  TextSpan(
                    text: ' / ${formatDuration(planned)}',
                    style: TextStyle(color: p.inkTertiary),
                  ),
                ],
              ),
              textAlign: TextAlign.right,
              style: TypeScale.mono.copyWith(fontWeight: FontWeight.w400),
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              delta == null ? '' : '${delta >= 0 ? '+' : '−'}${formatDuration(delta.abs())}',
              textAlign: TextAlign.right,
              style: TypeScale.mono.copyWith(color: over ? p.cueText : p.inkTertiary, fontWeight: FontWeight.w400),
            ),
          ),
        ],
      ),
    );
  }
}

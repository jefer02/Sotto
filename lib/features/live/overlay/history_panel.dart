import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/l10n.dart';

import '../../../core/design/icons.dart';
import '../../../core/design/theme.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/typography.dart';
import '../../../core/widgets/display.dart';
import '../../../core/widgets/keycap.dart';
import '../../../data/models/qa_entry.dart';
import '../../../data/models/shortcut.dart';
import '../../../data/repositories.dart';
import '../live_controller.dart';

/// Every answer from this session, reopenable (⌃⌥H).
class HistoryPanel extends ConsumerWidget {
  const HistoryPanel({super.key, required this.sessionId});
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = context.overlayPalette;
    final entries = ref.watch(qaForSessionProvider(sessionId)).value ?? const <QaEntry>[];
    final settings = ref.watch(settingsProvider);
    final c = ref.read(liveControllerProvider.notifier);

    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: o.inkAt(0.08))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 36,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  SottoIcon(SottoIcons.history, size: 13, color: o.inkAt(0.8)),
                  const SizedBox(width: 8),
                  Text(context.l10n.questions, style: TypeScale.captionStrong.copyWith(color: o.inkAt(0.9))),
                  const SizedBox(width: 6),
                  Text('${entries.length}', style: TypeScale.caption.copyWith(color: o.inkAt(0.5))),
                  const Spacer(),
                  GestureDetector(
                    onTap: c.toggleHistory,
                    child: Row(
                      children: [
                        KeyCombo(settings.shortcutFor(LiveAction.history), tone: KeycapTone.overlay, merged: true),
                        const SizedBox(width: 6),
                        Text(
                          context.l10n.close,
                          style: TypeScale.micro.copyWith(color: o.inkAt(0.6), fontWeight: FontWeight.w400),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        context.l10n.historyEmpty,
                        textAlign: TextAlign.center,
                        style: TypeScale.caption.copyWith(color: o.inkAt(0.5)),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    itemCount: entries.length,
                    itemBuilder: (context, i) => _Entry(entry: entries[i], expanded: i == 0),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Entry extends ConsumerWidget {
  const _Entry({required this.entry, required this.expanded});
  final QaEntry entry;
  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = context.overlayPalette;
    final c = ref.read(liveControllerProvider.notifier);
    final (String status, Color color) = switch (entry.outcome) {
      AnswerOutcome.sentToChat => (context.l10n.outcomeCopied, o.confirmed),
      AnswerOutcome.readAloud => (context.l10n.outcomeReadAloud, o.inkAt(0.6)),
      AnswerOutcome.dismissed => (context.l10n.outcomeDismissed, o.inkAt(0.6)),
      AnswerOutcome.shown => (context.l10n.outcomeShown, o.inkAt(0.6)),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: expanded ? o.inkAt(0.05) : Colors.transparent, borderRadius: Radii.rM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                formatClock(entry.sessionElapsedSeconds ?? 0),
                style: TypeScale.mono.copyWith(fontSize: 11, fontWeight: FontWeight.w400, color: o.inkAt(0.55)),
              ),
              const Spacer(),
              if (entry.outcome == AnswerOutcome.sentToChat) ...[
                SottoIcon(SottoIcons.check, size: 11, color: color),
                const SizedBox(width: 4),
              ],
              Text(
                status,
                style: TypeScale.micro.copyWith(color: color, fontWeight: FontWeight.w400),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(entry.question, style: TypeScale.body.copyWith(color: o.inkAt(0.9))),
          if (expanded) ...[
            const SizedBox(height: 8),
            Text(entry.headline, style: withWeight(TypeScale.body, 600).copyWith(color: o.ink)),
            const SizedBox(height: 10),
            Row(
              children: [
                _SmallButton(
                  icon: SottoIcons.quote,
                  label: context.l10n.showAgain,
                  filled: true,
                  onTap: () => c.showAgain(entry),
                ),
                const SizedBox(width: 6),
                _SmallButton(icon: SottoIcons.copy, label: context.l10n.copy, onTap: () => c.copyEntry(entry)),
              ],
            ),
          ] else
            GestureDetector(
              onTap: () => c.showAgain(entry),
              child: const SizedBox(height: 2, width: double.infinity),
            ),
        ],
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({required this.icon, required this.label, required this.onTap, this.filled = false});
  final SottoIcons icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final o = context.overlayPalette;
    return TextButton(
      onPressed: onTap,
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, 26)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: Radii.rS,
            side: BorderSide(color: filled ? o.inkAt(0.12) : Colors.transparent),
          ),
        ),
        backgroundColor: WidgetStatePropertyAll(filled ? o.inkAt(0.08) : Colors.transparent),
        overlayColor: WidgetStatePropertyAll(o.inkAt(0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SottoIcon(icon, size: 12, color: o.inkAt(0.85)),
          const SizedBox(width: 6),
          Text(label, style: TypeScale.micro.copyWith(color: o.inkAt(0.85))),
        ],
      ),
    );
  }
}

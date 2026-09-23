import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../l10n/l10n.dart';

import '../../core/design/icons.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/controls.dart';
import '../../core/widgets/display.dart';
import '../../core/widgets/keycap.dart';
import '../../data/models/script.dart';
import '../../data/models/settings.dart';
import '../../data/models/shortcut.dart';
import '../../data/repositories.dart';
import '../library/readiness.dart';
import '../live/live_controller.dart';

Future<void> showPreflight(BuildContext context, WidgetRef ref, String scriptId, {bool rehearsal = false}) async {
  final script = ref.read(scriptRepositoryProvider).get(scriptId);
  if (script == null || ref.read(liveControllerProvider).isLive) return;
  ref.invalidate(readinessProvider);
  await showDialog<void>(
    context: context,
    barrierColor: const Color(0x99000000),
    builder: (_) => PreflightDialog(script: script, rehearsal: rehearsal),
  );
}

class PreflightDialog extends ConsumerStatefulWidget {
  const PreflightDialog({super.key, required this.script, this.rehearsal = false});

  final Script script;
  final bool rehearsal;

  @override
  ConsumerState<PreflightDialog> createState() => _PreflightDialogState();
}

class _PreflightDialogState extends ConsumerState<PreflightDialog> {
  int _startSection = 0;
  bool _starting = false;

  Future<void> _go({bool? rehearsal}) async {
    if (_starting) return;
    setState(() => _starting = true);
    final controller = ref.read(liveControllerProvider.notifier);
    Navigator.of(context).pop();
    await controller.start(widget.script, startSection: _startSection, rehearsal: rehearsal ?? widget.rehearsal);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final settings = ref.watch(settingsProvider);
    final readiness = ref.watch(readinessProvider).value;
    final s = widget.script;
    final minutes = formatMinutes(s.targetSeconds ?? s.estimatedSeconds(settings.wordsPerMinute));

    final l = context.l10n;
    final checks = readiness == null
        ? const <_Check>[]
        : [
            _Check(
              icon: SottoIcons.mic,
              title: l.pfMicrophone,
              detail: readiness.mic.level == CheckLevel.ok ? l.pfMicReady(readiness.mic.label) : l.pfNoInput,
              level: readiness.mic.level,
              action: readiness.mic.level == CheckLevel.ok ? null : (l.pfChoose, '/settings/voice'),
            ),
            _Check(
              icon: SottoIcons.wave,
              title: l.pfVoiceFollowing,
              detail: readiness.voice.level == CheckLevel.ok
                  ? l.pfTunedTo(readiness.voice.label, settings.wordsPerMinute)
                  : (readiness.voice.detail ?? readiness.voice.label),
              level: readiness.voice.level,
              action: readiness.voice.level == CheckLevel.ok ? null : (l.pfSetUp, '/settings/voice'),
            ),
            _Check(
              icon: SottoIcons.camera,
              title: l.pfOverlay,
              detail: l.pfOverlayDetail(
                _placementLabel(settings.placement),
                (settings.overlayOpacity * 100).round(),
                settings.readingSize.label,
              ),
              level: CheckLevel.ok,
              action: (l.pfAdjust, '/settings/appearance'),
            ),
            _Check(
              icon: SottoIcons.eyeOff,
              title: l.pfScreenSharing,
              detail: settings.excludeFromCapture
                  ? l.pfShareProtected
                  : l.pfShareUnprotected,
              level: CheckLevel.warn,
              highlight: true,
            ),
            _Check(
              icon: SottoIcons.ask,
              title: l.pfAnswers,
              detail: readiness.answers.level == CheckLevel.ok
                  ? l.pfGrounded +
                        (s.prepDocs.isEmpty ? '' : l.pfPlusPrepDocs(s.prepDocs.length)) +
                        (settings.answerLanguage == AnswerLanguage.sameAsQuestion ? l.pfQuestionLanguage : '')
                  : (readiness.answers.detail ?? l.engineUnavailable),
              level: readiness.answers.level,
              action: readiness.answers.level == CheckLevel.ok ? null : (l.pfAddKey, '/settings/integrations'),
            ),
            _Check(
              icon: SottoIcons.send,
              title: l.pfMeetingChat,
              detail: l.pfMeetingChatDetail,
              level: CheckLevel.ok,
            ),
          ];
    final passed = checks.where((c) => c.level == CheckLevel.ok).length;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): () => unawaited(_go()),
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop(),
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          backgroundColor: p.raised,
          insetPadding: const EdgeInsets.all(40),
          shape: RoundedRectangleBorder(
            borderRadius: Radii.rXl,
            side: BorderSide(color: p.control),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(26, 22, 26, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.rehearsal ? l.rehearse : l.goLive,
                              style: TypeScale.caption.copyWith(color: p.inkSecondary),
                            ),
                            const SizedBox(height: 4),
                            Text(s.title, style: TypeScale.title1.copyWith(color: p.inkPrimary)),
                            const SizedBox(height: 4),
                            Text(
                              l.pfSummary(minutes, l.sectionsCount(s.sections.length)) + (checks.isEmpty ? '' : l.pfChecksPassed(passed, checks.length)),
                              style: TypeScale.caption.copyWith(color: p.inkTertiary),
                            ),
                          ],
                        ),
                      ),
                      SottoIconButton(
                        icon: SottoIcons.close,
                        tooltip: l.closeEsc,
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (checks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 1.5)),
                    )
                  else
                    for (final c in checks) _CheckRow(check: c),
                  const SizedBox(height: 12),
                  Divider(height: 1, color: p.hairline),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(l.startFrom, style: TypeScale.body.copyWith(color: p.inkSecondary)),
                      const SizedBox(width: 10),
                      SottoSelect<int>(
                        width: 170,
                        value: _startSection,
                        options: [
                          for (var i = 0; i < s.sections.length; i++)
                            SelectOption(i, '${(i + 1).toString().padLeft(2, '0')} · ${s.sections[i].title}'),
                        ],
                        onChanged: (v) => setState(() => _startSection = v),
                      ),
                      const Spacer(),
                      SottoButton.ghost(
                        label: widget.rehearsal ? l.goLiveInstead : l.rehearseInstead,
                        onPressed: () => unawaited(_go(rehearsal: !widget.rehearsal)),
                      ),
                      const SizedBox(width: 10),
                      SottoButton.primary(
                        label: widget.rehearsal ? l.rehearse : l.goLive,
                        icon: widget.rehearsal ? SottoIcons.rehearse : SottoIcons.play,
                        size: ButtonSize.large,
                        shortcut: settings.shortcutFor(LiveAction.goLive),
                        onPressed: _starting ? null : () => unawaited(_go()),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _Hint(settings.shortcutFor(LiveAction.nextBeat), l.hintNextBeat),
                      const SizedBox(width: 18),
                      _Hint(settings.shortcutFor(LiveAction.ask), l.hintAsk),
                      const SizedBox(width: 18),
                      _Hint(settings.shortcutFor(LiveAction.hide), l.hintHide),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _placementLabel(OverlayPlacement p) => switch (p) {
    OverlayPlacement.topCenter => L10n.current.placeUnderCamera,
    OverlayPlacement.topLeft => L10n.current.placeTopLeft,
    OverlayPlacement.topRight => L10n.current.placeTopRight,
    OverlayPlacement.middleLeft => L10n.current.placeLeftEdge,
    OverlayPlacement.center => L10n.current.placeCentered,
    OverlayPlacement.middleRight => L10n.current.placeRightEdge,
    OverlayPlacement.bottomLeft => L10n.current.placeBottomLeft,
    OverlayPlacement.bottomCenter => L10n.current.placeBottomCentre,
    OverlayPlacement.bottomRight => L10n.current.placeBottomRight,
  };
}

class _Check {
  const _Check({
    required this.icon,
    required this.title,
    required this.detail,
    required this.level,
    this.action,
    this.highlight = false,
  });

  final SottoIcons icon;
  final String title;
  final String detail;
  final CheckLevel level;

  /// (label, settings route)
  final (String, String)? action;
  final bool highlight;
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.check});
  final _Check check;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = check;
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: c.highlight ? p.cueFill.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: Radii.rM,
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: Radii.rControl,
              border: Border.all(color: p.control),
              color: p.panel,
            ),
            child: SottoIcon(c.icon, size: 14, color: p.inkSecondary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.title, style: TypeScale.bodyStrong.copyWith(color: p.inkPrimary)),
                const SizedBox(height: 2),
                Text(c.detail, style: TypeScale.caption.copyWith(color: p.inkSecondary, height: 1.4)),
              ],
            ),
          ),
          if (c.action != null) ...[
            const SizedBox(width: 12),
            SottoButton.ghost(
              label: c.action!.$1,
              size: ButtonSize.small,
              onPressed: () {
                Navigator.of(context).pop();
                GoRouter.of(context).go(c.action!.$2);
              },
            ),
          ],
          const SizedBox(width: 12),
          switch (c.level) {
            CheckLevel.ok => SottoIcon(SottoIcons.check, size: 14, color: p.confirmed),
            CheckLevel.warn => SottoIcon(SottoIcons.alert, size: 14, color: p.cueText),
            CheckLevel.missing => SottoIcon(SottoIcons.alert, size: 14, color: p.inkTertiary),
          },
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.shortcut, this.label);
  final Shortcut shortcut;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        KeyCombo(shortcut, merged: true),
        const SizedBox(width: 8),
        Text(label, style: TypeScale.caption.copyWith(color: p.inkTertiary)),
      ],
    );
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/l10n.dart';

import '../../../core/design/icons.dart';
import '../../../core/design/theme.dart';
import '../../../core/design/typography.dart';
import '../../../core/platform/platform_keys.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/display.dart';
import '../../../core/widgets/interactive.dart';
import '../../../data/models/settings.dart';
import '../../../data/models/shortcut.dart';
import '../../../data/repositories.dart';
import '../../forms/autofill_controller.dart';
import '../../../services/screen/form_access.dart';
import '../../../services/screen/screen_service.dart';
import '../../../services/tts/tts_service.dart';
import '../settings_screen.dart';

final ttsVoicesProvider = FutureProvider<List<String>>((ref) => ref.read(ttsProvider).voices());

class AnswersPage extends ConsumerWidget {
  const AnswersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final voices = ref.watch(ttsVoicesProvider).value ?? const <String>[];

    Widget groundingOption(Grounding g, String title, String subtitle) => Interactive(
      onTap: () => n.update((x) => x.copyWith(grounding: g)),
      builder: (context, st) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SottoRadio(
                selected: s.grounding == g,
                onTap: () => n.update((x) => x.copyWith(grounding: g)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TypeScale.bodyStrong.copyWith(color: p.inkPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TypeScale.caption.copyWith(color: p.inkTertiary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return SettingsPageScaffold(
      title: context.l10n.pfAnswers,
      description: context.l10n.answersDescription,
      left: [
        SettingsGroup(
          title: context.l10n.grounding,
          children: [
            groundingOption(
              Grounding.scriptOnly,
              context.l10n.groundingScriptOnly,
              context.l10n.groundingScriptOnlySub,
            ),
            groundingOption(
              Grounding.scriptFirst,
              context.l10n.groundingScriptFirst,
              context.l10n.groundingScriptFirstSub,
            ),
            SettingRow(
              title: context.l10n.showSources,
              trailing: SottoToggle(
                value: s.showSources,
                onChanged: (v) => n.update((x) => x.copyWith(showSources: v)),
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: context.l10n.style,
          children: [
            SettingRow(
              title: context.l10n.length,
              subtitle: context.l10n.lengthSub,
              trailing: SegmentedControl<AnswerLength>(
                width: 270,
                segments: [
                  Segment(AnswerLength.headline, context.l10n.headline),
                  Segment(AnswerLength.headlinePlus3, context.l10n.headlinePlus3),
                  Segment(AnswerLength.detailed, context.l10n.detailed),
                ],
                value: s.answerLength,
                onChanged: (v) => n.update((x) => x.copyWith(answerLength: v)),
              ),
            ),
            SettingRow(
              title: context.l10n.language,
              trailing: SottoSelect<AnswerLanguage>(
                value: s.answerLanguage,
                options: [
                  SelectOption(AnswerLanguage.sameAsQuestion, context.l10n.sameAsQuestion),
                  SelectOption(AnswerLanguage.scriptLanguage, context.l10n.sameAsScript),
                ],
                onChanged: (v) => n.update((x) => x.copyWith(answerLanguage: v)),
              ),
            ),
            SettingRow(
              title: context.l10n.tone,
              trailing: SottoSelect<AnswerTone>(
                value: s.tone,
                options: [
                  SelectOption(AnswerTone.matchScript, context.l10n.matchScript),
                  SelectOption(AnswerTone.conversational, context.l10n.conversational),
                  SelectOption(AnswerTone.formal, context.l10n.formal),
                ],
                onChanged: (v) => n.update((x) => x.copyWith(tone: v)),
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: context.l10n.listeningForQuestions,
          children: [
            SettingRow(
              title: context.l10n.capture,
              subtitle: context.l10n.captureSub,
              trailing: SottoSelect<CaptureMode>(
                value: s.captureMode,
                options: [
                  SelectOption(CaptureMode.toggle, context.l10n.pressToToggle),
                  SelectOption(CaptureMode.hold, context.l10n.holdToTalk),
                ],
                onChanged: (v) => n.update((x) => x.copyWith(captureMode: v)),
              ),
            ),
            SettingRow(
              title: context.l10n.stopAfterSilence,
              trailing: SegmentedControl<double>(
                width: 190,
                segments: [
                  for (final v in const [0.8, 1.2, 2.0])
                    Segment(v, '${NumberFormat('0.#', context.l10n.localeName).format(v)} s'),
                ],
                value: s.silenceSeconds,
                onChanged: (v) => n.update((x) => x.copyWith(silenceSeconds: v)),
              ),
            ),
            SettingRow(
              title: context.l10n.predraft,
              subtitle: context.l10n.predraftSub,
              trailing: SottoToggle(
                value: s.predraft,
                onChanged: (v) => n.update((x) => x.copyWith(predraft: v)),
              ),
            ),
          ],
        ),
        const _QuestionnairesGroup(),
        SettingsGroup(
          title: context.l10n.chatGroup,
          children: [
            SettingRow(
              title: context.l10n.chatAutoSend,
              subtitle: context.l10n.chatAutoSendSub,
              trailing: SottoToggle(
                value: s.chatAutoSend,
                onChanged: (v) => n.update((x) => x.copyWith(chatAutoSend: v)),
              ),
            ),
            SettingRow(
              title: context.l10n.chatContext,
              subtitle: context.l10n.chatContextSub,
              trailing: SegmentedControl<int>(
                width: 170,
                segments: [
                  for (final v in const [10, 20, 40]) Segment(v, '$v'),
                ],
                value: s.chatContextMessages,
                onChanged: (v) => n.update((x) => x.copyWith(chatContextMessages: v)),
              ),
            ),
            SettingRow(title: context.l10n.chatPrivacy),
          ],
        ),
        SettingsGroup(
          title: context.l10n.delivery,
          children: [
            SettingRow(title: context.l10n.readAloudTitle, subtitle: context.l10n.readAloudHeadphones),
            if (voices.isNotEmpty)
              SettingRow(
                title: context.l10n.voice,
                trailing: SottoSelect<String?>(
                  width: 230,
                  value: s.ttsVoice,
                  options: [
                    SelectOption<String?>(null, context.l10n.systemDefault),
                    for (final v in voices.take(60)) SelectOption<String?>(v, v),
                  ],
                  onChanged: (v) => n.update((x) => x.copyWith(ttsVoice: v)),
                ),
              ),
            SettingRow(
              title: context.l10n.copyForChatAsks,
              trailing: Text(
                context.l10n.holdKeyHalfSecond(PlatformKeys.describe(s.shortcutFor(LiveAction.sendToChat))),
                style: TypeScale.mono.copyWith(color: p.inkSecondary, fontWeight: FontWeight.w400),
              ),
            ),
          ],
        ),
      ],
      right: [
        SettingsGroup(
          title: context.l10n.pfMeetingChat,
          children: [SettingRow(title: context.l10n.copyThenPaste, subtitle: context.l10n.copyThenPasteSub)],
        ),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SottoIcon(SottoIcons.shield, size: 14, color: p.inkSecondary),
                  const SizedBox(width: 8),
                  Text(context.l10n.whatLeaves, style: TypeScale.bodyStrong.copyWith(color: p.inkPrimary)),
                ],
              ),
              const SizedBox(height: 12),
              _Leaves(ok: false, text: context.l10n.leavesAudio),
              _Leaves(ok: true, text: context.l10n.leavesQuestion),
              _Leaves(ok: true, text: context.l10n.leavesNothingElse),
              const SizedBox(height: 8),
              TextLink('${context.l10n.setPrivacy}  ›', muted: true, onTap: () => context.go('/settings/privacy')),
            ],
          ),
        ),
      ],
    );
  }
}

class _Leaves extends StatelessWidget {
  const _Leaves({required this.ok, required this.text});
  final bool ok;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SottoIcon(ok ? SottoIcons.check : SottoIcons.close, size: 13, color: ok ? p.confirmed : p.inkTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TypeScale.body.copyWith(color: p.inkSecondary)),
          ),
        ],
      ),
    );
  }
}

/// Settings → Answers → Questionnaires on screen (chord + F).
class _QuestionnairesGroup extends ConsumerStatefulWidget {
  const _QuestionnairesGroup();

  @override
  ConsumerState<_QuestionnairesGroup> createState() => _QuestionnairesGroupState();
}

class _QuestionnairesGroupState extends ConsumerState<_QuestionnairesGroup> {
  /// macOS: Accessibility (read and fill forms) and Screen Recording.
  bool? _trusted;
  ScreenPermission? _screen;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  Future<void> _check() async {
    final trusted = await ref.read(formAccessProvider).hasPermission();
    final screen = await ref.read(screenServiceProvider).permission();
    if (!mounted) return;
    setState(() {
      _trusted = trusted;
      _screen = screen;
    });
  }

  /// Turning it on asks macOS for both permissions (each prompt appears
  /// once; after that, only System Settings can grant them).
  Future<void> _toggle(bool on) async {
    ref.read(settingsProvider.notifier).update((x) => x.copyWith(formsEnabled: on));
    if (!on || !Platform.isMacOS) return;
    if (_trusted == false) await ref.read(formAccessProvider).requestPermission();
    if (_screen == ScreenPermission.denied) await ref.read(screenServiceProvider).requestPermission();
    await _check();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final keys = PlatformKeys.describe(s.shortcutFor(LiveAction.fillForm));
    final stop = PlatformKeys.describe(s.shortcutFor(LiveAction.agentStop));
    return SettingsGroup(
      title: l.formsGroup,
      children: [
        SettingRow(
          title: l.formsEnable,
          subtitle: l.formsEnableSub(keys),
          trailing: SottoToggle(value: s.formsEnabled, onChanged: (v) => unawaited(_toggle(v))),
        ),
        if (s.formsEnabled && Platform.isMacOS && _trusted == false)
          SettingRow(
            title: l.accessibilityMissing,
            subtitle: l.accessibilityMissingSub,
            leading: SottoIcon(SottoIcons.alert, size: 14, color: p.cueText),
            trailing: SottoButton(
              label: l.openSystemSettings,
              size: ButtonSize.small,
              onPressed: () => unawaited(ref.read(screenServiceProvider).openPrivacySettings('accessibility')),
            ),
          ),
        if (s.formsEnabled && Platform.isMacOS && _screen == ScreenPermission.denied)
          SettingRow(
            title: l.screenPermissionMissing,
            subtitle: l.screenPermissionMissingSub,
            leading: SottoIcon(SottoIcons.alert, size: 14, color: p.cueText),
            trailing: SottoButton(
              label: l.openSystemSettings,
              size: ButtonSize.small,
              onPressed: () => unawaited(ref.read(screenServiceProvider).openPrivacySettings('screen')),
            ),
          ),
        if (s.formsEnabled) ...[
          SettingRow(
            title: l.autofillToggle,
            subtitle: l.autofillToggleSub,
            trailing: SottoToggle(
              value: s.formsAutoFill,
              onChanged: (v) => ref.read(autoFillControllerProvider.notifier).setEnabled(v),
            ),
          ),
          SettingRow(
            title: l.formsScrollTitle,
            subtitle: l.formsScrollSub,
            trailing: SottoToggle(
              value: s.formsScroll,
              onChanged: (v) => n.update((x) => x.copyWith(formsScroll: v)),
            ),
          ),
          SettingRow(
            title: l.formsMode,
            trailing: SottoSelect<FormFillMode>(
              width: 230,
              value: s.formsMode,
              options: [
                SelectOption(FormFillMode.fillAutomatically, l.formsModeAuto),
                SelectOption(FormFillMode.showFirst, l.formsModeFirst),
              ],
              onChanged: (v) => n.update((x) => x.copyWith(formsMode: v)),
            ),
          ),
          SettingRow(
            title: l.formsLanguage,
            trailing: SottoSelect<FormAnswerLanguage>(
              width: 230,
              value: s.formsLanguage,
              options: [
                SelectOption(FormAnswerLanguage.sameAsForm, l.formsLangSame),
                SelectOption(FormAnswerLanguage.appLanguage, l.formsLangApp),
              ],
              onChanged: (v) => n.update((x) => x.copyWith(formsLanguage: v)),
            ),
          ),
          SettingRow(
            title: l.formsStyle,
            trailing: SegmentedControl<FormAnswerStyle>(
              width: 190,
              segments: [
                Segment(FormAnswerStyle.short, l.formsStyleShort),
                Segment(FormAnswerStyle.detailed, l.formsStyleDetailed),
              ],
              value: s.formsStyle,
              onChanged: (v) => n.update((x) => x.copyWith(formsStyle: v)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.formsInstructions, style: TypeScale.bodyStrong.copyWith(color: p.inkPrimary)),
                const SizedBox(height: 2),
                Text(l.formsInstructionsSub, style: TypeScale.caption.copyWith(color: p.inkTertiary)),
                const SizedBox(height: 8),
                SottoTextField(
                  initialValue: s.formsInstructions,
                  placeholder: l.formsInstructionsHint,
                  maxLines: 4,
                  minLines: 2,
                  onChanged: (v) => n.update((x) => x.copyWith(formsInstructions: v)),
                ),
              ],
            ),
          ),
        ],
        SettingRow(title: l.formsPrivacy, subtitle: l.formsSubmitNote(stop)),
      ],
    );
  }
}

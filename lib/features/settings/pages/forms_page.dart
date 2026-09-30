import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/icons.dart';
import '../../../core/design/theme.dart';
import '../../../core/design/typography.dart';
import '../../../core/platform/platform_keys.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/display.dart';
import '../../../data/models/settings.dart';
import '../../../data/models/shortcut.dart';
import '../../../data/repositories.dart';
import '../../../l10n/l10n.dart';
import '../../../services/screen/form_access.dart';
import '../../../services/screen/screen_service.dart';
import '../../forms/autofill_controller.dart';
import '../settings_screen.dart';

/// Settings → Forms: everything about filling questionnaires on screen —
/// auto-fill, chord + F, how answers are written, and their history.
class FormsSettingsPage extends ConsumerStatefulWidget {
  const FormsSettingsPage({super.key});

  @override
  ConsumerState<FormsSettingsPage> createState() => _FormsSettingsPageState();
}

class _FormsSettingsPageState extends ConsumerState<FormsSettingsPage> {
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
    ref
        .read(settingsProvider.notifier)
        .update((x) => x.copyWith(formsEnabled: on, formsAutoFill: on && x.formsAutoFill));
    if (!on || !Platform.isMacOS) return;
    if (_trusted == false) await ref.read(formAccessProvider).requestPermission();
    if (_screen == ScreenPermission.denied) await ref.read(screenServiceProvider).requestPermission();
    await _check();
  }

  Future<void> _autoFill(bool on) async {
    ref.read(autoFillControllerProvider.notifier).setEnabled(on);
    if (on && Platform.isMacOS) await _toggle(true);
  }

  Future<void> _clearHistory() async {
    await ref.read(sessionRepositoryProvider).clearFormRuns();
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(context.l10n.formsHistoryCleared)));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final keys = PlatformKeys.describe(s.shortcutFor(LiveAction.fillForm));
    final stop = PlatformKeys.describe(s.shortcutFor(LiveAction.agentStop));
    return SettingsPageScaffold(
      title: l.setForms,
      description: l.formsDescription,
      left: [
        SettingsGroup(
          title: l.formsAutofillGroup,
          children: [
            SettingRow(
              title: l.autofillToggle,
              subtitle: l.autofillToggleSub,
              trailing: SottoToggle(value: s.formsAutoFill, onChanged: (v) => unawaited(_autoFill(v))),
            ),
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
              title: l.formsScrollTitle,
              subtitle: l.formsScrollSub,
              trailing: SottoToggle(
                value: s.formsScroll,
                onChanged: (v) => n.update((x) => x.copyWith(formsScroll: v)),
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: l.formsAnswersGroup,
          children: [
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
          ],
        ),
      ],
      right: [
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SottoIcon(SottoIcons.shield, size: 14, color: p.inkSecondary),
                  const SizedBox(width: 8),
                  Text(l.whatLeaves, style: TypeScale.bodyStrong.copyWith(color: p.inkPrimary)),
                ],
              ),
              const SizedBox(height: 10),
              Text(l.formsPrivacyNote, style: TypeScale.body.copyWith(color: p.inkSecondary)),
              const SizedBox(height: 8),
              Text(l.formsSubmitNote(stop), style: TypeScale.caption.copyWith(color: p.inkTertiary)),
            ],
          ),
        ),
        SettingsGroup(
          title: l.formsHistoryGroup,
          children: [
            SettingRow(
              title: l.formsClearHistory,
              subtitle: s.historyRetentionDays == 0 ? l.formsHistoryOff : l.formsClearHistorySub,
              trailing: SottoButton(
                label: l.formsClearHistory,
                size: ButtonSize.small,
                onPressed: () => unawaited(_clearHistory()),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

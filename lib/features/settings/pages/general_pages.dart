import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import '../../../l10n/l10n.dart';

import '../../../core/design/icons.dart';
import '../../../core/design/theme.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/typography.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/display.dart';
import '../../../data/models/settings.dart';
import '../../../data/repositories.dart';
import '../../../data/storage/secret_store.dart';
import '../../../core/platform/external_links.dart';
import '../../../core/secrets.dart';
import '../../../services/ai/deepseek_models.dart';
import '../../../services/ai/llm_client.dart';
import '../../../services/screen/screen_service.dart';
import '../../library/readiness.dart';
import '../settings_screen.dart';

// ─────────────────────────── General ───────────────────────────

final _dataDirProvider = FutureProvider<String>((ref) async => (await getApplicationSupportDirectory()).path);

class GeneralPage extends ConsumerWidget {
  const GeneralPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final dir = ref.watch(_dataDirProvider).value;
    return SettingsPageScaffold(
      title: context.l10n.setGeneral,
      description: context.l10n.generalDescription,
      left: [
        SettingsGroup(
          title: context.l10n.interface,
          children: [
            SettingRow(
              title: context.l10n.interfaceLanguage,
              subtitle: context.l10n.interfaceLanguageSub,
              trailing: SegmentedControl<AppLanguage>(
                width: 250,
                segments: [
                  Segment(AppLanguage.system, context.l10n.langSystem, icon: SottoIcons.globe),
                  // Language names are written in their own language.
                  const Segment(AppLanguage.en, 'English'),
                  const Segment(AppLanguage.es, 'Español'),
                ],
                value: s.uiLanguage,
                onChanged: (v) => n.update((x) => x.copyWith(uiLanguage: v)),
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: context.l10n.pace,
          children: [
            SettingRow(
              title: context.l10n.wordsPerMinute,
              subtitle: context.l10n.wordsPerMinuteSub,
              trailing: SottoSlider(
                value: s.wordsPerMinute.toDouble(),
                min: 100,
                max: 200,
                divisions: 50,
                marker: 148,
                label: '${s.wordsPerMinute}',
                onChanged: (v) => n.update((x) => x.copyWith(wordsPerMinute: v.round())),
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: context.l10n.storage,
          children: [
            SettingRow(
              title: context.l10n.dataFolder,
              subtitle: dir ?? '…',
              trailing: SottoButton(
                label: context.l10n.copyPath,
                size: ButtonSize.small,
                icon: SottoIcons.copy,
                onPressed: dir == null ? null : () => Clipboard.setData(ClipboardData(text: dir)),
              ),
            ),
            SettingRow(
              title: context.l10n.format,
              subtitle: context.l10n.formatSub,
            ),
          ],
        ),
        SettingsGroup(
          title: context.l10n.reset,
          children: [
            SettingRow(
              title: context.l10n.resetAllSettings,
              subtitle: context.l10n.resetAllSettingsSub,
              trailing: SottoButton(
                label: context.l10n.reset,
                size: ButtonSize.small,
                onPressed: () => n.update((_) => const AppSettings(onboarded: true)),
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
              Text(context.l10n.aboutSotto, style: TypeScale.bodyStrong.copyWith(color: p.inkPrimary)),
              const SizedBox(height: 6),
              Text(
                context.l10n.aboutSottoBody,
                style: TypeScale.body.copyWith(color: p.inkSecondary),
              ),
              const SizedBox(height: 12),
              Text(context.l10n.versionLine, style: TypeScale.monoSmall.copyWith(color: p.inkTertiary)),
              const SizedBox(height: 4),
              Text(
                context.l10n.typefaces,
                style: TypeScale.caption.copyWith(color: p.inkTertiary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────── Integrations ───────────────────────────

class IntegrationsPage extends ConsumerStatefulWidget {
  const IntegrationsPage({super.key});

  @override
  ConsumerState<IntegrationsPage> createState() => _IntegrationsPageState();
}

class _IntegrationsPageState extends ConsumerState<IntegrationsPage> {
  final _key = TextEditingController();
  bool _saved = false;
  String? _testResult;
  bool _testOk = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadKey());
  }

  Future<void> _loadKey() async {
    final saved = await ref.read(secretStoreProvider).read(SecretKey.deepseekApiKey);
    if (!mounted) return;
    setState(() {
      _key.text = saved ?? '';
      _saved = saved != null;
    });
  }

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _saveKey() async {
    await ref.read(secretStoreProvider).write(SecretKey.deepseekApiKey, _key.text);
    ref
      ..invalidate(readinessProvider)
      ..invalidate(deepSeekModelsProvider);
    if (mounted) setState(() => _saved = _key.text.trim().isNotEmpty);
  }

  Future<void> _test() async {
    await _saveKey();
    final client = await LlmClient.forSettings(ref.read(settingsProvider), ref.read(secretStoreProvider));
    if (!mounted) return;
    if (client == null) {
      setState(() {
        _testOk = false;
        _testResult = L10n.current.addKeyFirst;
      });
      return;
    }
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final sw = Stopwatch()..start();
    try {
      int? firstToken;
      await for (final _ in client.stream(
        system: 'Reply with the single word: ready',
        user: 'Are you there?',
        maxTokens: 16,
      )) {
        firstToken ??= sw.elapsedMilliseconds;
      }
      if (!mounted) return;
      setState(() {
        _testOk = true;
        _testResult = L10n.current.connectedFirstToken(
          NumberFormat('0.00', L10n.current.localeName).format((firstToken ?? sw.elapsedMilliseconds) / 1000),
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testResult = e is LlmException ? e.message : '$e';
      });
    } finally {
      client.close();
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    final s = ref.watch(settingsProvider);
    final models = ref.watch(deepSeekModelsProvider);
    // The saved model stays selectable even if the list doesn't have it (yet).
    final available = models.value ?? const <DeepSeekModel>[];
    final readsImages = {for (final m in available) m.id: m.images};
    final ids = {...readsImages.keys, s.aiModel}.toList()..sort();

    return SettingsPageScaffold(
      title: l.setIntegrations,
      description: kDeepSeekApiKey.isEmpty ? l.integrationsDescription : l.integrationsDescriptionBuiltIn,
      left: [
        SettingsGroup(
          title: 'DeepSeek',
          footer: l.deepseekFooter,
          children: [
            SettingRow(
              title: l.apiKey,
              subtitle: kDeepSeekApiKey.isEmpty ? null : l.apiKeyOverrideSub,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_saved) ...[
                    SottoIcon(SottoIcons.lock, size: 12, color: p.confirmed),
                    const SizedBox(width: 5),
                    Text(l.inKeychain, style: TypeScale.caption.copyWith(color: p.confirmed)),
                    const SizedBox(width: 10),
                  ],
                  SottoTextField(
                    width: 240,
                    controller: _key,
                    obscure: true,
                    mono: true,
                    placeholder: kDeepSeekApiKey.isEmpty ? 'sk-…' : l.builtInKey,
                    onSubmitted: (_) => unawaited(_saveKey()),
                  ),
                  const SizedBox(width: 8),
                  SottoButton(label: l.save, size: ButtonSize.small, onPressed: () => unawaited(_saveKey())),
                ],
              ),
            ),
            SettingRow(
              title: l.model,
              subtitle: switch (models) {
                AsyncLoading() => l.modelsLoading,
                AsyncError(:final error) => l.modelsLoadFailed(error is LlmException ? error.message : '$error'),
                _ => null,
              },
              trailing: SottoSelect<String>(
                width: 240,
                value: s.aiModel,
                options: [
                  for (final id in ids) SelectOption(id, id, detail: readsImages[id] == true ? l.modelReadsImages : null),
                ],
                onChanged: (v) => ref
                    .read(settingsProvider.notifier)
                    .update((x) => x.copyWith(aiModel: v, visionModel: pickVisionModel(available, v) ?? x.visionModel)),
              ),
            ),
            SettingRow(
              title: l.testConnection,
              subtitle: _testResult,
              trailing: _testing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.5))
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_testResult != null)
                          SottoIcon(
                            _testOk ? SottoIcons.check : SottoIcons.alert,
                            size: 14,
                            color: _testOk ? p.confirmed : p.cueText,
                          ),
                        const SizedBox(width: 10),
                        SottoButton(
                          label: l.test,
                          size: ButtonSize.small,
                          icon: SottoIcons.plug,
                          onPressed: () => unawaited(_test()),
                        ),
                      ],
                    ),
            ),
            SettingRow(
              title: l.deepseekPlatform,
              subtitle: 'platform.deepseek.com',
              trailing: SottoButton(
                label: l.open,
                size: ButtonSize.small,
                onPressed: () => unawaited(openExternal('https://platform.deepseek.com')),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────── Privacy ───────────────────────────

class PrivacyPage extends ConsumerWidget {
  const PrivacyPage({super.key});

  Future<bool> _confirm(BuildContext context, String title, String body) async {
    final p = context.palette;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: p.float,
            shape: RoundedRectangleBorder(
              borderRadius: Radii.rL,
              side: BorderSide(color: p.control),
            ),
            title: Text(title, style: TypeScale.title2.copyWith(color: p.inkPrimary)),
            content: Text(body, style: TypeScale.body.copyWith(color: p.inkSecondary)),
            actions: [
              SottoButton.ghost(label: context.l10n.cancel, onPressed: () => Navigator.pop(context, false)),
              SottoButton(label: context.l10n.delete, onPressed: () => Navigator.pop(context, true)),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    return SettingsPageScaffold(
      title: context.l10n.setPrivacy,
      description: context.l10n.privacyDescription,
      left: [
        SettingsGroup(
          title: context.l10n.capture,
          children: [
            SettingRow(
              title: context.l10n.hideFromCapture,
              subtitle: context.l10n.hideFromCaptureSub,
              trailing: SottoToggle(
                value: s.excludeFromCapture,
                onChanged: (v) => n.update((x) => x.copyWith(excludeFromCapture: v)),
              ),
            ),
          ],
        ),
        const _ScreenAwarenessGroup(),
        SettingsGroup(
          title: context.l10n.retention,
          children: [
            SettingRow(
              title: context.l10n.keepHistoryFor,
              trailing: SottoSelect<int>(
                width: 140,
                value: s.historyRetentionDays,
                options: [
                  SelectOption(7, context.l10n.daysCount(7)),
                  SelectOption(30, context.l10n.daysCount(30)),
                  SelectOption(90, context.l10n.daysCount(90)),
                  SelectOption(365, context.l10n.aYear),
                ],
                onChanged: (v) {
                  n.update((x) => x.copyWith(historyRetentionDays: v));
                  unawaited(ref.read(qaRepositoryProvider).prune(v));
                },
              ),
            ),
            SettingRow(
              title: context.l10n.deleteQaHistory,
              trailing: SottoButton(
                label: context.l10n.delete,
                size: ButtonSize.small,
                onPressed: () async {
                  if (await _confirm(
                    context,
                    context.l10n.deleteQaHistoryConfirm,
                    context.l10n.deleteQaHistoryBody,
                  )) {
                    await ref.read(qaRepositoryProvider).clear();
                  }
                },
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: context.l10n.dangerZone,
          children: [
            SettingRow(
              title: context.l10n.removeApiKeys,
              subtitle: context.l10n.removeApiKeysSub,
              trailing: SottoButton(
                label: context.l10n.remove,
                size: ButtonSize.small,
                onPressed: () async {
                  if (await _confirm(context, context.l10n.removeApiKeysConfirm, context.l10n.removeApiKeysBody)) {
                    await ref.read(secretStoreProvider).wipe();
                    ref.invalidate(readinessProvider);
                  }
                },
              ),
            ),
            SettingRow(
              title: context.l10n.deleteAllData,
              subtitle: context.l10n.deleteAllDataSub,
              trailing: SottoButton(
                label: context.l10n.deleteEverything,
                size: ButtonSize.small,
                onPressed: () async {
                  if (await _confirm(
                    context,
                    context.l10n.deleteAllDataConfirm,
                    context.l10n.deleteAllDataBody,
                  )) {
                    await ref.read(localStoreProvider).wipe();
                    if (context.mounted) context.go('/');
                  }
                },
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
              Text(context.l10n.whatLeaves, style: TypeScale.bodyStrong.copyWith(color: p.inkPrimary)),
              const SizedBox(height: 12),
              for (final (label, text) in [
                (context.l10n.privVoice, context.l10n.privVoiceBody),
                (context.l10n.privRoom, context.l10n.privRoomBody),
                (context.l10n.privAnswers, context.l10n.privAnswersBody),
                (context.l10n.privScreen, s.screenAwareness ? context.l10n.privScreenOnBody : context.l10n.privScreenOffBody),
                (context.l10n.privModels, context.l10n.privModelsBody),
                (context.l10n.privConsent, context.l10n.privConsentBody),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text(label, style: TypeScale.bodyStrong.copyWith(color: p.inkPrimary)),
                      ),
                      Expanded(
                        child: Text(text, style: TypeScale.body.copyWith(color: p.inkSecondary)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Opt-in for screenshots. Off by default; nothing is captured until the
/// presenter asks, and nothing is kept.
class _ScreenAwarenessGroup extends ConsumerStatefulWidget {
  const _ScreenAwarenessGroup();

  @override
  ConsumerState<_ScreenAwarenessGroup> createState() => _ScreenAwarenessGroupState();
}

class _ScreenAwarenessGroupState extends ConsumerState<_ScreenAwarenessGroup> {
  ScreenPermission? _permission;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  Future<void> _check() async {
    final p = await ref.read(screenServiceProvider).permission();
    if (mounted) setState(() => _permission = p);
  }

  Future<void> _toggle(bool on) async {
    ref.read(settingsProvider.notifier).update((x) => x.copyWith(screenAwareness: on));
    // macOS asks once, the first time it is turned on.
    if (on && _permission == ScreenPermission.denied) {
      await ref.read(screenServiceProvider).requestPermission();
      await _check();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = context.palette;
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final on = s.screenAwareness;
    return SettingsGroup(
      title: l.screenAwareness,
      footer: l.screenAwarenessFooter,
      children: [
        SettingRow(
          title: l.screenAwarenessToggle,
          subtitle: l.screenAwarenessToggleSub,
          trailing: SottoToggle(value: on, onChanged: (v) => unawaited(_toggle(v))),
        ),
        if (on) ...[
          SettingRow(
            title: l.screenTarget,
            trailing: SottoSelect<ScreenTarget>(
              width: 220,
              value: s.screenTarget,
              options: [
                SelectOption(ScreenTarget.overlayDisplay, l.screenTargetOverlay),
                SelectOption(ScreenTarget.cursorDisplay, l.screenTargetCursor),
              ],
              onChanged: (v) => n.update((x) => x.copyWith(screenTarget: v)),
            ),
          ),
          SettingRow(
            title: l.attachSlide,
            subtitle: l.attachSlideSub,
            trailing: SottoToggle(
              value: s.attachSlideToAnswers,
              onChanged: (v) => n.update((x) => x.copyWith(attachSlideToAnswers: v)),
            ),
          ),
          if (Platform.isMacOS && _permission == ScreenPermission.denied)
            SettingRow(
              title: l.screenPermissionMissing,
              subtitle: l.screenPermissionMissingSub,
              leading: SottoIcon(SottoIcons.alert, size: 14, color: p.cueText),
              trailing: SottoButton(
                label: l.openSystemSettings,
                size: ButtonSize.small,
                onPressed: () async {
                  await ref.read(screenServiceProvider).openPrivacySettings('screen');
                },
              ),
            ),
        ],
      ],
    );
  }
}

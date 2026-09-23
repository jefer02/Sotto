import 'dart:async';

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
import '../../../services/ai/llm_client.dart';
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
  final _aiKey = TextEditingController();
  final _sttKey = TextEditingController();
  final _model = TextEditingController();
  final _baseUrl = TextEditingController();
  final _sttModel = TextEditingController();
  final _sttBase = TextEditingController();
  bool _aiSaved = false;
  bool _sttSaved = false;
  String? _testResult;
  bool _testOk = false;
  bool _testing = false;

  SecretKey _keyFor(AiProvider p) => switch (p) {
    AiProvider.anthropic => SecretKey.anthropicApiKey,
    AiProvider.openai => SecretKey.openaiApiKey,
    AiProvider.openaiCompatible => SecretKey.compatibleApiKey,
  };

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _model.text = s.aiModel;
    _baseUrl.text = s.aiBaseUrl;
    _sttModel.text = s.cloudSttModel;
    _sttBase.text = s.cloudSttBaseUrl;
    unawaited(_loadKeys());
  }

  Future<void> _loadKeys() async {
    final secrets = ref.read(secretStoreProvider);
    final s = ref.read(settingsProvider);
    final ai = await secrets.read(_keyFor(s.aiProvider));
    final stt = await secrets.read(SecretKey.cloudSttApiKey);
    if (!mounted) return;
    setState(() {
      _aiKey.text = ai ?? '';
      _sttKey.text = stt ?? '';
      _aiSaved = ai != null;
      _sttSaved = stt != null;
    });
  }

  @override
  void dispose() {
    for (final c in [_aiKey, _sttKey, _model, _baseUrl, _sttModel, _sttBase]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _saveAiKey() async {
    final s = ref.read(settingsProvider);
    await ref.read(secretStoreProvider).write(_keyFor(s.aiProvider), _aiKey.text);
    ref.invalidate(readinessProvider);
    if (mounted) setState(() => _aiSaved = _aiKey.text.trim().isNotEmpty);
  }

  Future<void> _test() async {
    await _saveAiKey();
    final s = ref.read(settingsProvider);
    final key = await ref.read(secretStoreProvider).read(_keyFor(s.aiProvider));
    if (key == null && s.aiProvider != AiProvider.openaiCompatible) {
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
    final client = LlmClient.create(s, key ?? '');
    final sw = Stopwatch()..start();
    try {
      int? firstToken;
      final buf = StringBuffer();
      await for (final t in client.stream(
        system: 'Reply with the single word: ready',
        user: 'Are you there?',
        maxTokens: 16,
      )) {
        firstToken ??= sw.elapsedMilliseconds;
        buf.write(t);
      }
      setState(() {
        _testOk = true;
        _testResult =
            L10n.current.connectedFirstToken(
              NumberFormat('0.00', L10n.current.localeName).format((firstToken ?? sw.elapsedMilliseconds) / 1000),
            );
      });
    } catch (e) {
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
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);

    Widget saved(bool v) => v
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SottoIcon(SottoIcons.lock, size: 12, color: p.confirmed),
              const SizedBox(width: 5),
              Text(context.l10n.inKeychain, style: TypeScale.caption.copyWith(color: p.confirmed)),
            ],
          )
        : const SizedBox.shrink();

    return SettingsPageScaffold(
      title: context.l10n.setIntegrations,
      description: context.l10n.integrationsDescription,
      left: [
        SettingsGroup(
          title: context.l10n.answersModel,
          children: [
            SettingRow(
              title: context.l10n.provider,
              trailing: SegmentedControl<AiProvider>(
                width: 330,
                segments: [for (final a in AiProvider.values) Segment(a, a.label)],
                value: s.aiProvider,
                onChanged: (v) {
                  n.update((x) => x.copyWith(aiProvider: v, aiModel: v.defaultModel, aiBaseUrl: ''));
                  _model.text = v.defaultModel;
                  _baseUrl.text = '';
                  unawaited(_loadKeys());
                },
              ),
            ),
            SettingRow(
              title: context.l10n.apiKey,
              subtitle: s.aiProvider == AiProvider.openaiCompatible
                  ? context.l10n.apiKeyOptional
                  : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  saved(_aiSaved),
                  const SizedBox(width: 10),
                  SottoTextField(
                    width: 240,
                    controller: _aiKey,
                    obscure: true,
                    mono: true,
                    placeholder: s.aiProvider == AiProvider.anthropic ? 'sk-ant-…' : 'sk-…',
                    onSubmitted: (_) => unawaited(_saveAiKey()),
                  ),
                  const SizedBox(width: 8),
                  SottoButton(label: context.l10n.save, size: ButtonSize.small, onPressed: () => unawaited(_saveAiKey())),
                ],
              ),
            ),
            SettingRow(
              title: context.l10n.model,
              subtitle: s.aiProvider == AiProvider.anthropic ? context.l10n.modelLowEffort : null,
              trailing: SottoTextField(
                width: 240,
                controller: _model,
                mono: true,
                placeholder: s.aiProvider.defaultModel,
                onChanged: (v) => n.update((x) => x.copyWith(aiModel: v.trim())),
              ),
            ),
            SettingRow(
              title: context.l10n.baseUrl,
              subtitle: context.l10n.baseUrlSub(s.aiProvider.defaultBaseUrl),
              trailing: SottoTextField(
                width: 240,
                controller: _baseUrl,
                mono: true,
                placeholder: s.aiProvider.defaultBaseUrl,
                onChanged: (v) => n.update((x) => x.copyWith(aiBaseUrl: v.trim())),
              ),
            ),
            SettingRow(
              title: context.l10n.testConnection,
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
                          label: context.l10n.test,
                          size: ButtonSize.small,
                          icon: SottoIcons.plug,
                          onPressed: () => unawaited(_test()),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ],
      right: [
        SettingsGroup(
          title: context.l10n.cloudStt,
          footer: context.l10n.cloudSttFooter,
          children: [
            SettingRow(
              title: context.l10n.provider,
              trailing: SegmentedControl<CloudSttProvider>(
                width: 230,
                segments: [
                  Segment(CloudSttProvider.openai, 'OpenAI'),
                  Segment(CloudSttProvider.openaiCompatible, context.l10n.compatible),
                ],
                value: s.cloudSttProvider,
                onChanged: (v) => n.update((x) => x.copyWith(cloudSttProvider: v)),
              ),
            ),
            SettingRow(
              title: context.l10n.apiKey,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  saved(_sttSaved),
                  const SizedBox(width: 10),
                  SottoTextField(
                    width: 200,
                    controller: _sttKey,
                    obscure: true,
                    mono: true,
                    placeholder: 'sk-…',
                    onSubmitted: (_) async {
                      await ref.read(secretStoreProvider).write(SecretKey.cloudSttApiKey, _sttKey.text);
                      setState(() => _sttSaved = _sttKey.text.trim().isNotEmpty);
                    },
                  ),
                  const SizedBox(width: 8),
                  SottoButton(
                    label: context.l10n.save,
                    size: ButtonSize.small,
                    onPressed: () async {
                      await ref.read(secretStoreProvider).write(SecretKey.cloudSttApiKey, _sttKey.text);
                      ref.invalidate(readinessProvider);
                      setState(() => _sttSaved = _sttKey.text.trim().isNotEmpty);
                    },
                  ),
                ],
              ),
            ),
            SettingRow(
              title: context.l10n.model,
              trailing: SottoTextField(
                width: 200,
                controller: _sttModel,
                mono: true,
                placeholder: 'whisper-1',
                onChanged: (v) => n.update((x) => x.copyWith(cloudSttModel: v.trim().isEmpty ? 'whisper-1' : v.trim())),
              ),
            ),
            if (s.cloudSttProvider == CloudSttProvider.openaiCompatible)
              SettingRow(
                title: context.l10n.baseUrl,
                trailing: SottoTextField(
                  width: 200,
                  controller: _sttBase,
                  mono: true,
                  placeholder: 'https://…/v1',
                  onChanged: (v) => n.update((x) => x.copyWith(cloudSttBaseUrl: v.trim())),
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

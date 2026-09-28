import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:record/record.dart';
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
import '../../../domain/following/follow_engine.dart';
import '../../../domain/following/script_aligner.dart';
import '../../../domain/following/text_normalizer.dart';
import '../../../services/speech/audio_capture.dart';
import '../../../services/speech/model_manager.dart';
import '../../../services/speech/speech_session.dart';
import '../../library/readiness.dart';
import '../settings_screen.dart';
import 'appearance_page.dart' show previewScriptProvider;

const languages = [
  SelectOption('en-US', 'English (United States)'),
  SelectOption('en-GB', 'English (United Kingdom)'),
  SelectOption('es-419', 'Español (Latinoamérica)'),
  SelectOption('es-ES', 'Español (España)'),
  SelectOption('pt-BR', 'Português (Brasil)'),
  SelectOption('fr-FR', 'Français'),
  SelectOption('de-DE', 'Deutsch'),
  SelectOption('it-IT', 'Italiano'),
];

final inputDevicesProvider = FutureProvider<List<InputDevice>>((ref) async {
  final r = AudioRecorder();
  try {
    return await r.listInputDevices();
  } finally {
    await r.dispose();
  }
});

class VoicePage extends ConsumerStatefulWidget {
  const VoicePage({super.key});

  @override
  ConsumerState<VoicePage> createState() => _VoicePageState();
}

class _VoicePageState extends ConsumerState<VoicePage> {
  AudioCapture? _monitor;
  StreamSubscription<double>? _levelSub;
  double _level = 0;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_startMonitor());
  }

  Future<void> _startMonitor() async {
    await _stopMonitor();
    final s = ref.read(settingsProvider);
    final cap = AudioCapture();
    try {
      await cap.start(deviceId: s.microphoneId, noiseSuppression: s.noiseSuppression);
      _monitor = cap;
      _levelSub = cap.level.listen((l) {
        if (mounted) setState(() => _level = l);
      });
    } catch (_) {
      await cap.dispose();
    }
  }

  Future<void> _stopMonitor() async {
    await _levelSub?.cancel();
    _levelSub = null;
    await _monitor?.dispose();
    _monitor = null;
  }

  @override
  void dispose() {
    unawaited(_stopMonitor());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final devices = ref.watch(inputDevicesProvider).value ?? const <InputDevice>[];
    final readiness = ref.watch(readinessProvider).value;

    final deviceOptions = [for (final d in devices) SelectOption<String?>(d.id, d.label)];

    return SettingsPageScaffold(
      title: context.l10n.setVoice,
      description:
          context.l10n.voiceDescription,
      action: SottoButton(
        label: _testing ? context.l10n.stopTest : context.l10n.testWithScript,
        icon: SottoIcons.mic,
        onPressed: () async {
          if (_testing) {
            setState(() => _testing = false);
            await _startMonitor();
          } else {
            await _stopMonitor();
            setState(() => _testing = true);
          }
        },
      ),
      left: [
        SettingsGroup(
          title: context.l10n.pfMicrophone,
          children: [
            SettingRow(
              title: context.l10n.pfMicrophone,
              trailing: SottoSelect<String?>(
                width: 230,
                value: s.microphoneId ?? (devices.isEmpty ? null : devices.first.id),
                options: deviceOptions,
                placeholder: context.l10n.noMicrophoneFound,
                onChanged: (v) {
                  n.update((x) => x.copyWith(microphoneId: v));
                  unawaited(_startMonitor());
                },
              ),
            ),
            SettingRow(
              title: context.l10n.inputLevel,
              subtitle: context.l10n.inputLevelSub,
              trailing: LevelMeter(level: _level, bars: 14),
            ),
            SettingRow(
              title: context.l10n.noiseSuppression,
              subtitle: context.l10n.noiseSuppressionSub,
              trailing: SottoToggle(
                value: s.noiseSuppression,
                onChanged: (v) {
                  n.update((x) => x.copyWith(noiseSuppression: v));
                  unawaited(_startMonitor());
                },
              ),
            ),
            SettingRow(
              title: context.l10n.questionsComeFrom,
              subtitle:
                  context.l10n.questionsComeFromSub,
              trailing: SottoSelect<String?>(
                width: 230,
                value: s.questionInputId,
                options: [SelectOption<String?>(null, context.l10n.sameAsMicrophone), ...deviceOptions],
                onChanged: (v) =>
                    n.update((x) => v == null ? x.copyWith(clearQuestionInput: true) : x.copyWith(questionInputId: v)),
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: context.l10n.recognition,
          children: [
            SettingRow(
              title: context.l10n.language,
              trailing: SottoSelect<String>(
                width: 230,
                value: s.language,
                options: languages,
                onChanged: (v) => n.update((x) => x.copyWith(language: v)),
              ),
            ),
            SettingRow(
              title: context.l10n.alsoRecognize,
              subtitle: context.l10n.alsoRecognizeSub,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final l in s.alsoRecognize) ...[
                    GestureDetector(
                      onTap: () => n.update((x) => x.copyWith(alsoRecognize: [...x.alsoRecognize]..remove(l))),
                      child: StatusChip(
                        languages.firstWhere((o) => o.value == l, orElse: () => SelectOption(l, l)).label,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  MenuAnchor(
                    menuChildren: [
                      for (final o in languages.where(
                        (o) => o.value != s.language && !s.alsoRecognize.contains(o.value),
                      ))
                        MenuItemButton(
                          onPressed: () => n.update((x) => x.copyWith(alsoRecognize: [...x.alsoRecognize, o.value])),
                          child: Text(o.label, style: TypeScale.body),
                        ),
                    ],
                    builder: (context, c, _) => SottoIconButton(
                      icon: SottoIcons.plus,
                      tooltip: context.l10n.addLanguage,
                      onPressed: () => c.isOpen ? c.close() : c.open(),
                    ),
                  ),
                ],
              ),
            ),
            SettingRow(
              title: context.l10n.engine,
              subtitle: context.l10n.engineOnDeviceSub,
              trailing: readiness == null ? null : _Status(item: readiness.voice),
            ),
          ],
        ),
        const _ModelsGroup(),
        SettingsGroup(
          title: context.l10n.following,
          children: [
            SettingRow(
              title: context.l10n.advance,
              trailing: SegmentedControl<AdvanceMode>(
                width: 300,
                segments: [
                  Segment(AdvanceMode.voice, context.l10n.followMyVoice),
                  Segment(AdvanceMode.timed, context.l10n.timed),
                  Segment(AdvanceMode.manual, context.l10n.manual),
                ],
                value: s.advanceMode,
                onChanged: (v) => n.update((x) => x.copyWith(advanceMode: v)),
              ),
            ),
            SettingRow(
              title: context.l10n.moveOnWhenSaid,
              subtitle: context.l10n.moveOnWhenSaidSub,
              trailing: SottoSlider(
                value: s.advanceThreshold,
                min: 0.5,
                max: 1,
                divisions: 10,
                marker: 0.8,
                label: NumberFormat.percentPattern(context.l10n.localeName).format(s.advanceThreshold),
                onChanged: (v) => n.update((x) => x.copyWith(advanceThreshold: v)),
              ),
            ),
            SettingRow(
              title: context.l10n.sensitivity,
              subtitle: context.l10n.sensitivitySub,
              trailing: SegmentedControl<Sensitivity>(
                width: 210,
                segments: [
                  Segment(Sensitivity.low, context.l10n.low),
                  Segment(Sensitivity.medium, context.l10n.medium),
                  Segment(Sensitivity.high, context.l10n.high),
                ],
                value: s.sensitivity,
                onChanged: (v) => n.update((x) => x.copyWith(sensitivity: v)),
              ),
            ),
            SettingRow(
              title: context.l10n.holdStill,
              subtitle: context.l10n.holdStillSub,
              trailing: SottoToggle(
                value: s.holdDuringAdLib,
                onChanged: (v) => n.update((x) => x.copyWith(holdDuringAdLib: v)),
              ),
            ),
            SettingRow(
              title: context.l10n.allowJumps,
              subtitle: context.l10n.allowJumpsSub,
              trailing: SottoToggle(
                value: s.allowSectionJumps,
                onChanged: (v) => n.update((x) => x.copyWith(allowSectionJumps: v)),
              ),
            ),
          ],
        ),
      ],
      right: [
        _LiveCheck(active: _testing),
        const _PaceCard(),
      ],
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.item});
  final ReadinessItem item;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ok = item.level == CheckLevel.ok;
    return Tooltip(
      message: item.detail ?? '',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: ok ? p.confirmed : p.cueFill),
          ),
          const SizedBox(width: 6),
          Text(ok ? context.l10n.filterReady : context.l10n.needsSetup, style: TypeScale.caption.copyWith(color: ok ? p.confirmed : p.cueText)),
        ],
      ),
    );
  }
}

class _ModelsGroup extends ConsumerWidget {
  const _ModelsGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final status = ref.watch(modelStatusProvider);
    final notifier = ref.read(modelStatusProvider.notifier);
    return SettingsGroup(
      title: context.l10n.onDeviceModels,
      footer: context.l10n.onDeviceModelsFooter,
      children: [
        for (final m in ModelCatalog.all)
          SettingRow(
            title: m.name,
            subtitle: '${m.description} · ${m.sizeMb} MB',
            trailing: switch (status[m.id]) {
              ModelReady() => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SottoIcon(SottoIcons.check, size: 14, color: p.confirmed),
                  const SizedBox(width: 6),
                  Text(context.l10n.installed, style: TypeScale.caption.copyWith(color: p.confirmed)),
                  const SizedBox(width: 8),
                  SottoIconButton(icon: SottoIcons.close, tooltip: context.l10n.removeModel, onPressed: () => notifier.remove(m)),
                ],
              ),
              ModelDownloading(:final progress, :final extracting) => SizedBox(
                width: 170,
                child: Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: extracting ? null : progress,
                          minHeight: 4,
                          color: p.cueFill,
                          backgroundColor: p.float,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      extracting ? context.l10n.unpacking : '${(progress * 100).round()}%',
                      style: TypeScale.monoSmall.copyWith(color: p.inkSecondary),
                    ),
                  ],
                ),
              ),
              ModelFailed(:final error) => Tooltip(
                message: error,
                child: SottoButton(
                  label: context.l10n.retry,
                  icon: SottoIcons.refresh,
                  size: ButtonSize.small,
                  onPressed: () => notifier.download(m),
                ),
              ),
              _ => SottoButton(
                label: context.l10n.download,
                icon: SottoIcons.import,
                size: ButtonSize.small,
                onPressed: () => notifier.download(m),
              ),
            },
          ),
      ],
    );
  }
}

/// "What Sotto hears": runs the real engine against the preview script so
/// the presenter can see matching before going live.
class _LiveCheck extends ConsumerStatefulWidget {
  const _LiveCheck({required this.active});
  final bool active;

  @override
  ConsumerState<_LiveCheck> createState() => _LiveCheckState();
}

class _LiveCheckState extends ConsumerState<_LiveCheck> {
  SpeechSession? _session;
  FollowEngine? _engine;
  FlatScript? _flat;
  StreamSubscription<String>? _sub;
  String _heard = '';
  String? _error;
  DateTime? _lastHeardAt;

  @override
  void didUpdateWidget(_LiveCheck old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) unawaited(_start());
    if (!widget.active && old.active) unawaited(_stop());
  }

  Future<void> _start() async {
    final script = ref.read(previewScriptProvider);
    if (script == null) return;
    final settings = ref.read(settingsProvider);
    try {
      _flat = FlatScript.from(script, language: settings.language);
      _engine = FollowEngine(_flat!, settings: settings);
      _session = await SpeechSession.start(
        settings: settings,
        models: ref.read(modelManagerProvider),
      );
      if (!_session!.report.canFollow) {
        setState(() => _error = _session!.report.warning ?? context.l10n.noSpeechEngine);
        return;
      }
      _sub = _session!.heard.listen((t) {
        _engine!.onHeard(t);
        if (mounted) {
          setState(() {
            _heard = t;
            _lastHeardAt = DateTime.now();
          });
        }
      });
      setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _stop() async {
    await _sub?.cancel();
    _sub = null;
    await _session?.dispose();
    _session = null;
  }

  @override
  void dispose() {
    unawaited(_stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final script = ref.watch(previewScriptProvider);
    final pos = _engine?.position;
    final flat = _flat ?? (script == null ? null : FlatScript.from(script));
    final beat = flat == null || flat.length == 0 ? null : flat.beats[(pos?.beat ?? 0).clamp(0, flat.length - 1)];
    final words = beat?.displayWords ?? const <String>[];
    final spoken = pos?.spokenWords ?? 0;
    final conf = pos?.confidence ?? 0;
    final heardWords = TextNormalizer.normalizeHeard(_heard, language: ref.watch(settingsProvider).language);
    final lag = _lastHeardAt == null ? null : DateTime.now().difference(_lastHeardAt!).inMilliseconds;

    return SettingsGroup(
      title: context.l10n.liveCheck,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(context.l10n.whatSottoHears, style: TypeScale.bodyStrong.copyWith(color: p.inkPrimary)),
                  const Spacer(),
                  SottoIcon(SottoIcons.wave, size: 12, color: p.inkTertiary),
                  const SizedBox(width: 6),
                  Text(
                    widget.active
                        ? (lag == null ? context.l10n.listeningLower : context.l10n.listeningLag(math.min(lag, 999)))
                        : context.l10n.idle,
                    style: TypeScale.caption.copyWith(color: p.inkTertiary),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (_error != null)
                Text(_error!, style: TypeScale.body.copyWith(color: p.inkSecondary))
              else if (!widget.active)
                Text(
                  script == null
                      ? context.l10n.checkWriteFirst
                      : context.l10n.checkPressTest(script.title),
                  style: TypeScale.body.copyWith(color: p.inkSecondary),
                )
              else ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < words.length; i++)
                      Container(
                        padding: const EdgeInsets.only(bottom: 2),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              width: 2,
                              color: i < spoken ? p.confirmed : (i == spoken ? p.cueFill : Colors.transparent),
                            ),
                          ),
                        ),
                        child: Text(
                          words[i],
                          style: ReadingType.live(
                            20,
                            lineHeight: 28,
                          ).copyWith(color: i < spoken ? p.inkTertiary : p.inkPrimary),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: p.ground,
                    borderRadius: Radii.rM,
                    border: Border.all(color: p.hairline),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.l10n.heard, style: TypeScale.caption.copyWith(color: p.inkTertiary)),
                      const SizedBox(height: 6),
                      Text(
                        heardWords.isEmpty
                            ? '…'
                            : '“${heardWords.skip(math.max(0, heardWords.length - 12)).join(' ')}”',
                        style: TypeScale.mono.copyWith(fontWeight: FontWeight.w400, color: p.inkSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _Meter(label: context.l10n.positionConfidence, value: conf, color: p.confirmed),
                _Meter(label: context.l10n.beatProgress, value: words.isEmpty ? 0 : spoken / words.length, color: p.cueFill),
                if (pos?.holding ?? false)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      context.l10n.holdingWaiting,
                      style: TypeScale.caption.copyWith(color: p.inkTertiary),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Meter extends StatelessWidget {
  const _Meter({required this.label, required this.value, required this.color});
  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: TypeScale.caption.copyWith(color: p.inkSecondary)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: value.clamp(0, 1),
                minHeight: 3,
                color: color,
                backgroundColor: p.float,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 36,
            child: Text(
              value.toStringAsFixed(2),
              textAlign: TextAlign.right,
              style: TypeScale.monoSmall.copyWith(color: p.inkTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaceCard extends ConsumerWidget {
  const _PaceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final samples = s.paceSamples;
    final maxS = samples.isEmpty ? 1 : samples.reduce(math.max);
    return SurfaceCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.yourPace, style: TypeScale.caption.copyWith(color: p.inkSecondary)),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '${s.wordsPerMinute}',
                    style: TypeScale.mono.copyWith(fontSize: 24, color: p.inkPrimary, fontWeight: FontWeight.w400),
                  ),
                  const SizedBox(width: 6),
                  Text(context.l10n.wpm, style: TypeScale.monoSmall.copyWith(color: p.inkTertiary)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                samples.isEmpty
                    ? context.l10n.paceDefault
                    : context.l10n.paceFromRehearsals(samples.length),
                style: TypeScale.caption.copyWith(color: p.inkTertiary),
              ),
            ],
          ),
          const SizedBox(width: 24),
          Expanded(
            child: SizedBox(
              height: 40,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < samples.length; i++)
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        height: 12 + 28 * (samples[i] / maxS),
                        color: i == samples.length - 1 ? p.cueFill : p.emphasis,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Column(
            children: [
              SottoButton(
                label: context.l10n.recalibrate,
                size: ButtonSize.small,
                onPressed: () => n.update((x) => x.copyWith(paceSamples: const [], wordsPerMinute: 148)),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  SottoIconButton(
                    icon: SottoIcons.down,
                    tooltip: context.l10n.slower,
                    size: 24,
                    onPressed: () => n.update((x) => x.copyWith(wordsPerMinute: math.max(80, x.wordsPerMinute - 4))),
                  ),
                  SottoIconButton(
                    icon: SottoIcons.up,
                    tooltip: context.l10n.faster,
                    size: 24,
                    onPressed: () => n.update((x) => x.copyWith(wordsPerMinute: math.min(240, x.wordsPerMinute + 4))),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

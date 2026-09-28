import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

import '../../core/platform/hotkey_service.dart';
import '../../core/platform/platform_keys.dart';
import '../../data/models/settings.dart';
import '../../data/repositories.dart';
import '../../data/storage/secret_store.dart';
import '../../l10n/l10n.dart';
import '../../services/ai/llm_client.dart';
import '../../services/speech/model_manager.dart';

enum CheckLevel { ok, warn, missing }

class ReadinessItem {
  const ReadinessItem(this.label, this.level, {this.detail});
  final String label;
  final CheckLevel level;
  final String? detail;
}

class Readiness {
  const Readiness({
    required this.mic,
    required this.voice,
    required this.hotkeys,
    required this.answers,
    required this.share,
  });

  final ReadinessItem mic;
  final ReadinessItem voice;
  final ReadinessItem hotkeys;
  final ReadinessItem answers;
  final ReadinessItem share;

  List<ReadinessItem> get sidebarItems => [mic, voice, hotkeys, share];

  int get passed => sidebarItems.where((i) => i.level == CheckLevel.ok).length;
}

/// The checks behind the sidebar's "Live readiness" card and pre-flight.
final readinessProvider = FutureProvider<Readiness>((ref) async {
  final settings = ref.watch(settingsProvider);
  final models = ref.watch(modelStatusProvider);
  final secrets = ref.read(secretStoreProvider);

  final l = L10n.current;
  var micLabel = l.readyNoMic;
  var micLevel = CheckLevel.missing;
  try {
    final recorder = AudioRecorder();
    final devices = await recorder.listInputDevices();
    await recorder.dispose();
    if (devices.isNotEmpty) {
      final chosen = devices.where((d) => d.id == settings.microphoneId).firstOrNull ?? devices.first;
      micLabel = chosen.label;
      micLevel = CheckLevel.ok;
    }
  } catch (_) {}

  bool ready(SpeechModel m) => models[m.id] is ModelReady;
  final lang = settings.language.split('-').first.toUpperCase();
  final extra = settings.alsoRecognize.map((l) => l.split('-').first.toUpperCase());
  final langs = [lang, ...extra].join(', ');
  final hasCloudKey = await secrets.read(SecretKey.cloudSttApiKey) != null;

  final ReadinessItem voice;
  if (settings.advanceMode == AdvanceMode.manual) {
    voice = ReadinessItem(l.readyHotkeysOnly, CheckLevel.ok, detail: l.readyAdvanceManual);
  } else if (settings.engine == SpeechEngine.cloud) {
    voice = ReadinessItem(
      l.readyCloud(langs),
      hasCloudKey ? CheckLevel.ok : CheckLevel.missing,
      detail: hasCloudKey ? null : l.readyAddSttKey,
    );
  } else {
    final english = settings.language.toLowerCase().startsWith('en');
    final canFollow =
        (english && (ready(ModelCatalog.streamingEn) || ready(ModelCatalog.streamingEnLight))) ||
        ready(ModelCatalog.whisperBase) ||
        ready(ModelCatalog.whisperTurbo);
    voice = canFollow
        ? ReadinessItem(l.readyOnDevice(langs), CheckLevel.ok)
        : ReadinessItem(
            l.readyOnDevice(langs),
            hasCloudKey ? CheckLevel.warn : CheckLevel.missing,
            detail: l.readyDownloadModels,
          );
  }

  final hk = ref.read(hotkeyServiceProvider);
  final chord = [for (final m in settings.chord) PlatformKeys.modifierSymbol(m)].join(PlatformKeys.isMac ? '' : '+');
  final hotkeys = ReadinessItem(
    l.readyHotkeys(chord),
    hk.failures.isEmpty ? CheckLevel.ok : CheckLevel.warn,
    detail: hk.failures.isEmpty ? null : l.readyTakenByOther(hk.failures.length),
  );

  // The built-in key counts: no warning unless there is no key at all.
  final aiKey = await resolveDeepSeekKey(secrets);
  final answers = aiKey != null
      ? ReadinessItem('DeepSeek · ${settings.aiModel}', CheckLevel.ok)
      : ReadinessItem(l.readyNoKey, CheckLevel.missing, detail: l.readyAddKey);

  return Readiness(
    mic: ReadinessItem(micLabel, micLevel),
    voice: voice,
    hotkeys: hotkeys,
    answers: answers,
    share: ReadinessItem(l.readyShareWindow, CheckLevel.warn, detail: l.readyShareWarning),
  );
});

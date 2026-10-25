// Frame times of the overlay's karaoke highlight while speech recognition
// runs for real: the reading view (Glow + sparkles, Cormorant, XL) follows
// the streaming recognizer decoding a WAV in real time in its worker isolate.
// Opens its own window, sends no input anywhere, prints and exits.
//
//   flutter run --profile -d windows -t tool/karaoke_bench.dart `
//     --dart-define=SOTTO_FRAME_STATS=true `
//     --dart-define=SOTTO_BENCH_MODEL=<folder of the Spanish streaming model> `
//     --dart-define=SOTTO_BENCH_WAV=<path>\test\fixtures\speech_es\long.wav
//
// Prints FrameStats' build / raster times every 5 s, then the time from each
// position update to the end of the frame that shows it.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:sotto/core/design/theme.dart';
import 'package:sotto/core/design/tokens.dart';
import 'package:sotto/core/design/typography.dart';
import 'package:sotto/core/utils/frame_stats.dart';
import 'package:sotto/data/models/script.dart';
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/domain/following/follow_engine.dart';
import 'package:sotto/domain/following/script_aligner.dart';
import 'package:sotto/domain/overlay/backdrop_tone.dart';
import 'package:sotto/features/live/live_state.dart';
import 'package:sotto/features/live/overlay/reading_view.dart';
import 'package:sotto/features/live/overlay_palette.dart';
import 'package:sotto/l10n/l10n.dart';
import 'package:sotto/services/speech/model_manager.dart';
import 'package:sotto/services/speech/recognizers.dart';

const _model = String.fromEnvironment('SOTTO_BENCH_MODEL');
const _wav = String.fromEnvironment('SOTTO_BENCH_WAV');

/// SOTTO_BENCH_EFFECT=off|simple|glow (default glow): the same run without
/// the highlight, to compare.
final _effect = HighlightEffect.values.byName(const String.fromEnvironment('SOTTO_BENCH_EFFECT', defaultValue: 'glow'));

Float32List _readWav(String path) {
  final b = File(path).readAsBytesSync();
  final data = ByteData.sublistView(b);
  var offset = 12;
  while (offset < b.length - 8) {
    final id = String.fromCharCodes(b.sublist(offset, offset + 4));
    final size = data.getUint32(offset + 4, Endian.little);
    if (id == 'data') {
      final n = size ~/ 2;
      final out = Float32List(n);
      for (var i = 0; i < n; i++) {
        out[i] = data.getInt16(offset + 8 + i * 2, Endian.little) / 32768.0;
      }
      return out;
    }
    offset += 8 + size;
  }
  throw StateError('no data chunk');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  L10n.current = lookupAppLocalizations(const Locale('es'));
  final beats = File('${File(_wav).parent.path}/long_beats.txt')
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty)
      .toList();
  final now = DateTime(2026);
  final script = Script(
    id: 'bench',
    title: 'Bench',
    createdAt: now,
    updatedAt: now,
    sections: [
      Section(id: 'a', title: 'A', beats: [for (final b in beats) Beat.create(b)]),
    ],
  );
  final flat = FlatScript.from(script, language: 'es-MX');
  final engine = FollowEngine(
    flat,
    settings: const AppSettings(language: 'es-MX', sensitivity: Sensitivity.high, advanceThreshold: 1),
  )..jumpTo(0);
  final state = ValueNotifier(
    LiveState(phase: LivePhase.reading, script: script, flat: flat, position: engine.position),
  );

  FrameStats.label = 'karaoke-${_effect.name}';
  FrameStats.start();
  runApp(_Bench(state: state));

  final files = await ModelManager.findFiles(_model);
  final recognizer = await SherpaEngine.start(
    streaming: files,
    streams: OffsetStreams.countFor(ModelCatalog.streamingEs.chunkSeconds),
  );
  final clock = Stopwatch()..start();
  final showLatency = <double>[];
  recognizer.updates.listen((u) {
    final before = engine.position;
    engine.onUpdate(u);
    final after = engine.position;
    if (after.saidBeat == before.saidBeat && after.saidWords == before.saidWords && after.beat == before.beat) return;
    final changed = clock.elapsedMicroseconds;
    state.value = state.value.copyWith(position: after);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      // Built; the raster of that frame follows (reported by FrameStats).
      showLatency.add((clock.elapsedMicroseconds - changed) / 1000);
    });
  });

  // The WAV, in real time, in 10 ms chunks like the microphone.
  final audio = _readWav(_wav);
  const chunk = 160;
  final play = Stopwatch()..start();
  for (var i = 0, n = 1; i < audio.length; i += chunk, n++) {
    recognizer.accept(Float32List.sublistView(audio, i, math.min(i + chunk, audio.length)));
    final wait = Duration(microseconds: n * 10000) - play.elapsed;
    if (wait > Duration.zero) await Future<void>.delayed(wait);
  }
  await Future<void>.delayed(const Duration(seconds: 2));
  FrameStats.report();
  showLatency.sort();
  double pct(double p) => showLatency[math.min(showLatency.length - 1, (showLatency.length * p).floor())];
  debugPrint(
    '[bench] position update → frame built: ${showLatency.length} updates · '
    'p50 ${pct(0.5).toStringAsFixed(1)} p90 ${pct(0.9).toStringAsFixed(1)} max ${showLatency.last.toStringAsFixed(1)} ms',
  );
  await recognizer.dispose();
  exit(0);
}

class _Bench extends StatelessWidget {
  const _Bench({required this.state});
  final ValueNotifier<LiveState> state;

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings(overlayStyle: OverlayStyle.textOnly, highlightEffect: _effect);
    final theme = buildSottoTheme(
      SottoPalette.stage,
      overlay: overlayPaletteFor(settings, dark: true, backdrop: BackdropTone.dark),
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Theme(
        data: theme,
        child: ColoredBox(
          color: const Color(0xFF3E5BAA),
          child: Material(
            type: MaterialType.transparency,
            child: ValueListenableBuilder<LiveState>(
              valueListenable: state,
              builder: (context, s, _) => AnchoredScript(
                state: s,
                style: ReadingStyle(
                  size: ReadingSize.xl,
                  linesShown: 5,
                  glide: true,
                  reduceMotion: false,
                  plate: false,
                  font: const ScriptFont(family: 'Cormorant', weight: 500),
                  highlight: _effect,
                ),
                fontSize: 40,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

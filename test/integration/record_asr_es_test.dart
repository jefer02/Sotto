// Records what both Spanish following paths hear while the Spanish takes
// play in real time, so the following rules can be replayed and measured
// offline (test/domain/following_metrics_test.dart):
// * Whisper Base, segmented (what Spanish used before a streaming model);
// * the Kroko streaming transducer (what Spanish follows with now).
//
//   $env:SOTTO_RECORD_ASR=1; flutter test --no-pub test/integration/record_asr_es_test.dart
//
// Writes test/fixtures/speech_es/asr_whisper_base_<refresh>ms.json (the
// refresh following runs with; SOTTO_RECORD_REFRESH overrides it) and
// asr_kroko_es.json. SOTTO_RECORD_PATHS=whisper or =streaming records one.
// Three takes:
// * natural — natural.wav, the whole read, ad-lib included;
// * skip — beats 0–3 of natural.wav, then straight to beat 9;
// * long — long.wav: ad-libs that borrow the script's words, a long silence,
//   slow and fast passages and a skipped stretch (word truth in
//   long_truth.json, see generate_long.py).
// Each natural/skip beat's span is measured from the audio itself (first and
// last frame above the noise floor), so the replay knows where the presenter
// really was.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/services/speech/model_manager.dart';
import 'package:sotto/services/speech/recognizers.dart';

import 'native_speech.dart';

const _fixtures = 'test/fixtures/speech_es';
const _rate = 16000;

/// (start s, beat) from natural_marks.txt; beat -1 is the ad-lib.
List<(double, int)> _marks() => [
  for (final l in File('$_fixtures/natural_marks.txt').readAsLinesSync())
    if (l.trim().isNotEmpty) (double.parse(l.split(' ')[0]), int.parse(l.split(' ')[1])),
];

/// The voiced part of [audio] between [from] and [to] seconds.
(double, double) _voiced(Float32List audio, double from, double to) {
  const frame = 320; // 20 ms
  double rms(int i) {
    var sum = 0.0;
    for (var k = i; k < math.min(i + frame, audio.length); k++) {
      sum += audio[k] * audio[k];
    }
    return math.sqrt(sum / frame);
  }

  final a = (from * _rate).round(), b = math.min((to * _rate).round(), audio.length);
  int? first, last;
  for (var i = a; i + frame <= b; i += frame) {
    if (rms(i) > 0.02) {
      first ??= i;
      last = i + frame;
    }
  }
  return ((first ?? a) / _rate, (last ?? b) / _rate);
}

/// Spans [(beat, start, end)] of a take cut from natural.wav.
typedef _Span = ({int beat, double start, double end});

typedef _Take = ({String name, Float32List audio, List<_Span> spans});

Future<Map<String, Object?>> _record(LiveRecognizer r, _Take take) async {
  final updates = <Map<String, Object?>>[];
  final clock = Stopwatch()..start();
  final sub = r.updates.listen((u) => updates.add({'t': clock.elapsedMilliseconds / 1000, ...u.toJson()}));
  await playInto(r, take.audio);
  await Future<void>.delayed(const Duration(seconds: 3));
  await sub.cancel();
  return {
    'spans': [
      for (final s in take.spans) {'beat': s.beat, 'start': s.start, 'end': s.end},
    ],
    'updates': updates,
  };
}

List<_Take> _takes() {
  final natural = readWav('$_fixtures/natural.wav');
  final marks = _marks();
  final total = natural.length / _rate;

  // Every beat's voiced span in natural.wav.
  final spans = <_Span>[];
  for (var i = 0; i < marks.length; i++) {
    final next = i + 1 < marks.length ? marks[i + 1].$1 : total;
    final (start, end) = _voiced(natural, marks[i].$1, next);
    spans.add((beat: marks[i].$2, start: start, end: end));
  }

  // The skip take: beats 0–3, a breath, then beat 9 onwards.
  final cutA = marks.firstWhere((m) => m.$2 == 4).$1;
  final cutB = marks.firstWhere((m) => m.$2 == 9).$1;
  final a = Float32List.sublistView(natural, 0, (cutA * _rate).round());
  final b = Float32List.sublistView(natural, (cutB * _rate).round());
  final skip = Float32List(a.length + b.length)
    ..setAll(0, a)
    ..setAll(a.length, b);
  final shift = cutB - cutA;
  final skipSpans = [
    for (final s in spans)
      if (s.beat >= 0 && s.beat <= 3)
        s
      else if (s.beat >= 9)
        (beat: s.beat, start: s.start - shift, end: s.end - shift),
  ];
  return [
    (name: 'natural', audio: natural, spans: spans),
    (name: 'skip', audio: skip, spans: skipSpans),
    // Word-level truth lives in long_truth.json.
    (name: 'long', audio: readWav('$_fixtures/long.wav'), spans: const <_Span>[]),
  ];
}

void main() {
  final record = Platform.environment['SOTTO_RECORD_ASR'] == '1';
  final native = record && loadNativeSpeech();
  final paths = Platform.environment['SOTTO_RECORD_PATHS'];
  String? skip(SpeechModel m) => !record
      ? 'set SOTTO_RECORD_ASR=1 to record'
      : !native
      ? 'native speech libraries not built'
      : modelDir(m.id) == null
      ? 'model not installed'
      : null;

  test(
    'record Whisper Base updates for the Spanish takes',
    () async {
      final refresh = switch (Platform.environment['SOTTO_RECORD_REFRESH']) {
        final ms? => Duration(milliseconds: int.parse(ms)),
        null => SegmentedRecognizer.followingRefresh,
      };
      final files = await ModelManager.findFiles(modelDir(ModelCatalog.whisperBase.id)!);
      final engine = await SherpaEngine.start(whisper: files, language: 'es');
      final takes = <String, Object?>{};
      for (final take in _takes()) {
        final seg = SegmentedRecognizer(engine, language: 'es-MX', refresh: refresh);
        takes[take.name] = await _record(seg, take);
        await seg.dispose();
      }
      await engine.dispose();
      final out = {'model': ModelCatalog.whisperBase.id, 'refreshMs': refresh.inMilliseconds, 'takes': takes};
      File('$_fixtures/asr_whisper_base_${refresh.inMilliseconds}ms.json')
          .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(out));
    },
    skip: paths == 'streaming' ? 'streaming only' : skip(ModelCatalog.whisperBase) ?? false,
    timeout: const Timeout(Duration(minutes: 10)),
  );

  test(
    'record streaming (Kroko) updates for the Spanish takes',
    () async {
      final files = await ModelManager.findFiles(modelDir(ModelCatalog.streamingEs.id)!);
      final takes = <String, Object?>{};
      for (final take in _takes()) {
        // A fresh engine per take: its clock starts with the take.
        final engine = await SherpaEngine.start(
          streaming: files,
          streams: OffsetStreams.countFor(ModelCatalog.streamingEs.chunkSeconds),
        );
        takes[take.name] = await _record(engine, take);
        await engine.dispose();
      }
      final out = {'model': ModelCatalog.streamingEs.id, 'takes': takes};
      File('$_fixtures/asr_kroko_es.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(out));
    },
    skip: paths == 'whisper' ? 'Whisper only' : skip(ModelCatalog.streamingEs) ?? false,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

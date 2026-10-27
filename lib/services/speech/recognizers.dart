import 'dart:async';
import 'dart:math' as math;
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../domain/following/heard_update.dart';
import '../../l10n/l10n.dart';
import 'audio_capture.dart';
import 'model_manager.dart';

export '../../domain/following/heard_update.dart';

/// Continuous recognition. [updates] emits after every recognizer update;
/// [heard] is the same as plain text (finalized words + the current partial).
abstract class LiveRecognizer {
  Stream<HeardUpdate> get updates;
  Stream<String> get heard;
  void accept(Float32List samples);

  /// Forget history — e.g. when a question capture starts.
  void clear();
  Future<void> dispose();
}

/// One-shot, accurate transcription of a captured clip.
abstract class Transcriber {
  Future<String> transcribe(Float32List audio, {String? language, String? prompt});
  Future<void> dispose();
}

/// Windows 11 ships an older `onnxruntime.dll` in System32 (1.17), and
/// sherpa-onnx needs the one bundled next to the app (1.28). Whichever copy
/// the process loads first wins, so load ours by full path before sherpa
/// binds; otherwise the engine aborts with "API version [N] is not
/// available". [dirs] lists where to look — the app folder by default.
void preloadOnnxRuntime([List<String>? dirs]) {
  if (!Platform.isWindows) return;
  for (final dir in dirs ?? [p.dirname(Platform.resolvedExecutable)]) {
    final dll = p.join(dir, 'onnxruntime.dll');
    if (!File(dll).existsSync()) continue;
    try {
      DynamicLibrary.open(dll);
      return;
    } catch (_) {}
  }
}

String isoLanguage(String bcp47) => bcp47.split(RegExp('[-_]')).first.toLowerCase();

// ───────────────────────── Streaming words ─────────────────────────

/// One streaming result as the worker sends it: the open utterance's
/// words, when each began (seconds on one clock for the whole session), how
/// many are final, and whether the utterance just ended.
typedef StreamingResult = ({List<String> words, List<double> times, int stable, bool endpoint, double clock});

/// Turns a streaming transducer's tokens into words and says which are
/// final. Greedy search only ever appends tokens, so a word is final once
/// the next word has begun. The last word may still grow ("día" → "días"):
/// it is final when the utterance ends, or once [settleGap] of decoded audio
/// follows its last piece with nothing added (a word's pieces come ~0.15 s
/// apart). Replayed over natural.wav and long.wav (≈ 400 words), no word
/// called final this way ever grew afterwards, even at 0.2 s.
///
/// Per result: O(t) for t tokens since the stream's last reset (it resets in
/// long silences, see [OffsetStreams]).
class StreamingWords {
  /// [startSamples]: where on the session's clock this stream's audio
  /// begins (a stream started later than the session).
  StreamingWords({int startSamples = 0})
    : _fed = startSamples,
      _segmentStart = startSamples,
      _ignoreBefore = startSamples == 0 ? double.negativeInfinity : startSamples / AudioCapture.sampleRate + startGap;

  static const settleGap = 0.35;

  /// A stream started mid-speech hears the tail of the word in progress as
  /// a word of its own ("yellow" → "ow"): words it hears starting this soon
  /// after its start are dropped — the stream before it heard them whole.
  static const startGap = 0.25;
  final double _ignoreBefore;

  /// Samples heard since the session began, and where the open utterance
  /// started — sherpa's timestamps count from the last reset.
  int _fed;
  int _segmentStart;
  List<String> _sent = const [];
  int _sentStable = -1;

  /// Tokens since the last reset, and when the last of them was heard.
  int tokenCount = 0;
  double lastTokenAt = 0;

  double get clock => _fed / AudioCapture.sampleRate;

  /// The utterance ended (or was cleared): the next tokens start a new one.
  void reset() {
    _segmentStart = _fed;
    _sent = const [];
    _sentStable = -1;
  }

  /// The result after [samples] more samples; null when nothing changed.
  StreamingResult? next(
    List<String> tokens,
    List<double> timestamps,
    int samples, {
    required bool decoded,
    required bool endpoint,
  }) {
    _fed += samples;
    final words = <String>[];
    final times = <double>[];
    final offset = _segmentStart / AudioCapture.sampleRate;
    var lastTokenAt = 0.0;
    for (var k = 0; k < tokens.length; k++) {
      final t = tokens[k];
      // SentencePiece marks a word start with a leading space (▁).
      final starts = k == 0 || t.startsWith(' ') || t.startsWith('▁');
      final piece = t.replaceAll('▁', ' ').trim();
      if (starts) {
        words.add(piece);
        times.add(offset + (k < timestamps.length ? timestamps[k] : 0));
      } else if (words.isNotEmpty) {
        words[words.length - 1] += piece;
      }
      if (k < timestamps.length) lastTokenAt = offset + timestamps[k];
    }
    tokenCount = tokens.length;
    if (tokens.isNotEmpty) this.lastTokenAt = lastTokenAt;
    // A lone "▁" token begins a word whose letters follow: drop the empties,
    // and the fragment a late-started stream heard first.
    for (var i = words.length - 1; i >= 0; i--) {
      if (words[i].isEmpty || times[i] < _ignoreBefore) {
        words.removeAt(i);
        times.removeAt(i);
      }
    }
    final settled = endpoint || (decoded && clock - lastTokenAt >= settleGap);
    var stable = words.isEmpty ? 0 : (settled ? words.length : words.length - 1);
    // A word once called final stays final (its text can't change: see above).
    if (_sentStable > stable && _sentStable <= words.length) stable = _sentStable;
    if (words.isEmpty && _sent.isEmpty) return null;
    if (!endpoint && stable == _sentStable && _sameWords(words, _sent)) return null;
    _sent = words;
    _sentStable = stable;
    return (words: words, times: times, stable: stable, endpoint: endpoint, clock: clock);
  }

  static bool _sameWords(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// What the merged streams have to say: words newly made final (with when
/// each began), and the open words after them, which may still change.
typedef MergedResult = ({
  List<String> finals,
  List<double> finalTimes,
  List<String> open,
  List<double> openTimes,
  double clock,
});

/// Merges what offset decoders heard of the same audio (see [OffsetStreams]) on
/// when each word began: a word one stream made final that the timeline
/// already holds (the same word within [dupWindow], or anything at or before
/// the last final word) is the same word heard twice. Per result: O(w) for
/// the w words of that result.
class MergedWords {
  /// The same word, heard by two streams, starts this close (timestamps
  /// differ by a frame or two).
  static const dupWindow = 0.4;

  double _lastAt = -1;
  String _lastKey = '';
  List<String> _open = const [];

  /// Letters only: "pasado." and "pasado" are the same word.
  static String _key(String w) => w.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

  bool _known(double at, String key) => at <= _lastAt + 0.02 || (key == _lastKey && at - _lastAt < dupWindow);

  /// Takes in one stream's result; null when it adds nothing.
  MergedResult? add(StreamingResult r) {
    final finals = <String>[], finalTimes = <double>[];
    for (var k = 0; k < r.stable && k < r.words.length; k++) {
      final key = _key(r.words[k]);
      // Punctuation the model wrote as a word says nothing.
      if (key.isEmpty || _known(r.times[k], key)) continue;
      finals.add(r.words[k]);
      finalTimes.add(r.times[k]);
      _lastAt = r.times[k];
      _lastKey = key;
    }
    final open = <String>[], openTimes = <double>[];
    for (var k = r.stable; k < r.words.length; k++) {
      final key = _key(r.words[k]);
      if (key.isEmpty || _known(r.times[k], key)) continue;
      open.add(r.words[k]);
      openTimes.add(r.times[k]);
    }
    if (finals.isEmpty && StreamingWords._sameWords(open, _open)) return null;
    _open = open;
    return (finals: finals, finalTimes: finalTimes, open: open, openTimes: openTimes, clock: r.clock);
  }

  void reset() {
    _lastAt = -1;
    _lastKey = '';
    _open = const [];
  }
}

/// Several decoders on the same audio, each started a share of a chunk
/// after the one before.
///
/// The streaming model decodes in fixed 1.28 s chunks (its encoder takes
/// exactly 141 feature frames, so no setting changes this): one stream
/// emits words a few at a time, every 1.28 s, about 1 s after they end.
/// [count] streams offset by 1.28 s / [count] decode in turn. Replayed on
/// long.wav (10 ms audio chunks): word end → emitted 1.01 s with one stream,
/// 0.69 s with two, 0.53 s with four — the model's own look-ahead sets a floor
/// near 0.4 s. Each stream costs ≈ 0.1 s of CPU (two threads) per chunk, so
/// a machine too slow for that falls back to fewer ([_adapt]).
///
/// Endpoint detection is off: a reset would put the streams back in step.
/// Instead, after [resetAfterSilence] without words and once the first
/// stream holds [resetTokens] tokens, the streams reset one after the other
/// at their offsets, which keeps them staggered and their results short.
class OffsetStreams {
  OffsetStreams(this._online, {this.count = defaultCount}) {
    for (var i = 0; i < count; i++) {
      _start.add(i * _offset);
      _words.add(StreamingWords(startSamples: i * _offset));
      _streams.add(null);
    }
  }

  static const defaultCount = 1;

  /// Offset decoders for a model that decodes in [chunkSeconds] chunks: one
  /// per 0.32 s of chunk (the English model already decodes that often; the
  /// Kroko models, in 1.28 s chunks, get four).
  static int countFor(double chunkSeconds) => math.max(1, (chunkSeconds / 0.32).round());

  static const chunkSamples = AudioCapture.sampleRate * 128 ~/ 100;
  static const resetTokens = 240;
  static const resetAfterSilence = 2.0;

  final sherpa.OnlineRecognizer _online;
  final int count;
  int get _offset => chunkSamples ~/ count;
  final _streams = <sherpa.OnlineStream?>[];
  final _words = <StreamingWords>[];

  /// Where on the session's clock each stream's audio begins.
  final _start = <int>[];
  final merged = MergedWords();
  int _fed = 0;

  /// Streams in use: fewer when decoding can't keep up.
  late int active = count;
  double _decodeSeconds = 0;
  int _decodes = 0;

  MergedResult? accept(Float32List samples) {
    final from = _fed;
    _fed += samples.length;
    final results = <MergedResult>[];
    for (var i = 0; i < active; i++) {
      if (_fed <= _start[i]) continue;
      final stream = _streams[i] ??= _online.createStream();
      final skip = math.max(0, _start[i] - from);
      final r = _decode(stream, _words[i], Float32List.sublistView(samples, skip));
      if (r != null) results.add(r);
    }
    // Long silence with a long history: start over, still staggered.
    if (_words[0].tokenCount > resetTokens &&
        [for (var i = 0; i < active; i++) _words[i].clock - _words[i].lastTokenAt]
            .every((g) => g > resetAfterSilence)) {
      _restart(_fed);
    }
    if (results.isEmpty) return null;
    if (results.length == 1) return results.single;
    return (
      finals: [for (final r in results) ...r.finals],
      finalTimes: [for (final r in results) ...r.finalTimes],
      open: results.last.open,
      openTimes: results.last.openTimes,
      clock: results.last.clock,
    );
  }

  MergedResult? _decode(sherpa.OnlineStream stream, StreamingWords words, Float32List samples) {
    stream.acceptWaveform(samples: samples, sampleRate: AudioCapture.sampleRate);
    var decoded = false;
    final watch = Stopwatch()..start();
    while (_online.isReady(stream)) {
      _online.decode(stream);
      decoded = true;
    }
    if (decoded) _adapt(watch.elapsedMicroseconds / 1e6);
    final r = _online.getResult(stream);
    final result = words.next(r.tokens, r.timestamps, samples.length, decoded: decoded, endpoint: false);
    return result == null ? null : merged.add(result);
  }

  /// Keeps decoding well ahead of real time: all [active] streams together
  /// may use at most half of each chunk's duration.
  void _adapt(double seconds) {
    _decodeSeconds += seconds;
    _decodes++;
    if (_decodes < 8) return;
    final perChunk = _decodeSeconds / _decodes;
    _decodeSeconds = 0;
    _decodes = 0;
    final budget = 0.5 * chunkSamples / AudioCapture.sampleRate;
    while (active > 1 && perChunk * active > budget) {
      active = active ~/ 2;
    }
  }

  /// Every stream starts over at [at], each again its offset after the one
  /// before.
  void _restart(int at) {
    for (var i = 0; i < count; i++) {
      _streams[i]?.free();
      _streams[i] = null;
      _start[i] = at + i * _offset;
      _words[i] = StreamingWords(startSamples: _start[i]);
    }
  }

  /// Forget what was heard (a question capture starts).
  void clear() {
    _restart(_fed);
    merged.reset();
  }

  void free() {
    for (final s in _streams) {
      s?.free();
    }
  }
}

// ───────────────────────── sherpa-onnx worker ─────────────────────────

class _WorkerConfig {
  const _WorkerConfig({
    this.streaming,
    this.whisper,
    this.whisperLanguage = '',
    this.streams = OffsetStreams.defaultCount,
  });
  final ModelFiles? streaming;
  final int streams;
  final ModelFiles? whisper;
  final String whisperLanguage;
}

/// Runs in a background isolate: model inference never touches the UI
/// thread, so the overlay keeps its 120 Hz budget.
void _sherpaWorker((SendPort, _WorkerConfig) args) {
  final (main, cfg) = args;
  final inbox = ReceivePort();
  main.send(inbox.sendPort);

  sherpa.OnlineRecognizer? online;
  OffsetStreams? dual;
  sherpa.OfflineRecognizer? offline;

  try {
    preloadOnnxRuntime();
    sherpa.initBindings();
    if (cfg.streaming case final s?) {
      online = sherpa.OnlineRecognizer(
        sherpa.OnlineRecognizerConfig(
          model: sherpa.OnlineModelConfig(
            transducer: sherpa.OnlineTransducerModelConfig(
              encoder: s.encoder!,
              decoder: s.decoder!,
              joiner: s.joiner ?? '',
            ),
            tokens: s.tokens,
            numThreads: 2,
            debug: false,
          ),
          // Streams kept staggered: no endpoint resets (see OffsetStreams).
          enableEndpoint: false,
        ),
      );
      dual = OffsetStreams(online, count: cfg.streams);
    }
    if (cfg.whisper case final w?) {
      offline = sherpa.OfflineRecognizer(
        sherpa.OfflineRecognizerConfig(
          model: sherpa.OfflineModelConfig(
            whisper: sherpa.OfflineWhisperModelConfig(
              encoder: w.encoder!,
              decoder: w.decoder!,
              language: cfg.whisperLanguage,
              task: 'transcribe',
            ),
            tokens: w.tokens,
            numThreads: 3,
            debug: false,
          ),
        ),
      );
    }
    main.send(('ready', null, null));
  } catch (e) {
    main.send(('error', '$e', null));
    return;
  }

  inbox.listen((msg) {
    final (String kind, Object? payload, int? id) = msg as (String, Object?, int?);
    try {
      switch (kind) {
        case 'audio' when dual != null:
          final update = dual.accept(payload! as Float32List);
          if (update != null) main.send(('words', update, null));
        case 'reset' when dual != null:
          dual.clear();
        case 'transcribe' when offline != null:
          final s = offline.createStream();
          // Whisper wants a little trailing silence to close the last word.
          final padded = Float32List((payload! as Float32List).length + AudioCapture.sampleRate ~/ 2)
            ..setAll(0, payload as Float32List);
          s.acceptWaveform(samples: padded, sampleRate: AudioCapture.sampleRate);
          offline.decode(s);
          final text = offline.getResult(s).text;
          s.free();
          main.send(('transcript', text, id));
        case 'dispose':
          dual?.free();
          online?.free();
          offline?.free();
          inbox.close();
          Isolate.exit();
      }
    } catch (e) {
      main.send(('error', '$e', id));
    }
  });
}

/// On-device engine: streaming transducer for following, Whisper for
/// questions. Either model may be absent.
class SherpaEngine implements LiveRecognizer, Transcriber {
  SherpaEngine._();

  late final SendPort _send;
  late final Isolate _isolate;
  final _heard = StreamController<HeardUpdate>.broadcast();
  final _pending = <int, Completer<String>>{};
  var _nextId = 0;
  bool _hasStreaming = false;
  bool _hasWhisper = false;

  final _committed = <String>[];
  final _committedTimes = <double>[];
  int _committedTotal = 0;

  bool get canFollow => _hasStreaming;
  bool get canTranscribe => _hasWhisper;

  /// [streams]: offset decoders for following (see [OffsetStreams]).
  static Future<SherpaEngine> start({
    ModelFiles? streaming,
    ModelFiles? whisper,
    String language = '',
    int streams = OffsetStreams.defaultCount,
    Duration startTimeout = const Duration(seconds: 30),
  }) async {
    final engine = SherpaEngine._();
    final port = ReceivePort();
    final ready = Completer<void>();
    engine._isolate = await Isolate.spawn(_sherpaWorker, (
      port.sendPort,
      _WorkerConfig(streaming: streaming, whisper: whisper, whisperLanguage: language, streams: streams),
    ), debugName: 'sherpa-onnx');
    engine._hasStreaming = streaming != null;
    engine._hasWhisper = whisper != null;

    port.listen((msg) {
      if (msg is SendPort) {
        engine._send = msg;
        return;
      }
      final (String kind, Object? payload, int? id) = msg as (String, Object?, int?);
      switch (kind) {
        case 'ready':
          ready.complete();
        case 'words':
          engine._onWords(payload! as MergedResult);
        case 'transcript':
          engine._pending.remove(id)?.complete((payload! as String).trim());
        case 'error':
          if (!ready.isCompleted) {
            ready.completeError(StateError(L10n.current.sttEngineFailed('$payload')));
          } else if (id != null) {
            engine._pending.remove(id)?.completeError(StateError('$payload'));
          }
      }
    });
    // A worker that never says it is ready (a model that won't load) fails
    // here rather than hanging the session.
    await ready.future.timeout(startTimeout);
    return engine;
  }

  /// Final words become committed at once; the open ones are offered as
  /// tentative: following may show them when they are the script's next
  /// words, and the final words confirm or correct that.
  void _onWords(MergedResult r) {
    if (_heard.isClosed) return;
    _committed.addAll(r.finals);
    _committedTimes.addAll(r.finalTimes);
    _committedTotal += r.finals.length;
    if (_committed.length > 40) {
      _committed.removeRange(0, _committed.length - 40);
      _committedTimes.removeRange(0, _committedTimes.length - 40);
    }
    _heard.add(
      HeardUpdate(
        committed: List.of(_committed),
        committedTotal: _committedTotal,
        partial: r.open.join(' '),
        stable: 0,
        tentative: r.open.length,
        times: [..._committedTimes, ...r.openTimes],
        clock: r.clock,
      ),
    );
  }

  @override
  Stream<HeardUpdate> get updates => _heard.stream;

  @override
  Stream<String> get heard => _heard.stream.map((u) => u.text);

  @override
  void accept(Float32List samples) {
    if (_hasStreaming) _send.send(('audio', samples, null));
  }

  @override
  void clear() {
    _committed.clear();
    _committedTimes.clear();
    _committedTotal = 0;
    if (_hasStreaming) _send.send(('reset', null, null));
  }

  @override
  Future<String> transcribe(Float32List audio, {String? language, String? prompt}) {
    if (!_hasWhisper) return Future.error(StateError(L10n.current.sttNoModel));
    final id = _nextId++;
    final c = Completer<String>();
    _pending[id] = c;
    _send.send(('transcribe', audio, id));
    return c.future.timeout(const Duration(seconds: 45));
  }

  @override
  Future<void> dispose() async {
    _send.send(('dispose', null, null));
    await _heard.close();
    for (final c in _pending.values) {
      c.completeError(StateError(L10n.current.sttStopped));
    }
    _pending.clear();
    Future<void>.delayed(const Duration(seconds: 2), () => _isolate.kill());
  }
}

// ─────────────────── Segmented recognition over a Transcriber ───────────────────

/// Pseudo-streaming for engines that only transcribe whole clips (Whisper): voice activity cuts the audio into utterances, and the open
/// utterance is re-transcribed about once a second so words keep arriving.
class SegmentedRecognizer implements LiveRecognizer {
  SegmentedRecognizer(
    this.transcriber, {
    required this.language,
    this.prompt,
    this.refresh = const Duration(milliseconds: 1100),
  });

  final Transcriber transcriber;
  final String language;
  final String? prompt;
  final Duration refresh;

  /// How often following re-reads the open utterance. Following only trusts
  /// a partial word once a second pass agrees with it, so this sets how soon
  /// the script moves; Whisper Base takes ~0.15 s a pass on a laptop CPU.
  static const followingRefresh = Duration(milliseconds: 700);

  final _vad = EnergyVad();
  final _heard = StreamController<HeardUpdate>.broadcast();
  final _segment = <double>[];

  /// Utterances that ended while a transcription was running.
  final _closed = <Float32List>[];
  final _committed = <String>[];
  int _committedTotal = 0;
  String _partial = '';
  bool _busy = false;
  DateTime _lastRun = DateTime.fromMillisecondsSinceEpoch(0);
  int _generation = 0;

  static const _maxSegmentSamples = AudioCapture.sampleRate * 8;

  /// Most audio sent in one catch-up pass (Whisper's window is 30 s).
  static const _maxPassSamples = AudioCapture.sampleRate * 20;
  static const _minSamples = AudioCapture.sampleRate ~/ 4;

  @override
  Stream<HeardUpdate> get updates => _heard.stream;

  @override
  Stream<String> get heard => _heard.stream.map((u) => u.text);

  @override
  void accept(Float32List samples) {
    _vad.accept(samples);
    if (_vad.speaking || _segment.isNotEmpty) _segment.addAll(samples);

    final ended = !_vad.speaking && _vad.silenceMs >= 450 && _segment.isNotEmpty;
    final tooLong = _segment.length >= _maxSegmentSamples;
    if (ended || tooLong) {
      if (_segment.length >= _minSamples) _closed.add(Float32List.fromList(_segment));
      _segment.clear();
      _pump();
    } else if (_vad.speaking && DateTime.now().difference(_lastRun) >= refresh) {
      _pump();
    }
  }

  /// Runs one transcription at a time. Requests never queue up behind a slow
  /// model: utterances that close meanwhile are transcribed together in the
  /// next pass, and the open one is only refreshed when nothing is pending.
  /// A queue made a slow model (Whisper Turbo on a CPU) fall seconds behind
  /// the presenter and then race through the backlog on the next pause.
  Future<void> _pump() async {
    if (_busy || _heard.isClosed) return;
    final Float32List audio;
    final bool finalize;
    if (_closed.isNotEmpty) {
      var take = 0, length = 0;
      while (take < _closed.length && (take == 0 || length + _closed[take].length <= _maxPassSamples)) {
        length += _closed[take++].length;
      }
      audio = Float32List(length);
      var offset = 0;
      for (final c in _closed.take(take)) {
        audio.setAll(offset, c);
        offset += c.length;
      }
      _closed.removeRange(0, take);
      finalize = true;
    } else if (_segment.length >= _minSamples) {
      audio = Float32List.fromList(_segment);
      finalize = false;
    } else {
      return;
    }

    _busy = true;
    _lastRun = DateTime.now();
    final gen = _generation;
    try {
      final text = await transcriber.transcribe(audio, language: language, prompt: prompt);
      if (gen != _generation || _heard.isClosed) return;
      if (finalize) {
        final words = text.split(' ').where((w) => w.isNotEmpty);
        _committed.addAll(words);
        _committedTotal += words.length;
        if (_committed.length > 40) _committed.removeRange(0, _committed.length - 40);
        _partial = '';
      } else {
        _partial = text;
      }
      _heard.add(HeardUpdate(committed: List.of(_committed), committedTotal: _committedTotal, partial: _partial));
    } catch (_) {
      // A dropped segment only costs a little tracking; hotkeys still work.
    } finally {
      _busy = false;
    }
    if (_closed.isNotEmpty) unawaited(_pump());
  }

  @override
  void clear() {
    _generation++;
    _segment.clear();
    _closed.clear();
    _committed.clear();
    _committedTotal = 0;
    _partial = '';
    _vad.reset();
  }

  @override
  Future<void> dispose() async {
    _generation++;
    await _heard.close();
  }
}

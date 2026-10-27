// Offline replay of recognizer output through the following rules, with the
// presenter's real position known, so following can be measured instead of
// eyeballed. Used by following_metrics_test.dart.
//
// Positions are in display words: the index of the next word the presenter
// has to say, counting every word of the script before it. "Shown" is the
// same for what the overlay shows as said.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:sotto/data/models/script.dart';
import 'package:sotto/domain/following/heard_update.dart';
import 'package:sotto/domain/following/script_aligner.dart';

/// One recognizer update at [t] seconds into the take.
typedef TimedUpdate = ({double t, HeardUpdate update});

/// What a follower is asked for: the overlay's position after each update,
/// and a line saying what it decided and why (for the logs).
abstract class Follower {
  /// [at]: seconds into the take — followers run on this clock.
  void feed(HeardUpdate update, double at);

  /// (beat, spoken display words of it) as the overlay shows them.
  (int, int) get shown;

  /// Manual move (the presenter's own key), before the take starts.
  void startAt(int beat);
  String get decision;
}

/// A take: what was heard, when, and where the presenter really was.
class Take {
  Take({
    required this.name,
    required this.script,
    required this.updates,
    required this.truth,
    this.path = 'synthetic',
    this.startBeat = 0,
    this.relockAt,
    this.relockWord,
    this.quiet = const [],
    this.wordEnds = const [],
  });

  final String name;
  final FlatScript script;
  final List<TimedUpdate> updates;

  /// Which recognizer produced [updates]: 'whisper' (segmented Whisper
  /// Base), 'streaming' (the Kroko transducer) or 'synthetic'.
  final String path;

  /// Display words the presenter has said by [t] seconds.
  final double Function(double t) truth;
  final int startBeat;

  /// A deliberate skip: from [relockAt] seconds the presenter reads from
  /// display word [relockWord].
  final double? relockAt;
  final int? relockWord;

  /// (start, end) seconds where the presenter says no script words: ad-libs
  /// and silence. Any move ahead of the truth in there is a false advance.
  final List<(double, double)> quiet;

  /// (display word, when the presenter finished saying it): how long each
  /// word takes to show as said.
  final List<(int, double)> wordEnds;

  late final List<int> beatOffset = () {
    final out = <int>[];
    var n = 0;
    for (final b in script.beats) {
      out.add(n);
      n += b.displayWords.length;
    }
    return out;
  }();

  int wordOf((int, int) p) => beatOffset[p.$1] + p.$2;
}

class Metrics {
  Metrics(this.take);
  final String take;
  int updates = 0, moves = 0, bigJumps = 0, maxJump = 0, falseAdvances = 0, maxAhead = 0, quietAdvances = 0;
  final lags = <double>[];

  /// Seconds between recognizer updates, and between moves on screen with
  /// the words each move covered.
  final updateGaps = <double>[];
  final moveGaps = <double>[];
  final moveWords = <int>[];

  /// Seconds from the end of each said word until it showed as said.
  final wordLatencies = <double>[];
  double? relockSeconds;
  bool relockedEarly = false;

  static double _mean(List<num> v) => v.isEmpty ? 0 : v.fold<double>(0, (a, b) => a + b) / v.length;
  static double _pct(List<num> v, double p) {
    if (v.isEmpty) return 0;
    final s = [...v]..sort();
    return s[math.min(s.length - 1, (s.length * p).floor())].toDouble();
  }

  double get meanLag => _mean(lags);
  double get p90Lag => _pct(lags, 0.9);
  double get updateGap => _pct(updateGaps, 0.5);
  double get moveGap => _pct(moveGaps, 0.5);
  double get wordsPerMove => _mean(moveWords);
  double get meanLatency => _mean(wordLatencies);
  double get p90Latency => _pct(wordLatencies, 0.9);
}

/// A jump this many display words or more in one update is "big".
const bigJump = 8;

/// Shown may run this far ahead of what was said before it counts as a false
/// advance (one word: a fast recognizer can be a word early).
const aheadTolerance = 2;

/// Replays [take] through [f]; writes one log line per update to [log].
Metrics replay(Take take, Follower f, {StringSink? log}) {
  final m = Metrics(take.name);
  f.startAt(take.startBeat);
  var before = take.wordOf(f.shown);
  double? lastUpdate, lastMove;
  var pending = 0; // next entry of take.wordEnds not yet shown
  for (final (:t, :update) in take.updates) {
    f.feed(update, t);
    final after = take.wordOf(f.shown);
    final truth = take.truth(t);
    final delta = after - before;
    m.updates++;
    if (lastUpdate != null) m.updateGaps.add(t - lastUpdate);
    lastUpdate = t;
    if (delta != 0) {
      m.moves++;
      if (delta > 0 && truth > take.beatOffset[take.startBeat]) {
        if (lastMove != null) m.moveGaps.add(t - lastMove);
        lastMove = t;
        m.moveWords.add(delta);
      }
    }
    if (delta >= bigJump) m.bigJumps++;
    m.maxJump = math.max(m.maxJump, delta);
    final ahead = after - truth;
    if (ahead.round() > m.maxAhead) m.maxAhead = ahead.round();
    if (delta > 0 && ahead > aheadTolerance) {
      m.falseAdvances++;
      if (take.quiet.any((q) => t >= q.$1 && t <= q.$2 + 1.5)) m.quietAdvances++;
    }
    // Lag only once the presenter has started on the take's first words.
    if (truth > take.beatOffset[take.startBeat]) m.lags.add(math.max(0, truth - after).toDouble());
    // Words that show as said with this update: how long after they ended.
    while (pending < take.wordEnds.length && take.wordEnds[pending].$2 <= t) {
      final (word, end) = take.wordEnds[pending];
      if (after > word) {
        m.wordLatencies.add(t - end);
        pending++;
      } else if (take.wordEnds.skip(pending + 1).any((w) => w.$1 < word)) {
        pending++; // never shown in order: a later word comes before it
      } else {
        break;
      }
    }
    if (take.relockAt case final at? when take.relockWord != null) {
      if (after >= take.relockWord! && m.relockSeconds == null) {
        if (t < at) m.relockedEarly = true;
        m.relockSeconds = t - at;
      }
    }
    log?.writeln(
      '${t.toStringAsFixed(2).padLeft(6)}s '
      'truth ${truth.toStringAsFixed(1).padLeft(5)} shown ${after.toString().padLeft(3)} '
      '(${delta >= 0 ? '+' : ''}$delta) ${f.decision}\n'
      '        committed …${update.committed.skip(math.max(0, update.committed.length - 8)).join(' ')} '
      '| partial "${update.partial}"${update.stable == null ? '' : ' (stable ${update.stable})'}',
    );
    before = after;
  }
  return m;
}

// ───────────────────────────── Takes ─────────────────────────────

Script scriptOf(List<String> beats, {String title = 'Take'}) {
  final now = DateTime(2026);
  return Script(
    id: 's',
    title: title,
    createdAt: now,
    updatedAt: now,
    sections: [
      Section(id: 'a', title: 'Uno', beats: [for (final b in beats) Beat.create(b)]),
    ],
  );
}

const fixtures = 'test/fixtures/speech_es';

List<String> spanishBeats() => File('$fixtures/beats.txt').readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();

List<String> longBeats() =>
    File('$fixtures/long_beats.txt').readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();

/// The recorded takes (see test/integration/record_asr_es_test.dart): the
/// segmented Whisper Base path and the streaming path, on the same audio.
List<Take> recordedTakes() => [
  for (final f in Directory(fixtures).listSync().whereType<File>().toList()..sort((a, b) => a.path.compareTo(b.path)))
    if (f.path.contains('asr_whisper_base_') || f.path.endsWith('asr_kroko_es.json')) ..._takesOf(f),
];

List<int> _offsets(FlatScript flat) {
  final offset = <int>[];
  var n = 0;
  for (final b in flat.beats) {
    offset.add(n);
    n += b.displayWords.length;
  }
  return offset;
}

List<Take> _takesOf(File file) {
  final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final streaming = file.path.endsWith('asr_kroko_es.json');
  final path = streaming ? 'streaming' : 'whisper';
  final label = streaming ? 'streaming' : 'whisper ${json['refreshMs']}ms';
  final takes = <Take>[];
  for (final MapEntry(key: name, value: raw) in (json['takes']! as Map<String, Object?>).entries) {
    final take = raw! as Map<String, Object?>;
    final updates = [
      for (final u in take['updates']! as List)
        (t: ((u as Map)['t'] as num).toDouble(), update: HeardUpdate.fromJson(u.cast<String, Object?>())),
    ];
    if (name == 'long') {
      takes.add(_longTake('$label: long', path, updates));
      continue;
    }
    final flat = FlatScript.from(scriptOf(spanishBeats()), language: 'es-MX');
    final offset = _offsets(flat);
    final spans = [
      for (final s in take['spans']! as List)
        (beat: (s as Map)['beat'] as int, start: (s['start'] as num).toDouble(), end: (s['end'] as num).toDouble()),
    ];
    // Words said by t: whole beats before, and the share of the current
    // beat's voiced span (words spread evenly over it).
    double truth(double t) {
      var said = 0.0;
      for (final s in spans) {
        if (s.start > t) break;
        if (s.beat < 0) continue; // the ad-lib says no script words
        final words = flat.beats[s.beat].displayWords.length;
        final share = s.end <= t ? 1.0 : ((t - s.start) / (s.end - s.start)).clamp(0.0, 1.0);
        said = offset[s.beat] + words * share;
      }
      return said;
    }

    final skipTo = name == 'skip' ? spans.firstWhere((s) => s.beat == 9) : null;
    takes.add(
      Take(
        name: '$label: $name',
        path: path,
        script: flat,
        updates: updates,
        truth: truth,
        relockAt: skipTo?.start,
        relockWord: skipTo == null ? null : offset[9] + 2,
        quiet: [
          for (final s in spans)
            if (s.beat < 0) (s.start, s.end),
        ],
        wordEnds: [
          for (final s in spans)
            if (s.beat >= 0)
              for (var k = 0; k < flat.beats[s.beat].displayWords.length; k++)
                (offset[s.beat] + k, s.start + (s.end - s.start) * (k + 1) / flat.beats[s.beat].displayWords.length),
        ],
      ),
    );
  }
  return takes;
}

/// long.wav: word-level truth from the synthesizer (long_truth.json).
Take _longTake(String name, String path, List<TimedUpdate> updates) {
  final flat = FlatScript.from(scriptOf(longBeats()), language: 'es-MX');
  final offset = _offsets(flat);
  final truthJson = jsonDecode(File('$fixtures/long_truth.json').readAsStringSync()) as Map<String, Object?>;
  final words = [
    for (final w in truthJson['words']! as List)
      (
        word: offset[(w as Map)['beat'] as int] + (w['word'] as int),
        start: (w['start'] as num).toDouble(),
        end: (w['end'] as num).toDouble(),
      ),
  ];
  final events = (truthJson['events']! as List).cast<Map<String, Object?>>();
  // The presenter's position is the last word begun: said up to it, and
  // into it by how much of it has been said.
  double truth(double t) {
    var said = 0.0;
    for (final w in words) {
      if (w.start > t) break;
      said = w.end <= t ? w.word + 1.0 : w.word + (t - w.start) / (w.end - w.start);
    }
    return said;
  }

  final skip = events.firstWhere((e) => e['kind'] == 'skip');
  final resume = words.firstWhere((w) => w.start >= (skip['start']! as num).toDouble());
  return Take(
    name: name,
    path: path,
    script: flat,
    updates: updates,
    truth: truth,
    relockAt: resume.start,
    relockWord: resume.word + 2,
    quiet: [
      for (final e in events)
        if (e['kind'] != 'skip') ((e['start']! as num).toDouble(), (e['end']! as num).toDouble()),
    ],
    wordEnds: [for (final w in words) (w.word, w.end)],
  );
}

/// Builds recognizer output by hand: partials that grow word by word (or
/// get rewritten), then a commit.
class AsrScript {
  final updates = <TimedUpdate>[];
  final _committed = <String>[];
  int _total = 0;
  double t = 0;

  void partial(String text, {double dt = 0.6}) {
    t += dt;
    updates.add((t: t, update: HeardUpdate(committed: List.of(_committed), committedTotal: _total, partial: text)));
  }

  void commit(String text, {double dt = 0.6}) {
    t += dt;
    final words = text.split(' ').where((w) => w.isNotEmpty).toList();
    _committed.addAll(words);
    _total += words.length;
    if (_committed.length > 40) _committed.removeRange(0, _committed.length - 40);
    updates.add((t: t, update: HeardUpdate(committed: List.of(_committed), committedTotal: _total)));
  }

  /// Says [text] the way Whisper reports it: the open utterance re-read
  /// every [refresh] s with [wordsPerRefresh] more words, then committed.
  void say(String text, {int wordsPerRefresh = 3, double refresh = 1.1}) {
    final words = text.split(' ');
    for (var k = wordsPerRefresh; k < words.length; k += wordsPerRefresh) {
      partial(words.take(k).join(' '), dt: refresh);
    }
    commit(text, dt: refresh);
  }

  void silence(double seconds) => t += seconds;
}

/// Synthetic takes for what the recordings don't cover.
List<Take> syntheticTakes() {
  final beats = spanishBeats();
  final flat = FlatScript.from(scriptOf(beats), language: 'es-MX');
  final offset = <int>[];
  var n = 0;
  for (final b in flat.beats) {
    offset.add(n);
    n += b.displayWords.length;
  }

  // Off-script talk that borrows the script's words: some behind the
  // presenter ("les quiero contar"), some just ahead ("clientes nuevos").
  final adLib = AsrScript()
    ..say('Bueno, antes de seguir les quiero contar algo.')
    ..say('El año pasado fue un año muy bueno para todos.')
    ..say('Y la verdad es que los clientes nuevos nos ayudaron mucho.')
    ..say('Pero bueno, eso lo vemos después en las preguntas.');

  // Silence and room noise: Whisper hallucinates its usual captions.
  final noise = AsrScript()
    ..silence(2)
    ..commit('Gracias.', dt: 1.5)
    ..commit('¡Gracias!', dt: 2.5)
    ..partial('Subtítulos realizados por', dt: 1.1)
    ..commit('Subtítulos realizados por la comunidad de Amara.org', dt: 1.1)
    ..commit('Muchas gracias.', dt: 3)
    ..commit('Gracias por ver el video.', dt: 2);

  // Partials that get rewritten: a misheard tail from two beats ahead
  // ("las ventas crecieron un doce") shows up once and is gone next time.
  final unstable = AsrScript()
    ..partial('Buenos días', dt: 1.1)
    ..partial('Buenos días a todos y', dt: 1.1)
    ..partial('Buenos días a todos, las ventas crecieron un doce', dt: 1.1)
    ..partial('Buenos días a todos y gracias por', dt: 1.1)
    ..commit('Buenos días a todos y gracias por estar aquí.', dt: 1.1);

  final stationary = [
    ('synthetic: off-script talk at beat 2', adLib, 2),
    ('synthetic: silence + noise at beat 5', noise, 5),
  ];
  final takes = [
    for (final (name, asr, beat) in stationary)
      Take(name: name, script: flat, updates: asr.updates, truth: (_) => offset[beat].toDouble(), startBeat: beat),
    Take(
      name: 'synthetic: unstable partials',
      script: flat,
      updates: unstable.updates,
      // Words said: as many as the stable transcript shows by then.
      truth: (t) => t < 2.2
          ? 2
          : t < 4.4
          ? 5
          : 9,
    ),
  ];

  // A phrase said twice in the script, far apart: reading the first one
  // must not jump to the second.
  final repeated = [
    'Bienvenidos a la presentación de resultados.',
    'Nuestro objetivo es crecer en todos los mercados del país.',
    'Primero hablemos de las ventas del trimestre.',
    'Las ventas subieron gracias a la nueva tienda en línea.',
    'Ahora hablemos de los costos de operación.',
    'Los costos bajaron por la eficiencia del equipo.',
    'Recuerden que nuestro objetivo es crecer en todos los mercados del país.',
    'Gracias por su atención.',
  ];
  final rFlat = FlatScript.from(scriptOf(repeated), language: 'es-MX');
  final rOffset = <int>[];
  var r = 0;
  for (final b in rFlat.beats) {
    rOffset.add(r);
    r += b.displayWords.length;
  }
  final read = AsrScript();
  final ends = <(double, int)>[];
  for (var b = 0; b < 4; b++) {
    final start = read.t;
    read.say(repeated[b]);
    ends.add((start, b));
    read.silence(0.5);
  }
  takes.add(
    Take(
      name: 'synthetic: repeated phrase',
      script: rFlat,
      updates: read.updates,
      truth: (t) {
        var said = 0.0;
        for (final (start, b) in ends) {
          if (start > t) break;
          final words = rFlat.beats[b].displayWords.length;
          final dur = ((words / 3).ceil()) * 1.1;
          said = rOffset[b] + words * ((t - start) / dur).clamp(0.0, 1.0);
        }
        return said;
      },
    ),
  );
  return takes;
}

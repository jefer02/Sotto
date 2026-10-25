// A frozen copy of the voice-following rules before streaming recognition
// (FollowEngine + ScriptAligner as they stood after the stability /
// evidence rework, before recognizer-reported stability and word timing),
// kept only so following_metrics_test.dart can show the old numbers beside
// the new ones on the same recordings. Not used by the app.
// ignore_for_file: prefer_const_constructors

import 'dart:math' as math;

import 'package:sotto/data/models/settings.dart';
import 'package:sotto/domain/following/heard_update.dart';
import 'package:sotto/domain/following/script_aligner.dart' show FlatScript;
import 'package:sotto/domain/following/text_normalizer.dart';

/// Where the presenter is, as the overlay needs it.
class PreviousPosition {
  const PreviousPosition({
    required this.beat,
    required this.spokenWords,
    required this.confidence,
    required this.holding,
    int? saidBeat,
    int? saidWords,
  }) : saidBeat = saidBeat ?? beat,
       saidWords = saidWords ?? spokenWords;

  /// Global beat index: the line the overlay shows as current.
  final int beat;

  /// Display words of [beat] already said (dimmed to "done").
  final int spokenWords;

  /// Where the presenter really is — the beat and display words of it said.
  /// The same as [beat] / [spokenWords] except while "Move on when said" has
  /// already made the next line current: the script scrolls by this, so the
  /// unsaid end of a line never slides out of view.
  final int saidBeat;
  final int saidWords;
  final double confidence;

  /// No match for a while — the presenter is ad-libbing; the overlay freezes.
  final bool holding;

  static const start = PreviousPosition(beat: 0, spokenWords: 0, confidence: 0, holding: false);
}

enum PreviousEvent { none, dimmed, advanced, jumped, heldStill, relocked }

/// What the engine did with one update, and why — for logs and tests.
class PreviousDecision {
  const PreviousDecision(this.event, this.reason, {this.target, this.evidence});

  final PreviousEvent event;
  final String reason;

  /// The script word the evidence pointed at, and how strong it was.
  final int? target;
  final double? evidence;

  @override
  String toString() =>
      '${event.name}: $reason'
      '${target == null ? '' : ' → word $target'}'
      '${evidence == null ? '' : ' (evidence ${evidence!.toStringAsFixed(2)})'}';
}

/// A far move waiting for the next update to confirm it.
class _Candidate {
  const _Candidate(this.token, this.hits);
  final int token;
  final int hits;
}

/// Turns recognizer output into the overlay's position, word by word:
///
/// 1. Only stable words count: committed ones, and partial words the
///    recognizer has left unchanged across [stableUpdates] updates. A word
///    that is later rewritten never moves the script.
/// 2. Only new words count: an update moves the script only when its
///    alignment ends on words not heard before. Old words, silence, noise
///    and ad-libs leave it where it is.
/// 3. Small steps are easy, big ones are earned. Moving ahead by up to
///    the new words heard (plus a few the recognizer dropped) needs two
///    matched words in a row, or one rare word right next to the presenter.
///    Anything further — or backwards — needs a long, distinctive run (rare
///    words, no equal match elsewhere in the script) that holds across two
///    consecutive updates.
/// 4. Position is a word, not a beat: the script never skips the unsaid end
///    of a line. "Move on when said" only decides when the overlay shows the
///    next line as current.
/// 5. Hold still during ad-libs: no match for 6 s → "Holding".
/// 6. Manual beats the machine: a key moves at once, discards what was
///    heard before it, and "previous beat" pauses following for 3 s.
///
/// Cost per update: one banded alignment (see [PreviousAligner]) — O(n·b)
/// with n ≤ 16 heard words and a band of b ≈ 40–60 script words — plus, only
/// when that finds nothing, one whole-script alignment, O(n·M). Stability
/// tracking is O(p) for p partial words. The engine keeps O(p) state besides
/// the script.
class PreviousFollowEngine {
  PreviousFollowEngine(this.script, {required AppSettings settings, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now,
      _aligner = PreviousAligner(script) {
    configure(settings);
    _lastMatch = _clock();
  }

  final FlatScript script;
  final PreviousAligner _aligner;
  final DateTime Function() _clock;

  late double _advanceAt;
  late double _minConfidence;
  late bool _holdDuringAdLib;
  late bool _allowJumps;

  /// A partial word counts once it is unchanged across this many updates
  /// (one more for the partial's last word, which is often cut short).
  static const stableUpdates = 2;
  static const _holdAfter = Duration(seconds: 6);

  /// A match this recent means the presenter is reading along.
  static const _readingFlow = Duration(seconds: 4);

  /// Words behind the presenter the band keeps (a recognizer that re-reads
  /// the end of the last line), and the most it looks ahead.
  static const _bandBack = 6;
  static const _bandAhead = 40;

  /// Script words a step may pass over beyond the new words heard: ones the
  /// recognizer dropped or the presenter skipped.
  static const _stepSlack = 3;

  /// A far move: at least this many words in a row, this much weight, and
  /// this much better than the best match anywhere else.
  static const _farRun = 5;
  static const _farWeight = 3.0;
  static const _farUnique = 1.4;
  static const _farConfidence = 0.75;

  PreviousPosition _pos = PreviousPosition.start;

  /// The last script word confirmed as said (global token index).
  int _token = -1;
  late DateTime _lastMatch;
  DateTime? _suspendedUntil;

  // Stability of the open partial.
  int _committedTotal = -1;
  List<String> _partialKeys = const [];
  List<int> _partialAge = const [];

  /// Stable words already used as evidence (committed + stable partial).
  int _consumed = 0;

  /// Stable words seen so far — a manual move consumes them all.
  int _seen = 0;
  _Candidate? _candidate;

  // For [onHeard]: the plain-text transcript tail as an update stream.
  List<String> _textWords = const [];
  int _textTotal = 0;

  PreviousPosition get position => _pos;

  /// The last script word confirmed as said, or −1.
  int get token => _token;

  PreviousDecision lastDecision = const PreviousDecision(PreviousEvent.none, 'start');

  void configure(AppSettings s) {
    _advanceAt = s.advanceThreshold.clamp(0.5, 1.0);
    _holdDuringAdLib = s.holdDuringAdLib;
    _allowJumps = s.allowSectionJumps;
    final (minSim, minConfidence) = switch (s.sensitivity) {
      Sensitivity.low => (0.88, 0.75),
      Sensitivity.medium => (0.8, 0.65),
      Sensitivity.high => (0.72, 0.55),
    };
    _minConfidence = minConfidence;
    _aligner.config = PreviousAlignerConfig(minSimilarity: minSim);
  }

  /// Plain-text input — the transcript tail as one string, all of it taken
  /// as final. Words past what the previous call ended with are new. For
  /// tests and simple callers; live following uses [onUpdate].
  PreviousEvent onHeard(String heardText) {
    final words = heardText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    var common = 0;
    while (common < words.length && common < _textWords.length && words[common] == _textWords[common]) {
      common++;
    }
    final grew = common == _textWords.length;
    _textTotal += grew ? words.length - common : words.length;
    _textWords = words;
    return onUpdate(HeardUpdate(committed: words, committedTotal: _textTotal));
  }

  /// Takes in [update] without following it (paused, manual mode): its
  /// words never count as evidence afterwards.
  void ignore(HeardUpdate update) => _stableWords(update);

  PreviousEvent onUpdate(HeardUpdate update) {
    final now = _clock();
    final fresh = _stableWords(update);
    if (_suspendedUntil != null && now.isBefore(_suspendedUntil!)) {
      return _decide(PreviousEvent.none, 'paused after a manual move');
    }
    if (fresh.added.isEmpty) return _hold(now, 'no new stable words');

    final heard = TextNormalizer.normalizeHeard(fresh.tail.join(' '), language: script.language);
    if (heard.length > PreviousAligner.maxHeard) heard.removeRange(0, heard.length - PreviousAligner.maxHeard);
    final newTokens = math.min(
      heard.length,
      TextNormalizer.normalizeHeard(fresh.added.join(' '), language: script.language).length,
    );
    if (newTokens == 0) return _hold(now, 'new words carry no speech');

    // 1. Near the presenter: small forward steps.
    final cap = newTokens + _stepSlack;
    final from = math.max(0, _token - _bandBack);
    final to = math.min(script.tokens.length, _token + 1 + math.max(_bandAhead, 2 * newTokens + 8).toInt());
    final near = _aligner.align(heard, from, to);
    final onNew = near != null && near.heardEnd > heard.length - newTokens;
    if (near != null && onNew && near.confidence >= _minConfidence) {
      final step = near.tokenIndex - _token;
      // One word moves the script only while the presenter is reading
      // along, and only when it is the word itself, not a near-miss.
      final reading = now.difference(_lastMatch) < _readingFlow;
      final exact =
          TextNormalizer.similarity(
            heard[near.heardEnd - 1],
            script.tokens[near.tokenIndex].text,
            spanish: script.spanish,
          ) >=
          0.95;
      final next = step <= 2 && near.trailingRun >= 1 && near.trailingWeight >= 0.75 && reading && exact;
      // A run of matched words may pass over as many script words before
      // it (dropped by the recognizer, skipped by the presenter) as it has
      // itself — at least [_stepSlack] — never a stretch of its own size more.
      final gap = near.runStart - _token - 1;
      final run = near.trailingRun >= 2 && near.trailingWeight >= 1.0 && gap <= math.max(_stepSlack, near.trailingRun);
      if (step > 0 && (next || run)) {
        _candidate = null;
        return _moveTo(near.tokenIndex, now, near, 'followed $step word${step == 1 ? '' : 's'}');
      }
    }

    // 2. Further away: only on a long, distinctive run, twice in a row.
    if (_allowJumps) {
      final far = _farEvidence(heard, newTokens, cap);
      if (far != null) {
        final prev = _candidate;
        final consistent = prev != null && far.tokenIndex > prev.token && far.tokenIndex <= prev.token + cap + 2;
        final hits = consistent ? prev.hits + 1 : 1;
        if (hits >= 2) {
          _candidate = null;
          return _moveTo(far.tokenIndex, now, far, 'relocked on sustained evidence', jump: true);
        }
        _candidate = _Candidate(far.tokenIndex, hits);
        return _decide(
          PreviousEvent.none,
          'far match, waiting for the next update to confirm',
          target: far.tokenIndex,
          evidence: far.trailingWeight,
        );
      }
    }
    _candidate = null;

    final why = near == null
        ? 'no script words in what was heard'
        : !onNew
        ? 'match ends on words already used'
        : near.confidence < _minConfidence
        ? 'weak match (${near.confidence.toStringAsFixed(2)})'
        : near.tokenIndex <= _token
        ? 'match is at or behind the presenter'
        : near.runStart - _token - 1 > math.max(_stepSlack, near.trailingRun)
        ? 'too many unsaid words before the match'
        : 'single weak word';
    return _hold(now, why, target: near?.tokenIndex, evidence: near?.trailingWeight);
  }

  /// A move beyond the step cap, or backwards: a long run of distinctive
  /// words ending on new ones, with no comparable match anywhere else.
  PreviousAlignment? _farEvidence(List<String> heard, int newTokens, int cap) {
    if (heard.length < _farRun) return null;
    // What was just read may match the heard tail too; it isn't a rival.
    final far = _aligner.alignAnywhere(heard, around: (_token - _bandBack - heard.length, _token + cap + 1));
    if (far == null || far.heardEnd <= heard.length - newTokens) return null;
    final distance = far.tokenIndex - _token;
    // The tail of what was already said is no move at all.
    if (distance > -_bandBack && distance <= 0) return null;
    final needed = _farWeight + 0.5 * math.log(1 + distance.abs() / 40) / math.ln2;
    if (far.trailingRun < _farRun || far.trailingWeight < needed) return null;
    if (far.confidence < _farConfidence || far.score < _farUnique * far.secondScore) return null;
    return far;
  }

  PreviousEvent _moveTo(int token, DateTime now, PreviousAlignment r, String reason, {bool jump = false}) {
    final wasHolding = _pos.holding;
    final before = _pos.beat;
    _token = token;
    _lastMatch = now;
    _pos = _display(r.confidence);
    final event = wasHolding
        ? PreviousEvent.relocked
        : jump
        ? PreviousEvent.jumped
        : _pos.beat != before
        ? PreviousEvent.advanced
        : PreviousEvent.dimmed;
    return _decide(event, reason, target: token, evidence: r.trailingWeight);
  }

  /// The overlay's position for [_token]: the beat being read and the words
  /// of it said. A finished beat — or one said past "Move on when said", or
  /// with only stop words left — shows the next one as current, but [_token]
  /// stays on the last word really said.
  PreviousPosition _display(double confidence) {
    final tokens = script.tokens;
    if (_token < 0) return PreviousPosition(beat: 0, spokenWords: 0, confidence: confidence, holding: false);
    final t = tokens[_token];
    final beat = script.beats[t.beat];
    final progress = beat.tokenCount == 0 ? 1.0 : (_token - beat.firstToken + 1) / beat.tokenCount;
    final done = _token >= beat.endToken - 1 || _token >= beat.lastContentToken || progress >= _advanceAt;
    final said = math.min(t.displayIndex + 1, beat.displayWords.length);
    if (done && t.beat < script.length - 1) {
      // The next beat with words to say (empty beats are passed over).
      var next = t.beat + 1;
      while (next < script.length - 1 && script.beats[next].tokenCount == 0) {
        next++;
      }
      final finished = said >= beat.displayWords.length;
      return PreviousPosition(
        beat: next,
        spokenWords: 0,
        confidence: confidence,
        holding: false,
        saidBeat: finished ? next : t.beat,
        saidWords: finished ? 0 : said,
      );
    }
    return PreviousPosition(beat: t.beat, spokenWords: said, confidence: confidence, holding: false);
  }

  PreviousEvent _hold(DateTime now, String reason, {int? target, double? evidence}) {
    if (_holdDuringAdLib && !_pos.holding && now.difference(_lastMatch) > _holdAfter) {
      _pos = PreviousPosition(
        beat: _pos.beat,
        spokenWords: _pos.spokenWords,
        confidence: 0,
        holding: true,
        saidBeat: _pos.saidBeat,
        saidWords: _pos.saidWords,
      );
      return _decide(PreviousEvent.heldStill, 'no script words for ${_holdAfter.inSeconds} s — holding');
    }
    return _decide(PreviousEvent.none, reason, target: target, evidence: evidence);
  }

  PreviousEvent _decide(PreviousEvent event, String reason, {int? target, double? evidence}) {
    lastDecision = PreviousDecision(event, reason, target: target, evidence: evidence);
    return event;
  }

  /// The stable words of [u] and which of them are new since the last call.
  ({List<String> tail, List<String> added}) _stableWords(HeardUpdate u) {
    final partial = u.partial.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final keys = [for (final w in partial) TextNormalizer.normalizeHeard(w, language: script.language).join(' ')];
    if (u.committedTotal != _committedTotal) {
      // A new utterance: the partial starts over.
      _partialKeys = const [];
      _partialAge = const [];
    }
    // A word keeps its age when the new partial still has it in the same
    // order — even if the recognizer slipped a word in before it.
    final match = _lcsMatch(keys, _partialKeys);
    final age = [for (var k = 0; k < keys.length; k++) match[k] >= 0 ? _partialAge[match[k]] + 1 : 1];
    // The partial's last word may be cut short: it needs one more update,
    // unless it ends a sentence (the presenter paused after it).
    bool settled(int k) {
      final last = k == keys.length - 1 && !RegExp(r'[.!?…]$').hasMatch(partial[k]);
      return age[k] >= stableUpdates + (last ? 1 : 0);
    }

    // Stable: one unbroken run of settled words, after at most two leading
    // words the recognizer has just inserted.
    var first = 0;
    while (first < math.min(2, keys.length) && !settled(first)) {
      first++;
    }
    var end = first;
    while (end < keys.length && settled(end)) {
      end++;
    }
    final stable = partial.sublist(first, end);
    _partialKeys = keys;
    _partialAge = age;
    _committedTotal = u.committedTotal;

    final total = u.committedTotal + stable.length;
    final fresh = math.max(0, total - _consumed);
    _consumed = total;
    _seen = total;
    final words = [...u.committed, ...stable];
    final added = words.sublist(math.max(0, words.length - fresh));
    return (tail: words.sublist(math.max(0, words.length - 24)), added: added);
  }

  /// For each word of [a], the index of the same word in [b] on a longest
  /// common subsequence, or −1. O(|a|·|b|) — two partials of a few dozen words.
  static List<int> _lcsMatch(List<String> a, List<String> b) {
    final n = a.length, m = b.length;
    final len = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        len[i][j] = a[i] == b[j] ? len[i + 1][j + 1] + 1 : math.max(len[i + 1][j], len[i][j + 1]);
      }
    }
    final out = List<int>.filled(n, -1);
    var i = 0, j = 0;
    while (i < n && j < m) {
      if (a[i] == b[j]) {
        out[i++] = j++;
      } else if (len[i + 1][j] >= len[i][j + 1]) {
        i++;
      } else {
        j++;
      }
    }
    return out;
  }

  /// Moves by hotkey or clicker. Going back also pauses following for 3 s so
  /// the recognizer can't immediately drag the script forward again. Words
  /// heard before the move never count as evidence after it.
  void jumpTo(int beat, {bool suspend = false}) {
    final b = beat.clamp(0, script.length - 1);
    _pos = PreviousPosition(beat: b, spokenWords: 0, confidence: 1, holding: false);
    _token = script.beats[b].firstToken - 1;
    _candidate = null;
    _consumed = _seen;
    _lastMatch = _clock();
    _decide(PreviousEvent.none, 'manual move to beat $b');
    if (suspend) _suspendedUntil = _clock().add(const Duration(seconds: 3));
  }

  void resetClock() => _lastMatch = _clock();

  int nextSectionBeat() {
    final s = script.sectionOf(_pos.beat);
    return s + 1 < script.sectionFirstBeat.length ? script.sectionFirstBeat[s + 1] : _pos.beat;
  }

  int previousSectionBeat() {
    final s = script.sectionOf(_pos.beat);
    final first = script.sectionFirstBeat[s];
    // Mid-section, "previous section" first returns to the section's start.
    if (_pos.beat > first) return first;
    return s > 0 ? script.sectionFirstBeat[s - 1] : 0;
  }
}

class PreviousAlignment {
  const PreviousAlignment({
    required this.tokenIndex,
    required this.confidence,
    required this.matchedTokens,
    required this.trailingRun,
    this.score = 0,
    this.secondScore = 0,
    this.heardEnd = 0,
    this.trailingWeight = 0,
    this.runStart = -1,
  });

  /// Global index of the script token aligned with the last heard word.
  final int tokenIndex;

  /// Score ÷ best possible score for the aligned span, 0..1.
  final double confidence;

  /// Number of heard tokens that matched a script token.
  final int matchedTokens;

  /// Consecutive matches ending at the last heard word.
  final int trailingRun;

  /// The alignment's raw score, and the best score of one ending somewhere
  /// else in the searched span — a phrase the script repeats scores close.
  final double score;
  final double secondScore;

  /// Heard words covered from the start: the alignment ends on heard word
  /// `heardEnd − 1` (the newest one, or the one before it).
  final int heardEnd;

  /// Summed weight of the script words in [trailingRun]: rare words count
  /// more than repeated ones, stop words little.
  final double trailingWeight;

  /// Global index of the first script token of [trailingRun].
  final int runStart;
}

class PreviousAlignerConfig {
  const PreviousAlignerConfig({
    this.minSimilarity = 0.78,
    this.beatsBack = 1,
    this.beatsAhead = 3,
    this.gapInScript = 0.6,
    this.gapInSpeech = 1.0,
  });

  /// Below this, two tokens count as a mismatch.
  final double minSimilarity;
  final int beatsBack;
  final int beatsAhead;

  /// Penalty for script words the presenter skipped.
  final double gapInScript;

  /// Penalty for words the presenter added (ad-libs, fillers).
  final double gapInSpeech;
}

/// Local (Smith–Waterman) alignment of the tail of what was heard against a
/// span of the script. The alignment must end on the newest heard word (or
/// the one before it), so the result says where the presenter is *now*.
///
/// Cost: one alignment fills an n × m table — n ≤ [maxHeard] heard words,
/// m script words in the span — in O(n·m) time and space (scores and
/// back-pointers). Following searches a band of about 50 words around the
/// presenter, so ≈ 800 cells per update; the whole script (O(n·M) for M
/// words, 16 × 5,000 = 80,000 cells for a long talk) only when the band
/// finds nothing.
class PreviousAligner {
  PreviousAligner(this.script, [this.config = const PreviousAlignerConfig()]);

  final FlatScript script;
  PreviousAlignerConfig config;

  static const maxHeard = 16;

  /// A stop word's weight: it says little about where the presenter is.
  static const stopWeight = 0.3;

  PreviousAlignment? alignNear(List<String> heard, int currentBeat) {
    final from = math.max(0, currentBeat - config.beatsBack);
    final to = math.min(script.length - 1, currentBeat + config.beatsAhead);
    return align(heard, script.beats[from].firstToken, script.beats[to].endToken);
  }

  /// Whole-script search, used to follow a presenter who skipped ahead.
  /// [around]: script words (global, start inclusive, end exclusive) the
  /// presenter has just read; a match there doesn't make a match elsewhere
  /// ambiguous.
  PreviousAlignment? alignAnywhere(List<String> heard, {(int, int)? around}) =>
      align(heard, 0, script.tokens.length, around: around);

  PreviousAlignment? align(List<String> heardAll, int start, int end, {(int, int)? around}) {
    if (heardAll.isEmpty || end <= start) return null;
    final heard = heardAll.length > maxHeard ? heardAll.sublist(heardAll.length - maxHeard) : heardAll;
    final n = heard.length;
    final m = end - start;
    final tokens = script.tokens;
    final spanish = script.spanish;
    double sim(String a, String b) => TextNormalizer.similarity(a, b, spanish: spanish);

    // H[i][j]: best local score aligning heard[..i) with script[start..start+j).
    final h = List.generate(n + 1, (_) => List<double>.filled(m + 1, 0));
    // Back-pointers: 0 stop, 1 diagonal, 2 up (speech gap), 3 left (script gap).
    final bp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));

    for (var i = 1; i <= n; i++) {
      final hw = heard[i - 1];
      final hWeight = script.weightOf(hw);
      for (var j = 1; j <= m; j++) {
        final tok = tokens[start + j - 1];
        final s = sim(hw, tok.text);
        final sub = s >= config.minSimilarity ? 2 * math.min(hWeight, tok.weight) * s : -1.0;
        final diag = h[i - 1][j - 1] + sub;
        final up = h[i - 1][j] - config.gapInSpeech;
        final left = h[i][j - 1] - config.gapInScript;
        var best = 0.0, dir = 0;
        if (diag > best) {
          best = diag;
          dir = 1;
        }
        if (up > best) {
          best = up;
          dir = 2;
        }
        if (left > best) {
          best = left;
          dir = 3;
        }
        h[i][j] = best;
        bp[i][j] = dir;
      }
    }

    // The newest heard word may be cut short, so the alignment may also end
    // one word early at a small cost. ends[j]: the best score ending on
    // script word j.
    final ends = List<double>.filled(m + 1, 0);
    final endI = List<int>.filled(m + 1, n);
    var bestScore = 0.0, bestI = n, bestJ = 0;
    for (var j = 1; j <= m; j++) {
      if (bp[n][j] == 1) ends[j] = h[n][j];
      if (n > 1 && bp[n - 1][j] == 1 && h[n - 1][j] - 0.5 > ends[j]) {
        ends[j] = h[n - 1][j] - 0.5;
        endI[j] = n - 1;
      }
      if (ends[j] > bestScore) {
        bestScore = ends[j];
        bestI = endI[j];
        bestJ = j;
      }
    }
    if (bestScore <= 0) return null;
    // The best alignment ending further away than the heard words could
    // stretch: a phrase the script repeats elsewhere scores close to the best.
    var second = 0.0;
    for (var j = 1; j <= m; j++) {
      final g = start + j - 1;
      if (around != null && g >= around.$1 && g < around.$2) continue;
      if ((j - bestJ).abs() > n + 2 && ends[j] > second) second = ends[j];
    }

    // Walk back to measure the span and count matches.
    var i = bestI, j = bestJ, matched = 0, trailing = 0;
    var inTrailingRun = true;
    var possible = 0.0, trailingWeight = 0.0, runStart = start + bestJ - 1;
    while (i > 0 && j > 0 && bp[i][j] != 0) {
      switch (bp[i][j]) {
        case 1:
          final hw = heard[i - 1];
          possible += 2 * script.weightOf(hw);
          final tok = tokens[start + j - 1];
          if (sim(hw, tok.text) >= config.minSimilarity) {
            matched++;
            if (inTrailingRun) {
              trailing++;
              trailingWeight += tok.weight;
              runStart = start + j - 1;
            }
          } else {
            inTrailingRun = false;
          }
          i--;
          j--;
        case 2:
          possible += 2 * script.weightOf(heard[i - 1]);
          inTrailingRun = false;
          i--;
        default:
          inTrailingRun = false;
          j--;
      }
    }
    if (possible == 0) return null;

    return PreviousAlignment(
      tokenIndex: start + bestJ - 1,
      confidence: (bestScore / possible).clamp(0.0, 1.0),
      matchedTokens: matched,
      trailingRun: trailing,
      score: bestScore,
      secondScore: second,
      heardEnd: bestI,
      trailingWeight: trailingWeight,
      runStart: runStart,
    );
  }
}

import 'dart:math' as math;

import '../../data/models/settings.dart';
import 'heard_update.dart';
import 'script_aligner.dart';
import 'text_normalizer.dart';

/// Where the presenter is, as the overlay needs it.
class FollowPosition {
  const FollowPosition({
    required this.beat,
    required this.spokenWords,
    required this.confidence,
    required this.holding,
    int? saidBeat,
    int? saidWords,
    this.charsPerSecond,
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

  /// How fast the presenter is speaking, in characters a second (spaces
  /// included), measured from when the recognizer heard each word. The
  /// overlay sweeps through newly said words at this pace instead of
  /// jumping a burst of them at once. Null: not measured yet.
  final double? charsPerSecond;

  static const start = FollowPosition(beat: 0, spokenWords: 0, confidence: 0, holding: false);
}

enum FollowEvent { none, dimmed, advanced, jumped, heldStill, relocked }

/// What the engine did with one update, and why — for logs and tests.
class FollowDecision {
  const FollowDecision(this.event, this.reason, {this.target, this.evidence});

  final FollowEvent event;
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
/// 1. Only stable words count: committed ones, and partial words that won't
///    change. A streaming recognizer says which those are
///    ([HeardUpdate.stable]); for segmented Whisper, a partial word counts
///    once it is unchanged across [stableUpdates] updates. A word that is
///    later rewritten never moves the script.
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
/// 7. When the recognizer says when each word began, the engine measures
///    the speaking rate ([FollowPosition.charsPerSecond]) for the overlay.
///
/// Cost per update: one banded alignment (see [ScriptAligner]) — O(n·b)
/// with n ≤ 16 heard words and a band of b ≈ 40–60 script words — plus, only
/// when that finds nothing, one whole-script alignment, O(n·M). Stability
/// tracking is O(p) with recognizer stability and O(p²) without (an LCS of
/// two partials of p words); the rate meter is O(1) per word over a window
/// of [_rateWindow] onsets. The engine keeps O(p) state besides the script.
class FollowEngine {
  FollowEngine(this.script, {required AppSettings settings, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now,
      _aligner = ScriptAligner(script) {
    configure(settings);
    _lastMatch = _clock();
  }

  final FlatScript script;
  final ScriptAligner _aligner;
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

  FollowPosition _pos = FollowPosition.start;

  /// The last script word confirmed as said (global token index), and the
  /// last one shown — the same, or ahead of it by open words that are the
  /// script's next ones (see [_tentatively]).
  int _token = -1;
  int _shown = -1;
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

  /// Recent stable words and when each began, for the speaking rate.
  final _onsets = <(double, int)>[];
  double? _rate;

  /// Onsets in the rate window; a gap longer than [_rateGap] (a pause, a
  /// breath between beats) starts the window over.
  static const _rateWindow = 10;
  static const _rateGap = 1.2;

  FollowPosition get position => _pos;

  /// Characters a second the presenter is speaking at, or null.
  double? get charsPerSecond => _rate;

  /// The last script word confirmed as said, or −1.
  int get token => _token;

  FollowDecision lastDecision = const FollowDecision(FollowEvent.none, 'start');

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
    _aligner.config = AlignerConfig(minSimilarity: minSim);
  }

  /// Plain-text input — the transcript tail as one string, all of it taken
  /// as final. Words past what the previous call ended with are new. For
  /// tests and simple callers; live following uses [onUpdate].
  FollowEvent onHeard(String heardText) {
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

  FollowEvent onUpdate(HeardUpdate update) => _tentatively(update, _follow(update));

  FollowEvent _follow(HeardUpdate update) {
    final now = _clock();
    final fresh = _stableWords(update);
    if (_suspendedUntil != null && now.isBefore(_suspendedUntil!)) {
      return _decide(FollowEvent.none, 'paused after a manual move');
    }
    if (fresh.added.isEmpty) return _hold(now, 'no new stable words');

    final heard = TextNormalizer.normalizeHeard(fresh.tail.join(' '), language: script.language);
    if (heard.length > ScriptAligner.maxHeard) heard.removeRange(0, heard.length - ScriptAligner.maxHeard);
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
          FollowEvent.none,
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
  AlignmentResult? _farEvidence(List<String> heard, int newTokens, int cap) {
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

  /// The open words a streaming recognizer offers ([HeardUpdate.tentative])
  /// show at once when, read in order, they are exactly the script's next
  /// words and the presenter is reading along. Only final words move the
  /// engine itself ([_token]); they confirm what was shown, and an open word
  /// that is then revised takes the display back. What shows is a word the
  /// recognizer heard, matched to the next unsaid one: never ahead of the
  /// voice.
  FollowEvent _tentatively(HeardUpdate u, FollowEvent event) {
    final now = _clock();
    var shown = _token;
    final n = u.tentative ?? 0;
    final paused = _suspendedUntil != null && now.isBefore(_suspendedUntil!);
    if (n > 0 && !paused && !_pos.holding && now.difference(_lastMatch) < _readingFlow) {
      final open = u.partialWords;
      final heard = TextNormalizer.normalizeHeard(
        open.sublist(math.max(0, open.length - n)).join(' '),
        language: script.language,
      );
      var k = 0;
      while (k < heard.length &&
          _token + 1 + k < script.tokens.length &&
          TextNormalizer.similarity(heard[k], script.tokens[_token + 1 + k].text, spanish: script.spanish) >= 0.95) {
        k++;
      }
      if (k > 0 && k == heard.length) shown = _token + k;
    }
    if (shown == _shown) return event;
    _shown = shown;
    _pos = _display(_pos.confidence);
    if (event != FollowEvent.none) return event;
    return _decide(
      FollowEvent.dimmed,
      shown > _token
          ? 'shown ${shown - _token} open word${shown - _token == 1 ? '' : 's'} tentatively'
          : 'open word revised',
      target: shown,
    );
  }

  FollowEvent _moveTo(int token, DateTime now, AlignmentResult r, String reason, {bool jump = false}) {
    final wasHolding = _pos.holding;
    final before = _pos.beat;
    _token = token;
    _shown = token;
    _lastMatch = now;
    _pos = _display(r.confidence);
    final event = wasHolding
        ? FollowEvent.relocked
        : jump
        ? FollowEvent.jumped
        : _pos.beat != before
        ? FollowEvent.advanced
        : FollowEvent.dimmed;
    return _decide(event, reason, target: token, evidence: r.trailingWeight);
  }

  /// The overlay's position for [_token]: the beat being read and the words
  /// of it said. A finished beat — or one said past "Move on when said", or
  /// with only stop words left — shows the next one as current, but [_token]
  /// stays on the last word really said.
  FollowPosition _display(double confidence) {
    final tokens = script.tokens;
    // The last word said, or shown tentatively.
    final at = math.max(_token, _shown);
    if (at < 0) {
      return FollowPosition(beat: 0, spokenWords: 0, confidence: confidence, holding: false, charsPerSecond: _rate);
    }
    final t = tokens[at];
    final beat = script.beats[t.beat];
    final progress = beat.tokenCount == 0 ? 1.0 : (at - beat.firstToken + 1) / beat.tokenCount;
    final done = at >= beat.endToken - 1 || at >= beat.lastContentToken || progress >= _advanceAt;
    final said = math.min(t.displayIndex + 1, beat.displayWords.length);
    if (done && t.beat < script.length - 1) {
      // The next beat with words to say (empty beats are passed over).
      var next = t.beat + 1;
      while (next < script.length - 1 && script.beats[next].tokenCount == 0) {
        next++;
      }
      final finished = said >= beat.displayWords.length;
      return FollowPosition(
        beat: next,
        spokenWords: 0,
        confidence: confidence,
        holding: false,
        saidBeat: finished ? next : t.beat,
        saidWords: finished ? 0 : said,
        charsPerSecond: _rate,
      );
    }
    return FollowPosition(
      beat: t.beat,
      spokenWords: said,
      confidence: confidence,
      holding: false,
      charsPerSecond: _rate,
    );
  }

  FollowEvent _hold(DateTime now, String reason, {int? target, double? evidence}) {
    if (_holdDuringAdLib && !_pos.holding && now.difference(_lastMatch) > _holdAfter) {
      _pos = FollowPosition(
        beat: _pos.beat,
        spokenWords: _pos.spokenWords,
        confidence: 0,
        holding: true,
        saidBeat: _pos.saidBeat,
        saidWords: _pos.saidWords,
        charsPerSecond: _rate,
      );
      return _decide(FollowEvent.heldStill, 'no script words for ${_holdAfter.inSeconds} s — holding');
    }
    return _decide(FollowEvent.none, reason, target: target, evidence: evidence);
  }

  FollowEvent _decide(FollowEvent event, String reason, {int? target, double? evidence}) {
    lastDecision = FollowDecision(event, reason, target: target, evidence: evidence);
    return event;
  }

  /// The stable words of [u] and which of them are new since the last call.
  ({List<String> tail, List<String> added}) _stableWords(HeardUpdate u) {
    final partial = u.partial.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final List<String> stable;
    if (u.stable case final n?) {
      // The recognizer knows: greedy streaming never rewrites a word it
      // has moved past, so its own count is exact and costs no extra wait.
      stable = partial.sublist(0, n.clamp(0, partial.length));
      _committedTotal = u.committedTotal;
    } else {
      stable = _settledPartial(u, partial);
    }

    final total = u.committedTotal + stable.length;
    final fresh = math.max(0, total - _consumed);
    _consumed = total;
    _seen = total;
    final words = [...u.committed, ...stable];
    final added = words.sublist(math.max(0, words.length - fresh));
    if (u.times case final times? when fresh > 0 && times.length >= words.length) {
      for (var k = words.length - added.length; k < words.length; k++) {
        _hearOnset(times[k], words[k]);
      }
    }
    return (tail: words.sublist(math.max(0, words.length - 24)), added: added);
  }

  /// Segmented Whisper re-reads the open utterance and may rewrite any of
  /// it: a partial word counts once it is unchanged across [stableUpdates]
  /// updates (one more for the last word, which is often cut short).
  List<String> _settledPartial(HeardUpdate u, List<String> partial) {
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
    _partialKeys = keys;
    _partialAge = age;
    _committedTotal = u.committedTotal;
    return partial.sublist(first, end);
  }

  /// One more stable word that began at [at] s: the speaking rate is the
  /// characters said (spaces included) over the time they took, across the
  /// last [_rateWindow] words of the current run of speech, smoothed.
  void _hearOnset(double at, String word) {
    final chars = TextNormalizer.normalizeHeard(word, language: script.language).join(' ').length;
    if (chars == 0) return; // punctuation the recognizer wrote as a word
    if (_onsets.isNotEmpty && (at - _onsets.last.$1 > _rateGap || at < _onsets.last.$1)) _onsets.clear();
    _onsets.add((at, chars + 1));
    if (_onsets.length > _rateWindow) _onsets.removeAt(0);
    if (_onsets.length < 3) return;
    final span = _onsets.last.$1 - _onsets.first.$1;
    if (span <= 0.2) return;
    var said = 0;
    for (var k = 0; k < _onsets.length - 1; k++) {
      said += _onsets[k].$2;
    }
    final now = (said / span).clamp(6.0, 30.0);
    _rate = _rate == null ? now : _rate! + 0.35 * (now - _rate!);
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
    _pos = FollowPosition(beat: b, spokenWords: 0, confidence: 1, holding: false, charsPerSecond: _rate);
    _token = script.beats[b].firstToken - 1;
    _shown = _token;
    _candidate = null;
    _consumed = _seen;
    _lastMatch = _clock();
    _decide(FollowEvent.none, 'manual move to beat $b');
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

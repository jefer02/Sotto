import 'dart:math' as math;

import '../../data/models/settings.dart';
import 'script_aligner.dart';
import 'text_normalizer.dart';

/// Where the presenter is, as the overlay needs it.
class FollowPosition {
  const FollowPosition({
    required this.beat,
    required this.spokenWords,
    required this.confidence,
    required this.holding,
  });

  /// Global beat index.
  final int beat;

  /// Display words of [beat] already said (dimmed to "done").
  final int spokenWords;
  final double confidence;

  /// No match for a while — the presenter is ad-libbing; the overlay freezes.
  final bool holding;

  static const start = FollowPosition(beat: 0, spokenWords: 0, confidence: 0, holding: false);
}

enum FollowEvent { none, dimmed, advanced, jumped, heldStill, relocked }

/// Turns recognizer output into overlay position, applying the rules on the
/// "Following your voice" board:
///
/// 1. Dim only what was really said (confidence ≥ 0.7).
/// 2. Advance at 80 % of a beat, or on its last content word.
/// 3. Never scroll back on a guess: backward jumps need four consecutive
///    matching words at ≥ 0.8.
/// 4. Hold still during ad-libs: no match for 6 s → "Holding"; re-lock on
///    the first 3-word match within 3 beats.
/// 5. Manual beats the machine: "previous beat" pauses following for 3 s.
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
  late double _dimConfidence;
  late bool _holdDuringAdLib;
  late bool _allowJumps;

  static const _holdAfter = Duration(seconds: 6);
  static const _backwardConfidence = 0.8;
  static const _backwardRun = 4;
  static const _relockRun = 3;
  static const _jumpConfidence = 0.85;
  static const _jumpMinMatches = 6;

  FollowPosition _pos = FollowPosition.start;
  late DateTime _lastMatch;
  DateTime? _suspendedUntil;

  /// Highest global token confirmed as spoken.
  int _confirmedToken = -1;

  FollowPosition get position => _pos;

  void configure(AppSettings s) {
    _advanceAt = s.advanceThreshold.clamp(0.5, 1.0);
    _holdDuringAdLib = s.holdDuringAdLib;
    _allowJumps = s.allowSectionJumps;
    final (minSim, dim) = switch (s.sensitivity) {
      Sensitivity.low => (0.88, 0.78),
      Sensitivity.medium => (0.78, 0.70),
      Sensitivity.high => (0.66, 0.60),
    };
    _dimConfidence = dim;
    _aligner.config = AlignerConfig(minSimilarity: minSim);
  }

  /// Feed the rolling tail of recognized words (finalized + partial).
  FollowEvent onHeard(String heardText) {
    final now = _clock();
    if (_suspendedUntil != null && now.isBefore(_suspendedUntil!)) return FollowEvent.none;

    final heard = TextNormalizer.normalizeHeard(heardText, language: script.language);
    if (heard.isEmpty) return FollowEvent.none;

    var result = _aligner.alignNear(heard, _pos.beat);
    var jumped = false;

    final weak = result == null || result.confidence < _dimConfidence;
    if (weak && _allowJumps && heard.length >= _jumpMinMatches) {
      final far = _aligner.alignAnywhere(heard);
      if (far != null &&
          far.confidence >= _jumpConfidence &&
          far.matchedTokens >= _jumpMinMatches &&
          script.tokens[far.tokenIndex].beat != _pos.beat) {
        result = far;
        jumped = true;
      }
    }

    if (result == null || result.confidence < _dimConfidence) {
      if (_holdDuringAdLib && !_pos.holding && now.difference(_lastMatch) > _holdAfter) {
        _pos = FollowPosition(beat: _pos.beat, spokenWords: _pos.spokenWords, confidence: 0, holding: true);
        return FollowEvent.heldStill;
      }
      return FollowEvent.none;
    }

    final token = script.tokens[result.tokenIndex];

    if (_pos.holding) {
      final nearEnough = (token.beat - _pos.beat).abs() <= 3;
      if (!nearEnough || result.trailingRun < _relockRun) return FollowEvent.none;
    }

    // A match behind the current beat is usually the transcript's tail
    // still ending on words already passed. Only a clear re-read — new words
    // well before the confirmed point, four in a row at ≥ 0.8 — moves back.
    final movingBack = token.beat < _pos.beat;
    if (movingBack &&
        (result.tokenIndex >= _confirmedToken - 2 ||
            result.trailingRun < _backwardRun ||
            result.confidence < _backwardConfidence)) {
      return FollowEvent.none;
    }

    final wasHolding = _pos.holding;
    _lastMatch = now;

    if (movingBack || jumped || token.beat != _pos.beat) {
      _confirmedToken = result.tokenIndex;
    } else {
      _confirmedToken = math.max(_confirmedToken, result.tokenIndex);
    }

    final beatIndex = script.tokens[_confirmedToken].beat;
    final beat = script.beats[beatIndex];
    final spoken = script.tokens[_confirmedToken].displayIndex + 1;

    // Rule 2: advance at the threshold, or once the last content word lands.
    final said = _confirmedToken - beat.firstToken + 1;
    final progress = beat.tokenCount == 0 ? 1.0 : said / beat.tokenCount;
    final lastContentSaid = beat.lastContentToken >= 0 && _confirmedToken >= beat.lastContentToken;
    if ((progress >= _advanceAt || lastContentSaid) && beatIndex < script.length - 1) {
      _pos = FollowPosition(beat: beatIndex + 1, spokenWords: 0, confidence: result.confidence, holding: false);
      _confirmedToken = script.beats[beatIndex + 1].firstToken - 1;
      return FollowEvent.advanced;
    }

    final changedBeat = beatIndex != _pos.beat;
    _pos = FollowPosition(
      beat: beatIndex,
      spokenWords: math.min(spoken, beat.displayWords.length),
      confidence: result.confidence,
      holding: false,
    );
    if (wasHolding) return FollowEvent.relocked;
    return changedBeat ? FollowEvent.jumped : FollowEvent.dimmed;
  }

  /// Moves by hotkey or clicker. Going back also pauses following for 3 s so
  /// the recognizer can't immediately drag the script forward again.
  void jumpTo(int beat, {bool suspend = false}) {
    final b = beat.clamp(0, script.length - 1);
    _pos = FollowPosition(beat: b, spokenWords: 0, confidence: 1, holding: false);
    _confirmedToken = script.beats[b].firstToken - 1;
    _lastMatch = _clock();
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

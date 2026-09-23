import 'dart:math' as math;

import '../../data/models/script.dart';
import 'text_normalizer.dart';

/// One spoken token of the flattened script.
class ScriptToken {
  const ScriptToken(this.text, this.beat, this.displayIndex, this.weight);

  final String text;

  /// Global beat index (across sections).
  final int beat;

  /// Index of the display word inside its beat.
  final int displayIndex;

  /// 1 for content words, 0.5 for stop words.
  final double weight;
}

class FlatBeat {
  FlatBeat({
    required this.sectionIndex,
    required this.beat,
    required this.firstToken,
    required this.tokenCount,
    required this.displayWords,
    required this.lastContentToken,
  });

  final int sectionIndex;
  final Beat beat;
  final int firstToken;
  final int tokenCount;
  final List<String> displayWords;

  /// Global index of the last non-stop-word token, or -1.
  final int lastContentToken;

  int get endToken => firstToken + tokenCount;
}

/// The script as one token stream, built once per session.
class FlatScript {
  FlatScript._(this.beats, this.tokens, this.sectionFirstBeat, this.language);

  final List<FlatBeat> beats;
  final List<ScriptToken> tokens;

  /// Global index of each section's first beat.
  final List<int> sectionFirstBeat;

  /// Spoken language; recognizer output is normalized the same way.
  final String language;

  /// [language] is the language the script is spoken in (BCP-47).
  factory FlatScript.from(Script script, {String language = 'en'}) {
    final beats = <FlatBeat>[];
    final tokens = <ScriptToken>[];
    final sectionFirst = <int>[];
    for (var s = 0; s < script.sections.length; s++) {
      sectionFirst.add(beats.length);
      for (final beat in script.sections[s].beats) {
        final spoken = TextNormalizer.tokenize(beat.text, language: language);
        final first = tokens.length;
        var lastContent = -1;
        for (final t in spoken) {
          final stop = TextNormalizer.isStopWord(t.text);
          if (!stop) lastContent = tokens.length;
          tokens.add(ScriptToken(t.text, beats.length, t.displayIndex, stop ? 0.5 : 1));
        }
        beats.add(
          FlatBeat(
            sectionIndex: s,
            beat: beat,
            firstToken: first,
            tokenCount: spoken.length,
            displayWords: TextNormalizer.displayWords(beat.text),
            lastContentToken: lastContent,
          ),
        );
      }
    }
    return FlatScript._(beats, tokens, sectionFirst, language);
  }

  int get length => beats.length;

  int sectionOf(int beat) => beats[beat].sectionIndex;
}

class AlignmentResult {
  const AlignmentResult({
    required this.tokenIndex,
    required this.confidence,
    required this.matchedTokens,
    required this.trailingRun,
  });

  /// Global index of the script token aligned with the last heard word.
  final int tokenIndex;

  /// Score ÷ best possible score for the aligned span, 0..1.
  final double confidence;

  /// Number of heard tokens that matched a script token.
  final int matchedTokens;

  /// Consecutive matches ending at the last heard word.
  final int trailingRun;
}

class AlignerConfig {
  const AlignerConfig({
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
/// band of the script around the current beat. The alignment must end on
/// the newest heard word, so the result says where the presenter is *now*.
class ScriptAligner {
  ScriptAligner(this.script, [this.config = const AlignerConfig()]);

  final FlatScript script;
  AlignerConfig config;

  static const maxHeard = 14;

  AlignmentResult? alignNear(List<String> heard, int currentBeat) {
    final from = math.max(0, currentBeat - config.beatsBack);
    final to = math.min(script.length - 1, currentBeat + config.beatsAhead);
    return align(heard, script.beats[from].firstToken, script.beats[to].endToken);
  }

  /// Whole-script search, used to follow a presenter who skipped ahead.
  AlignmentResult? alignAnywhere(List<String> heard) => align(heard, 0, script.tokens.length);

  AlignmentResult? align(List<String> heardAll, int start, int end) {
    if (heardAll.isEmpty || end <= start) return null;
    final heard = heardAll.length > maxHeard ? heardAll.sublist(heardAll.length - maxHeard) : heardAll;
    final n = heard.length;
    final m = end - start;
    final tokens = script.tokens;

    // H[i][j]: best local score aligning heard[..i) with script[start..start+j).
    final h = List.generate(n + 1, (_) => List<double>.filled(m + 1, 0));
    // Back-pointers: 0 stop, 1 diagonal, 2 up (speech gap), 3 left (script gap).
    final bp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));

    for (var i = 1; i <= n; i++) {
      final hw = heard[i - 1];
      final hWeight = TextNormalizer.isStopWord(hw) ? 0.5 : 1.0;
      for (var j = 1; j <= m; j++) {
        final tok = tokens[start + j - 1];
        final sim = TextNormalizer.similarity(hw, tok.text);
        final sub = sim >= config.minSimilarity ? 2 * math.min(hWeight, tok.weight) * sim : -1.0;
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

    // The newest heard word may be a still-changing partial result, so allow
    // the alignment to end one word early at a small cost.
    var bestScore = 0.0, bestI = n, bestJ = 0;
    for (var j = 1; j <= m; j++) {
      if (h[n][j] > bestScore && bp[n][j] == 1) {
        bestScore = h[n][j];
        bestI = n;
        bestJ = j;
      }
      if (n > 1 && h[n - 1][j] - 0.5 > bestScore && bp[n - 1][j] == 1) {
        bestScore = h[n - 1][j] - 0.5;
        bestI = n - 1;
        bestJ = j;
      }
    }
    if (bestScore <= 0) return null;

    // Walk back to measure the span and count matches.
    var i = bestI, j = bestJ, matched = 0, trailing = 0;
    var inTrailingRun = true;
    var possible = 0.0;
    while (i > 0 && j > 0 && bp[i][j] != 0) {
      switch (bp[i][j]) {
        case 1:
          final hw = heard[i - 1];
          final w = TextNormalizer.isStopWord(hw) ? 0.5 : 1.0;
          possible += 2 * w;
          final sim = TextNormalizer.similarity(hw, tokens[start + j - 1].text);
          if (sim >= config.minSimilarity) {
            matched++;
            if (inTrailingRun) trailing++;
          } else {
            inTrailingRun = false;
          }
          i--;
          j--;
        case 2:
          possible += 2 * (TextNormalizer.isStopWord(heard[i - 1]) ? 0.5 : 1.0);
          inTrailingRun = false;
          i--;
        default:
          inTrailingRun = false;
          j--;
      }
    }
    if (possible == 0) return null;

    return AlignmentResult(
      tokenIndex: start + bestJ - 1,
      confidence: (bestScore / possible).clamp(0.0, 1.0),
      matchedTokens: matched,
      trailingRun: trailing,
    );
  }
}

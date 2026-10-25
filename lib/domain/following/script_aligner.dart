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

  /// How much a match on this word says about where the presenter is:
  /// [ScriptAligner.stopWeight] for stop words; content words from 1 (said
  /// once in the script) down towards 0.5 the more often the script uses them.
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
  FlatScript._(this.beats, this.tokens, this.sectionFirstBeat, this.language, this._weights);

  final List<FlatBeat> beats;
  final List<ScriptToken> tokens;

  /// Global index of each section's first beat.
  final List<int> sectionFirstBeat;

  /// Spoken language; recognizer output is normalized the same way.
  final String language;

  final Map<String, double> _weights;

  bool get spanish => language.toLowerCase().startsWith('es');

  /// [language] is the language the script is spoken in (BCP-47).
  factory FlatScript.from(Script script, {String language = 'en'}) {
    final spokenBeats = [
      for (final section in script.sections)
        for (final beat in section.beats) TextNormalizer.tokenize(beat.text, language: language),
    ];
    // Rare words are strong evidence of where the presenter is; words the
    // script keeps repeating are weak, stop words weaker still.
    final counts = <String, int>{};
    for (final spoken in spokenBeats) {
      for (final t in spoken) {
        counts[t.text] = (counts[t.text] ?? 0) + 1;
      }
    }
    final weights = {
      for (final MapEntry(key: w, value: n) in counts.entries)
        w: TextNormalizer.isStopWord(w) ? ScriptAligner.stopWeight : 0.5 + 0.5 / n,
    };

    final beats = <FlatBeat>[];
    final tokens = <ScriptToken>[];
    final sectionFirst = <int>[];
    var b = 0;
    for (var s = 0; s < script.sections.length; s++) {
      sectionFirst.add(beats.length);
      for (final beat in script.sections[s].beats) {
        final spoken = spokenBeats[b++];
        final first = tokens.length;
        var lastContent = -1;
        for (final t in spoken) {
          if (!TextNormalizer.isStopWord(t.text)) lastContent = tokens.length;
          tokens.add(ScriptToken(t.text, beats.length, t.displayIndex, weights[t.text]!));
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
    return FlatScript._(beats, tokens, sectionFirst, language, weights);
  }

  int get length => beats.length;

  int sectionOf(int beat) => beats[beat].sectionIndex;

  /// Weight of a heard word: the script's for its own words, a content
  /// word's for anything else.
  double weightOf(String word) => _weights[word] ?? (TextNormalizer.isStopWord(word) ? ScriptAligner.stopWeight : 1.0);
}

class AlignmentResult {
  const AlignmentResult({
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
/// span of the script. The alignment must end on the newest heard word (or
/// the one before it), so the result says where the presenter is *now*.
///
/// Cost: one alignment fills an n × m table — n ≤ [maxHeard] heard words,
/// m script words in the span — in O(n·m) time and space (scores and
/// back-pointers). Following searches a band of about 50 words around the
/// presenter, so ≈ 800 cells per update; the whole script (O(n·M) for M
/// words, 16 × 5,000 = 80,000 cells for a long talk) only when the band
/// finds nothing.
class ScriptAligner {
  ScriptAligner(this.script, [this.config = const AlignerConfig()]);

  final FlatScript script;
  AlignerConfig config;

  static const maxHeard = 16;

  /// A stop word's weight: it says little about where the presenter is.
  static const stopWeight = 0.3;

  AlignmentResult? alignNear(List<String> heard, int currentBeat) {
    final from = math.max(0, currentBeat - config.beatsBack);
    final to = math.min(script.length - 1, currentBeat + config.beatsAhead);
    return align(heard, script.beats[from].firstToken, script.beats[to].endToken);
  }

  /// Whole-script search, used to follow a presenter who skipped ahead.
  /// [around]: script words (global, start inclusive, end exclusive) the
  /// presenter has just read; a match there doesn't make a match elsewhere
  /// ambiguous.
  AlignmentResult? alignAnywhere(List<String> heard, {(int, int)? around}) =>
      align(heard, 0, script.tokens.length, around: around);

  AlignmentResult? align(List<String> heardAll, int start, int end, {(int, int)? around}) {
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

    return AlignmentResult(
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

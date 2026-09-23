/// Turns written script text into the words a speech recognizer would emit,
/// so "$48.2 million — up 12% on Q2" can be matched against
/// "forty eight point two million up twelve percent on q two".
///
/// Each spoken token keeps the index of the display word it came from, which
/// is what lets the overlay dim exactly the words that were said.
class SpokenToken {
  const SpokenToken(this.text, this.displayIndex);

  final String text;
  final int displayIndex;

  @override
  String toString() => '$text@$displayIndex';
}

abstract final class TextNormalizer {
  static const _ones = [
    'zero',
    'one',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
    'ten',
    'eleven',
    'twelve',
    'thirteen',
    'fourteen',
    'fifteen',
    'sixteen',
    'seventeen',
    'eighteen',
    'nineteen',
  ];
  static const _tens = ['', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety'];

  /// Words that carry little evidence of position; they count half.
  static const stopWords = {
    'a',
    'an',
    'the',
    'and',
    'or',
    'but',
    'of',
    'to',
    'in',
    'on',
    'at',
    'for',
    'is',
    'it',
    'its',
    "it's",
    'we',
    'i',
    'you',
    'that',
    'this',
    'so',
    'with',
    'as',
    'be',
    'was',
    'are',
    'our',
    'my',
    'uh',
    'um',
    'just',
    'by',
    'from',
  };

  static const _stopWordsEs = {
    'el', 'la', 'los', 'las', 'un', 'una', 'unos', 'unas', 'y', 'e', 'o', 'u', 'de', 'del', 'a', 'al',
    'en', 'por', 'para', 'con', 'que', 'es', 'se', 'lo', 'le', 'les', 'su', 'sus', 'mi', 'nuestro',
    'nuestra', 'eh', 'este', 'esta', 'como', 'pero', 'ya', 'muy',
  };

  /// Words that carry little evidence of position, in English or Spanish.
  static bool isStopWord(String w) => stopWords.contains(w) || _stopWordsEs.contains(w);

  static bool _spanish(String language) => language.toLowerCase().startsWith('es');

  /// á → a, ñ → n… Recognizers and scripts don't always agree on accents.
  static String _fold(String s) => s.replaceAllMapped(RegExp('[áàäâéèëêíìïîóòöôúùüûñç]'), (m) {
    const map = {
      'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e', 'í': 'i', 'ì': 'i',
      'ï': 'i', 'î': 'i', 'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
      'ñ': 'n', 'ç': 'c',
    };
    return map[m[0]]!;
  });

  static final _wordSplit = RegExp(r'\s+');
  static final _numberish = RegExp(r'^([$€£]?)(\d[\d,.]*)(%|k|m|bn|b|st|nd|rd|th|s)?$');
  static final _alnum = RegExp(r'^([a-z]+)(\d+)$');
  static final _strip = RegExp(r"[^\p{L}\p{N}$€£%.,'\-]", unicode: true);

  /// Display words as the overlay renders them (emphasis markers removed).
  static List<String> displayWords(String text) =>
      text.replaceAll('**', '').split(_wordSplit).where((w) => w.isNotEmpty).toList();

  /// [language] is the spoken language (BCP-47); numbers are read out in it.
  static List<SpokenToken> tokenize(String text, {String language = 'en'}) {
    final words = displayWords(text);
    final out = <SpokenToken>[];
    for (var i = 0; i < words.length; i++) {
      for (final t in spokenForms(words[i], language: language)) {
        out.add(SpokenToken(t, i));
      }
    }
    return out;
  }

  /// Normalises recognizer output (which may itself contain digits).
  static List<String> normalizeHeard(String text, {String language = 'en'}) => [
    for (final w in text.split(_wordSplit))
      if (w.isNotEmpty) ...spokenForms(w, language: language),
  ];

  static List<String> spokenForms(String raw, {String language = 'en'}) {
    final es = _spanish(language);
    var w = _fold(raw.toLowerCase()).replaceAll('’', "'").replaceAll(_strip, '');
    // Spanish writes "31,4 %" with a space: the lone sign is still spoken.
    if (w == '%') return es ? const ['por', 'ciento'] : const ['percent'];
    // Trim sentence punctuation but keep decimal points inside numbers.
    w = w.replaceAll(RegExp(r'^[.,\-]+|[.,\-]+$'), '');
    if (w.isEmpty) return const [];

    final hyphenParts = w.split('-').where((p) => p.isNotEmpty).toList();
    if (hyphenParts.length > 1) {
      return [for (final p in hyphenParts) ...spokenForms(p, language: language)];
    }

    final num = _numberish.firstMatch(w);
    if (num != null) {
      final (whole, decimals) = _splitNumber(num.group(2)!);
      return es
          ? _numberWordsEs(whole, decimals, num.group(3))
          : _numberWords(num.group(1)!, whole, decimals, num.group(3));
    }

    final alnum = _alnum.firstMatch(w);
    if (alnum != null) {
      // "q2" → q two, "h2" → h two
      final n = int.parse(alnum.group(2)!);
      return [...alnum.group(1)!.split(''), ...(es ? _integerWordsEs(n) : _integerWords(n))];
    }

    return [w.replaceAll(RegExp(r'[$€£%.,]'), '').replaceAll("'", '')].where((s) => s.isNotEmpty).toList();
  }

  /// Splits "1,250.5" / "1.250,5" / "48.2" / "48,2" into whole and decimal
  /// digits. A separator followed by exactly three digits groups thousands;
  /// any other separator is the decimal point — so both conventions work.
  static (int, String?) _splitNumber(String digits) {
    final m = RegExp(r'^(.*?)(?:[.,](\d{1,2}|\d{4,}))?$').firstMatch(digits)!;
    final whole = int.tryParse(m.group(1)!.replaceAll(RegExp('[.,]'), '')) ?? 0;
    return (whole, m.group(2));
  }

  static List<String> _numberWords(String currency, int whole, String? decimals, String? suffix) {
    final words = <String>[];
    final parts = [whole.toString(), ?decimals];

    final isYear =
        currency.isEmpty &&
        suffix == null &&
        parts.length == 1 &&
        parts[0].length == 4 &&
        whole >= 1900 &&
        whole < 2100;
    if (isYear) {
      words.addAll(_yearWords(whole));
    } else if (suffix == 'st' || suffix == 'nd' || suffix == 'rd' || suffix == 'th') {
      words.addAll(_ordinalWords(whole));
    } else {
      words.addAll(_integerWords(whole));
      if (parts.length > 1) {
        words.add('point');
        for (final ch in parts[1].split('')) {
          words.add(_ones[int.parse(ch)]);
        }
      }
    }

    switch (suffix) {
      case '%':
        words.add('percent');
      case 'k':
        words.add('thousand');
      case 'm':
        words.add('million');
      case 'b' || 'bn':
        words.add('billion');
      case 's':
        words.add('s'); // "1990s" — rare; the fuzzy matcher absorbs it
    }
    // "$48.2" is usually said "forty eight point two (million) dollars";
    // the currency word is optional, so it is dropped rather than guessed.
    return words;
  }

  static List<String> _numberWordsEs(int whole, String? decimals, String? suffix) {
    final words = [..._integerWordsEs(whole)];
    if (decimals != null) {
      words.add('coma');
      // "31,4" → treinta y uno coma cuatro; "0,05" → cero coma cero cinco.
      if (decimals.length <= 2 && !decimals.startsWith('0')) {
        words.addAll(_integerWordsEs(int.parse(decimals)));
      } else {
        for (final ch in decimals.split('')) {
          words.addAll(_integerWordsEs(int.parse(ch)));
        }
      }
    }
    switch (suffix) {
      case '%':
        words.addAll(const ['por', 'ciento']);
      case 'k':
        words.add('mil');
      case 'm':
        words.add('millones');
    }
    return words;
  }

  static const _onesEs = [
    'cero', 'uno', 'dos', 'tres', 'cuatro', 'cinco', 'seis', 'siete', 'ocho', 'nueve', 'diez', 'once', 'doce',
    'trece', 'catorce', 'quince', 'dieciseis', 'diecisiete', 'dieciocho', 'diecinueve', 'veinte', 'veintiuno',
    'veintidos', 'veintitres', 'veinticuatro', 'veinticinco', 'veintiseis', 'veintisiete', 'veintiocho',
    'veintinueve',
  ];
  static const _tensEs = ['', '', '', 'treinta', 'cuarenta', 'cincuenta', 'sesenta', 'setenta', 'ochenta', 'noventa'];
  static const _hundredsEs = [
    '', 'ciento', 'doscientos', 'trescientos', 'cuatrocientos', 'quinientos', 'seiscientos', 'setecientos',
    'ochocientos', 'novecientos',
  ];

  /// Spanish cardinals, accent-folded: 31 → treinta y uno, 2026 → dos mil veintiseis.
  static List<String> _integerWordsEs(int n) {
    if (n < 30) return [_onesEs[n]];
    if (n < 100) return [_tensEs[n ~/ 10], if (n % 10 != 0) ...['y', _onesEs[n % 10]]];
    if (n == 100) return const ['cien'];
    if (n < 1000) return [_hundredsEs[n ~/ 100], if (n % 100 != 0) ..._integerWordsEs(n % 100)];
    if (n < 1000000) {
      final k = n ~/ 1000;
      return [if (k > 1) ..._integerWordsEs(k), 'mil', if (n % 1000 != 0) ..._integerWordsEs(n % 1000)];
    }
    final m = n ~/ 1000000;
    return [
      ...(m == 1 ? const ['un', 'millon'] : [..._integerWordsEs(m), 'millones']),
      if (n % 1000000 != 0) ..._integerWordsEs(n % 1000000),
    ];
  }

  static List<String> _integerWords(int n) {
    if (n < 20) return [_ones[n]];
    if (n < 100) {
      return [_tens[n ~/ 10], if (n % 10 != 0) _ones[n % 10]];
    }
    if (n < 1000) {
      return [_ones[n ~/ 100], 'hundred', if (n % 100 != 0) ..._integerWords(n % 100)];
    }
    for (final (size, name) in const [(1000000000, 'billion'), (1000000, 'million'), (1000, 'thousand')]) {
      if (n >= size) {
        return [..._integerWords(n ~/ size), name, if (n % size != 0) ..._integerWords(n % size)];
      }
    }
    return [n.toString()];
  }

  static List<String> _yearWords(int y) {
    final hi = y ~/ 100, lo = y % 100;
    if (lo == 0) return [..._integerWords(hi), 'hundred'];
    if (y >= 2000 && y < 2010) return _integerWords(y);
    return [..._integerWords(hi), if (lo < 10) 'oh', ..._integerWords(lo)];
  }

  static List<String> _ordinalWords(int n) {
    final words = _integerWords(n);
    final last = words.removeLast();
    const irregular = {
      'one': 'first',
      'two': 'second',
      'three': 'third',
      'five': 'fifth',
      'eight': 'eighth',
      'nine': 'ninth',
      'twelve': 'twelfth',
    };
    final ordinal = irregular[last] ?? (last.endsWith('y') ? '${last.substring(0, last.length - 1)}ieth' : '${last}th');
    return [...words, ordinal];
  }

  /// Similarity in 0..1 between two spoken tokens. Exact matches score 1;
  /// near-misses from the recognizer ("renegotiated" / "renegotiate") score
  /// by normalised edit distance on a light phonetic key.
  static double similarity(String a, String b) {
    if (a == b) return 1;
    if (a.isEmpty || b.isEmpty) return 0;
    final ka = _phoneticKey(a), kb = _phoneticKey(b);
    if (ka == kb) return 0.9;
    final d = _levenshtein(ka, kb);
    final len = ka.length > kb.length ? ka.length : kb.length;
    return (1 - d / len).clamp(0.0, 1.0);
  }

  static String _phoneticKey(String s) => s
      .replaceAll(RegExp(r'ph'), 'f')
      .replaceAll(RegExp(r'ck|q'), 'k')
      .replaceAll(RegExp(r'c(?=[eiy])'), 's')
      .replaceAll('c', 'k')
      .replaceAll(RegExp(r'z'), 's')
      .replaceAllMapped(RegExp(r'(.)\1+'), (m) => m[1]!)
      .replaceAll(RegExp(r'(?<=.)[aeiouy]+'), '');

  static int _levenshtein(String a, String b) {
    var prev = List<int>.generate(b.length + 1, (i) => i);
    var cur = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      cur[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost].reduce((x, y) => x < y ? x : y);
      }
      final t = prev;
      prev = cur;
      cur = t;
    }
    return prev[b.length];
  }
}

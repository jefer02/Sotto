import 'form_filler.dart';
import 'form_model.dart';

/// Every kind of question Sotto answers. [wire] is the name the model uses
/// and the session record stores.
enum QuestionType {
  text('text'),
  longText('long_text'),
  multipleChoice('multiple_choice'),
  trueFalse('true_false'),
  checkboxes('checkboxes'),
  dropdown('dropdown'),
  scale('scale'),
  matching('matching'),
  ordering('ordering'),
  imageChoice('image_choice'),

  /// A question shown as plain text with nothing to fill (a PDF, a
  /// form with no fields): the answer is shown in the overlay instead.
  readOnly('read_only');

  const QuestionType(this.wire);
  final String wire;

  /// Answered by a click on one spot (an option, a star, an image).
  bool get pickOne => switch (this) {
    multipleChoice || trueFalse || scale || imageChoice => true,
    _ => false,
  };
}

abstract final class QuestionTypes {
  static const _aliases = {
    'text': QuestionType.text,
    'short_text': QuestionType.text,
    'short': QuestionType.text,
    'long_text': QuestionType.longText,
    'textarea': QuestionType.longText,
    'paragraph': QuestionType.longText,
    'essay': QuestionType.longText,
    'multiple_choice': QuestionType.multipleChoice,
    'multiple choice': QuestionType.multipleChoice,
    'mc': QuestionType.multipleChoice,
    'radio': QuestionType.multipleChoice,
    'choice': QuestionType.multipleChoice,
    'single_choice': QuestionType.multipleChoice,
    'true_false': QuestionType.trueFalse,
    'true/false': QuestionType.trueFalse,
    'tf': QuestionType.trueFalse,
    'boolean': QuestionType.trueFalse,
    'checkboxes': QuestionType.checkboxes,
    'checkbox': QuestionType.checkboxes,
    'select_all': QuestionType.checkboxes,
    'multi_select': QuestionType.checkboxes,
    'dropdown': QuestionType.dropdown,
    'select': QuestionType.dropdown,
    'combo': QuestionType.dropdown,
    'scale': QuestionType.scale,
    'rating': QuestionType.scale,
    'likert': QuestionType.scale,
    'stars': QuestionType.scale,
    'matching': QuestionType.matching,
    'match': QuestionType.matching,
    'ordering': QuestionType.ordering,
    'ranking': QuestionType.ordering,
    'order': QuestionType.ordering,
    'image_choice': QuestionType.imageChoice,
    'image': QuestionType.imageChoice,
    'read_only': QuestionType.readOnly,
    'readonly': QuestionType.readOnly,
    'plain_text': QuestionType.readOnly,
  };

  /// The model's name for a type (tolerant of spelling), or null.
  static QuestionType? parse(String? s) => s == null ? null : _aliases[s.trim().toLowerCase().replaceAll('-', '_')];

  static final _number = RegExp(r'^\d{1,2}$');
  static final _star = RegExp(r'^(\d{1,2}\s*)?(stars?|estrellas?|★+|☆+)$');
  static const _likert = {
    'strongly disagree', 'disagree', 'neutral', 'agree', 'strongly agree', //
    'totalmente en desacuerdo',
    'en desacuerdo',
    'de acuerdo',
    'totalmente de acuerdo',
    'ni de acuerdo ni en desacuerdo',
    'never', 'rarely', 'sometimes', 'often', 'always', 'nunca', 'rara vez', 'a veces', 'a menudo', 'siempre',
  };
  static const _true = {'true', 'verdadero', 'v', 't', 'cierto', 'correct', 'correcto'};
  static const _false = {'false', 'falso', 'f', 'incorrect', 'incorrecto'};

  static bool isTrueWord(String s) => _true.contains(OptionMatcher.fold(s));
  static bool isFalseWord(String s) => _false.contains(OptionMatcher.fold(s));

  /// What a field from the accessibility tree asks, by its role and options.
  static QuestionType classify(FormField f) {
    switch (f.role) {
      case FieldRole.text:
        return f.multiline ? QuestionType.longText : QuestionType.text;
      case FieldRole.checkboxes || FieldRole.checkbox:
        return QuestionType.checkboxes;
      case FieldRole.combo:
        return QuestionType.dropdown;
      case FieldRole.radio:
        final labels = [for (final o in f.options) OptionMatcher.fold(o.label.replaceFirst(_enumerator, ''))];
        if (labels.length == 2 && labels.any(_true.contains) && labels.any(_false.contains)) {
          return QuestionType.trueFalse;
        }
        if (labels.length >= 3 && labels.every(_number.hasMatch)) {
          final n = [for (final l in labels) int.parse(l)];
          final consecutive = [for (var i = 1; i < n.length; i++) n[i] - n[i - 1]].every((d) => d == 1);
          if (consecutive) return QuestionType.scale;
        }
        if (labels.length >= 3 && (labels.every(_star.hasMatch) || labels.every(_likert.contains))) {
          return QuestionType.scale;
        }
        return QuestionType.multipleChoice;
    }
  }

  static final _enumerator = RegExp(r'^\s*\(?([a-zA-Z]|\d{1,2})[).:\-]\s*');
}

/// A/B/C/D answers: the model gives the letter *and* the option's text, and
/// either may match what's on screen (Google Forms shows no letters; other
/// platforms show only letters).
abstract final class ChoiceMatcher {
  static final _enumerator = RegExp(r'^\s*\(?([a-zA-Z])[).:\-]\s+');

  /// Index into [options]. The full option text wins when both are given
  /// and disagree (a letter is easier to get wrong); then the letter, by an
  /// "A)" / "B." prefix or by position; then true/false across languages.
  static int? match(List<String> options, {String answer = '', String? letter}) {
    if (options.isEmpty) return null;
    final text = answer.trim();
    // An option that *is* the answer ("M" among S / M / L) beats reading
    // it as a letter.
    final same = options.indexWhere((o) => OptionMatcher.fold(o) == OptionMatcher.fold(text));
    if (text.isNotEmpty && same >= 0) return same;
    final letterOnly = RegExp(r'^[a-zA-Z]$').hasMatch(text);
    if (text.isNotEmpty && !letterOnly) {
      final byText = _byText(options, text);
      if (byText != null) return byText;
    }
    final l = (letter ?? (letterOnly ? text : '')).trim().toLowerCase();
    if (RegExp(r'^[a-z]$').hasMatch(l)) {
      for (var i = 0; i < options.length; i++) {
        final m = _enumerator.firstMatch(options[i]);
        if (m != null && m.group(1)!.toLowerCase() == l) return i;
      }
      final n = l.codeUnitAt(0) - 96;
      if (n >= 1 && n <= options.length) return n - 1;
    }
    if (text.isNotEmpty && !letterOnly) return OptionMatcher.match(options, text);
    return null;
  }

  static int? _byText(List<String> options, String text) {
    final exact = OptionMatcher.match(options, text, threshold: 0.8);
    if (exact != null) return exact;
    // "True" answered, "Verdadero" shown (and the other way round).
    final yes = QuestionTypes.isTrueWord(text), no = QuestionTypes.isFalseWord(text);
    if (yes || no) {
      for (var i = 0; i < options.length; i++) {
        final o = options[i].replaceFirst(_enumerator, '');
        if (yes ? QuestionTypes.isTrueWord(o) : QuestionTypes.isFalseWord(o)) return i;
      }
    }
    return null;
  }
}

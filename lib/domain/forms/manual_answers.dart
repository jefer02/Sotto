import 'form_runner.dart' show ItemStatus;
import 'question_types.dart';

/// One question as the presenter sees it once a fill is over: what Sotto
/// suggests, and whether Sotto filled it already. What it couldn't fill is
/// filled in by hand from here.
class ManualAnswer {
  const ManualAnswer({
    required this.number,
    required this.question,
    required this.answer,
    this.letter,
    this.type = QuestionType.text,
    this.status = ItemStatus.pending,
    this.note = '',
  });

  /// 1-based, as the panel lists it ("answer question 4 in English").
  final int number;
  final String question;
  final String answer;

  /// A/B/C… for a lettered option.
  final String? letter;
  final QuestionType type;
  final ItemStatus status;
  final String note;

  bool get done => status == ItemStatus.filled;

  /// Password and payment fields: never answered, never copied.
  bool get sensitive => status == ItemStatus.blocked;

  bool get hasAnswer => !sensitive && answer.trim().isNotEmpty;

  /// Left to the presenter: Sotto has an answer but couldn't (or, for a
  /// read-only question, wouldn't) put it in the form.
  bool get manual => hasAnswer && !done && status != ItemStatus.pending && status != ItemStatus.filling;

  /// "B) Weekly" for a lettered option, else the answer as it is.
  String get shown => letter != null ? '$letter) $answer' : answer;

  /// What a copy button puts on the clipboard: the text to paste or look
  /// for — the option's own text, not its letter.
  String get copyText => answer;
}

abstract final class ManualAnswers {
  /// How many the presenter has to fill in by hand.
  static int needed(Iterable<ManualAnswer> all) => all.where((a) => a.manual).length;

  /// "Copy all": every answer, numbered, with its question; sensitive fields
  /// and questions without an answer are left out.
  static String copyAll(Iterable<ManualAnswer> all) => [
    for (final a in all)
      if (a.hasAnswer) '${a.number}. ${a.question}\n   ${a.shown}',
  ].join('\n\n');

  /// The form as the panel chat's context: numbered like the panel, with
  /// each suggestion and what became of it. Sensitive fields appear only as
  /// such — never with a value.
  static String context(Iterable<ManualAnswer> all, {String page = ''}) {
    final lines = <String>[
      if (page.trim().isNotEmpty) 'Window: ${page.trim()}',
      for (final a in all)
        if (a.sensitive)
          '${a.number}. ${a.question} — password or payment field: never read or answered'
        else
          '${a.number}. ${a.question} [${a.type.wire}] — '
              '${a.hasAnswer ? 'suggested: ${a.shown}' : 'no suggestion'} — ${_status(a)}',
    ];
    return lines.join('\n');
  }

  static String _status(ManualAnswer a) => switch (a.status) {
    ItemStatus.filled => 'filled by Sotto',
    ItemStatus.failed => 'Sotto could not fill it; the user fills it by hand',
    ItemStatus.skipped => 'skipped${a.note.isEmpty ? '' : ' (${a.note})'}',
    ItemStatus.shown => 'read-only question: the answer is only shown',
    ItemStatus.pending || ItemStatus.filling => 'not filled yet',
    ItemStatus.blocked => 'never answered',
  };
}

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'form_model.dart';

// ─────────────────────────── Option matching ───────────────────────────

/// Finds which option the model meant: exact, then ignoring case, accents
/// and punctuation, then by letter or number ("B", "2)"), then by overlap
/// and similarity. Null when nothing is close enough — never a guess.
abstract final class OptionMatcher {
  static const _accents = {
    'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'ã': 'a', 'å': 'a', 'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e', //
    'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i', 'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o', 'ú': 'u', //
    'ù': 'u', 'ü': 'u', 'û': 'u', 'ñ': 'n', 'ç': 'c', 'ß': 'ss',
  };

  /// Lowercase, no accents, punctuation as spaces, single-spaced.
  static String fold(String s) {
    final lower = s.toLowerCase();
    final out = StringBuffer();
    for (final ch in lower.split('')) {
      out.write(_accents[ch] ?? ch);
    }
    return out.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  static final _enumerator = RegExp(r'^\s*\(?([a-zA-Z]|\d{1,2})[).:\-]\s*');

  /// Index into [options] or null.
  static int? match(List<String> options, String answer, {double threshold = 0.6}) {
    if (options.isEmpty || answer.trim().isEmpty) return null;
    final exact = options.indexOf(answer.trim());
    if (exact >= 0) return exact;
    final a = fold(answer);
    final folded = [for (final o in options) fold(o)];
    final same = folded.indexOf(a);
    if (same >= 0) return same;

    // Options with their "A)" / "1." enumerators stripped.
    final bare = [for (final o in options) fold(o.replaceFirst(_enumerator, ''))];
    final bareAnswer = fold(answer.replaceFirst(_enumerator, ''));
    final sameBare = bare.indexOf(bareAnswer);
    if (sameBare >= 0 && bareAnswer.isNotEmpty) return sameBare;

    // "B" or "2" alone: the option with that enumerator, or that position.
    if (RegExp(r'^[a-z]$|^\d{1,2}$').hasMatch(a)) {
      for (var i = 0; i < options.length; i++) {
        final m = _enumerator.firstMatch(options[i]);
        if (m != null && m.group(1)!.toLowerCase() == a) return i;
      }
      final n = int.tryParse(a) ?? (a.codeUnitAt(0) - 96);
      if (n >= 1 && n <= options.length && options.every((o) => !RegExp(r'\d').hasMatch(o))) return n - 1;
    }

    // One contains the other (a whole-word match): the longest option wins.
    int? contained;
    for (var i = 0; i < bare.length; i++) {
      final o = bare[i];
      if (o.isEmpty) continue;
      final hit = ' $bareAnswer '.contains(' $o ') || ' $o '.contains(' $bareAnswer ');
      if (hit && (contained == null || o.length > bare[contained].length)) contained = i;
    }
    if (contained != null) return contained;

    // Similar spelling (typos, plural, extra words).
    var best = -1;
    var bestScore = 0.0;
    for (var i = 0; i < bare.length; i++) {
      final s = similarity(bare[i], bareAnswer);
      if (s > bestScore) {
        bestScore = s;
        best = i;
      }
    }
    return bestScore >= threshold ? best : null;
  }

  /// Sørensen–Dice over character bigrams, 0..1.
  static double similarity(String a, String b) {
    if (a == b) return 1;
    if (a.length < 2 || b.length < 2) return 0;
    List<String> grams(String s) => [for (var i = 0; i < s.length - 1; i++) s.substring(i, i + 2)];
    final ga = grams(a);
    final gb = [...grams(b)];
    var hits = 0;
    for (final g in ga) {
      final i = gb.indexOf(g);
      if (i >= 0) {
        hits++;
        gb.removeAt(i);
      }
    }
    return 2 * hits / (ga.length + grams(b).length);
  }

  /// "yes", "Sí", "true", "x"… (accents folded).
  static bool isYes(String s) =>
      RegExp(r'^(yes|y|true|checked|check|on|si|s|verdadero|marcar|marcado|1|x)$').hasMatch(fold(s));
}

// ─────────────────────────────── Answers ───────────────────────────────

/// One answer from the model.
class FieldAnswer {
  const FieldAnswer({
    required this.fieldId,
    required this.question,
    this.answer = '',
    this.choices = const [],
    this.confidence = 1,
    this.point,
    this.kind = 'text',
  });

  /// "f3", or "screen" for a question the accessibility tree didn't have.
  final String fieldId;
  final String question;
  final String answer;

  /// Checkbox groups: the labels to check.
  final List<String> choices;
  final double confidence;

  /// For "screen" answers: where to click, in screenshot pixels.
  final Offset? point;

  /// For "screen" answers: "text" (click, then type) or "choice" (click).
  final String kind;

  FieldAnswer copyWith({String? answer, List<String>? choices}) => FieldAnswer(
    fieldId: fieldId,
    question: question,
    answer: answer ?? this.answer,
    choices: choices ?? this.choices,
    confidence: confidence,
    point: point,
    kind: kind,
  );

  /// What the overlay shows.
  String get display => choices.isNotEmpty ? choices.join(', ') : answer;

  /// `{"answers":[{"field_id":"f1","question":"…","answer":"…" | [...],
  /// "confidence":0.9, "point":[x,y], "kind":"text"}]}`. Tolerant of fences
  /// and prose; throws [FormatException] when there is no answers list.
  static List<FieldAnswer> parseAll(String raw) {
    final from = raw.indexOf('{');
    final to = raw.lastIndexOf('}');
    if (from < 0 || to <= from) throw const FormatException('No JSON object');
    final j = jsonDecode(raw.substring(from, to + 1));
    final list = j is Map ? j['answers'] : null;
    if (list is! List) throw const FormatException('No "answers" list');
    return [
      for (final a in list.whereType<Map<Object?, Object?>>())
        if (a['field_id'] != null)
          () {
            final ans = a['answer'];
            final pt = a['point'];
            return FieldAnswer(
              fieldId: '${a['field_id']}'.trim(),
              question: '${a['question'] ?? ''}'.trim(),
              answer: switch (ans) {
                final String s => s.trim(),
                final bool b => b ? 'yes' : 'no',
                final num n => '$n',
                _ => '',
              },
              choices: ans is List ? [for (final c in ans) '$c'.trim()] : const [],
              confidence: ((a['confidence'] as num?)?.toDouble() ?? 1).clamp(0, 1).toDouble(),
              point: pt is List && pt.length == 2 && pt[0] is num && pt[1] is num
                  ? Offset((pt[0] as num).toDouble(), (pt[1] as num).toDouble())
                  : null,
              kind: '${a['kind'] ?? 'text'}',
            );
          }(),
    ];
  }
}

// ─────────────────────────────── Actions ───────────────────────────────

/// What to do to one control. Accessibility patterns first; a click (and
/// typing) at the control's centre only when it has none.
sealed class FillAction {
  const FillAction();
}

class SetValueAction extends FillAction {
  const SetValueAction(this.elementId, this.text);
  final String elementId;
  final String text;
}

class SelectAction extends FillAction {
  const SelectAction(this.elementId);
  final String elementId;
}

class ToggleAction extends FillAction {
  const ToggleAction(this.elementId, this.on);
  final String elementId;
  final bool on;
}

class ChooseAction extends FillAction {
  const ChooseAction(this.elementId, this.label);
  final String elementId;
  final String label;
}

/// Fallback: click at [point] (physical pixels), then type [text] if any.
class ClickTypeAction extends FillAction {
  const ClickTypeAction(this.point, {this.text});
  final Offset point;
  final String? text;
}

enum SkipReason { sensitive, noMatch, noAnswer, unknownField, lowConfidence }

/// One question to fill: the field, the answer and the actions.
class FillStep {
  const FillStep({required this.field, required this.answer, required this.actions, this.expected = const []});

  /// Null for a "screen" answer outside the accessibility tree.
  final FormField? field;
  final FieldAnswer answer;
  final List<FillAction> actions;

  /// Option labels that must end up selected (radio, checkboxes, combo).
  final List<String> expected;

  String get question => answer.question.isNotEmpty ? answer.question : (field?.label ?? '');
}

class SkippedAnswer {
  const SkippedAnswer(this.question, this.reason, {this.field, this.answer});
  final String question;
  final SkipReason reason;
  final FormField? field;
  final FieldAnswer? answer;
}

class FillPlan {
  const FillPlan(this.steps, this.skipped);
  final List<FillStep> steps;
  final List<SkippedAnswer> skipped;
}

abstract final class FormFiller {
  /// The ids the model sees: f1, f2… in reading order.
  static Map<String, FormField> idsFor(List<FormField> fields) => {
    for (var i = 0; i < fields.length; i++) 'f${i + 1}': fields[i],
  };

  static Offset _center(Rect r) => r.center;

  /// Maps answers to actions. [toScreen] maps a screenshot point to
  /// physical pixels ("screen" answers). Sensitive fields are never filled,
  /// whatever the model says.
  static FillPlan plan(
    Map<String, FormField> ids,
    List<FieldAnswer> answers, {
    Offset? Function(Offset imagePoint)? toScreen,
    double minConfidence = 0,
  }) {
    final steps = <FillStep>[];
    final skipped = <SkippedAnswer>[];
    final used = <String>{};
    for (final a in answers) {
      if (a.fieldId == 'screen') {
        final p = a.point == null ? null : toScreen?.call(a.point!);
        if (p == null || a.display.isEmpty) {
          skipped.add(SkippedAnswer(a.question, SkipReason.unknownField, answer: a));
        } else {
          steps.add(
            FillStep(
              field: null,
              answer: a,
              actions: [ClickTypeAction(p, text: a.kind == 'choice' ? null : a.answer)],
            ),
          );
        }
        continue;
      }
      final f = ids[a.fieldId];
      if (f == null || !used.add(a.fieldId)) {
        skipped.add(SkippedAnswer(a.question, SkipReason.unknownField, answer: a));
        continue;
      }
      SkippedAnswer skip(SkipReason r) =>
          SkippedAnswer(a.question.isEmpty ? f.label : a.question, r, field: f, answer: a);
      if (f.sensitive) {
        skipped.add(skip(SkipReason.sensitive));
        continue;
      }
      if (a.confidence < minConfidence) {
        skipped.add(skip(SkipReason.lowConfidence));
        continue;
      }
      if (a.display.trim().isEmpty && f.role != FieldRole.checkboxes) {
        skipped.add(skip(SkipReason.noAnswer));
        continue;
      }
      final step = _step(f, a);
      if (step == null) {
        skipped.add(skip(SkipReason.noMatch));
      } else {
        steps.add(step);
      }
    }
    return FillPlan(steps, skipped);
  }

  static FillStep? _step(FormField f, FieldAnswer a) {
    switch (f.role) {
      case FieldRole.text:
        final id = f.elementId!;
        return FillStep(
          field: f,
          answer: a,
          actions: [
            f.patterns.contains('value')
                ? SetValueAction(id, a.answer)
                : ClickTypeAction(_center(f.bounds), text: a.answer),
          ],
        );
      case FieldRole.radio:
        final i = OptionMatcher.match([for (final o in f.options) o.label], a.answer);
        if (i == null) return null;
        final o = f.options[i];
        final canSelect = f.patterns.contains('select') || f.patterns.contains('invoke');
        return FillStep(
          field: f,
          answer: a.copyWith(answer: o.label),
          expected: [o.label],
          actions: [canSelect && o.elementId != null ? SelectAction(o.elementId!) : ClickTypeAction(_center(o.bounds))],
        );
      case FieldRole.checkboxes:
        final labels = [for (final o in f.options) o.label];
        final wanted = <int>{};
        for (final c in a.choices.isNotEmpty ? a.choices : a.answer.split(RegExp(r'\s*[,;]\s*'))) {
          final i = OptionMatcher.match(labels, c);
          if (i != null) wanted.add(i);
        }
        if (wanted.isEmpty && (a.choices.isNotEmpty || a.answer.trim().isNotEmpty)) return null;
        final canToggle = f.patterns.contains('toggle');
        return FillStep(
          field: f,
          answer: a.copyWith(choices: [for (final i in wanted) labels[i]]),
          expected: [for (final i in wanted) labels[i]],
          actions: [
            for (var i = 0; i < f.options.length; i++)
              if (f.options[i].selected != wanted.contains(i))
                canToggle && f.options[i].elementId != null
                    ? ToggleAction(f.options[i].elementId!, wanted.contains(i))
                    : ClickTypeAction(_center(f.options[i].bounds)),
          ],
        );
      case FieldRole.checkbox:
        final on = OptionMatcher.isYes(a.answer);
        final current = f.options.firstOrNull?.selected ?? false;
        return FillStep(
          field: f,
          answer: a.copyWith(answer: on ? 'yes' : 'no'),
          expected: on ? [f.label] : const [],
          actions: [
            if (on != current)
              f.patterns.contains('toggle') ? ToggleAction(f.elementId!, on) : ClickTypeAction(_center(f.bounds)),
          ],
        );
      case FieldRole.combo:
        final id = f.elementId!;
        if (f.options.isEmpty) {
          // Options unknown until opened: choose by label, the native side
          // opens it and looks.
          return FillStep(
            field: f,
            answer: a,
            expected: [a.answer],
            actions: [
              f.patterns.contains('expand') || f.patterns.contains('value')
                  ? ChooseAction(id, a.answer)
                  : ClickTypeAction(_center(f.bounds), text: a.answer),
            ],
          );
        }
        final i = OptionMatcher.match([for (final o in f.options) o.label], a.answer);
        if (i == null) return null;
        final label = f.options[i].label;
        return FillStep(
          field: f,
          answer: a.copyWith(answer: label),
          expected: [label],
          actions: [
            f.patterns.contains('expand') || f.patterns.contains('value')
                ? ChooseAction(id, label)
                : ClickTypeAction(_center(f.bounds), text: label),
          ],
        );
    }
  }
}

// ─────────────────────────────── Verify ───────────────────────────────

abstract final class FormVerifier {
  /// Steps whose value did not stick, judged from a fresh read. Steps that
  /// can't be checked (screen clicks, fields that vanished) count as done.
  static List<FillStep> failed(List<FillStep> steps, FormSnapshot after) {
    final out = <FillStep>[];
    for (final s in steps) {
      final f = s.field;
      if (f == null) continue;
      final now = after.field(f.key);
      if (now == null) continue;
      final ok = switch (f.role) {
        FieldRole.text => _sameText(now.value, s.answer.answer),
        FieldRole.combo =>
          _sameText(now.value, s.expected.firstOrNull ?? s.answer.answer) ||
              now.selected.any((l) => _sameText(l, s.expected.firstOrNull ?? '')),
        FieldRole.radio ||
        FieldRole.checkboxes ||
        FieldRole.checkbox => _sameSet(now.selected, s.expected, whole: f.role != FieldRole.radio),
      };
      if (!ok) out.add(s);
    }
    return out;
  }

  static bool _sameText(String actual, String expected) {
    final a = OptionMatcher.fold(actual);
    final e = OptionMatcher.fold(expected);
    // Fields may reformat (phone numbers, trailing spaces) or truncate.
    return a == e ||
        (e.isNotEmpty && a.contains(e)) ||
        (a.isNotEmpty && e.startsWith(a) && a.length >= math.min(e.length, 40));
  }

  static bool _sameSet(List<String> actual, List<String> expected, {required bool whole}) {
    final a = {for (final x in actual) OptionMatcher.fold(x)};
    final e = {for (final x in expected) OptionMatcher.fold(x)};
    return whole ? a.length == e.length && a.containsAll(e) : e.every(a.contains);
  }
}

// ─────────────────────────────── Paging ───────────────────────────────

enum PageMove {
  /// Fields still empty here: answer them.
  answer,

  /// Everything answered and there's a Next button.
  next,

  /// Everything answered and there's a Submit button: stop for the user.
  submit,

  /// Nothing left and no button: scroll to look for more.
  scroll,

  /// Nothing left, nothing to press, scrolling found nothing new.
  done,
}

abstract final class FormPager {
  /// The fields to ask about: not sensitive, still empty, not tried yet.
  static List<FormField> pending(FormSnapshot s, Set<String> attempted) => [
    for (final f in s.fields)
      if (!f.sensitive && f.empty && !attempted.contains(f.key)) f,
  ];

  static PageMove decide(FormSnapshot s, Set<String> attempted, {required bool scrolledWithoutNews}) {
    if (pending(s, attempted).isNotEmpty) return PageMove.answer;
    if (s.next != null) return PageMove.next;
    if (s.submit != null) return PageMove.submit;
    return scrolledWithoutNews ? PageMove.done : PageMove.scroll;
  }
}

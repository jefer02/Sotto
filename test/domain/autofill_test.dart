import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/domain/agent/safety.dart';
import 'package:sotto/domain/forms/autofill_watcher.dart';
import 'package:sotto/domain/forms/form_filler.dart';
import 'package:sotto/domain/forms/form_model.dart';

const _chrome = ForegroundWindow(id: '42', title: 'Quiz - Google Chrome', app: 'chrome');
const _notepad = ForegroundWindow(id: '7', title: 'notes.txt - Notepad', app: 'notepad');

FormField _text(String key, String label, {String value = '', bool password = false}) => FormField(
  key: key,
  role: FieldRole.text,
  label: label,
  bounds: const Rect.fromLTWH(0, 0, 100, 20),
  elementId: key,
  value: value,
  sensitive: password,
  patterns: const {'value'},
);

FormField _radio(String label, List<String> options, {Set<String> patterns = const {'select'}}) => FormField(
  key: 'g:$label',
  role: FieldRole.radio,
  label: label,
  bounds: Rect.fromLTWH(0, 0, 200, 40.0 * options.length),
  options: [
    for (var i = 0; i < options.length; i++)
      FormOption(options[i], elementId: 'o$i', bounds: Rect.fromLTWH(0, 40.0 * i, 200, 30)),
  ],
  patterns: patterns,
);

void main() {
  group('watcher', () {
    test('only a real change starts a cycle', () {
      final w = AutoFillWatcher()..enable();
      final fields = [_text('a', 'Name'), _text('b', 'Email')];
      final page = PageSignature.of(_chrome, fields);
      expect(w.observe(_chrome, page, eligible: true), WatchDecision.start);
      expect(w.cycleFinished(page), isFalse);

      // The same page, now with answers in it: still the same page.
      final filled = [_text('a', 'Name', value: 'Ana'), _text('b', 'Email', value: 'a@b.c')];
      expect(PageSignature.of(_chrome, filled), page);
      expect(w.observe(_chrome, PageSignature.of(_chrome, filled), eligible: true), WatchDecision.none);

      // A new question appears: a new page.
      final more = [...fields, _text('c', 'Phone')];
      expect(w.observe(_chrome, PageSignature.of(_chrome, more), eligible: true), WatchDecision.start);
    });

    test('never its own window, never a window with nothing to fill, never while paused', () {
      final w = AutoFillWatcher()..enable();
      const own = ForegroundWindow(id: '1', title: 'Sotto', app: 'sotto', own: true);
      expect(w.observe(own, 'x', eligible: true), WatchDecision.none);
      expect(w.observe(_notepad, 'w:7|notes', eligible: _notepad.mayShowQuestions), WatchDecision.none);
      w.pause();
      expect(w.status, AutoFillStatus.paused);
      expect(w.observe(_chrome, 'p1', eligible: true), WatchDecision.none);
      w.resume();
      expect(w.observe(_chrome, 'p1', eligible: true), WatchDecision.start);
    });

    test('one cycle at a time; one page waits and is looked at right after', () {
      final w = AutoFillWatcher()..enable();
      expect(w.observe(_chrome, 'p1', eligible: true), WatchDecision.start);
      expect(w.observe(_chrome, 'p1', eligible: true), WatchDecision.none);
      expect(w.observe(_chrome, 'p2', eligible: true), WatchDecision.queued);
      expect(w.observe(_chrome, 'p3', eligible: true), WatchDecision.queued);
      expect(w.queued, 'p3', reason: 'at most one waits: the latest');
      expect(w.cycleFinished('p1'), isTrue);
      expect(w.status, AutoFillStatus.watching);
    });

    test('pause lets the running cycle finish, then rests; the emergency stop rests at once', () {
      final w = AutoFillWatcher()..enable();
      w.observe(_chrome, 'p1', eligible: true);
      w.pause();
      expect(w.status, AutoFillStatus.filling);
      expect(w.observe(_chrome, 'p2', eligible: true), WatchDecision.none);
      expect(w.cycleFinished('p1'), isFalse);
      expect(w.status, AutoFillStatus.paused);

      final e = AutoFillWatcher()..enable();
      e.observe(_chrome, 'p1', eligible: true);
      e.emergencyStop();
      expect(e.status, AutoFillStatus.paused);
    });

    test('a manual fill goes through the same queue and leaves auto-fill as it was', () {
      final w = AutoFillWatcher();
      expect(w.startManual('p1'), isTrue);
      expect(w.startManual('p2'), isFalse, reason: 'never two at once');
      w.cycleFinished('p1');
      expect(w.status, AutoFillStatus.off);

      final on = AutoFillWatcher()..enable();
      on.startManual('p1');
      on.cycleFinished('p1');
      expect(on.status, AutoFillStatus.watching);
      expect(on.observe(_chrome, 'p1', eligible: true), WatchDecision.none, reason: 'handled already');
    });

    test('pages with fewer than two fields are told apart by window and title', () {
      expect(
        PageSignature.of(_chrome, const []),
        isNot(PageSignature.of(_chrome.copyTitle('Quiz 2 - Google Chrome'), const [])),
      );
      expect(_chrome.pageName, 'Quiz');
      expect(const ForegroundWindow(id: '1', app: 'AcroRd32').mayShowQuestions, isTrue);
    });
  });

  group('scroll loop', () {
    test('respects the limit', () {
      final loop = ScrollLoop(limit: 10);
      var n = 0;
      while (loop.shouldScroll(newFieldsSinceLastScroll: true, atSubmit: false)) {
        n++;
      }
      expect(n, 10);
    });

    test('stops when a scroll found nothing, at the bottom, at Submit, or when off', () {
      final loop = ScrollLoop();
      expect(loop.shouldScroll(newFieldsSinceLastScroll: false, atSubmit: false), isTrue, reason: 'first look');
      expect(loop.shouldScroll(newFieldsSinceLastScroll: false, atSubmit: false), isFalse);
      expect(ScrollLoop().shouldScroll(newFieldsSinceLastScroll: true, atSubmit: false, canScrollMore: false), isFalse);
      expect(ScrollLoop().shouldScroll(newFieldsSinceLastScroll: true, atSubmit: true), isFalse);
      expect(ScrollLoop(enabled: false).shouldScroll(newFieldsSinceLastScroll: true, atSubmit: false), isFalse);
    });
  });

  group('stop', () {
    test('needs a one-second hold', () {
      final t0 = DateTime(2026);
      final h = HoldToConfirm();
      h.press(t0);
      expect(h.progress(t0.add(const Duration(milliseconds: 500))), closeTo(0.5, 1e-9));
      expect(h.release(t0.add(const Duration(milliseconds: 500))), isFalse);
      expect(h.holding, isFalse);
      h.press(t0);
      expect(h.release(t0.add(const Duration(milliseconds: 1000))), isTrue);
      expect(HoldToConfirm().release(t0), isFalse, reason: 'a release without a press');
    });
  });

  group('A/B/C/D', () {
    const lettered = ['A) Paris', 'B) Rome', 'C) Madrid', 'D) Lisbon'];
    const plain = ['Paris', 'Rome', 'Madrid', 'Lisbon'];

    test('matches by letter', () {
      expect(ChoiceMatcher.match(lettered, letter: 'C'), 2);
      expect(ChoiceMatcher.match(lettered, answer: 'c'), 2);
      expect(ChoiceMatcher.match(plain, letter: 'B'), 1, reason: 'no letters shown: by position');
    });

    test('matches by full option text, which wins over a wrong letter', () {
      expect(ChoiceMatcher.match(lettered, answer: 'Madrid'), 2);
      expect(ChoiceMatcher.match(plain, answer: 'Lisbon', letter: 'D'), 3);
      expect(ChoiceMatcher.match(lettered, answer: 'Rome', letter: 'A'), 1);
    });

    test('true / false across languages, and an option that is itself a letter', () {
      expect(ChoiceMatcher.match(['Verdadero', 'Falso'], answer: 'False'), 1);
      expect(ChoiceMatcher.match(['True', 'False'], answer: 'Verdadero'), 0);
      expect(ChoiceMatcher.match(['S', 'M', 'L'], answer: 'M'), 1);
      expect(ChoiceMatcher.match(plain, answer: 'Berlin'), isNull);
    });
  });

  group('lettered options in an ordinary form', () {
    test('"Which option best describes you" is selected by letter or by text, through the tree or visually', () {
      const options = ['A) Student', 'B) Employee', 'C) Freelancer', 'D) Other'];
      expect(ChoiceMatcher.match(options, answer: 'Freelancer'), 2);
      expect(ChoiceMatcher.match(options, letter: 'B'), 1);
      expect(ChoiceMatcher.match(options, answer: 'C) Freelancer', letter: 'C'), 2);

      final tree = FormSnapshot.fromElements([
        const UiElement(
          id: 'g',
          type: 'group',
          name: 'Which option best describes you?',
          bounds: Rect.fromLTWH(0, 0, 300, 200),
        ),
        for (var i = 0; i < options.length; i++)
          UiElement(
            id: 'r$i',
            type: 'radio',
            name: options[i],
            parent: 'g',
            bounds: Rect.fromLTWH(0, 40.0 * i + 20, 300, 30),
            patterns: const {'select'},
          ),
      ]);
      final f = tree.fields.single;
      expect(f.label, 'Which option best describes you?');
      final plan = FormFiller.plan(
        {'f1': f},
        const [
          FieldAnswer(fieldId: 'f1', question: 'Which option best describes you?', answer: 'Employee', letter: 'B'),
        ],
      );
      expect((plan.steps.single.actions.single as SelectAction).elementId, 'r1');

      // The same options drawn as plain text: a click at the chosen one.
      final visual = _radio('Which option best describes you?', options, patterns: const {});
      final click =
          FormFiller.plan(
                {'f1': visual},
                const [FieldAnswer(fieldId: 'f1', question: 'Q', answer: 'D')],
              ).steps.single.actions.single
              as ClickTypeAction;
      expect(click.point, visual.options[3].bounds.center);
    });
  });

  group('question types', () {
    test('classified from the field', () {
      expect(QuestionTypes.classify(_radio('Q', ['True', 'False'])), QuestionType.trueFalse);
      expect(QuestionTypes.classify(_radio('Q', ['1', '2', '3', '4', '5'])), QuestionType.scale);
      expect(QuestionTypes.classify(_radio('Q', ['Disagree', 'Neutral', 'Agree'])), QuestionType.scale);
      expect(QuestionTypes.classify(_radio('Q', ['A) Paris', 'B) Rome', 'C) Madrid'])), QuestionType.multipleChoice);
      expect(
        QuestionTypes.classify(
          const FormField(key: 'x', role: FieldRole.text, label: 'Essay', bounds: Rect.zero, multiline: true),
        ),
        QuestionType.longText,
      );
      expect(QuestionTypes.parse('ranking'), QuestionType.ordering);
      expect(QuestionTypes.parse('Image-Choice'), QuestionType.imageChoice);
    });
  });

  group('safety', () {
    test('password and payment fields are never filled', () {
      final snap = FormSnapshot.fromElements([
        for (final (id, name, pw) in [
          ('p', 'Password', true),
          ('c', 'Card number', false),
          ('v', 'CVV', false),
          ('x', 'CVC', false),
          ('e', 'Expiry date', false),
          ('b', 'Billing address', false),
          ('n', 'Name', false),
        ])
          UiElement(
            id: id,
            type: 'edit',
            name: name,
            password: pw,
            bounds: const Rect.fromLTWH(0, 0, 100, 20),
            patterns: const {'value'},
          ),
      ]);
      expect(
        [for (final f in snap.fields) (f.label, f.sensitive)],
        [
          ('Password', true),
          ('Card number', true),
          ('CVV', true),
          ('CVC', true),
          ('Expiry date', true),
          ('Billing address', true),
          ('Name', false),
        ],
      );
      final ids = FormFiller.idsFor(snap.fields);
      final plan = FormFiller.plan(ids, [
        for (final id in ids.keys) FieldAnswer(fieldId: id, question: ids[id]!.label, answer: '4111 1111 1111 1111'),
      ]);
      expect(plan.steps.map((s) => s.question), ['Name']);
      expect(plan.skipped.where((s) => s.reason == SkipReason.sensitive).length, 6);
    });

    test('buttons that submit, send, pay, buy, confirm or delete are never pressed on their own', () {
      for (final label in ['Submit', 'Send', 'Pay now', 'Buy', 'Confirm', 'Delete', 'Enviar', 'Pagar', 'Confirmar']) {
        expect(SafetyGate.isForbiddenButton(label), isTrue, reason: label);
      }
      for (final label in ['Next', 'Continue', 'Siguiente', 'Back']) {
        expect(SafetyGate.isForbiddenButton(label), isFalse, reason: label);
      }
    });
  });

  group('answers to actions', () {
    test('options without an accessible action fall back to a click at their centre', () {
      final f = _radio('Capital of Spain?', ['A) Paris', 'B) Rome', 'C) Madrid'], patterns: const {});
      final plan = FormFiller.plan(
        {'f1': f},
        const [FieldAnswer(fieldId: 'f1', question: 'Capital of Spain?', answer: 'Madrid', letter: 'C')],
      );
      final action = plan.steps.single.actions.single as ClickTypeAction;
      expect(action.point, f.options[2].bounds.center);
      expect(plan.steps.single.expected, ['C) Madrid']);
    });

    test('an accessible option is selected, by letter alone too', () {
      final f = _radio('Capital of Spain?', ['A) Paris', 'B) Rome', 'C) Madrid']);
      final plan = FormFiller.plan({'f1': f}, const [FieldAnswer(fieldId: 'f1', question: 'Q', answer: 'C')]);
      expect((plan.steps.single.actions.single as SelectAction).elementId, 'o2');
    });

    test('visual options, scales and images are one click at the mapped point', () {
      Offset toScreen(Offset p) => Offset(p.dx * 2 - 2560, p.dy * 2);
      final reply = FormReply.parse(
        '{"answers":['
        '{"field_id":"screen","question_text":"Rate us","question_type":"scale","kind":"radio","answer":"4",'
        '"box":[100,100,20,20],"reasoning_summary":"a fair score"},'
        '{"field_id":"screen","question_text":"Pick the cat","question_type":"image_choice","kind":"radio",'
        '"answer":"cat.jpg","answer_letter":"b","box":[300,200,100,80]}]}',
      );
      final plan = FormFiller.plan(const {}, reply.answers, toScreen: toScreen);
      expect(
        [for (final s in plan.steps) (s.actions.single as ClickTypeAction).point],
        [toScreen(const Offset(110, 110)), toScreen(const Offset(350, 240))],
      );
      expect([for (final s in plan.steps) s.type], [QuestionType.scale, QuestionType.imageChoice]);
      expect(reply.answers.first.reasoning, 'a fair score');
      expect(reply.answers.last.letter, 'B');
    });

    test('matching and ordering become drags; read-only questions touch nothing', () {
      final reply = FormReply.parse(
        '{"answers":['
        '{"field_id":"screen","question_text":"Order these","question_type":"ordering","kind":"drag","answer":"1, 2",'
        '"drags":[{"from":[0,0,10,10],"to":[0,100,10,10]},{"from":[5,5],"to":[5,55]}]},'
        '{"field_id":"screen","question_text":"What is 2+2?","question_type":"read_only","answer":"4"}]}',
      );
      final plan = FormFiller.plan(const {}, reply.answers, toScreen: (p) => p);
      expect(
        [for (final a in plan.steps.first.actions) ((a as DragAction).from, a.to)],
        [(const Offset(5, 5), const Offset(5, 105)), (const Offset(5, 5), const Offset(5, 55))],
      );
      expect(plan.steps.last.showOnly, isTrue);
      expect(plan.steps.last.actions, isEmpty);
    });

    test('"no questions here" parses', () {
      expect(FormReply.parse('{"questionnaire":false,"answers":[]}').questionnaire, isFalse);
      expect(FormReply.parse('{"answers":[]}').questionnaire, isTrue);
    });
  });
}

extension on ForegroundWindow {
  ForegroundWindow copyTitle(String title) => ForegroundWindow(id: id, title: title, app: app, own: own);
}

import 'dart:convert';
import 'dart:ui' show Locale, Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/domain/agent/coordinates.dart';
import 'package:sotto/domain/forms/form_filler.dart';
import 'package:sotto/domain/forms/form_model.dart';
import 'package:sotto/l10n/l10n.dart';
import 'package:sotto/services/ai/llm_client.dart';
import 'package:sotto/services/ai/questionnaire_service.dart';

const _all = ['value', 'select', 'toggle', 'expand', 'invoke', 'focus'];

Map<String, Object?> el(
  String id,
  String type,
  String name, {
  String? parent,
  String? value,
  bool? checked,
  List<num> bounds = const [100, 100, 200, 24],
  List<String> patterns = _all,
  List<String> options = const [],
  bool password = false,
}) => {
  'id': id,
  'type': type,
  'name': name,
  'parent': ?parent,
  'value': ?value,
  'checked': ?checked,
  'bounds': bounds,
  'patterns': patterns,
  'options': options,
  'password': password,
};

/// A browser-like questionnaire, as UI Automation would report it.
List<UiElement> fakeTree({bool withPatterns = true, String? nameValue, bool colorChecked = false}) {
  final p = withPatterns ? _all : const <String>[];
  return [
    for (final m in [
      el('1', 'edit', 'Full name', value: nameValue ?? '', bounds: [100, 100, 300, 24], patterns: p),
      el('2', 'edit', 'Password', password: true, bounds: [100, 140, 300, 24], patterns: p),
      el('3', 'edit', 'Card number', bounds: [100, 180, 300, 24], patterns: p),
      el('g1', 'group', '¿Con qué frecuencia usas la app?', bounds: [100, 220, 400, 90]),
      el('4', 'radio', 'Nunca', parent: 'g1', checked: false, bounds: [110, 240, 80, 20], patterns: p),
      el('5', 'radio', 'A veces', parent: 'g1', checked: false, bounds: [110, 262, 80, 20], patterns: p),
      el('6', 'radio', 'A diario', parent: 'g1', checked: false, bounds: [110, 284, 80, 20], patterns: p),
      el('g2', 'group', 'Favourite colours', bounds: [100, 320, 400, 60]),
      el('7', 'checkbox', 'Red', parent: 'g2', checked: colorChecked, bounds: [110, 330, 60, 20], patterns: p),
      el('8', 'checkbox', 'Green', parent: 'g2', checked: false, bounds: [180, 330, 60, 20], patterns: p),
      el('9', 'checkbox', 'Blue', parent: 'g2', checked: false, bounds: [250, 330, 60, 20], patterns: p),
      el('10', 'checkbox', 'I accept the terms', checked: false, bounds: [100, 400, 200, 20], patterns: p),
      el(
        '11',
        'combo',
        'Country',
        value: '',
        options: ['Spain', 'Mexico', 'United States'],
        bounds: [100, 440, 200, 24],
        patterns: p,
      ),
      el('l1', 'list', '', parent: '11', bounds: [100, 470, 200, 80]),
      el('12', 'listitem', 'Spain', parent: 'l1', bounds: [100, 470, 200, 20]),
      el('13', 'button', 'Back', bounds: [100, 600, 80, 30]),
      el('14', 'button', 'Next', bounds: [300, 600, 80, 30]),
    ])
      UiElement.fromMap(m),
  ];
}

class _FakeLlm extends LlmClient {
  _FakeLlm(this.reply);
  final String reply;
  String? system;
  String? user;
  List<String> images = const [];
  DeepSeekTaskProfile? profile;
  bool? json;

  @override
  Stream<String> stream({
    required String system,
    required String user,
    int maxTokens = 4096,
    DeepSeekTaskProfile profile = DeepSeekTaskProfile.answers,
    List<String> images = const [],
    bool json = false,
  }) async* {
    this.system = system;
    this.user = user;
    this.images = images;
    this.profile = profile;
    this.json = json;
    yield reply;
  }

  @override
  void close() {}
}

void main() {
  setUpAll(() => L10n.current = lookupAppLocalizations(const Locale('en')));

  group('FormSnapshot', () {
    test('groups radios and checkboxes by parent, keeps combo items as options', () {
      final s = FormSnapshot.fromElements(fakeTree());
      expect(s.fields.map((f) => (f.role, f.label)).toList(), [
        (FieldRole.text, 'Full name'),
        (FieldRole.text, 'Password'),
        (FieldRole.text, 'Card number'),
        (FieldRole.radio, '¿Con qué frecuencia usas la app?'),
        (FieldRole.checkboxes, 'Favourite colours'),
        (FieldRole.checkbox, 'I accept the terms'),
        (FieldRole.combo, 'Country'),
      ]);
      final radio = s.fields[3];
      expect(radio.options.map((o) => o.label), ['Nunca', 'A veces', 'A diario']);
      expect(s.fields.last.options.map((o) => o.label), ['Spain', 'Mexico', 'United States']);
      expect(s.next?.label, 'Next');
      expect(s.submit, isNull);
    });

    test('password and payment fields are sensitive and never pending', () {
      final s = FormSnapshot.fromElements(fakeTree());
      expect(s.fields[1].sensitive, isTrue); // IsPassword
      expect(s.fields[2].sensitive, isTrue); // "Card number"
      final pending = FormPager.pending(s, {});
      expect(pending.any((f) => f.sensitive), isFalse);
      expect(pending.length, 5);
    });

    test('next vs submit labels, English and Spanish', () {
      for (final l in ['Next', 'Siguiente', 'Continuar', '›']) {
        expect(FormSnapshot.isNextLabel(l), isTrue, reason: l);
      }
      for (final l in ['Submit', 'Enviar', 'Send form', 'Finalizar']) {
        expect(FormSnapshot.isSubmitLabel(l), isTrue, reason: l);
      }
      expect(FormSnapshot.isSubmitLabel('Next'), isFalse);
      expect(FormSnapshot.isSubmitLabel('Back'), isFalse);
    });
  });

  group('OptionMatcher', () {
    const options = ['Nunca', 'A veces', 'A diario', 'Más de una vez al día'];

    test('exact, case, accents and punctuation', () {
      expect(OptionMatcher.match(options, 'A diario'), 2);
      expect(OptionMatcher.match(options, 'a DIARIO.'), 2);
      expect(OptionMatcher.match(options, 'mas de una vez al dia'), 3);
    });

    test('letters and numbers', () {
      const lettered = ['A) Strongly agree', 'B) Agree', 'C) Disagree'];
      expect(OptionMatcher.match(lettered, 'B'), 1);
      expect(OptionMatcher.match(lettered, 'Agree'), 1);
      expect(OptionMatcher.match(['Yes', 'No', 'Maybe'], '2'), 1);
    });

    test('fuzzy spelling, and no guess when nothing is close', () {
      expect(OptionMatcher.match(['Monthly', 'Weekly', 'Daily'], 'weekley'), 1);
      expect(OptionMatcher.match(['Monthly', 'Weekly', 'Daily'], 'Every day of the year'), isNull);
      expect(OptionMatcher.match(['Red', 'Green'], 'Purple'), isNull);
    });

    test('yes / sí', () {
      expect(OptionMatcher.isYes('Sí'), isTrue);
      expect(OptionMatcher.isYes('yes'), isTrue);
      expect(OptionMatcher.isYes('no'), isFalse);
    });
  });

  test('FieldAnswer.parseAll is tolerant', () {
    final answers = FieldAnswer.parseAll(
      'Here you go:\n```json\n{"answers":[{"field_id":"f1","question":"Name","answer":"Ana","confidence":0.9},'
      '{"field_id":"f3","answer":["Red","Blue"]},{"field_id":"f4","answer":true},'
      '{"field_id":"screen","question":"Rate us","answer":"5","point":[640,320],"kind":"choice"}]}\n```',
    );
    expect(answers.length, 4);
    expect(answers[1].choices, ['Red', 'Blue']);
    expect(answers[2].answer, 'yes');
    expect(answers[3].point, const Offset(640, 320));
    expect(() => FieldAnswer.parseAll('nope'), throwsFormatException);
  });

  group('FormFiller', () {
    Map<String, FormField> ids({bool withPatterns = true}) =>
        FormFiller.idsFor(FormPager.pending(FormSnapshot.fromElements(fakeTree(withPatterns: withPatterns)), {}));

    test('maps answers to accessibility actions', () {
      final i = ids();
      expect(i.keys, ['f1', 'f2', 'f3', 'f4', 'f5']);
      final plan = FormFiller.plan(i, const [
        FieldAnswer(fieldId: 'f1', question: 'Name', answer: 'Ana Ruiz'),
        FieldAnswer(fieldId: 'f2', question: 'Frequency', answer: 'a diario'),
        FieldAnswer(fieldId: 'f3', question: 'Colours', choices: ['red', 'Blue']),
        FieldAnswer(fieldId: 'f4', question: 'Terms', answer: 'yes'),
        FieldAnswer(fieldId: 'f5', question: 'Country', answer: 'mexico'),
      ]);
      expect(plan.skipped, isEmpty);
      final a = plan.steps.map((s) => s.actions).toList();
      expect((a[0].single as SetValueAction).text, 'Ana Ruiz');
      expect((a[1].single as SelectAction).elementId, '6');
      expect(plan.steps[1].answer.answer, 'A diario');
      expect([for (final t in a[2].cast<ToggleAction>()) (t.elementId, t.on)], [('7', true), ('9', true)]);
      expect((a[3].single as ToggleAction).on, isTrue);
      expect((a[4].single as ChooseAction).label, 'Mexico');
    });

    test('never fills sensitive fields, even if the model answers them', () {
      final all = FormFiller.idsFor(FormSnapshot.fromElements(fakeTree()).fields);
      final plan = FormFiller.plan(all, const [
        FieldAnswer(fieldId: 'f2', question: 'Password', answer: 'hunter2'),
        FieldAnswer(fieldId: 'f3', question: 'Card', answer: '4111 1111 1111 1111'),
      ]);
      expect(plan.steps, isEmpty);
      expect(plan.skipped.map((s) => s.reason), [SkipReason.sensitive, SkipReason.sensitive]);
    });

    test('an answer that is not an option is skipped, not guessed', () {
      final plan = FormFiller.plan(ids(), const [FieldAnswer(fieldId: 'f2', question: 'Frequency', answer: 'Hourly')]);
      expect(plan.steps, isEmpty);
      expect(plan.skipped.single.reason, SkipReason.noMatch);
    });

    test('falls back to click + type at the control when it has no patterns', () {
      final plan = FormFiller.plan(ids(withPatterns: false), const [
        FieldAnswer(fieldId: 'f1', question: 'Name', answer: 'Ana'),
        FieldAnswer(fieldId: 'f2', question: 'Frequency', answer: 'Nunca'),
      ]);
      final type = plan.steps[0].actions.single as ClickTypeAction;
      expect(type.point, const Rect.fromLTWH(100, 100, 300, 24).center);
      expect(type.text, 'Ana');
      final click = plan.steps[1].actions.single as ClickTypeAction;
      expect(click.point, const Rect.fromLTWH(110, 240, 80, 20).center);
      expect(click.text, isNull);
    });

    test('a "screen" answer maps vision coordinates to the display', () {
      const mapper = CoordinateMapper(
        imageWidth: 1300,
        imageHeight: 731,
        screen: Rect.fromLTWH(-2560, 0, 2560, 1440),
        scale: 1.5,
      );
      final plan = FormFiller.plan(const {}, const [
        FieldAnswer(fieldId: 'screen', question: 'Rate', answer: '5', point: Offset(650, 365.5), kind: 'choice'),
      ], toScreen: (p) => mapper.toScreen(p.dx, p.dy));
      final a = plan.steps.single.actions.single as ClickTypeAction;
      expect(a.point, const Offset(-1280, 720));
      expect(a.text, isNull);
    });
  });

  test('FormVerifier finds what did not stick', () {
    final i = FormFiller.idsFor(FormPager.pending(FormSnapshot.fromElements(fakeTree()), {}));
    final plan = FormFiller.plan(i, const [
      FieldAnswer(fieldId: 'f1', question: 'Name', answer: 'Ana Ruiz'),
      FieldAnswer(fieldId: 'f3', question: 'Colours', choices: ['Red']),
    ]);
    // Re-read: the name stuck, the checkbox didn't.
    final after = FormSnapshot.fromElements(fakeTree(nameValue: 'Ana Ruiz'));
    final failed = FormVerifier.failed(plan.steps, after);
    expect(failed.map((s) => s.question), ['Colours']);
    final fixed = FormSnapshot.fromElements(fakeTree(nameValue: 'Ana Ruiz', colorChecked: true));
    expect(FormVerifier.failed(plan.steps, fixed), isEmpty);
  });

  test('FormPager: answer, then next; submit waits; scroll, then done', () {
    final s = FormSnapshot.fromElements(fakeTree());
    expect(FormPager.decide(s, {}, scrolledWithoutNews: false), PageMove.answer);
    final attempted = {for (final f in s.fields) f.key};
    expect(FormPager.decide(s, attempted, scrolledWithoutNews: false), PageMove.next);

    final last = FormSnapshot.fromElements([
      UiElement.fromMap(el('1', 'edit', 'Comments', value: 'ok')),
      UiElement.fromMap(el('2', 'button', 'Enviar', bounds: [100, 600, 80, 30])),
    ]);
    expect(FormPager.decide(last, {}, scrolledWithoutNews: false), PageMove.submit);

    final bare = FormSnapshot.fromElements([UiElement.fromMap(el('1', 'edit', 'Comments', value: 'ok'))]);
    expect(FormPager.decide(bare, {}, scrolledWithoutNews: false), PageMove.scroll);
    expect(FormPager.decide(bare, {}, scrolledWithoutNews: true), PageMove.done);
  });

  test('QuestionnaireService: screenshot + fields in image pixels, JSON, low-effort thinking', () async {
    final llm = _FakeLlm('{"answers":[{"field_id":"f1","question":"Full name","answer":"Ana","confidence":0.8}]}');
    const mapper = CoordinateMapper(
      imageWidth: 1300,
      imageHeight: 650,
      screen: Rect.fromLTWH(0, 0, 2600, 1300),
      scale: 2,
    );
    final ids = FormFiller.idsFor(FormPager.pending(FormSnapshot.fromElements(fakeTree()), {}));
    final answers = await QuestionnaireService(llm).answer(
      screenshot: 'data:image/jpeg;base64,AAAA',
      ids: ids,
      mapper: mapper,
      settings: const AppSettings(formsInstructions: 'My name is Ana.', formsStyle: FormAnswerStyle.detailed),
      appLanguageName: 'English',
    );
    expect(answers.answers.single.answer, 'Ana');
    expect(llm.images, ['data:image/jpeg;base64,AAAA']);
    expect(llm.profile, DeepSeekTaskProfile.questionnaire);
    expect(llm.profile!.requestFields['thinking'], {'type': 'enabled', 'reasoning_effort': 'low'});
    expect(llm.json, isTrue);
    expect(llm.system, contains('Return only JSON'));
    expect(llm.user, contains('My name is Ana.'));
    expect(llm.user, contains('the language of the questionnaire'));
    expect(llm.user, contains('two to four sentences'));
    // Boxes are in screenshot pixels (half the physical size here).
    final fields = jsonDecode(llm.user!.split('Fields:\n').last) as List;
    expect((fields.first as Map)['box'], [50, 50, 150, 12]);
    // Options carry their letter and, where known, their box.
    final options = ((fields[1] as Map)['options'] as List).cast<Map<String, Object?>>();
    expect([for (final o in options) o['label']], ['Nunca', 'A veces', 'A diario']);
    expect([for (final o in options) o['letter']], ['A', 'B', 'C']);
    expect((fields[1] as Map)['question_type'], 'multiple_choice');
  });
}

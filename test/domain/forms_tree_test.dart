// Form filling through the accessibility tree, without the extension:
// reads recorded from Edge and Firefox on test/fixtures/forms (see
// test/integration/form_fixture_live_test.dart for the live run), the
// labels found for controls the page didn't label, sliders and spinners,
// the checks right after each fill, and the loop around them.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/domain/agent/coordinates.dart';
import 'package:sotto/domain/agent/safety.dart';
import 'package:sotto/domain/forms/form_filler.dart';
import 'package:sotto/domain/forms/form_model.dart';
import 'package:sotto/domain/forms/form_runner.dart';
import 'package:sotto/services/ai/questionnaire_service.dart';

List<UiElement> _recorded(String name) {
  final j = jsonDecode(File('test/fixtures/forms/reads/$name.json').readAsStringSync()) as Map<String, Object?>;
  return [for (final m in (j['elements']! as List).whereType<Map<Object?, Object?>>()) UiElement.fromMap(m)];
}

const _longPage = [
  ('What is your full name?', FieldRole.text),
  ('Which city do you live in?', FieldRole.text),
  ('Email address', FieldRole.text),
  ('What would you improve first?', FieldRole.text),
  ('How often do you use the app?', FieldRole.radio),
  ('Which features do you use? (select all that apply)', FieldRole.checkboxes),
  ('Your role', FieldRole.combo),
  ('Send me the newsletter', FieldRole.checkbox),
  ('Country', FieldRole.combo),
  ('How likely are you to recommend us? (1–10)', FieldRole.range),
  ('Overall satisfaction (1–5)', FieldRole.range),
  ('How many years have you been presenting?', FieldRole.range),
  ('Which language do you present in most?', FieldRole.text),
  ('Choose a password', FieldRole.text),
  ('Card number', FieldRole.text),
];

/// What the presenter's instructions say, by a word of the question.
const _answers = <String, String>{
  'full name': 'Ana Ruiz',
  'city': 'Santo Domingo',
  'email': 'ana@example.com',
  'improve': 'Faster exports',
  'how often': 'Weekly',
  'features': 'Teleprompter, Answers',
  'role': 'Designer',
  'newsletter': 'no',
  'country': 'Dominican Republic',
  'recommend': '9',
  'satisfaction': '4 out of 5',
  'presenting': '6',
  'language': 'Spanish',
  'name': 'Ana Ruiz',
  'session': 'Afternoon',
  'dietary': 'Vegetarian',
  'anything we should know': 'Arriving late',
};

/// The model: answers the fields it is given from [_answers], by label.
class _Vision implements FormVision {
  final asked = <List<String>>[];

  @override
  Future<FormReply> answer(ScreenFrame frame, Map<String, FormField> ids) async {
    asked.add([for (final f in ids.values) f.label]);
    return FormReply([
      for (final MapEntry(key: id, value: f) in ids.entries)
        if (_answers.entries.where((e) => f.label.toLowerCase().contains(e.key)).firstOrNull case final hit?)
          FieldAnswer(
            fieldId: id,
            question: f.label,
            answer: f.role == FieldRole.checkboxes ? '' : hit.value,
            choices: f.role == FieldRole.checkboxes ? hit.value.split(', ') : const [],
          ),
    ]);
  }

  @override
  Future<Offset?> locateOption(ScreenFrame frame, String label) async => null;

  @override
  Future<Map<int, String>> readValues(ScreenFrame frame, List<VisualCheck> checks) async => const {};
}

/// A browser page as its accessibility tree shows it, replayed from a
/// recorded read: actions change what the next read and [state] report.
class _Page implements FormDriver {
  _Page(List<UiElement> recorded, {this.ignoresRangeValue = const {}, this.ignoresListPick = const {}})
    : _elements = {for (final e in recorded) e.id: e} {
    for (final e in recorded) {
      values[e.id] = e.value;
      checked[e.id] = e.checked;
      ranges[e.id] = e.range?.value;
    }
  }

  final Map<String, UiElement> _elements;

  /// Takes RangeValue and ignores it, like a custom ARIA slider.
  final Set<String> ignoresRangeValue;

  /// Ignores a pick from its own list, like a Firefox select.
  final Set<String> ignoresListPick;

  final values = <String, String?>{};
  final checked = <String, bool?>{};
  final ranges = <String, double?>{};
  final touched = <String>{};
  final clicks = <Offset>[];
  final keys = <String>[];
  var reads = 0;
  var scrolledWith = <String?>[];

  /// Each read hands out new ids (as a browser may after a scroll).
  bool churnIds = false;
  String? focus;

  static const screen = Rect.fromLTWH(0, 0, 1920, 1080);

  String _real(String id) => id.split('~').first;

  @override
  Future<ScreenFrame> capture() async => ScreenFrame(
    'data:image/jpeg;base64,',
    const CoordinateMapper(imageWidth: 1280, imageHeight: 720, screen: screen, scale: 1),
  );

  @override
  Future<FormSnapshot> read() async {
    reads++;
    String id(String i) => churnIds && reads > 1 ? '$i~$reads' : i;
    return FormSnapshot.fromElements([
      for (final e in _elements.values)
        UiElement(
          id: id(e.id),
          type: e.type,
          name: e.name,
          value: values[e.id],
          bounds: e.bounds,
          password: e.password,
          enabled: e.enabled,
          offscreen: e.offscreen,
          readOnly: e.readOnly,
          checked: checked[e.id],
          parent: e.parent == null ? null : id(e.parent!),
          options: e.options,
          patterns: e.patterns,
          multiline: e.multiline,
          labeledBy: e.labeledBy,
          help: e.help,
          range: e.range == null
              ? null
              : RangeSpec(min: e.range!.min, max: e.range!.max, value: ranges[e.id]!, step: e.range!.step),
        ),
    ]);
  }

  bool _touch(String id) {
    final real = _real(id);
    touched.add(real);
    return _elements.containsKey(real);
  }

  @override
  Future<bool> setValue(String id, String text) async {
    if (!_touch(id)) return false;
    values[_real(id)] = text;
    return true;
  }

  @override
  Future<bool> select(String id) async {
    if (!_touch(id)) return false;
    checked[_real(id)] = true;
    return true;
  }

  @override
  Future<bool> toggle(String id, bool on) async {
    if (!_touch(id)) return false;
    checked[_real(id)] = on;
    return true;
  }

  @override
  Future<bool> choose(String id, String label) async {
    if (!_touch(id)) return false;
    // The native side reads the combo back: an ignored pick is a failure.
    if (ignoresListPick.contains(_real(id))) return false;
    values[_real(id)] = label;
    return true;
  }

  @override
  Future<bool> invoke(String id) async => _touch(id);

  @override
  Future<bool> setRange(String id, double value) async {
    if (!_touch(id)) return false;
    if (!ignoresRangeValue.contains(_real(id))) ranges[_real(id)] = value;
    return true;
  }

  @override
  Future<bool> focusElement(String id) async {
    if (!_touch(id)) return false;
    focus = _real(id);
    return true;
  }

  @override
  Future<ElementState?> state(String id) async {
    final real = _real(id);
    if (!_elements.containsKey(real)) return null;
    return ElementState(value: values[real] ?? '', checked: checked[real], rangeValue: ranges[real]);
  }

  @override
  bool get canInput => true;

  @override
  Future<void> click(Offset p) async {
    expect(screen.contains(p), isTrue, reason: 'a click off the screen: $p');
    clicks.add(p);
  }

  @override
  Future<void> selectAll() async {}

  @override
  Future<void> typeKeys(String text, Duration interval) async {
    final f = focus;
    if (f == null) return;
    final e = _elements[f]!;
    // A focused select jumps to the option whose name is typed.
    if (e.type == 'combo') values[f] = e.options.firstWhere((o) => o.startsWith(text), orElse: () => text);
  }

  @override
  Future<void> pressKey(String key) async {
    keys.add(key);
    final f = focus;
    final r = f == null ? null : _elements[f]!.range;
    if (f == null || r == null) return;
    final step = r.keyStep * (key == 'right' ? 1 : (key == 'left' ? -1 : 0));
    ranges[f] = (ranges[f]! + step).clamp(r.min, r.max).toDouble();
  }

  @override
  Future<void> scroll(Offset physical, int notches) async {}

  @override
  Future<void> scrollDown({String? anchor, required Offset fallback}) async {
    scrolledWith.add(anchor);
    expect(screen.contains(fallback), isTrue);
  }

  @override
  Future<void> drag(Offset from, Offset to) async {}

  @override
  Future<bool?> canScrollDown({String? anchor}) async => false;

  @override
  Future<FocusInfo?> focused() async => null;

  @override
  Future<void> pause(Duration d) async {}
}

class _Host implements FormRunHost, FormRunTexts {
  final progress_ = <(int, ItemStatus, String?)>[];

  @override
  bool get cancelled => false;
  @override
  void phase(FormPhase phase, {int? page, String? label}) {}
  @override
  void planned(FillPlan plan) {}
  @override
  void progress(int step, ItemStatus status, {String? note}) => progress_.add((step, status, note));
  @override
  Future<bool> confirm(FormPhase phase, {String? label}) async => false;
  @override
  FillPlan edited(FillPlan plan, Map<String, FormField> ids, Offset? Function(Offset) toScreen) => plan;
  @override
  String couldNotFill() => 'could not fill';
  @override
  String blocked(SafetyReason reason) => 'blocked';
  @override
  String skipped(SkipReason reason) => 'skipped';
}

FormRunner _runner(_Page page, _Vision vision) =>
    FormRunner(driver: page, vision: vision, host: _Host(), texts: _Host(), auto: true);

void main() {
  group('what Edge and Firefox expose', () {
    for (final browser in ['edge', 'firefox']) {
      test('$browser, the long page: every question, with the label a reader sees', () {
        final s = FormSnapshot.fromElements(_recorded('long_page_$browser'));
        expect([for (final f in s.fields) (f.label, f.role)], _longPage);

        FormField field(String label) => s.fields.firstWhere((f) => f.label == label);
        // Password and card number: flagged, never asked.
        expect(s.fields.where((f) => f.sensitive).map((f) => f.label), ['Choose a password', 'Card number']);
        // Help text goes with its field.
        expect(field('Email address').help, 'We only use it to send you the results.');
        // A select's "Choose…" and a custom combo's "Select a country" are prompts.
        expect(field('Your role').empty, isTrue);
        expect(field('Country').empty, isTrue);
        // Options grouped under their question, not one question per option.
        expect(field('How often do you use the app?').options.map((o) => o.label), [
          'Daily',
          'Weekly',
          'Monthly',
          'Rarely',
        ]);
        expect(field('Which features do you use? (select all that apply)').options, hasLength(4));
        // Sliders and the spinner, with their ranges.
        expect(field('How likely are you to recommend us? (1–10)').range?.max, 10);
        expect(field('Overall satisfaction (1–5)').range?.max, 5);
        expect(field('How many years have you been presenting?').range?.max, 60);
        // Everything is reachable through the tree; the page reaches well
        // below the screen.
        expect(s.fields.every((f) => f.access == FieldAccess.nativeAx), isTrue);
        expect(s.fields.where((f) => f.offscreen), isNotEmpty);
        expect(s.fields.map((f) => f.signature).toSet(), hasLength(s.fields.length));
        // The Submit button is found; nothing of the browser's own is a field.
        expect(s.submit?.label, 'Submit');
      });

      test('$browser, the scroll container: unlabelled radios take the question above them', () {
        final s = FormSnapshot.fromElements(_recorded('scroll_container_$browser'));
        expect(
          [for (final f in s.fields) f.label],
          ['Name', 'Which session will you attend?', 'Dietary needs', 'Anything we should know?'],
        );
        expect(s.fields[1].options.map((o) => o.label), ['Morning', 'Afternoon']);
      });
    }
  });

  group('labels from the page', () {
    UiElement text(String id, String name, Rect r) => UiElement(id: id, type: 'text', name: name, bounds: r);
    UiElement radio(String id, String name, double top) => UiElement(
      id: id,
      type: 'radio',
      name: name,
      bounds: Rect.fromLTWH(20, top, 16, 16),
      parent: 'form',
      patterns: const {'select'},
      checked: false,
    );

    test('two radio sets in one form, each under its own question, stay two questions', () {
      final s = FormSnapshot.fromElements([
        const UiElement(id: 'form', type: 'group', bounds: Rect.fromLTWH(0, 0, 800, 600)),
        text('q1', 'Morning or afternoon?', const Rect.fromLTWH(20, 10, 300, 20)),
        radio('a', 'Morning', 40),
        radio('b', 'Afternoon', 70),
        text('q2', 'Will you bring a guest?', const Rect.fromLTWH(20, 110, 300, 20)),
        radio('c', 'Yes', 140),
        radio('d', 'No', 170),
      ]);
      expect(
        [for (final f in s.fields) (f.label, f.options.length)],
        [('Morning or afternoon?', 2), ('Will you bring a guest?', 2)],
      );
    });

    test('a label beside a field on the same line; text inside a control labels nothing', () {
      final s = FormSnapshot.fromElements([
        text('l', 'Phone', const Rect.fromLTWH(20, 100, 60, 20)),
        const UiElement(id: 'e', type: 'edit', bounds: Rect.fromLTWH(100, 95, 300, 30), patterns: {'value'}, value: ''),
        text('inside', 'Type here', const Rect.fromLTWH(110, 100, 80, 20)),
      ]);
      expect(s.fields.single.label, 'Phone');
    });

    test('combos: a prompt is not an answer; a real choice is', () {
      for (final (value, empty) in [
        ('Choose…', true),
        ('-- Elige --', true),
        ('Seleccione una opción', true),
        ('Select a country ▾', true),
        ('Designer', false),
      ]) {
        final s = FormSnapshot.fromElements([
          UiElement(
            id: 'c',
            type: 'combo',
            name: 'Role',
            value: value,
            bounds: const Rect.fromLTWH(0, 0, 200, 30),
            options: const ['Choose…', 'Designer'],
            patterns: const {'expand'},
          ),
        ]);
        expect(s.fields.single.empty, empty, reason: value);
      }
    });
  });

  group('sliders and spinners', () {
    test('a number in the answer, on a step, within the range', () {
      expect(FormFiller.numberIn('9/10'), 9);
      expect(FormFiller.numberIn('about 4,5 hours'), 4.5);
      expect(FormFiller.numberIn('★★★★'), 4);
      expect(FormFiller.numberIn('mucho'), isNull);
      const r = RangeSpec(min: 1, max: 10, value: 5, step: 1);
      expect(r.snap(9.4), 9);
      expect(r.snap(42), 10);
      const half = RangeSpec(min: 0, max: 5, value: 0, step: 0.5);
      expect(half.snap(3.3), 3.5);
    });

    test('a slider with no accessible action is clicked where its value sits', () {
      const a = SetRangeAction('s', 7.5, RangeSpec(min: 5, max: 10, value: 5), Rect.fromLTWH(100, 50, 200, 20));
      expect(a.point, const Offset(200, 60));
    });
  });

  group('reading a field back right after filling it', () {
    FillStep step(FormField f, String answer, List<String> expected) => FillStep(
      field: f,
      answer: FieldAnswer(fieldId: 'f1', question: f.label, answer: answer),
      actions: const [],
      expected: expected,
    );

    test('text, choices, ranges', () {
      const text = FormField(key: 't', role: FieldRole.text, label: 'Name', bounds: Rect.zero, elementId: 't');
      expect(FormVerifier.holds(step(text, 'Ana', ['Ana']), {'t': const ElementState(value: 'Ana')}), isTrue);
      expect(FormVerifier.holds(step(text, 'Ana', ['Ana']), {'t': const ElementState(value: '')}), isFalse);
      expect(FormVerifier.holds(step(text, 'Ana', ['Ana']), const {}), isNull);

      const radio = FormField(
        key: 'g',
        role: FieldRole.radio,
        label: 'Often',
        bounds: Rect.zero,
        options: [
          FormOption('Daily', elementId: 'a'),
          FormOption('Weekly', elementId: 'b'),
        ],
      );
      final weekly = step(radio, 'Weekly', ['Weekly']);
      expect(
        FormVerifier.holds(weekly, {'a': const ElementState(checked: false), 'b': const ElementState(checked: true)}),
        isTrue,
      );
      expect(
        FormVerifier.holds(weekly, {'a': const ElementState(checked: true), 'b': const ElementState(checked: false)}),
        isFalse,
      );

      const slider = FormField(
        key: 's',
        role: FieldRole.range,
        label: 'Satisfaction',
        bounds: Rect.zero,
        elementId: 's',
        range: RangeSpec(min: 1, max: 5, value: 3),
      );
      expect(FormVerifier.holds(step(slider, '4', ['4']), {'s': const ElementState(rangeValue: 4)}), isTrue);
      expect(FormVerifier.holds(step(slider, '4', ['4']), {'s': const ElementState(rangeValue: 3)}), isFalse);
    });
  });

  group('what the model is sent', () {
    test('a field off the screenshot has no box; help and ranges go along', () {
      final s = FormSnapshot.fromElements(_recorded('long_page_edge'));
      const mapper = CoordinateMapper(imageWidth: 1280, imageHeight: 720, screen: _Page.screen, scale: 1);
      final ids = FormFiller.idsFor(s.fields.where((f) => !f.sensitive).toList());
      final sent = jsonDecode(QuestionnaireService.fieldsJson(ids, mapper)) as List;
      Map<String, Object?> byLabel(String l) => sent.cast<Map<String, Object?>>().firstWhere((m) => m['label'] == l);
      expect(byLabel('What is your full name?')['box'], isNotNull);
      expect(byLabel('Which language do you present in most?')['offscreen'], isTrue);
      expect(byLabel('Which language do you present in most?').containsKey('box'), isFalse);
      expect(byLabel('Email address')['help'], 'We only use it to send you the results.');
      expect(byLabel('How likely are you to recommend us? (1–10)')['range'], {'min': '1', 'max': '10', 'step': '1'});
      final prompt = QuestionnaireService.user(
        ids: ids,
        mapper: mapper,
        settings: const AppSettings(),
        appLanguageName: 'English',
      );
      expect(prompt, isNot(contains('password')));
    });
  });

  group('a fill through the tree', () {
    test('the whole long page in one model call — every question through the tree', () async {
      final page = _Page(_recorded('long_page_edge'));
      final vision = _Vision();
      final runner = _runner(page, vision);
      final result = await runner.run();

      expect(runner.modelCalls, 1);
      expect(vision.asked.single, hasLength(13));
      expect(
        {for (final f in result.fields) f.question: f.status},
        {for (final (label, _) in _longPage.take(13)) label: ItemStatus.filled},
      );
      expect(result.fields.where((f) => f.visual), isEmpty);
      expect(page.clicks, isEmpty);
      expect(page.values.values, contains('ana@example.com'));
      // Password and card number: never read into a question, never touched.
      final sensitive = page._elements.values.where((e) => e.name == 'Choose a password' || e.name == 'Card number');
      expect(sensitive.map((e) => e.id).where(page.touched.contains), isEmpty);
      // Submit is the presenter's.
      final submit = page._elements.values.firstWhere((e) => e.name == 'Submit');
      expect(page.touched, isNot(contains(submit.id)));
    });

    test('a custom slider that ignores RangeValue moves with the arrow keys', () async {
      final els = _recorded('long_page_edge');
      final slider = els.firstWhere((e) => e.type == 'slider' && e.name == 'Overall satisfaction (1–5)');
      final page = _Page(els, ignoresRangeValue: {slider.id});
      final result = await _runner(page, _Vision()).run();
      expect(page.ranges[slider.id], 4);
      expect(page.keys, ['right']);
      expect(result.fields.firstWhere((f) => f.question.startsWith('Overall')).status, ItemStatus.filled);
    });

    test('a select that ignores picks from its list takes the option typed into it', () async {
      final els = _recorded('long_page_firefox');
      final role = els.firstWhere((e) => e.type == 'combo' && e.name == 'Your role');
      final page = _Page(els, ignoresListPick: {role.id});
      final vision = _Vision();
      final runner = _runner(page, vision);
      final result = await runner.run();
      expect(page.values[role.id], 'Designer');
      expect(result.fields.firstWhere((f) => f.question == 'Your role').status, ItemStatus.filled);
      expect(runner.modelCalls, 1, reason: 'no screenshot lookup for the option');
    });

    test('a value that never sticks is tried once more, then left for the presenter', () async {
      final els = _recorded('long_page_edge');
      final page = _Page(els);
      final city = FormSnapshot.fromElements(els).fields.firstWhere((f) => f.label.startsWith('Which city'));
      // The page undoes whatever is put in this box.
      final stubborn = _Stubborn(page, city.elementId!);
      final result = await FormRunner(
        driver: stubborn,
        vision: _Vision(),
        host: _Host(),
        texts: _Host(),
        auto: true,
      ).run();
      final f = result.fields.firstWhere((f) => f.question.startsWith('Which city'));
      expect(f.status, ItemStatus.failed);
      expect(f.note, 'could not fill');
      expect(stubborn.attempts, 2);
      // It was offscreen-safe: no click anywhere.
      expect(page.clicks, isEmpty);
    });

    test('a question is asked once, even when the browser renames its elements', () async {
      final page = _Page(_recorded('long_page_edge'))..churnIds = true;
      final vision = _Vision();
      final runner = _runner(page, vision);
      await runner.run();
      expect(vision.asked, hasLength(1));
    });

    test('nothing left and no button: scrolls the form, not the screen, and stops when nothing is new', () async {
      final els = _recorded('scroll_container_edge');
      final page = _Page(els);
      final vision = _Vision();
      final runner = FormRunner(driver: _Scrolls(page), vision: vision, host: _Host(), texts: _Host(), auto: true);
      final result = await runner.run();
      expect(result.fields.where((f) => f.status == ItemStatus.filled), hasLength(4));
      expect(page.scrolledWith, hasLength(1));
      expect(page.scrolledWith.single, isNotNull, reason: 'scrolled through a field of the form');
      // The tree had every question: no second look at the screenshot.
      expect(runner.modelCalls, 1);
    });

    test('a field only the screenshot could fill is asked about, never clicked off screen', () async {
      final s = FormSnapshot.fromElements([
        const UiElement(
          id: 'on',
          type: 'edit',
          name: 'Full name',
          bounds: Rect.fromLTWH(100, 100, 300, 30),
          patterns: {'focus'},
          value: '',
        ),
        const UiElement(
          id: 'below',
          type: 'edit',
          name: 'Which language do you present in most?',
          bounds: Rect.fromLTWH(100, 2400, 300, 30),
          patterns: {'focus'},
          value: '',
          offscreen: true,
        ),
      ]);
      final page = _Fixed(s);
      final vision = _Vision();
      final result = await FormRunner(driver: page, vision: vision, host: _Host(), texts: _Host(), auto: true).run();
      // Asked once, from its label, with the one on screen.
      expect(vision.asked.single, ['Full name', 'Which language do you present in most?']);
      expect(page.clicks.every(_Page.screen.contains), isTrue);
      // It never came on screen: left to the presenter, with its answer.
      final lang = result.fields.singleWhere((f) => f.question.startsWith('Which language'));
      expect((lang.status, lang.answer), (ItemStatus.skipped, 'Spanish'));
    });
  });
}

/// [_Page], with one text box that undoes whatever is put in it.
class _Stubborn extends _Delegate {
  _Stubborn(super.inner, this.id);
  final String id;
  var attempts = 0;

  @override
  Future<bool> setValue(String elementId, String text) async {
    if (elementId.split('~').first != id) return inner.setValue(elementId, text);
    attempts++;
    return true;
  }
}

/// [_Page] that can scroll once more.
class _Scrolls extends _Delegate {
  _Scrolls(super.inner);
  var asked = 0;

  @override
  Future<bool?> canScrollDown({String? anchor}) async => asked++ == 0;
}

/// A page that never changes, for checking what is asked and clicked.
class _Fixed extends _Delegate {
  _Fixed(this.snapshot) : super(_Page(const []));
  final FormSnapshot snapshot;
  List<Offset> get clicks => inner.clicks;

  @override
  Future<FormSnapshot> read() async => snapshot;
}

class _Delegate implements FormDriver {
  _Delegate(this.inner);
  final _Page inner;

  @override
  Future<ScreenFrame> capture() => inner.capture();
  @override
  Future<FormSnapshot> read() => inner.read();
  @override
  Future<bool> setValue(String id, String text) => inner.setValue(id, text);
  @override
  Future<bool> select(String id) => inner.select(id);
  @override
  Future<bool> toggle(String id, bool on) => inner.toggle(id, on);
  @override
  Future<bool> choose(String id, String label) => inner.choose(id, label);
  @override
  Future<bool> invoke(String id) => inner.invoke(id);
  @override
  Future<bool> setRange(String id, double value) => inner.setRange(id, value);
  @override
  Future<bool> focusElement(String id) => inner.focusElement(id);
  @override
  Future<ElementState?> state(String id) => inner.state(id);
  @override
  bool get canInput => inner.canInput;
  @override
  Future<void> click(Offset p) => inner.click(p);
  @override
  Future<void> selectAll() => inner.selectAll();
  @override
  Future<void> typeKeys(String text, Duration interval) => inner.typeKeys(text, interval);
  @override
  Future<void> pressKey(String key) => inner.pressKey(key);
  @override
  Future<void> scroll(Offset p, int notches) => inner.scroll(p, notches);
  @override
  Future<void> scrollDown({String? anchor, required Offset fallback}) =>
      inner.scrollDown(anchor: anchor, fallback: fallback);
  @override
  Future<void> drag(Offset from, Offset to) => inner.drag(from, to);
  @override
  Future<bool?> canScrollDown({String? anchor}) => inner.canScrollDown(anchor: anchor);
  @override
  Future<FocusInfo?> focused() => inner.focused();
  @override
  Future<void> pause(Duration d) => inner.pause(d);
}

// Questionnaire filling against a fake browser window that exposes NO
// accessibility content — like Chrome, Edge or Firefox on macOS often don't —
// only what a screenshot shows. Every field goes through the visual path:
// click where the screenshot shows it, type key by key, open drop-downs and
// click the option, verify on a fresh screenshot, retry slower, give up
// visibly. The window sits on a second display left of the primary one, at
// 2× scale, so every click also exercises the screenshot → screen mapping.
import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/domain/agent/coordinates.dart';
import 'package:sotto/domain/agent/safety.dart';
import 'package:sotto/domain/forms/form_filler.dart';
import 'package:sotto/domain/forms/form_model.dart';
import 'package:sotto/domain/forms/form_runner.dart';

// ───────────────────────────── The fake window ─────────────────────────────

enum Kind { text, textarea, select, radio, checkbox, button, password }

class Control {
  Control(this.kind, this.question, this.rect, {this.options = const [], this.flaky = false, this.locked = false});

  final Kind kind;

  /// The question (text-like fields, groups) or the button label.
  final String question;

  /// Physical screen pixels. For radios / checkboxes: the whole group.
  final Rect rect;
  final List<String> options;

  /// Drops keys typed faster than 30 ms apart (some web inputs do).
  final bool flaky;

  /// Ignores typing entirely.
  final bool locked;

  String value = '';
  final checked = <String>{};
  var selectedAll = false;

  static const rowHeight = 60.0;

  Rect optionRect(int i) => Rect.fromLTWH(rect.left, rect.top + i * rowHeight, rect.width, rowHeight - 10);

  /// A native select's open list, below it.
  Rect listRect(int i) => Rect.fromLTWH(rect.left, rect.bottom + i * 50, rect.width, 50);
}

class FakeBrowser implements FormDriver {
  FakeBrowser(this.pages);

  static const screen = Rect.fromLTWH(-2560, 0, 2560, 1440);
  static const mapper = CoordinateMapper(imageWidth: 1280, imageHeight: 720, screen: screen, scale: 2);

  final List<List<Control>> pages;
  var page = 0;
  Control? focus;
  Control? openSelect;
  var submitted = false;

  final clicks = <Offset>[];
  final typed = <(String, Duration)>[];
  final keys = <String>[];
  var reads = 0;
  var captures = 0;

  List<Control> get controls => pages[page];
  Control byQuestion(String q, {int? onPage}) => pages[onPage ?? page].firstWhere((c) => c.question == q);

  @override
  Future<ScreenFrame> capture() async {
    captures++;
    return const ScreenFrame('data:image/jpeg;base64,FAKE', mapper);
  }

  /// Nothing: this browser exposes no accessibility tree.
  @override
  Future<FormSnapshot> read() async {
    reads++;
    return const FormSnapshot(fields: []);
  }

  @override
  Future<bool> setValue(String elementId, String text) async => false;
  @override
  Future<bool> select(String elementId) async => false;
  @override
  Future<bool> toggle(String elementId, bool on) async => false;
  @override
  Future<bool> choose(String elementId, String label) async => false;
  @override
  Future<bool> invoke(String elementId) async => false;

  @override
  bool get canInput => true;

  @override
  Future<void> click(Offset p) async {
    clicks.add(p);
    final open = openSelect;
    if (open != null) {
      openSelect = null;
      for (var i = 0; i < open.options.length; i++) {
        if (open.listRect(i).contains(p)) open.value = open.options[i];
      }
      return;
    }
    for (final c in controls) {
      if (!c.rect.contains(p)) continue;
      switch (c.kind) {
        case Kind.text || Kind.textarea || Kind.password:
          focus = c;
        case Kind.select:
          focus = c;
          openSelect = c;
        case Kind.radio:
          for (var i = 0; i < c.options.length; i++) {
            if (c.optionRect(i).contains(p)) c.value = c.options[i];
          }
        case Kind.checkbox:
          for (var i = 0; i < c.options.length; i++) {
            if (!c.optionRect(i).contains(p)) continue;
            final o = c.options[i];
            c.checked.contains(o) ? c.checked.remove(o) : c.checked.add(o);
          }
        case Kind.button:
          if (c.question == 'Next') {
            page++;
          } else {
            submitted = true;
          }
      }
    }
  }

  @override
  Future<void> selectAll() async => focus?.selectedAll = true;

  final _typeAhead = StringBuffer();

  @override
  Future<void> typeKeys(String text, Duration interval) async {
    typed.add((text, interval));
    if (openSelect != null) {
      _typeAhead.write(text);
      return;
    }
    final f = focus;
    if (f == null || f.locked || f.kind == Kind.select) return;
    if (f.selectedAll) f.value = '';
    f.selectedAll = false;
    final dropping = f.flaky && interval < const Duration(milliseconds: 30);
    final runes = text.runes.toList();
    f.value += String.fromCharCodes([
      for (var i = 0; i < runes.length; i++)
        if (!dropping || i.isEven) runes[i],
    ]);
  }

  @override
  Future<void> pressKey(String key) async {
    keys.add(key);
    final open = openSelect;
    if (key == 'enter' && open != null) {
      final want = _typeAhead.toString().toLowerCase();
      for (final o in open.options) {
        if (o.toLowerCase().startsWith(want)) open.value = o;
      }
      openSelect = null;
      _typeAhead.clear();
    }
  }

  @override
  Future<void> scroll(Offset physical, int notches) async {}

  @override
  Future<FocusInfo?> focused() async => FocusInfo(isPassword: focus?.kind == Kind.password);

  final paused = <Duration>[];

  @override
  Future<void> pause(Duration d) async => paused.add(d);

  /// Physical → screenshot pixels.
  static Offset image(Offset physical) => Offset((physical.dx - screen.left) / 2, (physical.dy - screen.top) / 2);

  static List<num> box(Rect r) => [(r.left - screen.left) / 2, (r.top - screen.top) / 2, r.width / 2, r.height / 2];
}

/// The model, looking at the fake window: answers what isn't answered yet,
/// with boxes in screenshot pixels, and reads values back.
class FakeVision implements FormVision {
  FakeVision(this.browser, this.answers, {this.canLocate = true});

  final FakeBrowser browser;

  /// Question → answer (checkboxes: "Red, Blue").
  final Map<String, String> answers;
  final bool canLocate;
  var calls = 0;
  var locates = 0;
  var reads = 0;

  @override
  Future<FormReply> answer(ScreenFrame frame, Map<String, FormField> ids) async {
    calls++;
    expect(ids, isEmpty, reason: 'no accessibility tree: nothing but the screenshot');
    final out = <FieldAnswer>[];
    NavTarget? next, submit;
    for (final c in browser.controls) {
      final a = answers[c.question];
      switch (c.kind) {
        case Kind.button:
          final nav = NavTarget(c.question, FakeBrowser.image(c.rect.center));
          c.question == 'Next' ? next = nav : submit = nav;
        case Kind.radio when a != null && c.value != a:
          final i = c.options.indexOf(a);
          out.add(_screen(c.question, a, 'radio', c.optionRect(i)));
        case Kind.checkbox when a != null:
          for (final label in a.split(', ')) {
            if (c.checked.contains(label)) continue;
            out.add(_screen(c.question, label, 'checkbox', c.optionRect(c.options.indexOf(label))));
          }
        case Kind.text || Kind.textarea || Kind.select || Kind.password when a != null && c.value != a:
          final kind = switch (c.kind) {
            Kind.textarea => 'textarea',
            Kind.select => 'dropdown',
            _ => 'text',
          };
          out.add(_screen(c.question, a, kind, c.rect));
        default:
          break;
      }
    }
    return FormReply(out, next: next, submit: submit);
  }

  FieldAnswer _screen(String q, String a, String kind, Rect r) {
    final b = FakeBrowser.box(r);
    return FieldAnswer.parseAll(
      '{"answers":[{"field_id":"screen","question":"${q.replaceAll('"', '')}${kind == 'checkbox' ? ' · $a' : ''}",'
      '"kind":"$kind","answer":${_json(a)},"box":[${b.join(',')}]}]}',
    ).single;
  }

  static String _json(String s) => '"${s.replaceAll('\n', r'\n')}"';

  @override
  Future<Offset?> locateOption(ScreenFrame frame, String label) async {
    locates++;
    final open = browser.openSelect;
    if (!canLocate || open == null) return null;
    final i = open.options.indexOf(label);
    return i < 0 ? null : FakeBrowser.image(open.listRect(i).center);
  }

  @override
  Future<Map<int, String>> readValues(ScreenFrame frame, List<VisualCheck> checks) async {
    reads++;
    final out = <int, String>{};
    for (final check in checks) {
      final p = FakeBrowser.mapper.toScreen(check.point.dx, check.point.dy)!;
      for (final c in browser.controls) {
        if (!c.rect.contains(p)) continue;
        out[check.id] = switch (c.kind) {
          Kind.radio => () {
            final i = [for (var i = 0; i < c.options.length; i++) i].firstWhere((i) => c.optionRect(i).contains(p));
            return c.value == c.options[i] ? 'checked' : 'unchecked';
          }(),
          Kind.checkbox => () {
            final i = [for (var i = 0; i < c.options.length; i++) i].firstWhere((i) => c.optionRect(i).contains(p));
            return c.checked.contains(c.options[i]) ? 'checked' : 'unchecked';
          }(),
          _ => c.value,
        };
      }
    }
    return out;
  }
}

class FakeHost implements FormRunHost {
  FakeHost({this.confirmSubmit = true, this.stopAfterSteps});

  final bool confirmSubmit;
  final int? stopAfterSteps;
  final phases = <FormPhase>[];
  final confirmed = <FormPhase>[];
  final statuses = <String, (ItemStatus, String?)>{};
  var plans = <FillPlan>[];
  var _filling = 0;
  var clicksAtSubmitConfirm = -1;
  FakeBrowser? browser;

  @override
  bool get cancelled => stopAfterSteps != null && _filling > stopAfterSteps!;

  @override
  void phase(FormPhase phase, {int? page, String? label}) => phases.add(phase);

  @override
  void planned(FillPlan plan) => plans = [...plans, plan];

  @override
  void progress(int step, ItemStatus status, {String? note}) {
    final q = plans.last.steps[step].question;
    if (status == ItemStatus.filling) _filling++;
    statuses[q] = (status, note);
  }

  @override
  Future<bool> confirm(FormPhase phase, {String? label}) async {
    confirmed.add(phase);
    if (phase == FormPhase.confirmSubmit) {
      clicksAtSubmitConfirm = browser?.clicks.length ?? -1;
      expect(browser?.submitted, isFalse, reason: 'nothing is submitted before Enter');
      return confirmSubmit;
    }
    return true;
  }

  @override
  FillPlan edited(FillPlan plan, Map<String, FormField> ids, Offset? Function(Offset) toScreen) => plan;
}

class _Texts implements FormRunTexts {
  @override
  String couldNotFill() => 'could not fill';
  @override
  String blocked(SafetyReason reason) => 'blocked: ${reason.name}';
  @override
  String skipped(SkipReason reason) => 'skipped: ${reason.name}';
}

// ───────────────────────────── The form ─────────────────────────────

Rect _row(double y, {double h = 60}) => Rect.fromLTWH(-2400, y, 800, h);

List<List<Control>> _twoPageForm() => [
  [
    Control(Kind.text, 'Full name', _row(200)),
    Control(Kind.textarea, 'Tell us about yourself', _row(300, h: 200)),
    Control(Kind.select, 'Country', _row(560), options: ['Spain', 'Mexico', 'Chile']),
    Control(Kind.button, 'Next', Rect.fromLTWH(-2400, 1300, 200, 70)),
  ],
  [
    Control(Kind.radio, 'How often do you use it?', _row(100, h: 180), options: ['Never', 'Sometimes', 'Daily']),
    Control(Kind.checkbox, 'Favourite colours', _row(320, h: 180), options: ['Red', 'Green', 'Blue']),
    Control(Kind.text, 'Nickname', _row(540), flaky: true),
    Control(Kind.text, 'Member number', _row(640), locked: true),
    Control(Kind.button, 'Send', Rect.fromLTWH(-2400, 1300, 200, 70)),
  ],
];

const _answers = {
  'Full name': 'Ana Ruiz',
  'Tell us about yourself': 'Product manager.\nI love maps.',
  'Country': 'Mexico',
  'How often do you use it?': 'Daily',
  'Favourite colours': 'Red, Blue',
  'Nickname': 'Anita',
  'Member number': 'A-1024',
};

({FakeBrowser browser, FakeVision vision, FakeHost host, FormRunner runner}) _setup({
  List<List<Control>>? pages,
  Map<String, String> answers = _answers,
  bool canLocate = true,
  bool confirmSubmit = true,
  int? stopAfterSteps,
}) {
  final browser = FakeBrowser(pages ?? _twoPageForm());
  final vision = FakeVision(browser, answers, canLocate: canLocate);
  final host = FakeHost(confirmSubmit: confirmSubmit, stopAfterSteps: stopAfterSteps)..browser = browser;
  final runner = FormRunner(driver: browser, vision: vision, host: host, texts: _Texts());
  return (browser: browser, vision: vision, host: host, runner: runner);
}

void main() {
  test('a two-page form with no accessibility content is filled visually, then waits for Enter to submit', () async {
    final s = _setup();
    final result = await s.runner.run();
    final b = s.browser;

    // Page 1: single-line and multi-line text, a native select.
    expect(b.byQuestion('Full name', onPage: 0).value, 'Ana Ruiz');
    expect(b.byQuestion('Tell us about yourself', onPage: 0).value, 'Product manager.\nI love maps.');
    expect(b.byQuestion('Country', onPage: 0).value, 'Mexico');
    // Page 2: a radio group, a checkbox group, a flaky input, a dead one.
    expect(b.byQuestion('How often do you use it?', onPage: 1).value, 'Daily');
    expect(b.byQuestion('Favourite colours', onPage: 1).checked, {'Red', 'Blue'});
    expect(b.byQuestion('Nickname', onPage: 1).value, 'Anita');
    expect(b.byQuestion('Member number', onPage: 1).value, '');

    // Next was pressed on its own; Submit only after Enter.
    expect(result.outcome, 'submitted');
    expect(result.pages, 2);
    expect(b.submitted, isTrue);
    expect(s.host.confirmed, [FormPhase.confirmSubmit]);
    expect(b.clicks.length, s.host.clicksAtSubmitConfirm + 1, reason: 'the only click after Enter is Submit');

    // Every click landed on the left display (negative x), inside a control.
    expect(b.clicks.every((p) => p.dx < 0 && FakeBrowser.screen.contains(p)), isTrue);
  });

  test('typing is key by key at 20 ms, the retry at 40 ms, and a field that never takes it is reported', () async {
    final s = _setup();
    final result = await s.runner.run();
    final nickname = [
      for (final (t, i) in s.browser.typed)
        if (t == 'Anita') i,
    ];
    expect(nickname, [const Duration(milliseconds: 20), const Duration(milliseconds: 40)]);
    expect(s.host.statuses['Nickname'], (ItemStatus.filled, null));
    expect(s.host.statuses['Member number'], (ItemStatus.failed, 'could not fill'));
    final member = result.fields.firstWhere((f) => f.question == 'Member number');
    expect(member.status, ItemStatus.failed);
    expect(member.visual, isTrue);
    // After filling, the tree was read again and a fresh screenshot checked.
    expect(s.browser.reads, greaterThan(2));
    expect(s.vision.reads, greaterThanOrEqualTo(2));
    // 80 ms after each click into a field before typing.
    expect(s.browser.paused, contains(const Duration(milliseconds: 80)));
  });

  test('a line break is typed only into a multi-line field', () async {
    final s = _setup(
      pages: [
        [Control(Kind.text, 'Full name', _row(200)), Control(Kind.button, 'Send', Rect.fromLTWH(-2400, 1300, 200, 70))],
      ],
      answers: {'Full name': 'Ana\nRuiz'},
    );
    await s.runner.run();
    expect(s.browser.typed.first.$1, 'Ana Ruiz');
    expect(s.browser.keys, isNot(contains('enter')));
  });

  test('a drop-down whose option cannot be located falls back to type-ahead + Enter', () async {
    final s = _setup(
      pages: [
        [
          Control(Kind.select, 'Country', _row(560), options: ['Spain', 'Mexico', 'Chile']),
          Control(Kind.button, 'Send', Rect.fromLTWH(-2400, 1300, 200, 70)),
        ],
      ],
      canLocate: false,
    );
    await s.runner.run();
    expect(s.browser.byQuestion('Country').value, 'Mexico');
    expect(s.vision.locates, 1);
    expect(s.browser.keys, contains('enter'));
  });

  test('Esc at the end leaves the form unsent', () async {
    final s = _setup(confirmSubmit: false);
    final result = await s.runner.run();
    expect(result.outcome, 'ready');
    expect(s.browser.submitted, isFalse);
  });

  test('the emergency stop halts filling at once', () async {
    final s = _setup(stopAfterSteps: 1);
    final result = await s.runner.run();
    expect(result.outcome, 'stopped');
    expect(s.browser.byQuestion('Country', onPage: 0).value, '');
    expect(s.browser.page, 0);
  });

  test('never types into a password field, even when the screenshot suggests it', () async {
    final s = _setup(
      pages: [
        [
          Control(Kind.password, 'Password', _row(200)),
          Control(Kind.button, 'Send', Rect.fromLTWH(-2400, 1300, 200, 70)),
        ],
      ],
      answers: {'Password': 'hunter2'},
    );
    await s.runner.run();
    expect(s.browser.byQuestion('Password').value, '');
    expect(s.browser.typed, isEmpty);
    expect(s.host.statuses['Password']?.$1, ItemStatus.blocked);
  });

  test('fields the tree lists but cannot act on are visual_only and filled by click + type', () async {
    // A browser that lists the controls (with bounds) but exposes no actions.
    final tree = FormSnapshot.fromElements([
      UiElement.fromMap({
        'id': 't1',
        'type': 'edit',
        'name': 'City',
        'value': '',
        'bounds': [-2400, 200, 800, 60],
      }),
      UiElement.fromMap({
        'id': 'c1',
        'type': 'combo',
        'name': 'Size',
        'value': '',
        'bounds': [-2400, 560, 600, 60],
        'options': ['S', 'M', 'L'],
      }),
      UiElement.fromMap({
        'id': 't2',
        'type': 'edit',
        'name': 'Zip',
        'value': '',
        'bounds': [-2400, 700, 800, 60],
        'patterns': ['value'],
      }),
    ]);
    expect(tree.field('t1')!.access, FieldAccess.visualOnly);
    expect(tree.field('c1')!.access, FieldAccess.visualOnly);
    expect(tree.field('t2')!.access, FieldAccess.nativeAx);
    final plan = FormFiller.plan(FormFiller.idsFor(tree.fields), const [
      FieldAnswer(fieldId: 'f1', question: 'City', answer: 'Lima'),
      FieldAnswer(fieldId: 'f2', question: 'Size', answer: 'm'),
      FieldAnswer(fieldId: 'f3', question: 'Zip', answer: '15001'),
    ]);
    expect(plan.steps[0].actions.single, isA<ClickTypeAction>());
    expect((plan.steps[1].actions.single as VisualChooseAction).label, 'M');
    expect(plan.steps[2].actions.single, isA<SetValueAction>());
    expect([for (final s in plan.steps) s.visual], [true, true, false]);
  });
}

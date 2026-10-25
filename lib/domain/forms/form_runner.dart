import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import '../agent/agent_action.dart';
import '../agent/coordinates.dart';
import '../agent/safety.dart';
import 'autofill_watcher.dart' show ScrollLoop;
import 'form_filler.dart';
import 'form_model.dart';
import 'screen_text.dart';

// The questionnaire loop, independent of the platform: read the form, ask the
// model, fill every field — through its accessibility action when it has one
// (native_ax), by clicking and typing where it appears on screen when it
// doesn't (visual_only) — verify, retry once slower, page through, and stop
// before Submit. The platform comes in through [FormDriver], the model
// through [FormVision], the overlay through [FormRunHost]; tests drive it
// with a fake browser window.

enum FormPhase {
  idle,
  reading,
  thinking,

  /// "Show me the answers first": waiting for Enter.
  review,
  filling,
  verifying,

  /// "Show me the answers first": the page is filled, Enter for the next.
  nextPage,

  /// Everything answered: Enter clicks Submit. Never automatic.
  confirmSubmit,
  finished,
}

enum ItemStatus {
  pending,
  filling,
  filled,
  failed,
  skipped,
  blocked,

  /// A read-only question: its answer is shown, nothing is filled.
  shown,
}

/// A screenshot (JPEG data URL) and how its pixels map to the screen.
/// Once the model has seen it, [release] drops the image (the mapper stays
/// for clicks): a fill never holds more than one screenshot.
class ScreenFrame {
  ScreenFrame(String image, this.mapper, {this.ocr = const []}) : _image = image;
  String? _image;
  final CoordinateMapper mapper;

  /// The text on it, read on this computer — screenshot pixels.
  final List<OcrLine> ocr;

  /// The page the form is on (a browser's page, without its toolbar) in
  /// physical pixels, from the read that went with this screenshot.
  Rect? page;

  String get image => _image ?? (throw StateError('Screenshot already released'));
  bool get released => _image == null;

  void release() => _image = null;
}

/// The platform: the accessibility tree and its actions, plus synthetic
/// input for what the tree can't reach. Points are physical screen pixels.
abstract interface class FormDriver {
  Future<ScreenFrame> capture();
  Future<FormSnapshot> read();

  Future<bool> setValue(String elementId, String text);
  Future<bool> select(String elementId);
  Future<bool> toggle(String elementId, bool on);
  Future<bool> choose(String elementId, String label);
  Future<bool> invoke(String elementId);

  /// A slider or spinner to [value] (RangeValue); false when the control
  /// didn't take it.
  Future<bool> setRange(String elementId, double value);

  /// Keyboard focus to the element (a browser scrolls it into view).
  Future<bool> focusElement(String elementId);

  /// One element as it is now — cheap, unlike [read]; null when unknown.
  Future<ElementState?> state(String elementId);

  /// Synthetic mouse and keyboard are available (SendInput / CGEvent).
  bool get canInput;
  Future<void> click(Offset physical);

  /// Selects the focused field's text, so typing replaces it.
  Future<void> selectAll();

  /// Types [text] as one Unicode key event per character, [interval]
  /// apart — never through the clipboard, so web inputs see real typing.
  Future<void> typeKeys(String text, Duration interval);
  Future<void> pressKey(String key);
  Future<void> scroll(Offset physical, int notches);

  /// Scrolls the form one screen down: the scroll container around
  /// [anchor] (the form's own panel, never a sidebar) through the
  /// accessibility tree, else the mouse wheel at [fallback].
  Future<void> scrollDown({String? anchor, required Offset fallback});

  /// Press at [from], move to [to] in small steps, release — matching and
  /// ordering questions.
  Future<void> drag(Offset from, Offset to);

  /// Whether the page — the container around [anchor] — can scroll further
  /// down (UIA ScrollPattern, the AX scroll bar); null when it can't be told.
  Future<bool?> canScrollDown({String? anchor});
  Future<FocusInfo?> focused();
  Future<void> pause(Duration d);
}

/// One visual-only field to read back from a screenshot.
class VisualCheck {
  const VisualCheck(this.id, this.question, this.kind, this.point);
  final int id;
  final String question;

  /// text, textarea, dropdown, radio, checkbox.
  final String kind;

  /// Screenshot pixels.
  final Offset point;
}

/// The model: answers, and eyes for what the accessibility tree can't show.
abstract interface class FormVision {
  Future<FormReply> answer(ScreenFrame frame, Map<String, FormField> ids);

  /// Where the open drop-down's option [label] is, in screenshot pixels.
  Future<Offset?> locateOption(ScreenFrame frame, String label);

  /// What each checked control shows now: its text or selected option, or
  /// "checked" / "unchecked" for radios and checkboxes. Missing ids: unknown.
  Future<Map<int, String>> readValues(ScreenFrame frame, List<VisualCheck> checks);
}

/// Strings the overlay shows, in the interface language.
abstract interface class FormRunTexts {
  String couldNotFill();
  String blocked(SafetyReason reason);
  String skipped(SkipReason reason);
}

/// The overlay.
abstract interface class FormRunHost {
  bool get cancelled;
  void phase(FormPhase phase, {int? page, String? label});

  /// A page's plan: [FillPlan.steps] first, then [FillPlan.skipped].
  void planned(FillPlan plan);
  void progress(int step, ItemStatus status, {String? note});

  /// Enter (true) or Esc (false).
  Future<bool> confirm(FormPhase phase, {String? label});

  /// "Show me the answers first": the plan with the presenter's edits.
  FillPlan edited(FillPlan plan, Map<String, FormField> ids, Offset? Function(Offset) toScreen);
}

class FillTiming {
  const FillTiming({
    this.afterClick = const Duration(milliseconds: 80),
    this.keyInterval = const Duration(milliseconds: 20),
    this.slowKeyInterval = const Duration(milliseconds: 40),
    this.betweenFields = const (Duration(milliseconds: 100), Duration(milliseconds: 300)),
    this.dropdownOpen = const Duration(milliseconds: 350),
    this.settle = const Duration(milliseconds: 400),
    this.pageLoad = const Duration(milliseconds: 1500),
    this.afterScroll = const Duration(milliseconds: 600),
  });

  final Duration afterClick;
  final Duration keyInterval;

  /// The retry types at half speed: some web inputs drop fast keys.
  final Duration slowKeyInterval;
  final (Duration, Duration) betweenFields;
  final Duration dropdownOpen;
  final Duration settle;
  final Duration pageLoad;
  final Duration afterScroll;
}

/// What happened to one question, for the session record.
class FilledField {
  FilledField(
    this.question,
    this.answer,
    this.status, {
    this.note = '',
    this.visual = false,
    this.type = QuestionType.text,
    this.reasoning = '',
    this.letter,
    DateTime? at,
  }) : at = at ?? DateTime.now();
  final String question;
  final String answer;
  final ItemStatus status;
  final String note;
  final bool visual;
  final QuestionType type;

  /// A lettered option's letter (A, B, C…).
  final String? letter;

  /// The model's one-line why.
  final String reasoning;
  final DateTime at;
}

class FormRunResult {
  const FormRunResult(this.outcome, this.pages, this.fields);

  /// submitted, ready (Submit is the presenter's), stopped, or none (auto-
  /// fill looked and found no questions).
  final String outcome;
  final int pages;
  final List<FilledField> fields;
}

class FormRunner {
  FormRunner({
    required this.driver,
    required this.vision,
    required this.host,
    required this.texts,
    this.showFirst = false,
    this.maxPages = 10,
    this.auto = false,
    this.scrollForMore = true,
    this.timing = const FillTiming(),
    math.Random? random,
  }) : _random = random ?? math.Random();

  final FormDriver driver;
  final FormVision vision;
  final FormRunHost host;
  final FormRunTexts texts;
  final bool showFirst;
  final int maxPages;

  /// An auto-fill cycle: nobody asked, so it stops at Submit without asking
  /// either ("Done — review and submit yourself").
  final bool auto;

  /// Scroll down to look for more questions (up to 10 times a page).
  final bool scrollForMore;
  final FillTiming timing;
  final math.Random _random;

  final _log = <FilledField>[];

  bool get _stop => host.cancelled;

  /// Model calls this fill made: answers, drop-down lookups, visual checks.
  int modelCalls = 0;

  /// The captured display (physical pixels): nothing is clicked outside it.
  Rect? _screen;

  /// Steps whose result was read back right after filling them: true held,
  /// false didn't stick even after a retry.
  final _checked = <FillStep, bool>{};

  /// Answered fields only the screen can fill, waiting to come on screen —
  /// by signature, with the field id they were answered under.
  final _waiting = <String, (FormField, FieldAnswer)>{};

  /// Ends the run: what still waits goes to the presenter, answer and all.
  FormRunResult _done(String outcome, int page, List<FilledField> log) {
    for (final (field, answer) in _waiting.values) {
      _log.add(
        FilledField(
          answer.question.isNotEmpty ? answer.question : field.label,
          answer.display,
          ItemStatus.skipped,
          note: texts.skipped(SkipReason.offscreen),
          type: QuestionTypes.parse(answer.type) ?? QuestionTypes.classify(field),
          reasoning: answer.reasoning,
          letter: answer.letter,
        ),
      );
    }
    _waiting.clear();
    return FormRunResult(outcome, page, log);
  }

  /// Can only be clicked and typed into, and isn't on the screenshot.
  bool _outOfReach(FormField f) => f.access == FieldAccess.visualOnly && (f.offscreen || !_onScreen(f.bounds));

  Future<FormRunResult> run() async {
    final attempted = <String>{};
    final askedSignatures = <String>{};
    final screenAsked = <String>{};
    // The model found questions outside the tree on this page: worth asking
    // again (with a fresh screenshot) after each scroll.
    var screenQuestions = false;
    var page = 1;
    var askedThisPage = false;
    final scrolls = ScrollLoop(enabled: scrollForMore && driver.canInput, limit: maxPages);
    var newSinceScroll = true;
    var sawQuestions = false;
    NavTarget? seenNext;
    NavTarget? seenSubmit;
    CoordinateMapper? mapper;

    String result(String outcome) => outcome;

    // The last screenshot, released before the next is taken (the model may
    // not have needed it: a page already answered goes straight to Next).
    ScreenFrame? held;
    for (var round = 0; round < 60; round++) {
      if (_stop) return _done(result('stopped'), page, _log);
      host.phase(FormPhase.reading, page: page);
      held?.release();
      final frame = held = await driver.capture();
      mapper = frame.mapper;
      _screen = frame.mapper.screen;
      final snap = await driver.read();
      frame.page = snap.page;
      if (_stop) continue;

      // Fields answered earlier that only the screen can fill, now on it.
      final reached = [
        for (final f in snap.fields)
          if (_waiting[f.signature] case (_, final answer)? when !_outOfReach(f)) (f, answer),
      ];
      if (reached.isNotEmpty && !_stop) {
        for (final (f, _) in reached) {
          _waiting.remove(f.signature);
        }
        final ids = {for (final (f, a) in reached) a.fieldId: f};
        final plan = FormFiller.plan(ids, [
          for (final (_, a) in reached) a,
        ], toScreen: (p) => frame.mapper.toScreen(p.dx, p.dy));
        host.planned(plan);
        await _fillAndVerify(plan);
        newSinceScroll = true;
        continue;
      }

      // Questions not asked yet — by key, and by what they ask (a browser
      // may hand the same question a new id after a scroll). One only the
      // screen can fill is asked about too, from its label; it is filled
      // once it is on screen.
      final pending = [
        for (final f in FormPager.pending(snap, attempted))
          if (!askedSignatures.contains(f.signature)) f,
      ];
      // After a scroll, the screenshot is worth another look only if this
      // page had questions outside the tree, or the tree shows nothing.
      final lookAgain = !askedThisPage && (scrolls.scrolls == 0 || screenQuestions || snap.fields.isEmpty);
      if (pending.isNotEmpty || lookAgain) {
        askedThisPage = true;
        attempted.addAll(pending.map((f) => f.key));
        askedSignatures.addAll(pending.map((f) => f.signature));
        final ids = FormFiller.idsFor(pending);
        host.phase(FormPhase.thinking, page: page);
        final FormReply reply;
        try {
          modelCalls++;
          reply = await vision.answer(frame, ids);
        } finally {
          frame.release();
        }
        if (reply.answers.any((a) => a.fieldId == 'screen')) screenQuestions = true;
        if (reply.questionnaire || ids.isNotEmpty || reply.answers.isNotEmpty) sawQuestions = true;
        // Auto-fill looked at a page with no questions: leave it be.
        if (auto && !sawQuestions && page == 1 && scrolls.scrolls == 0) return _done('none', page, _log);
        seenNext = reply.next ?? seenNext;
        seenSubmit = reply.submit ?? seenSubmit;
        // A question read off the screenshot is answered once per page,
        // however often the page is looked at again.
        final answers = [
          for (final a in reply.answers)
            if (a.fieldId != 'screen' || screenAsked.add(OptionMatcher.fold(a.question))) a,
        ];
        if (_stop) continue;
        Offset? toScreen(Offset p) => frame.mapper.toScreen(p.dx, p.dy);
        var plan = FormFiller.plan(ids, answers, toScreen: toScreen);
        // Out of reach for now: held back (shown as left to the presenter
        // until Sotto gets to them).
        final later = [
          for (final s in plan.steps)
            if (s.field != null && _outOfReach(s.field!)) s,
        ];
        for (final s in later) {
          _waiting[s.field!.signature] = (s.field!, s.answer);
        }
        if (later.isNotEmpty) {
          plan = FillPlan(
            [
              for (final s in plan.steps)
                if (!later.contains(s)) s,
            ],
            [
              ...plan.skipped,
              for (final s in later) SkippedAnswer(s.question, SkipReason.offscreen, field: s.field, answer: s.answer),
            ],
          );
        }
        if (plan.steps.isEmpty && plan.skipped.isEmpty) continue;
        newSinceScroll = true;
        host.planned(plan);
        if (showFirst) {
          host.phase(FormPhase.review, page: page);
          if (!await host.confirm(FormPhase.review)) return _done('stopped', page, _log);
          plan = host.edited(plan, ids, toScreen);
          host.planned(plan);
        }
        await _fillAndVerify(plan);
        continue;
      }

      // Answers waiting for their field to come on screen: scroll to it
      // before moving on.
      if (_waiting.isNotEmpty) {
        final anchor = _anchor(snap);
        if (scrolls.shouldScroll(
          newFieldsSinceLastScroll: newSinceScroll,
          atSubmit: false,
          canScrollMore: await driver.canScrollDown(anchor: anchor),
        )) {
          await driver.scrollDown(anchor: anchor, fallback: _wheelPoint(snap, frame.mapper.screen));
          newSinceScroll = false;
          askedThisPage = false;
          await driver.pause(timing.afterScroll);
          continue;
        }
      }

      // Everything on this page is answered: move on. A "Next" that would
      // confirm, pay, send or delete is treated as Submit — never pressed
      // without the presenter.
      var next = _nav(snap.next, seenNext, mapper);
      var submit = _nav(snap.submit, seenSubmit, mapper);
      if (next != null && SafetyGate.isForbiddenButton(next.label)) {
        submit ??= next;
        next = null;
      }
      if (next != null) {
        if (page >= maxPages) return _done('ready', page, _log);
        if (showFirst) {
          host.phase(FormPhase.nextPage, page: page, label: next.label);
          if (!await host.confirm(FormPhase.nextPage, label: next.label)) {
            return _done('stopped', page, _log);
          }
        }
        await _press(next);
        page++;
        askedThisPage = false;
        screenQuestions = false;
        scrolls.reset();
        newSinceScroll = true;
        seenNext = null;
        seenSubmit = null;
        await driver.pause(timing.pageLoad);
        continue;
      }
      if (submit != null && auto) return _done('ready', page, _log);
      if (submit != null) {
        host.phase(FormPhase.confirmSubmit, page: page, label: submit.label);
        if (!await host.confirm(FormPhase.confirmSubmit, label: submit.label)) {
          return _done('ready', page, _log);
        }
        await _press(submit);
        return _done('submitted', page, _log);
      }
      // More questions below the fold? Scroll one viewport and look again —
      // until a scroll turns up nothing new or the page ends.
      final anchor = _anchor(snap);
      if (scrolls.shouldScroll(
        newFieldsSinceLastScroll: newSinceScroll,
        atSubmit: false,
        canScrollMore: await driver.canScrollDown(anchor: anchor),
      )) {
        await driver.scrollDown(anchor: anchor, fallback: _wheelPoint(snap, frame.mapper.screen));
        newSinceScroll = false;
        askedThisPage = false;
        await driver.pause(timing.afterScroll);
        continue;
      }
      return _done(sawQuestions || !auto ? 'ready' : 'none', page, _log);
    }
    return _done(_stop ? 'stopped' : 'ready', page, _log);
  }

  bool _onScreen(Rect r) {
    final s = _screen;
    return s == null || s.contains(r.center);
  }

  /// An element of the form to scroll by: its container is the one to
  /// scroll (not a sidebar, not the page around a scrolling panel).
  static String? _anchor(FormSnapshot s) {
    for (final f in s.fields.reversed) {
      final id = f.elementIds.where((i) => i.isNotEmpty).firstOrNull;
      if (id != null) return id;
    }
    return null;
  }

  /// Where the wheel scrolls when the tree can't: over the form's fields
  /// that are on screen, else the middle of the display.
  Offset _wheelPoint(FormSnapshot s, Rect screen) {
    final on = [
      for (final f in s.fields)
        if (!f.offscreen && screen.contains(f.bounds.center)) f.bounds,
    ];
    if (on.isEmpty) return screen.center;
    final c = on.reduce((a, b) => a.expandToInclude(b)).center;
    return Offset(c.dx.clamp(screen.left, screen.right - 1), c.dy.clamp(screen.top, screen.bottom - 1));
  }

  _Nav? _nav(FormButton? tree, NavTarget? seen, CoordinateMapper? mapper) {
    if (tree != null) return _Nav(tree.label, tree.bounds.center, elementId: tree.invokable ? tree.elementId : null);
    if (seen == null || mapper == null) return null;
    final p = mapper.toScreen(seen.point.dx, seen.point.dy);
    return p == null ? null : _Nav(seen.label, p);
  }

  Future<void> _press(_Nav nav) async {
    if (nav.elementId != null && await driver.invoke(nav.elementId!)) return;
    if (driver.canInput) await driver.click(nav.point);
  }

  // ─────────────────────────── Filling ───────────────────────────

  Future<void> _fillAndVerify(FillPlan plan) async {
    final status = <FillStep, (ItemStatus, String)>{};
    // Read-only questions: shown in the overlay, nothing to fill or check.
    for (var i = 0; i < plan.steps.length; i++) {
      if (!plan.steps[i].showOnly) continue;
      status[plan.steps[i]] = (ItemStatus.shown, '');
      host.progress(i, ItemStatus.shown);
    }
    final steps = [
      for (final s in plan.steps)
        if (!s.showOnly) s,
    ];
    int indexOf(FillStep s) => plan.steps.indexOf(s);
    for (var i = 0; i < steps.length && !_stop; i++) {
      status[steps[i]] = await _fillOne(indexOf(steps[i]), steps[i], timing.keyInterval);
    }

    // What was read back right after filling it is settled; the rest is
    // checked together on a fresh read (and a screenshot for screen answers).
    final unsettled = [
      for (final s in steps)
        if (!_checked.containsKey(s)) s,
    ];
    if (!_stop && steps.isNotEmpty) {
      host.phase(FormPhase.verifying);
      var wrong = <FillStep>[];
      if (unsettled.isNotEmpty) {
        await driver.pause(timing.settle);
        wrong = await _unverified(unsettled, status);
        if (wrong.isNotEmpty && !_stop) {
          // Once more, typing at half speed: some web inputs drop fast keys.
          for (final s in wrong) {
            if (_stop) break;
            status[s] = await _fillOne(indexOf(s), s, timing.slowKeyInterval);
          }
          await driver.pause(timing.settle);
          wrong = await _unverified(wrong, status);
        }
      }
      for (final s in steps) {
        final (st, note) = status[s] ?? (ItemStatus.failed, '');
        if (st == ItemStatus.blocked) continue;
        final i = indexOf(s);
        if (wrong.contains(s) || _checked[s] == false) {
          status[s] = (ItemStatus.failed, texts.couldNotFill());
          host.progress(i, ItemStatus.failed, note: texts.couldNotFill());
        } else {
          status[s] = (ItemStatus.filled, note);
          host.progress(i, ItemStatus.filled);
        }
      }
    }

    for (final s in plan.steps) {
      final (st, note) = status[s] ?? (ItemStatus.failed, texts.couldNotFill());
      _log.add(
        FilledField(
          s.question,
          s.answer.display,
          st,
          note: note,
          visual: s.visual,
          type: s.type,
          reasoning: s.answer.reasoning,
          letter: s.answer.letter,
        ),
      );
    }
    for (final s in plan.skipped) {
      if (s.reason == SkipReason.offscreen) continue;
      _log.add(
        FilledField(
          s.question,
          s.answer?.display ?? '',
          s.reason == SkipReason.sensitive ? ItemStatus.blocked : ItemStatus.skipped,
          note: texts.skipped(s.reason),
          type: s.field != null
              ? QuestionTypes.classify(s.field!)
              : (QuestionTypes.parse(s.answer?.type) ?? QuestionType.text),
          reasoning: s.answer?.reasoning ?? '',
          letter: s.answer?.letter,
        ),
      );
    }
  }

  /// Steps that didn't stick: failed actions, fields the fresh tree shows
  /// wrong, and visual-only answers a fresh screenshot shows wrong.
  Future<List<FillStep>> _unverified(List<FillStep> steps, Map<FillStep, (ItemStatus, String)> status) async {
    final candidates = [
      for (final s in steps)
        if (status[s]?.$1 != ItemStatus.blocked) s,
    ];
    if (candidates.isEmpty) return const [];
    final after = await driver.read();
    final wrong = <FillStep>{
      for (final s in candidates)
        if (status[s]?.$1 == ItemStatus.failed) s,
      ...FormVerifier.failed(candidates.where((s) => s.field != null).toList(), after),
    };

    // Answers read off the screenshot can only be checked on a screenshot.
    final screenSteps = [
      for (final s in candidates)
        if (s.field == null && s.answer.point != null && s.answer.drags.isEmpty && !wrong.contains(s)) s,
    ];
    if (screenSteps.isNotEmpty) {
      final frame = await driver.capture();
      Map<int, String> shown;
      try {
        modelCalls++;
        shown = await vision.readValues(frame, [
          for (var i = 0; i < screenSteps.length; i++)
            VisualCheck(i, screenSteps[i].question, screenSteps[i].answer.kind, screenSteps[i].answer.point!),
        ]);
      } on TimeoutException {
        rethrow; // the model is unreachable: the cycle ends
      } catch (_) {
        shown = const {}; // can't tell: don't retry blindly
      } finally {
        frame.release();
      }
      for (var i = 0; i < screenSteps.length; i++) {
        final value = shown[i];
        if (value != null && !_shows(screenSteps[i], value)) wrong.add(screenSteps[i]);
      }
    }
    return [
      for (final s in steps)
        if (wrong.contains(s)) s,
    ];
  }

  static bool _shows(FillStep s, String shown) => switch (s.answer.kind) {
    'radio' || 'checkbox' || 'choice' => OptionMatcher.fold(shown) == 'checked',
    _ => FormVerifier.sameText(shown, s.answer.answer),
  };

  Future<(ItemStatus, String)> _fillOne(int index, FillStep step, Duration keyInterval) async {
    host.phase(FormPhase.filling);
    host.progress(index, ItemStatus.filling);
    var ok = true;
    for (final action in step.actions) {
      if (_stop) break;
      final (done, blocked) = await _perform(action, step, keyInterval);
      if (blocked != null) {
        host.progress(index, ItemStatus.blocked, note: blocked);
        return (ItemStatus.blocked, blocked);
      }
      ok &= done;
    }
    // Read the field back at once — its own elements, not the whole page —
    // and try once more, slower, if the value didn't stick.
    if (!_stop && step.field != null && !_checked.containsKey(step)) {
      var held = await _holds(step);
      if (held == false && !_stop) {
        await driver.pause(timing.afterClick);
        for (final action in step.actions) {
          if (_stop) break;
          await _perform(action, step, timing.slowKeyInterval);
        }
        held = await _holds(step);
      }
      if (held != null) {
        _checked[step] = held;
        ok = held;
      }
    }
    host.progress(index, ok ? ItemStatus.filled : ItemStatus.failed);
    // Web forms need a beat to register each change.
    final (lo, hi) = timing.betweenFields;
    final span = hi.inMilliseconds - lo.inMilliseconds;
    await driver.pause(lo + Duration(milliseconds: span <= 0 ? 0 : _random.nextInt(span)));
    return (ok ? ItemStatus.filled : ItemStatus.failed, '');
  }

  /// [step]'s field as its elements show it now: true it holds, false it
  /// doesn't, null when they can't tell.
  Future<bool?> _holds(FillStep step) async {
    final f = step.field;
    if (f == null) return null;
    await driver.pause(timing.afterClick);
    final states = <String, ElementState>{};
    for (final id in f.elementIds) {
      final st = await driver.state(id);
      if (st != null) states[id] = st;
    }
    return states.isEmpty ? null : FormVerifier.holds(step, states);
  }

  /// The accessibility action first; the visual fallback when there is
  /// none or it fails. Returns (worked, why it was blocked).
  Future<(bool, String?)> _perform(FillAction action, FillStep step, Duration keyInterval) async {
    final field = step.field;
    Offset? optionCenter(String id) => field?.options.where((o) => o.elementId == id).firstOrNull?.bounds.center;
    switch (action) {
      case SetValueAction(:final elementId, :final text):
        if (SafetyGate.looksLikeCardNumber(text)) return (false, texts.blocked(SafetyReason.cardNumber));
        if (await driver.setValue(elementId, text)) return (true, null);
        return _clickType(field?.bounds.center, text, multiline: field?.multiline ?? false, interval: keyInterval);
      case SelectAction(:final elementId):
        if (await driver.select(elementId)) return (true, null);
        return _clickType(optionCenter(elementId), null, interval: keyInterval);
      case ToggleAction(:final elementId, :final on):
        if (await driver.toggle(elementId, on)) return (true, null);
        return _clickType(optionCenter(elementId), null, interval: keyInterval);
      case ChooseAction(:final elementId, :final label):
        if (await driver.choose(elementId, label)) return (true, null);
        // A select that ignores picks from its own list (Firefox): focused,
        // it jumps to the option whose name is typed. No screenshot needed.
        if (driver.canInput && await driver.focusElement(elementId)) {
          await driver.pause(timing.afterClick);
          final verdict = SafetyGate.check(TypeTextAction(label), mode: AgentMode.auto, focus: await driver.focused());
          if (verdict is Block) return (false, texts.blocked(verdict.reason));
          await driver.typeKeys(label, keyInterval);
          await driver.pause(timing.afterClick);
          final now = (await driver.state(elementId))?.value;
          if (now != null && FormVerifier.sameText(now, label)) return (true, null);
        }
        final c = field?.bounds.center;
        return c == null ? (false, null) : (await _visualChoose(c, label, keyInterval), null);
      case ClickTypeAction(:final point, :final text, :final multiline):
        return _clickType(point, text, multiline: multiline, interval: keyInterval);
      case VisualChooseAction(:final point, :final label):
        return (await _visualChoose(point, label, keyInterval), null);
      case DragAction(:final from, :final to):
        if (!driver.canInput || !_onScreenPoint(from) || !_onScreenPoint(to)) return (false, null);
        await driver.drag(from, to);
        await driver.pause(timing.afterClick);
        return (true, null);
      case SetRangeAction(:final elementId, :final value, :final range):
        // A custom slider accepts RangeValue and ignores it (Chromium even
        // reports the new value for a moment): only a value still there a
        // beat later counts.
        if (await driver.setRange(elementId, value)) {
          await driver.pause(timing.afterClick);
          final now = (await driver.state(elementId))?.rangeValue;
          if (now == null || (now - value).abs() < 1e-6) return (true, null);
        }
        // Then the arrow keys move it, from where it really is.
        if (driver.canInput && await driver.focusElement(elementId)) {
          await driver.pause(timing.afterClick);
          final now = (await driver.state(elementId))?.rangeValue ?? range.value;
          final steps = ((value - now) / range.keyStep).round();
          for (var i = 0; i < steps.abs() && i < 200 && !_stop; i++) {
            await driver.pressKey(steps > 0 ? 'right' : 'left');
          }
          return (true, null);
        }
        if (field?.offscreen ?? false) return (false, null);
        return _clickType(action.point, null, interval: keyInterval);
    }
  }

  bool _onScreenPoint(Offset p) => _screen == null || _screen!.contains(p);

  /// Click the field, wait for focus, select what's there, then type the
  /// answer key by key — through the same safety gate as agent mode.
  Future<(bool, String?)> _clickType(
    Offset? point,
    String? text, {
    bool multiline = false,
    required Duration interval,
  }) async {
    // Never a click off the captured display: a field scrolled out of view
    // reports a place below the screen, and the click would land on
    // whatever is there (the taskbar).
    if (point == null || !driver.canInput || !_onScreenPoint(point)) return (false, null);
    await driver.click(point);
    await driver.pause(timing.afterClick);
    if (text == null || text.isEmpty) return (true, null);
    final verdict = SafetyGate.check(TypeTextAction(text), mode: AgentMode.auto, focus: await driver.focused());
    if (verdict is Block) return (false, texts.blocked(verdict.reason));
    await driver.selectAll();
    final typed = multiline ? text : text.replaceAll(RegExp(r'\s*[\r\n]+\s*'), ' ');
    await driver.typeKeys(typed, interval);
    return (true, null);
  }

  /// Click the drop-down open, find the option on a fresh screenshot and
  /// click it; if it can't be seen, type its label and press Enter (native
  /// select menus jump to what is typed).
  Future<bool> _visualChoose(Offset point, String label, Duration interval) async {
    if (!driver.canInput || !_onScreenPoint(point)) return false;
    await driver.click(point);
    await driver.pause(timing.dropdownOpen);
    final frame = await driver.capture();
    Offset? option;
    try {
      modelCalls++;
      option = await vision.locateOption(frame, label);
    } on TimeoutException {
      rethrow;
    } catch (_) {
      option = null;
    } finally {
      frame.release();
    }
    final target = option == null ? null : frame.mapper.toScreen(option.dx, option.dy);
    if (target != null) {
      await driver.click(target);
    } else {
      await driver.typeKeys(label, interval);
      await driver.pressKey('enter');
    }
    await driver.pause(timing.afterClick);
    return true;
  }
}

class _Nav {
  const _Nav(this.label, this.point, {this.elementId});
  final String label;
  final Offset point;
  final String? elementId;
}

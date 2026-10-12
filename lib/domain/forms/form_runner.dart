import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../agent/agent_action.dart';
import '../agent/coordinates.dart';
import '../agent/safety.dart';
import 'autofill_watcher.dart' show ScrollLoop;
import 'form_filler.dart';
import 'form_model.dart';

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
  ScreenFrame(String image, this.mapper) : _image = image;
  String? _image;
  final CoordinateMapper mapper;

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

  /// Press at [from], move to [to] in small steps, release — matching and
  /// ordering questions.
  Future<void> drag(Offset from, Offset to);

  /// Whether the page can scroll further down (UIA ScrollPattern, the AX
  /// scroll bar); null when it can't be told.
  Future<bool?> canScrollDown();
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
    DateTime? at,
  }) : at = at ?? DateTime.now();
  final String question;
  final String answer;
  final ItemStatus status;
  final String note;
  final bool visual;
  final QuestionType type;

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

  Future<FormRunResult> run() async {
    final attempted = <String>{};
    final screenAsked = <String>{};
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
      if (_stop) return FormRunResult(result('stopped'), page, _log);
      host.phase(FormPhase.reading, page: page);
      held?.release();
      final frame = held = await driver.capture();
      mapper = frame.mapper;
      final snap = await driver.read();
      if (_stop) continue;

      final pending = FormPager.pending(snap, attempted);
      if (pending.isNotEmpty || !askedThisPage) {
        askedThisPage = true;
        attempted.addAll(pending.map((f) => f.key));
        final ids = FormFiller.idsFor(pending);
        host.phase(FormPhase.thinking, page: page);
        final FormReply reply;
        try {
          reply = await vision.answer(frame, ids);
        } finally {
          frame.release();
        }
        if (reply.questionnaire || ids.isNotEmpty || reply.answers.isNotEmpty) sawQuestions = true;
        // Auto-fill looked at a page with no questions: leave it be.
        if (auto && !sawQuestions && page == 1 && scrolls.scrolls == 0) return FormRunResult('none', page, _log);
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
        if (plan.steps.isEmpty && plan.skipped.isEmpty) continue;
        newSinceScroll = true;
        host.planned(plan);
        if (showFirst) {
          host.phase(FormPhase.review, page: page);
          if (!await host.confirm(FormPhase.review)) return FormRunResult('stopped', page, _log);
          plan = host.edited(plan, ids, toScreen);
          host.planned(plan);
        }
        await _fillAndVerify(plan);
        continue;
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
        if (page >= maxPages) return FormRunResult('ready', page, _log);
        if (showFirst) {
          host.phase(FormPhase.nextPage, page: page, label: next.label);
          if (!await host.confirm(FormPhase.nextPage, label: next.label)) {
            return FormRunResult('stopped', page, _log);
          }
        }
        await _press(next);
        page++;
        askedThisPage = false;
        scrolls.reset();
        newSinceScroll = true;
        seenNext = null;
        seenSubmit = null;
        await driver.pause(timing.pageLoad);
        continue;
      }
      if (submit != null && auto) return FormRunResult('ready', page, _log);
      if (submit != null) {
        host.phase(FormPhase.confirmSubmit, page: page, label: submit.label);
        if (!await host.confirm(FormPhase.confirmSubmit, label: submit.label)) {
          return FormRunResult('ready', page, _log);
        }
        await _press(submit);
        return FormRunResult('submitted', page, _log);
      }
      // More questions below the fold? Scroll one viewport and look again —
      // until a scroll turns up nothing new or the page ends.
      if (scrolls.shouldScroll(
        newFieldsSinceLastScroll: newSinceScroll,
        atSubmit: false,
        canScrollMore: await driver.canScrollDown(),
      )) {
        await driver.scroll(frame.mapper.screen.center, 5);
        newSinceScroll = false;
        askedThisPage = false;
        await driver.pause(timing.afterScroll);
        continue;
      }
      return FormRunResult(sawQuestions || !auto ? 'ready' : 'none', page, _log);
    }
    return FormRunResult(_stop ? 'stopped' : 'ready', page, _log);
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

    if (!_stop && steps.isNotEmpty) {
      host.phase(FormPhase.verifying);
      await driver.pause(timing.settle);
      var wrong = await _unverified(steps, status);
      if (wrong.isNotEmpty && !_stop) {
        // Once more, typing at half speed: some web inputs drop fast keys.
        for (final s in wrong) {
          if (_stop) break;
          status[s] = await _fillOne(indexOf(s), s, timing.slowKeyInterval);
        }
        await driver.pause(timing.settle);
        wrong = await _unverified(wrong, status);
      }
      for (final s in steps) {
        final (st, note) = status[s] ?? (ItemStatus.failed, '');
        if (st == ItemStatus.blocked) continue;
        final i = indexOf(s);
        if (wrong.contains(s)) {
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
        ),
      );
    }
    for (final s in plan.skipped) {
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
    host.progress(index, ok ? ItemStatus.filled : ItemStatus.failed);
    // Web forms need a beat to register each change.
    final (lo, hi) = timing.betweenFields;
    final span = hi.inMilliseconds - lo.inMilliseconds;
    await driver.pause(lo + Duration(milliseconds: span <= 0 ? 0 : _random.nextInt(span)));
    return (ok ? ItemStatus.filled : ItemStatus.failed, '');
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
        final c = field?.bounds.center;
        return c == null ? (false, null) : (await _visualChoose(c, label, keyInterval), null);
      case ClickTypeAction(:final point, :final text, :final multiline):
        return _clickType(point, text, multiline: multiline, interval: keyInterval);
      case VisualChooseAction(:final point, :final label):
        return (await _visualChoose(point, label, keyInterval), null);
      case DragAction(:final from, :final to):
        if (!driver.canInput) return (false, null);
        await driver.drag(from, to);
        await driver.pause(timing.afterClick);
        return (true, null);
    }
  }

  /// Click the field, wait for focus, select what's there, then type the
  /// answer key by key — through the same safety gate as agent mode.
  Future<(bool, String?)> _clickType(
    Offset? point,
    String? text, {
    bool multiline = false,
    required Duration interval,
  }) async {
    if (point == null || !driver.canInput) return (false, null);
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
    if (!driver.canInput) return false;
    await driver.click(point);
    await driver.pause(timing.dropdownOpen);
    final frame = await driver.capture();
    Offset? option;
    try {
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

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../../core/platform/hotkey_service.dart';
import '../../core/platform/window_service.dart';
import '../../core/utils/ids.dart';
import '../../data/models/session_record.dart';
import '../../data/models/settings.dart';
import '../../data/models/shortcut.dart';
import '../../data/repositories.dart';
import '../../domain/agent/agent_action.dart';
import '../../domain/agent/coordinates.dart';
import '../../domain/agent/safety.dart';
import '../../domain/forms/form_filler.dart';
import '../../domain/forms/form_model.dart';
import '../../l10n/l10n.dart';
import '../../services/agent/input_service.dart';
import '../../services/agent/native_executor.dart';
import '../../services/ai/llm_client.dart';
import '../../services/ai/questionnaire_service.dart';
import '../../services/screen/form_access.dart';
import '../../services/screen/screen_service.dart';
import '../live/live_controller.dart';

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

enum ItemStatus { pending, filling, filled, failed, skipped, blocked }

/// One question in the overlay list.
class FormItem {
  const FormItem({
    required this.question,
    required this.answer,
    this.status = ItemStatus.pending,
    this.note = '',
    this.editable = true,
  });

  final String question;
  final String answer;
  final ItemStatus status;
  final String note;

  /// Text and choice answers can be edited in review; skipped ones can't.
  final bool editable;

  FormItem copyWith({String? answer, ItemStatus? status, String? note}) => FormItem(
    question: question,
    answer: answer ?? this.answer,
    status: status ?? this.status,
    note: note ?? this.note,
    editable: editable,
  );
}

class QuestionnaireState {
  const QuestionnaireState({
    this.phase = FormPhase.idle,
    this.page = 1,
    this.items = const [],
    this.current,
    this.error,
    this.standalone = false,
    this.submitLabel,
    this.outcome,
  });

  final FormPhase phase;
  final int page;
  final List<FormItem> items;

  /// Index into [items] being filled.
  final int? current;
  final String? error;

  /// Started from the main window: the window became an overlay for it.
  final bool standalone;
  final String? submitLabel;

  /// submitted, ready, stopped, failed — when finished.
  final String? outcome;

  bool get active => phase != FormPhase.idle;

  /// Sotto is moving things on screen right now: the indicator is on.
  bool get inControl => switch (phase) {
    FormPhase.reading || FormPhase.thinking || FormPhase.filling || FormPhase.verifying => true,
    _ => false,
  };

  int get filledCount => items.where((i) => i.status == ItemStatus.filled).length;

  /// Items that fill (not skipped / blocked) — the "7/12" denominator.
  int get fillableCount => items.where((i) => i.status != ItemStatus.skipped && i.status != ItemStatus.blocked).length;

  QuestionnaireState copyWith({
    FormPhase? phase,
    int? page,
    List<FormItem>? items,
    int? current,
    bool clearCurrent = false,
    String? error,
    String? submitLabel,
    String? outcome,
  }) => QuestionnaireState(
    phase: phase ?? this.phase,
    page: page ?? this.page,
    items: items ?? this.items,
    current: clearCurrent ? null : (current ?? this.current),
    error: error ?? this.error,
    standalone: standalone,
    submitLabel: submitLabel ?? this.submitLabel,
    outcome: outcome ?? this.outcome,
  );
}

/// Questionnaires on screen (chord + F): capture the display, read the
/// foreground window's form through accessibility, let DeepSeek answer from
/// its own knowledge, fill each field (accessibility patterns first, a
/// click and typing only as a fallback), verify, and page through — then
/// stop before Submit and wait for Enter. Opt-in; the emergency stop
/// (chord + Esc) always works; password and payment fields are never
/// touched; every field is logged in the session record.
class QuestionnaireController extends Notifier<QuestionnaireState> {
  static const maxPages = 10;

  bool _cancelled = false;
  Completer<bool>? _confirm;
  late HotkeyService _hotkeys;
  late WindowService _window;
  final _random = math.Random();

  /// Answers edited in review, by item index.
  final _edits = <int, String>{};

  AppSettings get _settings => ref.read(settingsProvider);

  @override
  QuestionnaireState build() {
    _hotkeys = ref.read(hotkeyServiceProvider);
    _window = ref.read(windowServiceProvider);
    ref.onDispose(() {
      _cancelled = true;
      unawaited(_clearKeys());
    });
    return const QuestionnaireState();
  }

  /// Null when ready, else why not (in the interface language).
  Future<String?> preflight() async {
    final l = L10n.current;
    if (!_settings.formsEnabled) return l.formsOff;
    if (!FormAccessService.supported) return l.formsUnsupported;
    // macOS: the system prompt appears the first time; after that the
    // message says where to allow it.
    final forms = ref.read(formAccessProvider);
    if (!await forms.hasPermission()) {
      await forms.requestPermission();
      return l.formsNeedsAccessibility;
    }
    final screen = ref.read(screenServiceProvider);
    if (await screen.permission() == ScreenPermission.denied) {
      await screen.requestPermission();
      return l.noticeScreenPermission;
    }
    if (await resolveDeepSeekKey(ref.read(secretStoreProvider)) == null) return l.answerNeedsKey;
    return null;
  }

  Future<void> start() async {
    if (state.active && state.phase != FormPhase.finished) return;
    final live = ref.read(liveControllerProvider).isLive;
    final settings = _settings;
    final problem = await preflight();
    state = QuestionnaireState(phase: FormPhase.reading, standalone: !live);
    if (!live) await _window.enterOverlay(settings);
    if (problem != null) {
      state = state.copyWith(phase: FormPhase.finished, error: problem, outcome: 'failed');
      return;
    }
    if (!live) {
      // In a live session the live shortcut set already carries the stop.
      await _hotkeys.registerExtra(
        'formStop',
        HotkeyService.toHotKey(settings.shortcutFor(LiveAction.agentStop)),
        stop,
      );
    }
    _cancelled = false;
    _edits.clear();

    final client = (await LlmClient.forSettings(settings, ref.read(secretStoreProvider)))!;
    var outcome = 'ready';
    final log = <FormFieldRecord>[];
    var pages = 1;
    try {
      outcome = await _run(QuestionnaireService(client), log, (p) => pages = p);
    } on FormAccessException catch (e) {
      outcome = 'failed';
      state = state.copyWith(error: e.code == 'own_window' ? L10n.current.formsNoWindow : L10n.current.formsReadFailed);
    } on ScreenCaptureException catch (e) {
      outcome = 'failed';
      state = state.copyWith(error: e.permissionDenied ? L10n.current.noticeScreenPermission : e.message);
    } on LlmException catch (e) {
      outcome = 'failed';
      state = state.copyWith(error: e.message);
    } on FormatException {
      outcome = 'failed';
      state = state.copyWith(error: L10n.current.formsBadReply);
    } finally {
      client.close();
      await _clearKeys();
    }
    if (_cancelled) outcome = 'stopped';
    state = state.copyWith(phase: FormPhase.finished, clearCurrent: true, outcome: outcome);
    await _record(FormRunRecord(status: outcome, pages: pages, fields: log));
  }

  /// The page loop. Returns the outcome.
  Future<String> _run(QuestionnaireService service, List<FormFieldRecord> log, void Function(int) onPage) async {
    final forms = ref.read(formAccessProvider);
    final attempted = <String>{};
    var page = 1;
    var scrolledWithoutNews = false;
    final showFirst = _settings.formsMode == FormFillMode.showFirst;

    for (var round = 0; round < 60 && !_cancelled; round++) {
      state = state.copyWith(phase: FormPhase.reading, page: page, clearCurrent: true);
      final shot = await ref.read(screenServiceProvider).capture(target: CaptureTarget.foregroundDisplay);
      final mapper = CoordinateMapper(
        imageWidth: shot.width,
        imageHeight: shot.height,
        screen: shot.screen,
        scale: shot.scale,
      );
      final snap = await forms.snapshot();
      if (_cancelled) break;

      switch (FormPager.decide(snap, attempted, scrolledWithoutNews: scrolledWithoutNews)) {
        case PageMove.answer:
          scrolledWithoutNews = false;
          final pending = FormPager.pending(snap, attempted);
          attempted.addAll(pending.map((f) => f.key));
          final ids = FormFiller.idsFor(pending);
          state = state.copyWith(phase: FormPhase.thinking);
          final answers = await service.answer(
            screenshot: shot.dataUrl,
            ids: ids,
            mapper: mapper,
            settings: _settings,
            appLanguageName: L10n.current.localeName == 'es' ? 'Spanish' : 'English',
          );
          if (_cancelled) break;
          var plan = FormFiller.plan(ids, answers, toScreen: (p) => mapper.toScreen(p.dx, p.dy));
          _showPlan(plan);
          if (showFirst) {
            state = state.copyWith(phase: FormPhase.review);
            if (!await _waitForEnter()) return 'stopped';
            plan = _applyEdits(plan, ids, mapper);
            _showPlan(plan, keepEdits: true);
          }
          await _fillAndVerify(plan, forms);
          _log(plan, log);
        case PageMove.next:
          final next = snap.next!;
          if (showFirst) {
            state = state.copyWith(phase: FormPhase.nextPage, submitLabel: next.label);
            if (!await _waitForEnter()) return 'stopped';
          }
          if (page >= maxPages) return 'ready';
          await _press(next, forms);
          page++;
          onPage(page);
          scrolledWithoutNews = false;
          // Let the next page load before reading it.
          await Future<void>.delayed(const Duration(milliseconds: 1500));
        case PageMove.submit:
          final submit = snap.submit!;
          state = state.copyWith(phase: FormPhase.confirmSubmit, submitLabel: submit.label, clearCurrent: true);
          if (!await _waitForEnter()) return 'ready';
          await _press(submit, forms);
          return 'submitted';
        case PageMove.scroll:
          if (!InputService.supported) return 'ready';
          final c = shot.screen.center;
          await ref.read(inputServiceProvider).scroll(0, 5, x: c.dx, y: c.dy);
          scrolledWithoutNews = true;
          await Future<void>.delayed(const Duration(milliseconds: 600));
        case PageMove.done:
          return 'ready';
      }
    }
    return _cancelled ? 'stopped' : 'ready';
  }

  List<FillStep> _steps = const [];

  void _showPlan(FillPlan plan, {bool keepEdits = false}) {
    _steps = plan.steps;
    final l = L10n.current;
    state = state.copyWith(
      items: [
        for (var i = 0; i < plan.steps.length; i++)
          FormItem(
            question: plan.steps[i].question,
            answer: keepEdits ? (_edits[i] ?? plan.steps[i].answer.display) : plan.steps[i].answer.display,
          ),
        for (final s in plan.skipped)
          FormItem(
            question: s.question,
            answer: s.answer?.display ?? '',
            status: s.reason == SkipReason.sensitive ? ItemStatus.blocked : ItemStatus.skipped,
            note: switch (s.reason) {
              SkipReason.sensitive => l.formsWhySensitive,
              SkipReason.noMatch => l.formsWhyNoMatch,
              SkipReason.unknownField => l.formsWhyNoField,
              SkipReason.noAnswer || SkipReason.lowConfidence => l.formsWhyNoAnswer,
            },
            editable: false,
          ),
      ],
    );
  }

  /// Review edits become the answers to fill.
  FillPlan _applyEdits(FillPlan plan, Map<String, FormField> ids, CoordinateMapper mapper) {
    if (_edits.isEmpty) return plan;
    final answers = [
      for (var i = 0; i < plan.steps.length; i++)
        switch (_edits[i]) {
          null => plan.steps[i].answer,
          final e when plan.steps[i].field?.role == FieldRole.checkboxes => plan.steps[i].answer.copyWith(
            choices: e.split(RegExp(r'\s*[,;]\s*')).where((c) => c.isNotEmpty).toList(),
          ),
          final e => plan.steps[i].answer.copyWith(answer: e),
        },
    ];
    final replanned = FormFiller.plan(ids, answers, toScreen: (p) => mapper.toScreen(p.dx, p.dy));
    return FillPlan(replanned.steps, [...replanned.skipped, ...plan.skipped]);
  }

  /// In review: the presenter changed an answer.
  void editAnswer(int index, String text) {
    if (state.phase != FormPhase.review || index >= _steps.length) return;
    _edits[index] = text;
    final items = [...state.items];
    items[index] = items[index].copyWith(answer: text);
    state = state.copyWith(items: items);
  }

  Future<void> _fillAndVerify(FillPlan plan, FormAccessService forms) async {
    final failed = await _fill(plan.steps, forms);
    if (_cancelled || plan.steps.isEmpty) return;
    state = state.copyWith(phase: FormPhase.verifying, clearCurrent: true);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    var after = await forms.snapshot();
    var wrong = {...FormVerifier.failed(plan.steps, after), ...failed};
    if (wrong.isNotEmpty && !_cancelled) {
      // One more try for what didn't stick.
      final retry = [
        for (final s in plan.steps)
          if (wrong.contains(s)) s,
      ];
      await _fill(retry, forms);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      after = await forms.snapshot();
      wrong = FormVerifier.failed(retry, after).toSet();
    }
    final items = [...state.items];
    for (var i = 0; i < plan.steps.length && i < items.length; i++) {
      if (items[i].status == ItemStatus.blocked) continue;
      items[i] = items[i].copyWith(status: wrong.contains(plan.steps[i]) ? ItemStatus.failed : ItemStatus.filled);
    }
    state = state.copyWith(items: items);
  }

  /// Fills [steps] one by one; returns the ones whose actions failed.
  Future<Set<FillStep>> _fill(List<FillStep> steps, FormAccessService forms) async {
    final failed = <FillStep>{};
    for (final step in steps) {
      if (_cancelled) break;
      final index = _steps.indexOf(step);
      _setItem(index, ItemStatus.filling);
      state = state.copyWith(phase: FormPhase.filling, current: index);
      var ok = true;
      String? blocked;
      for (final action in step.actions) {
        if (_cancelled) break;
        final (done, why) = await _perform(action, step, forms);
        ok &= done;
        blocked ??= why;
      }
      if (blocked != null) {
        _setItem(index, ItemStatus.blocked, note: blocked);
      } else {
        _setItem(index, ok ? ItemStatus.filled : ItemStatus.failed);
        if (!ok) failed.add(step);
      }
      // Web forms need a beat to register each change.
      await Future<void>.delayed(Duration(milliseconds: 100 + _random.nextInt(200)));
    }
    return failed;
  }

  void _setItem(int index, ItemStatus status, {String? note}) {
    if (index < 0 || index >= state.items.length) return;
    final items = [...state.items];
    items[index] = items[index].copyWith(status: status, note: note);
    state = state.copyWith(items: items);
  }

  /// Accessibility pattern first; click (and type) only as a fallback.
  /// Returns (worked, why it was blocked).
  Future<(bool, String?)> _perform(FillAction action, FillStep step, FormAccessService forms) async {
    final field = step.field;
    Offset? fallback;
    switch (action) {
      case SetValueAction(:final elementId, :final text):
        if (SafetyGate.looksLikeCardNumber(text)) return (false, L10n.current.agentWhyCard);
        if (await forms.setValue(elementId, text)) return (true, null);
        fallback = field?.bounds.center;
      case SelectAction(:final elementId):
        if (await forms.select(elementId)) return (true, null);
        fallback = field?.options.where((o) => o.elementId == elementId).firstOrNull?.bounds.center;
      case ToggleAction(:final elementId, :final on):
        if (await forms.toggle(elementId, on)) return (true, null);
        fallback = field?.options.where((o) => o.elementId == elementId).firstOrNull?.bounds.center;
      case ChooseAction(:final elementId, :final label):
        if (await forms.choose(elementId, label)) return (true, null);
        return _clickType(field?.bounds.center, '$label\n');
      case ClickTypeAction(:final point, :final text):
        return _clickType(point, text);
    }
    final text = action is SetValueAction ? action.text : null;
    return _clickType(fallback, text);
  }

  /// The Phase 6 executor: click at a physical point, then type — through
  /// the same safety gate as agent mode.
  Future<(bool, String?)> _clickType(Offset? point, String? text) async {
    if (point == null || !InputService.supported) return (false, null);
    final input = ref.read(inputServiceProvider);
    final executor = NativeAgentExecutor(
      screen: ref.read(screenServiceProvider),
      input: input,
      target: CaptureTarget.foregroundDisplay,
    );
    await executor.perform(ClickAction(point.dx, point.dy), point: point);
    if (text == null || text.isEmpty) return (true, null);
    final typing = TypeTextAction(text);
    final verdict = SafetyGate.check(typing, mode: AgentMode.auto, focus: await input.focused());
    if (verdict is Block) return (false, const LocalizedFormText().reason(verdict.reason));
    await executor.perform(typing);
    return (true, null);
  }

  Future<void> _press(FormButton b, FormAccessService forms) async {
    if (b.invokable && await forms.invoke(b.elementId)) return;
    await _clickType(b.bounds.center, null);
  }

  void _log(FillPlan plan, List<FormFieldRecord> log) {
    final items = state.items;
    for (var i = 0; i < items.length; i++) {
      log.add(
        FormFieldRecord(
          question: items[i].question,
          answer: items[i].answer,
          status: switch (items[i].status) {
            ItemStatus.filled => 'filled',
            ItemStatus.blocked => 'blocked',
            ItemStatus.skipped => 'skipped',
            _ => 'failed',
          },
          note: items[i].note,
        ),
      );
    }
  }

  Future<bool> _waitForEnter() async {
    final done = _confirm = Completer<bool>();
    // Plain Enter / Esc, only while waiting: the overlay never has the
    // keyboard, so these are system-wide for that moment.
    await _hotkeys.registerExtra('formRun', HotKey(key: PhysicalKeyboardKey.enter), approve);
    await _hotkeys.registerExtra('formSkip', HotKey(key: PhysicalKeyboardKey.escape), reject);
    try {
      return await done.future;
    } finally {
      await _hotkeys.unregisterExtra('formRun');
      await _hotkeys.unregisterExtra('formSkip');
    }
  }

  /// Enter: go on (fill the reviewed answers, next page, or submit).
  void approve() {
    final c = _confirm;
    if (c != null && !c.isCompleted) c.complete(true);
  }

  /// Esc: don't.
  void reject() {
    final c = _confirm;
    if (c != null && !c.isCompleted) c.complete(false);
  }

  /// The emergency stop: nothing more is typed or clicked.
  void stop() {
    if (!state.active) return;
    _cancelled = true;
    reject();
    unawaited(ref.read(inputServiceProvider).releaseAll());
  }

  /// Dismisses the finished run; a standalone run gives the window back.
  Future<void> close() async {
    if (state.inControl) stop();
    final standalone = state.standalone;
    state = const QuestionnaireState();
    if (standalone) await _window.exitOverlay();
  }

  Future<void> _clearKeys() async {
    for (final id in ['formStop', 'formRun', 'formSkip']) {
      await _hotkeys.unregisterExtra(id);
    }
  }

  /// Every filled field goes in the session record — unless history is off.
  Future<void> _record(FormRunRecord run) async {
    if (run.fields.isEmpty || _settings.historyRetentionDays == 0) return;
    if (ref.read(liveControllerProvider).isLive) {
      ref.read(liveControllerProvider.notifier).recordFormRun(run);
      return;
    }
    final now = DateTime.now();
    await ref
        .read(sessionRepositoryProvider)
        .save(
          SessionRecord(
            id: newId(),
            scriptId: '',
            scriptTitle: L10n.current.formsSessionTitle,
            startedAt: now,
            endedAt: now,
            rehearsal: false,
            formRuns: [run],
          ),
        );
  }
}

final questionnaireControllerProvider = NotifierProvider<QuestionnaireController, QuestionnaireState>(
  QuestionnaireController.new,
);

/// Why the gate blocked typing, in the interface language.
class LocalizedFormText {
  const LocalizedFormText();

  String reason(SafetyReason r) {
    final l = L10n.current;
    return switch (r) {
      SafetyReason.passwordField => l.agentWhyPassword,
      SafetyReason.secretField => l.agentWhySecret,
      SafetyReason.paymentField => l.agentWhyPayment,
      SafetyReason.cardNumber => l.agentWhyCard,
      SafetyReason.irreversible => l.agentWhyIrreversible,
      SafetyReason.submitKey => l.agentWhySubmitKey,
    };
  }
}

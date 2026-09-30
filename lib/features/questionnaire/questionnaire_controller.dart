import 'dart:async';

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
import '../../domain/agent/safety.dart';
import '../../domain/forms/form_filler.dart';
import '../../domain/forms/form_model.dart';
import '../../domain/forms/form_runner.dart';
import '../../l10n/l10n.dart';
import '../../services/agent/input_service.dart';
import '../../services/ai/llm_client.dart';
import '../../services/ai/questionnaire_service.dart';
import '../../services/screen/form_access.dart';
import '../../services/screen/native_form_driver.dart';
import '../../services/screen/screen_service.dart';
import '../live/live_controller.dart';

export '../../domain/forms/form_runner.dart' show FormPhase, ItemStatus;

/// One question in the overlay list.
class FormItem {
  const FormItem({
    required this.question,
    required this.answer,
    this.status = ItemStatus.pending,
    this.note = '',
    this.editable = true,
    this.visual = false,
  });

  final String question;
  final String answer;
  final ItemStatus status;
  final String note;

  /// Text and choice answers can be edited in review; skipped ones can't.
  final bool editable;

  /// Filled by clicking and typing (no accessibility action).
  final bool visual;

  FormItem copyWith({String? answer, ItemStatus? status, String? note}) => FormItem(
    question: question,
    answer: answer ?? this.answer,
    status: status ?? this.status,
    note: note ?? this.note,
    editable: editable,
    visual: visual,
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

/// Questionnaires on screen (chord + F): the overlay side of [FormRunner].
/// Opt-in; the emergency stop (chord + Esc) always works; password and
/// payment fields are never touched; every field is logged in the session.
class QuestionnaireController extends Notifier<QuestionnaireState> implements FormRunHost, FormRunTexts {
  static const maxPages = 10;

  bool _cancelled = false;
  Completer<bool>? _confirm;
  late HotkeyService _hotkeys;
  late WindowService _window;

  /// Answers edited in review, by item index.
  final _edits = <int, String>{};
  List<FillStep> _steps = const [];

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
    final runner = FormRunner(
      driver: NativeFormDriver(
        screen: ref.read(screenServiceProvider),
        forms: ref.read(formAccessProvider),
        input: ref.read(inputServiceProvider),
      ),
      vision: DeepSeekFormVision(
        QuestionnaireService(client),
        settings: settings,
        appLanguageName: L10n.current.localeName == 'es' ? 'Spanish' : 'English',
      ),
      host: this,
      texts: this,
      showFirst: settings.formsMode == FormFillMode.showFirst,
      maxPages: maxPages,
    );
    var result = const FormRunResult('failed', 1, []);
    try {
      result = await runner.run();
    } on FormAccessException catch (e) {
      state = state.copyWith(error: e.code == 'own_window' ? L10n.current.formsNoWindow : L10n.current.formsReadFailed);
    } on ScreenCaptureException catch (e) {
      state = state.copyWith(error: e.permissionDenied ? L10n.current.noticeScreenPermission : e.message);
    } on LlmException catch (e) {
      state = state.copyWith(error: e.message);
    } on FormatException {
      state = state.copyWith(error: L10n.current.formsBadReply);
    } finally {
      client.close();
      await _clearKeys();
    }
    final outcome = _cancelled ? 'stopped' : result.outcome;
    state = state.copyWith(phase: FormPhase.finished, clearCurrent: true, outcome: outcome, page: result.pages);
    await _record(
      FormRunRecord(
        status: outcome,
        pages: result.pages,
        fields: [
          for (final f in result.fields)
            FormFieldRecord(
              question: f.question,
              answer: f.answer,
              status: switch (f.status) {
                ItemStatus.filled => 'filled',
                ItemStatus.blocked => 'blocked',
                ItemStatus.skipped => 'skipped',
                _ => 'failed',
              },
              note: f.note,
            ),
        ],
      ),
    );
  }

  // ─────────────────────────── FormRunHost ───────────────────────────

  @override
  bool get cancelled => _cancelled;

  @override
  void phase(FormPhase phase, {int? page, String? label}) {
    state = state.copyWith(phase: phase, page: page, submitLabel: label, clearCurrent: phase != FormPhase.filling);
  }

  @override
  void planned(FillPlan plan) {
    _steps = plan.steps;
    state = state.copyWith(
      items: [
        for (var i = 0; i < plan.steps.length; i++)
          FormItem(
            question: plan.steps[i].question,
            answer: _edits[i] ?? plan.steps[i].answer.display,
            visual: plan.steps[i].visual,
          ),
        for (final s in plan.skipped)
          FormItem(
            question: s.question,
            answer: s.answer?.display ?? '',
            status: s.reason == SkipReason.sensitive ? ItemStatus.blocked : ItemStatus.skipped,
            note: skipped(s.reason),
            editable: false,
          ),
      ],
    );
  }

  @override
  void progress(int step, ItemStatus status, {String? note}) {
    if (step < 0 || step >= state.items.length) return;
    final items = [...state.items];
    items[step] = items[step].copyWith(status: status, note: note);
    state = state.copyWith(items: items, current: status == ItemStatus.filling ? step : null);
  }

  @override
  Future<bool> confirm(FormPhase phase, {String? label}) async {
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

  /// Review edits become the answers to fill.
  @override
  FillPlan edited(FillPlan plan, Map<String, FormField> ids, Offset? Function(Offset) toScreen) {
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
    final replanned = FormFiller.plan(ids, answers, toScreen: toScreen);
    _edits.clear();
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

  // ─────────────────────────── FormRunTexts ───────────────────────────

  @override
  String couldNotFill() => L10n.current.formsCouldNotFill;

  @override
  String blocked(SafetyReason r) {
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

  @override
  String skipped(SkipReason r) {
    final l = L10n.current;
    return switch (r) {
      SkipReason.sensitive => l.formsWhySensitive,
      SkipReason.noMatch => l.formsWhyNoMatch,
      SkipReason.unknownField => l.formsWhyNoField,
      SkipReason.noAnswer || SkipReason.lowConfidence => l.formsWhyNoAnswer,
    };
  }

  // ─────────────────────────── Controls ───────────────────────────

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

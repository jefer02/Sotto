import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../../core/platform/hotkey_service.dart';
import '../../core/platform/window_service.dart';
import '../../core/utils/ids.dart';
import '../../data/models/script.dart';
import '../../data/models/session_record.dart';
import '../../data/models/settings.dart';
import '../../data/models/shortcut.dart';
import '../../data/repositories.dart';
import '../../domain/agent/agent_action.dart';
import '../../domain/agent/agent_loop.dart';
import '../../domain/agent/safety.dart';
import '../../l10n/l10n.dart';
import '../../services/agent/input_service.dart';
import '../../services/agent/native_executor.dart';
import '../../services/ai/deepseek_agent.dart';
import '../../services/ai/llm_client.dart';
import '../../services/screen/screen_service.dart';
import '../live/live_controller.dart';

enum AgentPhase { idle, starting, thinking, confirming, acting, finished }

class AgentState {
  const AgentState({
    this.phase = AgentPhase.idle,
    this.task = '',
    this.step = 0,
    this.pending,
    this.log = const [],
    this.result,
    this.error,
    this.standalone = false,
  });

  final AgentPhase phase;
  final String task;
  final int step;

  /// The action waiting for Enter / Esc.
  final PendingAction? pending;
  final List<AgentLogEntry> log;
  final AgentRunResult? result;

  /// Why the task could not start (permission, key, opt-in).
  final String? error;

  /// Started from the main window rather than inside a live session: the
  /// window became an overlay just for the agent.
  final bool standalone;

  bool get active => phase != AgentPhase.idle;

  /// Controlling the machine right now — the indicator is on.
  bool get inControl => active && phase != AgentPhase.finished;

  AgentState copyWith({
    AgentPhase? phase,
    int? step,
    PendingAction? pending,
    bool clearPending = false,
    List<AgentLogEntry>? log,
    AgentRunResult? result,
    String? error,
  }) => AgentState(
    phase: phase ?? this.phase,
    task: task,
    step: step ?? this.step,
    pending: clearPending ? null : (pending ?? this.pending),
    log: log ?? this.log,
    result: result ?? this.result,
    error: error ?? this.error,
    standalone: standalone,
  );
}

/// Agent mode: a task in words → screenshot, DeepSeek tool call, safety
/// gate, confirmation, input → … (see [AgentLoop]). Off by default; the
/// emergency stop (chord + Esc) always works while it runs.
class AgentController extends Notifier<AgentState> {
  static const maxSteps = 25;

  AgentCancel? _cancel;
  Completer<bool>? _confirm;
  late HotkeyService _hotkeys;
  late WindowService _window;

  AppSettings get _settings => ref.read(settingsProvider);

  @override
  AgentState build() {
    _hotkeys = ref.read(hotkeyServiceProvider);
    _window = ref.read(windowServiceProvider);
    ref.onDispose(() {
      _cancel?.cancel();
      unawaited(_clearKeys());
    });
    return const AgentState();
  }

  /// Checks everything the agent needs; null when ready, else why not.
  Future<String?> preflight() async {
    final l = L10n.current;
    if (!_settings.agentEnabled) return l.agentOff;
    if (!InputService.supported) return l.agentUnsupported;
    if (!await ref.read(inputServiceProvider).hasPermission()) return l.agentNeedsAccessibility;
    if (await ref.read(screenServiceProvider).permission() == ScreenPermission.denied) {
      return l.noticeScreenPermission;
    }
    if (await resolveDeepSeekKey(ref.read(secretStoreProvider)) == null) return l.answerNeedsKey;
    return null;
  }

  Future<void> start(String task, {required Script script}) async {
    if (state.inControl || task.trim().isEmpty) return;
    final live = ref.read(liveControllerProvider).isLive;
    final problem = await preflight();
    if (problem != null) {
      state = AgentState(phase: AgentPhase.finished, task: task, error: problem, standalone: !live);
      if (!live) await _window.enterOverlay(_settings);
      return;
    }
    final settings = _settings;
    state = AgentState(phase: AgentPhase.starting, task: task, standalone: !live);
    if (!live) {
      await _window.enterOverlay(settings);
      // In a live session the live shortcut set already carries the stop.
      await _hotkeys.registerExtra(
        'agentStop',
        HotkeyService.toHotKey(settings.shortcutFor(LiveAction.agentStop)),
        stop,
      );
    }

    final key = (await resolveDeepSeekKey(ref.read(secretStoreProvider)))!;
    final client = DeepSeekClient(apiKey: key, model: settings.aiModel);
    final cancel = _cancel = AgentCancel();
    final started = DateTime.now();
    final loop = AgentLoop(
      executor: NativeAgentExecutor(
        screen: ref.read(screenServiceProvider),
        input: ref.read(inputServiceProvider),
        target: settings.screenTarget == ScreenTarget.cursorDisplay
            ? CaptureTarget.cursorDisplay
            : CaptureTarget.overlayDisplay,
      ),
      model: DeepSeekAgentModel(
        client: client,
        model: settings.visionModel,
        userData: [for (final d in script.prepDocs) '## ${d.name}\n${d.text}'].join('\n\n'),
        language: L10n.current.localeName,
      ),
      mode: settings.agentAutonomy == AgentAutonomy.auto ? AgentMode.auto : AgentMode.confirmEach,
      maxSteps: maxSteps,
      confirm: _confirmAction,
      text: const LocalizedAgentText(),
      onStep: (entry, step) {
        if (state.inControl) state = state.copyWith(log: [...state.log, entry], step: step, clearPending: true);
      },
      onThinking: (thinking) {
        if (state.inControl) {
          state = state.copyWith(phase: thinking ? AgentPhase.thinking : AgentPhase.acting, clearPending: true);
        }
      },
    );

    final result = await loop.run(task, cancel);
    client.close();
    await _clearKeys();
    _cancel = null;
    state = state.copyWith(phase: AgentPhase.finished, result: result, clearPending: true);
    await _record(script, task, result, started);
  }

  Future<bool> _confirmAction(PendingAction pending) async {
    final done = _confirm = Completer<bool>();
    state = state.copyWith(phase: AgentPhase.confirming, pending: pending);
    // Plain Enter / Esc, only while an action waits: the overlay never has
    // keyboard focus, so these are system-wide for that moment.
    await _hotkeys.registerExtra('agentRun', HotKey(key: PhysicalKeyboardKey.enter), approve);
    await _hotkeys.registerExtra('agentSkip', HotKey(key: PhysicalKeyboardKey.escape), reject);
    try {
      return await done.future;
    } finally {
      await _hotkeys.unregisterExtra('agentRun');
      await _hotkeys.unregisterExtra('agentSkip');
    }
  }

  /// Enter: run the pending action.
  void approve() {
    final c = _confirm;
    if (c != null && !c.isCompleted) c.complete(true);
  }

  /// Esc: don't run it, and end the task.
  void reject() {
    final c = _confirm;
    if (c != null && !c.isCompleted) c.complete(false);
  }

  /// The emergency stop: cancels the loop at once and lets go of every key.
  void stop() {
    _cancel?.cancel();
    reject();
    unawaited(ref.read(inputServiceProvider).releaseAll());
  }

  /// Dismisses the finished task; a standalone run gives the window back.
  Future<void> close() async {
    if (state.inControl) stop();
    final standalone = state.standalone;
    state = const AgentState();
    if (standalone) await _window.exitOverlay();
  }

  Future<void> _clearKeys() async {
    for (final id in ['agentStop', 'agentRun', 'agentSkip']) {
      await _hotkeys.unregisterExtra(id);
    }
  }

  /// Every action goes in the session record, for review in Sessions.
  Future<void> _record(Script script, String task, AgentRunResult result, DateTime started) async {
    final run = AgentRunRecord(
      task: task,
      status: result.status.name,
      summary: result.summary,
      log: [for (final e in result.log) AgentLogRecord.fromJson(e.toJson())],
    );
    final live = ref.read(liveControllerProvider.notifier);
    if (ref.read(liveControllerProvider).isLive) {
      live.recordAgentRun(run);
      return;
    }
    await ref
        .read(sessionRepositoryProvider)
        .save(
          SessionRecord(
            id: newId(),
            scriptId: script.id,
            scriptTitle: script.title,
            startedAt: started,
            endedAt: DateTime.now(),
            rehearsal: false,
            agentRuns: [run],
          ),
        );
  }
}

final agentControllerProvider = NotifierProvider<AgentController, AgentState>(AgentController.new);

/// Log lines and reasons in the interface language.
class LocalizedAgentText extends AgentText {
  const LocalizedAgentText();

  @override
  String describe(AgentAction action) {
    final l = L10n.current;
    String at(double x, double y) => '${x.round()},${y.round()}';
    return switch (action) {
      ClickAction(:final x, :final y, :final target, button: MouseButton.right) => l.agentDoRightClick(
        target,
        at(x, y),
      ),
      ClickAction(:final x, :final y, :final target, clicks: 2) => l.agentDoDoubleClick(target, at(x, y)),
      ClickAction(:final x, :final y, :final target) => l.agentDoClick(target, at(x, y)),
      MoveAction(:final x, :final y) => l.agentDoMove(at(x, y)),
      TypeTextAction(:final text, :final target) => l.agentDoType(
        text.length > 60 ? '${text.substring(0, 57)}…' : text,
        target,
      ),
      PressKeysAction(:final keys) => l.agentDoKeys(keys.join('+')),
      ScrollAction(:final dy) => dy >= 0 ? l.agentDoScrollDown : l.agentDoScrollUp,
      WaitAction(:final ms) => l.agentDoWait(ms),
      ScreenshotAction() => l.agentDoScreenshot,
      DoneAction() => l.agentDoDone,
    };
  }

  @override
  String reason(SafetyReason reason) {
    final l = L10n.current;
    return switch (reason) {
      SafetyReason.passwordField => l.agentWhyPassword,
      SafetyReason.secretField => l.agentWhySecret,
      SafetyReason.paymentField => l.agentWhyPayment,
      SafetyReason.cardNumber => l.agentWhyCard,
      SafetyReason.irreversible => l.agentWhyIrreversible,
      SafetyReason.submitKey => l.agentWhySubmitKey,
    };
  }

  @override
  String get outsideScreenshot => L10n.current.agentWhyOutside;
}

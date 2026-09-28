import 'dart:async';
import 'dart:ui' show Offset;

import 'agent_action.dart';
import 'coordinates.dart';
import 'safety.dart';

/// A screenshot as the agent sees it: an image for the model and the
/// mapping from its pixels to the real screen.
class AgentScreen {
  const AgentScreen({required this.image, required this.mapper});

  /// JPEG data URL.
  final String image;
  final CoordinateMapper mapper;
}

/// Native IO. The real one captures and injects input; tests use a fake.
abstract interface class AgentExecutor {
  Future<AgentScreen> capture();

  /// The focused control, for the password / payment rules. Null if unknown.
  Future<FocusInfo?> focusedElement();

  /// Runs [action]; [point] is its position in physical screen pixels
  /// (null for actions without one).
  Future<void> perform(AgentAction action, {Offset? point});

  /// Releases any held mouse button or key — the emergency stop calls it.
  Future<void> releaseAll();
}

class AgentToolCall {
  const AgentToolCall({required this.id, required this.name, required this.arguments});
  final String id;
  final String name;
  final String arguments;
}

/// One model reply: optional text and (at most one used) tool call.
class AgentTurn {
  const AgentTurn({this.text = '', this.call});
  final String text;
  final AgentToolCall? call;
}

/// The model side of the conversation (DeepSeek with tool calls in the
/// app). Implementations keep their own message history.
abstract interface class AgentModel {
  Future<AgentTurn> start(String task, AgentScreen screen);

  /// [result] answers the previous tool call; [screen] is the new state.
  Future<AgentTurn> next({required String result, AgentScreen? screen});
}

enum AgentOutcome { done, blocked, declined, failed, skipped }

class AgentLogEntry {
  const AgentLogEntry({required this.at, required this.action, required this.outcome, this.note = ''});
  final DateTime at;
  final String action;
  final AgentOutcome outcome;
  final String note;

  Map<String, Object?> toJson() => {
    'at': at.toIso8601String(),
    'action': action,
    'outcome': outcome.name,
    'note': note,
  };

  factory AgentLogEntry.fromJson(Map<dynamic, dynamic> j) => AgentLogEntry(
    at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
    action: j['action'] as String? ?? '',
    outcome: AgentOutcome.values.asNameMap()[j['outcome']] ?? AgentOutcome.done,
    note: j['note'] as String? ?? '',
  );
}

enum AgentStatus { completed, stopped, declined, limit, failed }

class AgentRunResult {
  const AgentRunResult({required this.status, required this.log, this.summary = '', this.steps = 0});
  final AgentStatus status;
  final String summary;
  final List<AgentLogEntry> log;
  final int steps;
}

/// An action waiting for the presenter: "Click 'Submit' at 812,440".
class PendingAction {
  const PendingAction({required this.action, required this.step, this.point, this.sensitive = false, this.reason});
  final AgentAction action;
  final int step;
  final Offset? point;
  final bool sensitive;
  final SafetyReason? reason;
}

/// The words the log is written in. English by default (the model reads
/// English); the app passes its interface language.
class AgentText {
  const AgentText();
  String describe(AgentAction action) => action.describe();
  String reason(SafetyReason reason) => reason.english;
  String get outsideScreenshot => 'outside the screenshot';
}

/// Cancelled by the emergency stop; checked between every await.
class AgentCancel {
  bool _cancelled = false;
  final _completer = Completer<void>();

  bool get isCancelled => _cancelled;

  /// Completes when cancelled — to race long waits against.
  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _completer.complete();
  }
}

class _Stopped implements Exception {
  const _Stopped();
}

/// screenshot → model (tool call) → safety gate → confirm → execute →
/// new screenshot → … until `done`, a stop, or [maxSteps] model turns.
class AgentLoop {
  AgentLoop({
    required this.executor,
    required this.model,
    required this.confirm,
    this.mode = AgentMode.confirmEach,
    this.maxSteps = 25,
    this.onStep,
    this.onThinking,
    this.text = const AgentText(),
  });

  final AgentExecutor executor;
  final AgentModel model;

  /// Resolves true to run the action, false to stop the task.
  final Future<bool> Function(PendingAction pending) confirm;
  final AgentMode mode;
  final int maxSteps;

  /// Every logged action, as it happens.
  final void Function(AgentLogEntry entry, int step)? onStep;

  /// True while waiting for the model.
  final void Function(bool thinking)? onThinking;

  /// How log lines are worded.
  final AgentText text;

  Future<AgentRunResult> run(String task, AgentCancel cancel) async {
    final log = <AgentLogEntry>[];
    var steps = 0;

    Future<T> guard<T>(Future<T> f) async {
      if (cancel.isCancelled) throw const _Stopped();
      final r = await Future.any<Object?>([f, cancel.whenCancelled.then((_) => const _Stopped())]);
      if (r is _Stopped || cancel.isCancelled) throw const _Stopped();
      return r as T;
    }

    void record(AgentAction a, AgentOutcome o, [String note = '']) {
      final e = AgentLogEntry(at: DateTime.now(), action: text.describe(a), outcome: o, note: note);
      log.add(e);
      onStep?.call(e, steps);
    }

    Future<AgentTurn> ask(Future<AgentTurn> Function() call) async {
      onThinking?.call(true);
      try {
        return await guard(call());
      } finally {
        onThinking?.call(false);
      }
    }

    try {
      var screen = await guard(executor.capture());
      var turn = await ask(() => model.start(task, screen));
      steps = 1;
      var nudged = false;

      while (true) {
        final call = turn.call;
        if (call == null) {
          // The model answered in prose; remind it once, then take it as done.
          if (nudged) {
            return AgentRunResult(status: AgentStatus.completed, summary: turn.text, log: log, steps: steps);
          }
          nudged = true;
          if (steps >= maxSteps) break;
          turn = await ask(() => model.next(result: 'Reply with exactly one tool call.', screen: null));
          steps++;
          continue;
        }

        AgentAction action;
        String result;
        try {
          action = AgentAction.parse(call.name, call.arguments);
        } on FormatException catch (e) {
          result = 'ERROR: ${e.message}. Call a tool with valid arguments.';
          if (steps >= maxSteps) break;
          turn = await ask(() => model.next(result: result));
          steps++;
          continue;
        }

        if (action is DoneAction) {
          record(action, AgentOutcome.done);
          return AgentRunResult(status: AgentStatus.completed, summary: action.summary, log: log, steps: steps);
        }

        // Map screenshot pixels to the real screen.
        Offset? point;
        final (px, py) = switch (action) {
          ClickAction(:final x, :final y) || MoveAction(:final x, :final y) => (x, y),
          ScrollAction(:final x?, :final y?) => (x, y),
          _ => (null, null),
        };
        if (px != null && py != null) {
          point = screen.mapper.toScreen(px, py);
          if (point == null) {
            record(action, AgentOutcome.failed, text.outsideScreenshot);
            result =
                'ERROR: (${px.round()}, ${py.round()}) is outside the '
                '${screen.mapper.imageWidth}×${screen.mapper.imageHeight} screenshot.';
            if (steps >= maxSteps) break;
            turn = await ask(() => model.next(result: result));
            steps++;
            continue;
          }
        }

        final focus = action is TypeTextAction ? await guard(executor.focusedElement()) : null;
        final verdict = SafetyGate.check(action, mode: mode, focus: focus);
        switch (verdict) {
          case Block(:final reason):
            record(action, AgentOutcome.blocked, text.reason(reason));
            result = 'BLOCKED: ${reason.english}. Sotto never does this. Continue without it, or call done.';
          case Confirm(:final sensitive, :final reason):
            final ok = await guard(
              confirm(PendingAction(action: action, step: steps, point: point, sensitive: sensitive, reason: reason)),
            );
            if (!ok) {
              record(action, AgentOutcome.declined);
              return AgentRunResult(status: AgentStatus.declined, log: log, steps: steps);
            }
            await guard(executor.perform(action, point: point));
            record(action, AgentOutcome.done);
            result = 'ok';
          case Allow():
            await guard(executor.perform(action, point: point));
            record(action, AgentOutcome.done);
            result = 'ok';
        }

        if (steps >= maxSteps) break;
        final fresh = await guard(executor.capture());
        screen = fresh;
        turn = await ask(() => model.next(result: result, screen: fresh));
        steps++;
      }
      return AgentRunResult(status: AgentStatus.limit, log: log, steps: steps);
    } on _Stopped {
      await executor.releaseAll();
      return AgentRunResult(status: AgentStatus.stopped, log: log, steps: steps);
    } catch (e) {
      await executor.releaseAll();
      return AgentRunResult(status: AgentStatus.failed, summary: '$e', log: log, steps: steps);
    }
  }
}

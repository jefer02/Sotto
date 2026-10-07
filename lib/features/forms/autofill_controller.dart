import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/power_service.dart';
import '../../core/platform/window_service.dart';
import '../../core/utils/skipping_ticker.dart';
import '../../data/repositories.dart';
import '../../domain/forms/autofill_watcher.dart';
import '../../domain/forms/form_model.dart';
import '../../domain/forms/question_types.dart';
import '../../l10n/l10n.dart';
import '../../services/screen/form_access.dart';
import '../live/live_controller.dart';
import '../questionnaire/questionnaire_controller.dart';

export '../../domain/forms/autofill_watcher.dart' show AutoFillStatus;

/// One answered question in the overlay log.
class AutoFillLogEntry {
  const AutoFillLogEntry({
    required this.question,
    required this.answer,
    required this.status,
    this.type = QuestionType.text,
    this.reasoning = '',
    this.note = '',
  });

  final String question;
  final String answer;
  final ItemStatus status;
  final QuestionType type;
  final String reasoning;
  final String note;
}

class AutoFillState {
  const AutoFillState({
    this.status = AutoFillStatus.off,
    this.log = const [],
    this.overlay = false,
    this.message,
    this.app = '',
    this.countdown = 0,
  });

  final AutoFillStatus status;

  /// Answers so far this session of auto-fill, oldest first.
  final List<AutoFillLogEntry> log;

  /// Outside a live session the window became the auto-fill overlay (the
  /// status bar and the log) and stays one until "Open Sotto" or Stop.
  final bool overlay;

  /// After a cycle: "Done — review and submit yourself", or why it stopped.
  final String? message;

  /// The app or website of the last cycle.
  final String app;

  /// "Fill what's on screen now" from the main window: seconds left to
  /// switch to the form.
  final int countdown;

  bool get on => status != AutoFillStatus.off;

  AutoFillState copyWith({
    AutoFillStatus? status,
    List<AutoFillLogEntry>? log,
    bool? overlay,
    String? message,
    bool clearMessage = false,
    String? app,
    int? countdown,
  }) => AutoFillState(
    status: status ?? this.status,
    log: log ?? this.log,
    overlay: overlay ?? this.overlay,
    message: clearMessage ? null : (message ?? this.message),
    app: app ?? this.app,
    countdown: countdown ?? this.countdown,
  );
}

/// Always-on auto-fill: every 1.5 s it looks at the window in front, and a
/// new questionnaire there (its questions, not their answers — see
/// [PageSignature]) gets a fill cycle through [QuestionnaireController] in
/// auto mode, which never presses Submit. One cycle at a time; a page that
/// shows up meanwhile is looked at right after. "Fill what's on screen now"
/// and chord + F go through the same controller.
///
/// While a cycle runs the accessibility tree isn't read here (the fill
/// owns it): only the window in front and its title are polled. A poll
/// still running when the next is due makes that one skip (the native side
/// reads on its own thread, so a slow page never blocks the UI); on
/// battery saver the poll slows to [pollSaver].
class AutoFillController extends Notifier<AutoFillState> {
  static const poll = Duration(milliseconds: 1500);
  static const pollSaver = Duration(seconds: 3);
  static const _powerCheck = Duration(seconds: 30);
  static const _maxLog = 200;

  final _watcher = AutoFillWatcher();
  late final _ticker = SkippingTicker(_poll, interval: poll);
  Timer? _powerTimer;
  ForegroundWindow? _cycleWindow;

  @override
  AutoFillState build() {
    ref.onDispose(_stopPolling);
    final enabled = settingsProvider.select((s) => s.formsEnabled && s.formsAutoFill);
    ref.listen(enabled, (_, on) => on ? _enable() : unawaited(_disable()));
    // On at launch: start watching once the state exists (not from inside
    // build, where it doesn't yet).
    if (ref.read(enabled)) scheduleMicrotask(_enable);
    return const AutoFillState();
  }

  void _enable() {
    if (_watcher.status != AutoFillStatus.off) return;
    _watcher.enable();
    _ticker.start();
    _powerTimer?.cancel();
    _powerTimer = Timer.periodic(_powerCheck, (_) => unawaited(_checkPower()));
    unawaited(_checkPower());
    _sync(clearMessage: true);
  }

  void _stopPolling() {
    _ticker.stop();
    _powerTimer?.cancel();
    _powerTimer = null;
  }

  Future<void> _checkPower() async {
    final saving = await ref.read(powerServiceProvider).saving();
    if (!ref.mounted) return;
    _ticker.interval = saving ? pollSaver : poll;
  }

  Future<void> _disable() async {
    if (_watcher.status == AutoFillStatus.off && !state.overlay) return;
    _stopPolling();
    if (_watcher.status == AutoFillStatus.filling) ref.read(questionnaireControllerProvider.notifier).stop();
    _watcher.disable();
    final overlay = state.overlay;
    state = const AutoFillState();
    if (overlay && !ref.read(liveControllerProvider).isLive) await ref.read(windowServiceProvider).exitOverlay();
  }

  void _sync({bool clearMessage = false}) =>
      state = state.copyWith(status: _watcher.status, clearMessage: clearMessage);

  // ─────────────────────────── Controls ───────────────────────────

  /// The master toggle (Forms page, Settings → Forms).
  void setEnabled(bool on) => ref
      .read(settingsProvider.notifier)
      .update((s) => s.copyWith(formsAutoFill: on, formsEnabled: on || s.formsEnabled));

  /// Pause: a running cycle finishes first.
  void pause() {
    _watcher.pause();
    _sync();
  }

  void resume() {
    _watcher.resume();
    _sync(clearMessage: true);
    unawaited(_ticker.tick());
  }

  /// Stop (after its one-second hold): auto-fill off.
  void stop() => setEnabled(false);

  /// "Stop now" and chord + Esc: nothing more is typed or clicked, and the
  /// watcher rests until Resume.
  void emergencyStop() {
    ref.read(questionnaireControllerProvider.notifier).stop();
    _watcher.emergencyStop();
    _sync();
  }

  /// The overlay's "Open Sotto": back to the main window, still watching.
  Future<void> openMainWindow() async {
    if (!state.overlay) return;
    state = state.copyWith(overlay: false);
    if (!ref.read(liveControllerProvider).isLive) {
      final q = ref.read(questionnaireControllerProvider);
      if (q.active && !q.inControl) await ref.read(questionnaireControllerProvider.notifier).close();
      await ref.read(windowServiceProvider).exitOverlay();
    }
  }

  /// "Fill what's on screen now" / chord + F: one cycle now, whatever the
  /// watcher is doing — through the same queue, so never two at once. From
  /// the main window ([fromMainWindow]) the window becomes the overlay and
  /// counts down three seconds for the presenter to switch to the form.
  /// A manual fill asks before Submit (Enter) instead of stopping there.
  Future<void> fillNow({bool fromMainWindow = false}) async {
    if (_watcher.status == AutoFillStatus.filling || state.countdown > 0) return;
    final live = ref.read(liveControllerProvider).isLive;
    // The button on the Forms page is an explicit ask: it turns questionnaire
    // filling on (chord + F still needs the setting).
    if (fromMainWindow && !ref.read(settingsProvider).formsEnabled) {
      ref.read(settingsProvider.notifier).update((s) => s.copyWith(formsEnabled: true));
    }
    if (fromMainWindow && !live) {
      await _showOverlay();
      for (var s = 3; s > 0; s--) {
        state = state.copyWith(countdown: s, clearMessage: true);
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      state = state.copyWith(countdown: 0);
    }
    final w = await ref.read(formAccessProvider).foreground();
    if (w == null || w.own) {
      state = state.copyWith(message: L10n.current.formsNoWindow);
      return;
    }
    if (!_watcher.startManual(await _key(w))) return;
    await _cycle(w, auto: false);
  }

  Future<void> _showOverlay() async {
    if (state.overlay || ref.read(liveControllerProvider).isLive) return;
    state = state.copyWith(overlay: true);
    await ref
        .read(windowServiceProvider)
        .enterOverlay(ref.read(settingsProvider), height: QuestionnaireController.panelHeight);
  }

  // ─────────────────────────── Watching ───────────────────────────

  Future<String> _key(ForegroundWindow w) async {
    var fields = const <FormField>[];
    try {
      fields = (await ref.read(formAccessProvider).snapshot()).fields;
    } on FormAccessException {
      // Unreadable: the window and its title stand in.
    }
    return PageSignature.of(w, fields);
  }

  /// One tick of [_ticker] — never two at once.
  Future<void> _poll() async {
    final status = _watcher.status;
    if (status == AutoFillStatus.off || status == AutoFillStatus.paused) return;
    final forms = ref.read(formAccessProvider);
    final w = await forms.foreground();
    if (w == null || w.own || !ref.mounted) return;
    if (status == AutoFillStatus.filling) {
      // Another window, or the page changed title, while filling: queue a look.
      final c = _cycleWindow;
      if (c != null && (w.id != c.id || w.title != c.title)) {
        _watcher.observe(w, 'w:${w.id}|${w.title}', eligible: true);
      }
      return;
    }
    var fields = const <FormField>[];
    try {
      fields = (await forms.snapshot()).fields;
    } on FormAccessException {
      // Unreadable: the window and its title stand in.
    }
    if (!ref.mounted) return;
    final eligible = fields.any((f) => !f.sensitive) || w.mayShowQuestions;
    final decision = _watcher.observe(w, PageSignature.of(w, fields), eligible: eligible);
    if (decision == WatchDecision.start) unawaited(_cycle(w));
    _sync();
  }

  Future<void> _cycle(ForegroundWindow w, {bool auto = true}) async {
    _cycleWindow = w;
    state = state.copyWith(status: AutoFillStatus.filling, app: w.pageName, clearMessage: true);
    await _showOverlay();
    final q = ref.read(questionnaireControllerProvider.notifier);
    var outcome = 'failed';
    try {
      outcome = await q.start(auto: auto, managed: true, app: w.pageName);
    } catch (e) {
      state = state.copyWith(message: '$e');
    }
    final qs = ref.read(questionnaireControllerProvider);
    final l = L10n.current;
    state = state.copyWith(
      log: [
        ...state.log,
        for (final i in qs.items)
          if (i.status != ItemStatus.pending && i.status != ItemStatus.filling)
            AutoFillLogEntry(
              question: i.question,
              answer: i.answer,
              status: i.status,
              type: i.type,
              reasoning: i.reasoning,
              note: i.note,
            ),
      ].reversed.take(_maxLog).toList().reversed.toList(),
      message: switch (outcome) {
        'ready' || 'submitted' => l.autofillDone,
        'stopped' => l.formsStopped,
        'failed' => qs.error ?? l.formsFailed,
        _ => null,
      },
    );
    _cycleWindow = null;
    // The page the cycle ended on is handled (it may be a later page).
    String? end;
    try {
      final now = await ref.read(formAccessProvider).foreground();
      if (now != null && !now.own) end = await _key(now);
    } catch (_) {}
    final recheck = _watcher.cycleFinished(end);
    _sync();
    if (recheck) unawaited(_ticker.tick());
  }
}

final autoFillControllerProvider = NotifierProvider<AutoFillController, AutoFillState>(AutoFillController.new);

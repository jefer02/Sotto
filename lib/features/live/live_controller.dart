import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/typography.dart';
import '../../core/platform/hotkey_service.dart';
import '../../core/platform/window_service.dart';
import '../../core/utils/ids.dart';
import '../../data/models/qa_entry.dart';
import '../../data/models/script.dart';
import '../../data/models/session_record.dart';
import '../../data/models/settings.dart';
import '../../data/models/shortcut.dart';
import '../../data/repositories.dart';
import '../../data/storage/secret_store.dart';
import '../../domain/following/follow_engine.dart';
import '../../domain/following/script_aligner.dart';
import '../../domain/structuring/script_structurer.dart';
import '../../services/ai/answer_service.dart';
import '../../services/ai/llm_client.dart';
import '../../services/speech/model_manager.dart';
import '../../services/speech/speech_session.dart';
import '../../services/tts/tts_service.dart';
import '../../l10n/l10n.dart';
import 'live_state.dart';

/// Called when a session ends, with the ended session's record.
typedef SessionEnded = void Function(SessionRecord record);

class LiveController extends Notifier<LiveState> {
  SpeechSession? _speech;
  FollowEngine? _engine;
  LlmClient? _llm;
  final _subs = <StreamSubscription<dynamic>>[];
  StreamSubscription<AnswerDraft>? _draftSub;
  Timer? _clock;
  Timer? _timedAdvance;
  Timer? _sendTimer;
  Timer? _noticeTimer;
  DateTime? _sectionEnteredAt;
  int _lastSection = 0;
  int _questionCount = 0;
  SessionEnded? onEnded;

  // Captured in build: teardown also runs from onDispose, where providers
  // can't be read.
  late WindowService _window;
  late HotkeyService _hotkeys;
  late TtsService _tts;

  AppSettings get _settings => ref.read(settingsProvider);

  @override
  LiveState build() {
    _window = ref.read(windowServiceProvider);
    _hotkeys = ref.read(hotkeyServiceProvider);
    _tts = ref.read(ttsProvider);
    ref.onDispose(_teardown);
    // Reconfigure following when settings change mid-session.
    ref.listen(settingsProvider, (_, next) => _engine?.configure(next));
    return LiveState(readingSize: ref.read(settingsProvider).readingSize);
  }

  // ───────────────────────────── Lifecycle ─────────────────────────────

  /// Idle-time shortcuts: ⌃⌥L works from anywhere to start from pre-flight.
  Future<void> registerIdleHotkeys(VoidCallback openPreflight) async {
    if (state.isLive) return;
    await _hotkeys.registerAll(_settings, {LiveAction.goLive: (onDown: openPreflight, onUp: null)});
  }

  Future<void> start(Script script, {int startSection = 0, bool rehearsal = false}) async {
    if (state.isLive) return;
    final flat = FlatScript.from(script, language: _settings.language);
    if (flat.length == 0) return;
    final startBeat = startSection < flat.sectionFirstBeat.length ? flat.sectionFirstBeat[startSection] : 0;

    final settings = _settings;
    _questionCount = 0;
    _engine = FollowEngine(flat, settings: settings)..jumpTo(startBeat);
    state = LiveState(
      phase: LivePhase.starting,
      script: script,
      flat: flat,
      sessionId: newId(),
      rehearsal: rehearsal,
      position: _engine!.position,
      readingSize: settings.readingSize,
    );

    await _window.enterOverlay(settings);
    await _registerLiveHotkeys();

    if (settings.advanceMode != AdvanceMode.manual) {
      try {
        final hints = script.hintWords.isNotEmpty ? script.hintWords : ScriptStructurer.hintWordsFor(script.sections);
        _speech = await SpeechSession.start(
          settings: settings,
          secrets: ref.read(secretStoreProvider),
          models: ref.read(modelManagerProvider),
          hints: hints,
        );
        _subs.add(_speech!.heard.listen(_onHeard));
        _subs.add(
          _speech!.level.listen((l) {
            if ((l - state.voiceLevel).abs() > 0.04) state = state.copyWith(voiceLevel: l);
          }),
        );
        final report = _speech!.report;
        state = state.copyWith(
          engine: report,
          manualMode: !report.canFollow && settings.advanceMode == AdvanceMode.voice,
        );
        if (report.warning != null) _notice(report.warning!, seconds: 8);
      } catch (e) {
        state = state.copyWith(manualMode: true);
        // StateError's toString adds "Bad state:"; show just the message.
        _notice(e is StateError ? e.message : '$e', seconds: 8);
      }
    } else {
      state = state.copyWith(manualMode: true);
    }

    // Standby: armed at the first beat; the clock starts on the first words
    // (or the first manual advance).
    state = state.copyWith(phase: LivePhase.standby);
    _sectionEnteredAt = DateTime.now();
    _lastSection = state.sectionIndex;
    if (state.manualMode || settings.advanceMode == AdvanceMode.timed) _beginReading();
  }

  void _beginReading() {
    if (state.phase != LivePhase.standby) return;
    final now = DateTime.now();
    state = state.copyWith(phase: LivePhase.reading, startedAt: now);
    _sectionEnteredAt = now;
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      final started = state.startedAt;
      if (started != null) state = state.copyWith(elapsed: DateTime.now().difference(started));
    });
    if (_settings.advanceMode == AdvanceMode.timed) _scheduleTimedAdvance();
  }

  Future<SessionRecord?> end() async {
    if (!state.isLive) return null;
    _accumulateSection();
    final s = state;
    final record = SessionRecord(
      id: s.sessionId ?? newId(),
      scriptId: s.script!.id,
      scriptTitle: s.script!.title,
      startedAt: s.startedAt ?? DateTime.now(),
      endedAt: DateTime.now(),
      rehearsal: s.rehearsal,
      sectionSeconds: {
        for (final e in s.sectionSeconds.entries)
          if (e.key.isNotEmpty) e.key: e.value,
      },
      wordsSpoken: s.wordsSpoken,
      questionCount: _questionCount,
      plannedSeconds: s.plannedSeconds(_settings.wordsPerMinute),
    );
    await _teardown();
    state = LiveState(readingSize: _settings.readingSize);

    await ref.read(sessionRepositoryProvider).save(record);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    if (record.rehearsal) {
      final repo = ref.read(scriptRepositoryProvider);
      final script = repo.get(record.scriptId);
      if (script != null) {
        await repo.save(script.copyWith(rehearsalCount: script.rehearsalCount + 1, updatedAt: script.updatedAt));
      }
    }
    // Calibrate "your pace" from real runs of at least a minute.
    final wpm = record.wordsPerMinute;
    if (wpm != null && record.durationSeconds >= 60 && wpm > 60 && wpm < 260) {
      settingsNotifier.update((st) {
        final samples = [...st.paceSamples, wpm];
        final recent = samples.length > 6 ? samples.sublist(samples.length - 6) : samples;
        final avg = (recent.reduce((a, b) => a + b) / recent.length).round();
        return st.copyWith(paceSamples: recent, wordsPerMinute: avg);
      });
    }
    unawaited(ref.read(qaRepositoryProvider).prune(_settings.historyRetentionDays));
    onEnded?.call(record);
    return record;
  }

  /// Every step runs even if an earlier one fails: whatever breaks, the
  /// presenter must get their normal window back.
  Future<void> _teardown() async {
    _clock?.cancel();
    _timedAdvance?.cancel();
    _sendTimer?.cancel();
    _noticeTimer?.cancel();
    final draft = _draftSub;
    final subs = [..._subs];
    final speech = _speech;
    _draftSub = null;
    _subs.clear();
    _speech = null;
    _llm?.close();
    _llm = null;
    _engine = null;
    final tts = _tts;
    for (final step in <Future<void> Function()>[
      () async => draft?.cancel(),
      () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
      () async => speech?.dispose(),
      tts.stop,
      _hotkeys.unregisterAll,
      _window.exitOverlay,
    ]) {
      try {
        await step();
      } catch (e) {
        debugPrint('live teardown step failed: $e');
      }
    }
  }

  Future<void> _registerLiveHotkeys() async {
    final failures = await _hotkeys.registerAll(_settings, {
      LiveAction.goLive: (onDown: () => unawaited(end()), onUp: null),
      LiveAction.pauseResume: (onDown: togglePause, onUp: null),
      LiveAction.nextBeat: (onDown: nextBeat, onUp: null),
      LiveAction.previousBeat: (onDown: previousBeat, onUp: null),
      LiveAction.nextSection: (onDown: nextSection, onUp: null),
      LiveAction.previousSection: (onDown: previousSection, onUp: null),
      LiveAction.ask: (onDown: askDown, onUp: askUp),
      LiveAction.sendToChat: (onDown: sendDown, onUp: sendUp),
      LiveAction.readAloud: (onDown: readAloud, onUp: null),
      LiveAction.dismiss: (onDown: dismiss, onUp: null),
      LiveAction.history: (onDown: toggleHistory, onUp: null),
      LiveAction.hide: (onDown: toggleHidden, onUp: null),
      LiveAction.clickThrough: (onDown: toggleClickThrough, onUp: null),
      LiveAction.textBigger: (onDown: () => textSize(1), onUp: null),
      LiveAction.textSmaller: (onDown: () => textSize(-1), onUp: null),
      LiveAction.moveDisplay: (onDown: moveDisplay, onUp: null),
    });
    if (failures.isNotEmpty) {
      _notice(L10n.current.noticeShortcutsTaken(failures.length));
    }
  }

  void _notice(String text, {int seconds = 4}) {
    _noticeTimer?.cancel();
    state = state.copyWith(notice: text);
    _noticeTimer = Timer(Duration(seconds: seconds), () {
      if (state.isLive) state = state.copyWith(clearNotice: true);
    });
  }

  // ───────────────────────────── Following ─────────────────────────────

  void _onHeard(String text) {
    final engine = _engine;
    if (engine == null) return;
    if (state.phase == LivePhase.standby && text.trim().isNotEmpty) _beginReading();
    if (state.phase != LivePhase.reading || _settings.advanceMode != AdvanceMode.voice) return;

    final before = engine.position;
    final event = engine.onHeard(text);
    if (event == FollowEvent.none) return;
    final after = engine.position;
    var spoken = state.wordsSpoken;
    if (after.beat != before.beat) {
      spoken += state.flat!.beats[before.beat].displayWords.length;
    }
    state = state.copyWith(
      position: after,
      wordsSpoken: spoken,
      lastAdvanceAt: event == FollowEvent.advanced || event == FollowEvent.jumped ? DateTime.now() : null,
    );
    _trackSection();
  }

  void _moveTo(int beat, {bool suspend = false}) {
    final engine = _engine;
    final flat = state.flat;
    if (engine == null || flat == null) return;
    if (state.phase == LivePhase.standby) _beginReading();
    final target = beat.clamp(0, flat.length - 1);
    if (target > state.position.beat) {
      var spoken = state.wordsSpoken;
      for (var i = state.position.beat; i < target; i++) {
        spoken += flat.beats[i].displayWords.length;
      }
      state = state.copyWith(wordsSpoken: spoken);
    }
    engine.jumpTo(target, suspend: suspend);
    state = state.copyWith(position: engine.position, lastAdvanceAt: DateTime.now());
    _trackSection();
    if (_settings.advanceMode == AdvanceMode.timed) _scheduleTimedAdvance();
  }

  void nextBeat() {
    if (!_canNavigate) return;
    _moveTo(state.position.beat + 1);
  }

  void previousBeat() {
    if (!_canNavigate) return;
    _moveTo(state.position.beat - 1, suspend: true);
  }

  void nextSection() {
    if (!_canNavigate || _engine == null) return;
    _moveTo(_engine!.nextSectionBeat());
  }

  void previousSection() {
    if (!_canNavigate || _engine == null) return;
    _moveTo(_engine!.previousSectionBeat(), suspend: true);
  }

  void jumpToBeat(int beat) {
    if (!_canNavigate) return;
    _moveTo(beat, suspend: beat < state.position.beat);
  }

  /// Hotkeys still move while paused; they wait during Q&A.
  bool get _canNavigate =>
      state.phase == LivePhase.reading || state.phase == LivePhase.paused || state.phase == LivePhase.standby;

  void togglePause() {
    switch (state.phase) {
      case LivePhase.reading || LivePhase.standby:
        _timedAdvance?.cancel();
        state = state.copyWith(phase: LivePhase.paused);
      case LivePhase.paused:
        _engine?.resetClock();
        state = state.copyWith(phase: state.startedAt == null ? LivePhase.standby : LivePhase.reading);
        if (_settings.advanceMode == AdvanceMode.timed) _scheduleTimedAdvance();
      default:
        break;
    }
  }

  void _scheduleTimedAdvance() {
    _timedAdvance?.cancel();
    final flat = state.flat;
    if (flat == null || state.phase != LivePhase.reading) return;
    final words = flat.beats[state.position.beat].displayWords.length;
    final ms = (words * 60000 / _settings.wordsPerMinute).round().clamp(1200, 30000);
    _timedAdvance = Timer(Duration(milliseconds: ms), () {
      if (state.phase == LivePhase.reading && state.position.beat < flat.length - 1) {
        _moveTo(state.position.beat + 1);
      }
    });
  }

  void _trackSection() {
    final s = state.sectionIndex;
    if (s != _lastSection) {
      _accumulateSection();
      _lastSection = s;
      _sectionEnteredAt = DateTime.now();
    }
  }

  void _accumulateSection() {
    final script = state.script;
    final entered = _sectionEnteredAt;
    if (script == null || entered == null || state.startedAt == null) return;
    if (_lastSection >= script.sections.length) return;
    final id = script.sections[_lastSection].id;
    final secs = DateTime.now().difference(entered).inSeconds;
    state = state.copyWith(sectionSeconds: {...state.sectionSeconds, id: (state.sectionSeconds[id] ?? 0) + secs});
    _sectionEnteredAt = DateTime.now();
  }

  // ───────────────────────────── Q&A ─────────────────────────────

  void askDown() {
    if (_settings.captureMode == CaptureMode.hold) {
      unawaited(_startListening());
    } else if (state.phase == LivePhase.listening) {
      unawaited(finishQuestion());
    } else {
      unawaited(_startListening());
    }
  }

  void askUp() {
    if (_settings.captureMode == CaptureMode.hold && state.phase == LivePhase.listening) {
      unawaited(finishQuestion());
    }
  }

  Future<void> _startListening() async {
    final speech = _speech;
    if (speech == null) {
      _notice(L10n.current.noticeNoSpeechForQuestions);
      return;
    }
    if (state.phase == LivePhase.listening || state.phase == LivePhase.drafting) return;
    final resume = switch (state.phase) {
      LivePhase.paused => LivePhase.paused,
      LivePhase.standby => LivePhase.standby,
      LivePhase.answer => state.resumePhase,
      _ => LivePhase.reading,
    };
    await _draftSub?.cancel();
    _timedAdvance?.cancel();
    await _tts.stop();
    state = state.copyWith(
      phase: LivePhase.listening,
      resumePhase: resume,
      clearAnswer: true,
      question: const QuestionProgress(text: '', silence: 0, elapsed: Duration.zero),
      historyOpen: false,
    );
    await speech.beginQuestion();
    _subs.add(
      speech.questionProgress.listen((p) {
        if (state.phase == LivePhase.listening) state = state.copyWith(question: p);
      }),
    );
    if (_settings.captureMode == CaptureMode.toggle) {
      late final StreamSubscription<void> silenceSub;
      silenceSub = speech.questionSilence.listen((_) {
        silenceSub.cancel();
        if (state.phase == LivePhase.listening) unawaited(finishQuestion());
      });
      _subs.add(silenceSub);
    }
  }

  Future<void> cancelQuestion() async {
    if (state.phase != LivePhase.listening) return;
    await _speech?.cancelQuestion();
    _resume();
  }

  Future<void> finishQuestion() async {
    final speech = _speech;
    if (speech == null || state.phase != LivePhase.listening) return;
    final live = state.question?.text ?? '';
    state = state.copyWith(phase: LivePhase.drafting, questionText: live, clearQuestion: true);
    final question = (await speech.endQuestion()).trim();
    if (question.split(' ').length < 2) {
      _notice(L10n.current.noticeNoQuestion);
      _resume();
      return;
    }
    await _answer(question);
  }

  Future<void> _answer(String question) async {
    final script = state.script!;
    final settings = _settings;
    final started = DateTime.now();
    state = state.copyWith(phase: LivePhase.drafting, questionText: question, draftStartedAt: started);

    // Pre-drafted answers from Q&A prep appear instantly.
    if (settings.predraft) {
      final hit = AnswerService.matchPredrafted(script, question);
      if (hit != null) {
        _completeAnswer(question, hit, started);
        return;
      }
    }

    final llm = await _client();
    if (llm == null) {
      state = state.copyWith(
        phase: LivePhase.answer,
        answerError: L10n.current.answerNeedsKey,
      );
      return;
    }
    final service = AnswerService(llm);
    _draftSub = service
        .draft(script: script, question: question, settings: settings, currentSection: state.sectionIndex)
        .listen(
          (d) {
            if (!state.isLive) return;
            if (d.complete) {
              _completeAnswer(question, d, started);
            } else if (d.headline.isNotEmpty) {
              state = state.copyWith(phase: LivePhase.answer, draft: d);
            } else {
              state = state.copyWith(draft: d);
            }
          },
          onError: (Object e) {
            if (!state.isLive) return;
            state = state.copyWith(phase: LivePhase.answer, answerError: e is LlmException ? e.message : '$e');
          },
        );
  }

  void _completeAnswer(String question, AnswerDraft d, DateTime started) {
    final millis = DateTime.now().difference(started).inMilliseconds;
    final entry = QaEntry(
      id: newId(),
      scriptId: state.script!.id,
      sessionId: state.sessionId,
      askedAt: started,
      question: question,
      headline: d.headline,
      points: d.points,
      sources: d.sources,
      grounded: d.grounded,
      draftMillis: millis,
      sessionElapsedSeconds: state.elapsed.inSeconds,
      predrafted: d.predrafted,
    );
    unawaited(ref.read(qaRepositoryProvider).save(entry));
    _questionCount++;
    state = state.copyWith(phase: LivePhase.answer, draft: d, draftMillis: millis, currentQa: entry);
  }

  Future<LlmClient?> _client() async {
    if (_llm != null) return _llm;
    final s = _settings;
    final secrets = ref.read(secretStoreProvider);
    final key = await secrets.read(switch (s.aiProvider) {
      AiProvider.anthropic => SecretKey.anthropicApiKey,
      AiProvider.openai => SecretKey.openaiApiKey,
      AiProvider.openaiCompatible => SecretKey.compatibleApiKey,
    });
    if (key == null && s.aiProvider != AiProvider.openaiCompatible) return null;
    return _llm = LlmClient.create(s, key ?? '');
  }

  /// Returns to the script at the exact word, with a sweep to re-anchor.
  void dismiss() {
    if (state.phase == LivePhase.listening) {
      unawaited(cancelQuestion());
      return;
    }
    if (state.phase != LivePhase.answer && state.phase != LivePhase.drafting) return;
    unawaited(_draftSub?.cancel());
    _draftSub = null;
    final qa = state.currentQa;
    if (qa != null && qa.outcome == AnswerOutcome.shown) {
      unawaited(ref.read(qaRepositoryProvider).save(qa.copyWith(outcome: AnswerOutcome.dismissed)));
    }
    unawaited(_tts.stop());
    _resume();
  }

  void _resume() {
    _engine?.resetClock();
    state = state.copyWith(
      phase: state.resumePhase,
      clearAnswer: true,
      clearQuestion: true,
      resumedAt: DateTime.now(),
      sendHold: 0,
    );
    if (state.phase == LivePhase.reading && _settings.advanceMode == AdvanceMode.timed) _scheduleTimedAdvance();
  }

  /// Posting to the audience is irreversible, so it takes a 500 ms hold.
  void sendDown() {
    if (state.phase != LivePhase.answer || state.draft?.complete != true) return;
    _sendTimer?.cancel();
    final start = DateTime.now();
    _sendTimer = Timer.periodic(const Duration(milliseconds: 16), (t) {
      final p = DateTime.now().difference(start).inMilliseconds / 500;
      if (p >= 1) {
        t.cancel();
        state = state.copyWith(sendHold: 0);
        unawaited(_sendToChat());
      } else {
        state = state.copyWith(sendHold: p);
      }
    });
  }

  void sendUp() {
    // Released early: nothing happens.
    if (_sendTimer?.isActive ?? false) {
      _sendTimer!.cancel();
      state = state.copyWith(sendHold: 0);
    }
  }

  /// Local-only build: "send" places the answer on the clipboard, ready to
  /// paste into the meeting chat. The button says so ("Copy for chat").
  Future<void> _sendToChat() async {
    final qa = state.currentQa;
    if (qa == null) return;
    await Clipboard.setData(ClipboardData(text: qa.plainAnswer));
    final updated = qa.copyWith(outcome: AnswerOutcome.sentToChat);
    await ref.read(qaRepositoryProvider).save(updated);
    state = state.copyWith(currentQa: updated);
    _notice(L10n.current.noticeCopiedForChat);
  }

  Future<void> copyCurrent() async {
    final qa = state.currentQa;
    if (qa == null) return;
    await Clipboard.setData(ClipboardData(text: qa.plainAnswer));
    _notice(L10n.current.noticeAnswerCopied);
  }

  Future<void> copyEntry(QaEntry e) async {
    await Clipboard.setData(ClipboardData(text: e.plainAnswer));
    _notice(L10n.current.noticeAnswerCopied);
  }

  Future<void> readAloud() async {
    final qa = state.currentQa;
    if (state.phase != LivePhase.answer || qa == null) return;
    final tts = _tts;
    if (tts.isSpeaking) {
      await tts.stop();
      return;
    }
    final updated = qa.copyWith(outcome: AnswerOutcome.readAloud);
    unawaited(ref.read(qaRepositoryProvider).save(updated));
    state = state.copyWith(currentQa: updated);
    await tts.speak(
      [qa.headline, for (final p in qa.points) p.text].join('. '),
      language: _settings.language,
      voice: _settings.ttsVoice,
    );
  }

  /// Regenerate: ask again with the same question.
  Future<void> redraft() async {
    final q = state.questionText;
    if (q == null || state.phase != LivePhase.answer) return;
    await _draftSub?.cancel();
    state = state.copyWith(clearAnswer: true, phase: LivePhase.drafting, questionText: q);
    final llm = await _client();
    if (llm == null) return;
    await _answer(q);
  }

  void showAgain(QaEntry e) {
    state = state.copyWith(
      phase: LivePhase.answer,
      resumePhase: state.phase == LivePhase.answer ? state.resumePhase : _resumableFrom(state.phase),
      questionText: e.question,
      draft: AnswerDraft(
        sources: e.sources,
        headline: e.headline,
        points: e.points,
        grounded: e.grounded,
        complete: true,
      ),
      draftMillis: e.draftMillis,
      currentQa: e,
      historyOpen: false,
    );
  }

  LivePhase _resumableFrom(LivePhase p) => p == LivePhase.paused || p == LivePhase.standby ? p : LivePhase.reading;

  // ───────────────────────────── Overlay ─────────────────────────────

  void toggleHistory() => state = state.copyWith(historyOpen: !state.historyOpen);

  Future<void> toggleHidden() async {
    await _window.toggleHidden();
    state = state.copyWith(hidden: _window.isHidden);
  }

  Future<void> toggleClickThrough() async {
    await _window.setClickThrough(!_window.isClickThrough);
    state = state.copyWith(clickThrough: _window.isClickThrough);
  }

  void textSize(int delta) {
    final i = (state.readingSize.index + delta).clamp(0, ReadingSize.values.length - 1);
    final size = ReadingSize.values[i];
    state = state.copyWith(readingSize: size);
    ref.read(settingsProvider.notifier).update((s) => s.copyWith(readingSize: size));
  }

  Future<void> moveDisplay() async {
    final settings = _settings;
    await _window.moveToNextDisplay(settings);
  }

  /// Remembers the overlay's geometry after the user drags or resizes it.
  Future<void> rememberGeometry() async {
    final b = await _window.bounds();
    final display = _window.displayId;
    ref
        .read(settingsProvider.notifier)
        .update(
          (s) => s.copyWith(
            overlaySize: state.phase == LivePhase.answer ? s.overlaySize : (b.width, b.height),
            overlayPositions: display == null || !s.rememberPositionPerDisplay
                ? s.overlayPositions
                : {...s.overlayPositions, display: (b.left, b.top)},
          ),
        );
  }
}

final liveControllerProvider = NotifierProvider<LiveController, LiveState>(LiveController.new);

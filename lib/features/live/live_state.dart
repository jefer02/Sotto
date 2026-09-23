import '../../core/design/typography.dart';
import '../../data/models/qa_entry.dart';
import '../../data/models/script.dart';
import '../../domain/following/follow_engine.dart';
import '../../domain/following/script_aligner.dart';
import '../../services/ai/answer_service.dart';
import '../../services/speech/speech_session.dart';

/// Overlay states from the Screen architecture board:
/// Standby → Reading ⇄ Paused; ⌃⌥Q → Listening → Drafting → Answer →
/// (dismiss) back where you were.
enum LivePhase { idle, starting, standby, reading, paused, listening, drafting, answer }

enum PaceStatus { onPace, ahead, behind, holding }

class LiveState {
  const LiveState({
    this.phase = LivePhase.idle,
    this.script,
    this.flat,
    this.sessionId,
    this.rehearsal = false,
    this.position = FollowPosition.start,
    this.startedAt,
    this.elapsed = Duration.zero,
    this.resumePhase = LivePhase.reading,
    this.voiceLevel = 0,
    this.question,
    this.questionText,
    this.draft,
    this.draftStartedAt,
    this.draftMillis,
    this.answerError,
    this.currentQa,
    this.historyOpen = false,
    this.readingSize = ReadingSize.m,
    this.engine,
    this.notice,
    this.hidden = false,
    this.clickThrough = false,
    this.lastAdvanceAt,
    this.resumedAt,
    this.sendHold = 0,
    this.sectionSeconds = const {},
    this.wordsSpoken = 0,
    this.manualMode = false,
  });

  final LivePhase phase;
  final Script? script;
  final FlatScript? flat;
  final String? sessionId;
  final bool rehearsal;
  final FollowPosition position;
  final DateTime? startedAt;
  final Duration elapsed;

  /// Where Dismiss returns to (Reading or Paused).
  final LivePhase resumePhase;

  /// Presenter's mic level (0..1), for the voice glyph.
  final double voiceLevel;

  /// Live progress while a question is being captured.
  final QuestionProgress? question;

  /// Final transcript of the question being answered.
  final String? questionText;
  final AnswerDraft? draft;
  final DateTime? draftStartedAt;
  final int? draftMillis;
  final String? answerError;
  final QaEntry? currentQa;
  final bool historyOpen;
  final ReadingSize readingSize;
  final EngineReport? engine;

  /// A transient line in the meta strip ("Hotkeys only — no speech engine").
  final String? notice;
  final bool hidden;
  final bool clickThrough;

  /// Drives the cue-dot pulse, which plays on advance only.
  final DateTime? lastAdvanceAt;

  /// Drives the 300 ms tungsten sweep that re-anchors the eye after Dismiss.
  final DateTime? resumedAt;

  /// Hold-to-send ring progress, 0..1.
  final double sendHold;
  final Map<String, int> sectionSeconds;
  final int wordsSpoken;

  /// No speech engine: advance by hotkey or timer only.
  final bool manualMode;

  bool get isLive => phase != LivePhase.idle;

  bool get following => phase == LivePhase.reading || phase == LivePhase.standby;

  int get sectionIndex => flat == null || flat!.length == 0 ? 0 : flat!.sectionOf(position.beat);

  Section? get section => script == null || script!.sections.isEmpty ? null : script!.sections[sectionIndex];

  /// Planned total for the talk, at the presenter's pace.
  int plannedSeconds(int wpm) => script?.targetSeconds ?? script?.estimatedSeconds(wpm) ?? 0;

  /// Planned elapsed time at the start of the current beat.
  int plannedAtBeat(int wpm) {
    final f = flat;
    final s = script;
    if (f == null || s == null) return 0;
    var total = 0.0;
    for (var i = 0; i < position.beat && i < f.length; i++) {
      final sec = s.sections[f.beats[i].sectionIndex];
      final words = f.beats[i].displayWords.length;
      // Within a budgeted section, time is shared out by word count.
      total += sec.budgetSeconds != null && sec.wordCount > 0
          ? sec.budgetSeconds! * words / sec.wordCount
          : words * 60 / wpm;
    }
    return total.round();
  }

  PaceStatus pace(int wpm) {
    if (position.holding) return PaceStatus.holding;
    final delta = elapsed.inSeconds - plannedAtBeat(wpm);
    final slack = 15 + plannedSeconds(wpm) * 0.03;
    if (delta > slack) return PaceStatus.behind;
    if (delta < -slack * 2) return PaceStatus.ahead;
    return PaceStatus.onPace;
  }

  LiveState copyWith({
    LivePhase? phase,
    Script? script,
    FlatScript? flat,
    String? sessionId,
    bool? rehearsal,
    FollowPosition? position,
    DateTime? startedAt,
    Duration? elapsed,
    LivePhase? resumePhase,
    double? voiceLevel,
    QuestionProgress? question,
    bool clearQuestion = false,
    String? questionText,
    AnswerDraft? draft,
    bool clearAnswer = false,
    DateTime? draftStartedAt,
    int? draftMillis,
    String? answerError,
    QaEntry? currentQa,
    bool? historyOpen,
    ReadingSize? readingSize,
    EngineReport? engine,
    String? notice,
    bool clearNotice = false,
    bool? hidden,
    bool? clickThrough,
    DateTime? lastAdvanceAt,
    DateTime? resumedAt,
    double? sendHold,
    Map<String, int>? sectionSeconds,
    int? wordsSpoken,
    bool? manualMode,
  }) => LiveState(
    phase: phase ?? this.phase,
    script: script ?? this.script,
    flat: flat ?? this.flat,
    sessionId: sessionId ?? this.sessionId,
    rehearsal: rehearsal ?? this.rehearsal,
    position: position ?? this.position,
    startedAt: startedAt ?? this.startedAt,
    elapsed: elapsed ?? this.elapsed,
    resumePhase: resumePhase ?? this.resumePhase,
    voiceLevel: voiceLevel ?? this.voiceLevel,
    question: clearQuestion ? null : (question ?? this.question),
    questionText: clearAnswer ? null : (questionText ?? this.questionText),
    draft: clearAnswer ? null : (draft ?? this.draft),
    draftStartedAt: clearAnswer ? null : (draftStartedAt ?? this.draftStartedAt),
    draftMillis: clearAnswer ? null : (draftMillis ?? this.draftMillis),
    answerError: clearAnswer ? null : (answerError ?? this.answerError),
    currentQa: clearAnswer ? null : (currentQa ?? this.currentQa),
    historyOpen: historyOpen ?? this.historyOpen,
    readingSize: readingSize ?? this.readingSize,
    engine: engine ?? this.engine,
    notice: clearNotice ? null : (notice ?? this.notice),
    hidden: hidden ?? this.hidden,
    clickThrough: clickThrough ?? this.clickThrough,
    lastAdvanceAt: lastAdvanceAt ?? this.lastAdvanceAt,
    resumedAt: resumedAt ?? this.resumedAt,
    sendHold: sendHold ?? this.sendHold,
    sectionSeconds: sectionSeconds ?? this.sectionSeconds,
    wordsSpoken: wordsSpoken ?? this.wordsSpoken,
    manualMode: manualMode ?? this.manualMode,
  );
}

import 'package:flutter/services.dart' show PhysicalKeyboardKey;

import '../../core/design/typography.dart';
import 'shortcut.dart';

enum AppThemeMode { dark, light, auto }

/// Interface language. `system` follows the OS.
enum AppLanguage { system, en, es }

enum OverlayThemeMode { dark, light, matchApp }

/// Container-query breakpoints (Overlay — responsive sizes board).
enum OverlayLayout { auto, ticker, compact, standard, column, rail }

/// Nine-point placement grid; `topCenter` is "under the camera".
enum OverlayPlacement {
  topLeft,
  topCenter,
  topRight,
  middleLeft,
  center,
  middleRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
}

enum ScrollStyle { glide, step }

enum AdvanceMode { voice, timed, manual }

enum Sensitivity { low, medium, high }

enum Grounding { scriptOnly, scriptFirst }

enum AnswerLength { headline, headlinePlus3, detailed }

enum AnswerLanguage { sameAsQuestion, scriptLanguage }

enum AnswerTone { matchScript, conversational, formal }

enum CaptureMode { toggle, hold }

const defaultAiModel = 'deepseek-flash';

/// Every preference Sotto keeps. Secrets (API keys) are NOT stored here —
/// they live in the OS keychain, see `SecretStore`.
class AppSettings {
  const AppSettings({
    // Appearance
    this.appTheme = AppThemeMode.dark,
    this.uiLanguage = AppLanguage.system,
    this.overlayTheme = OverlayThemeMode.dark,
    this.readingSize = ReadingSize.m,
    this.linesShown = 5,
    this.overlayOpacity = 0.8,
    this.placement = OverlayPlacement.topCenter,
    this.layout = OverlayLayout.auto,
    this.rememberPositionPerDisplay = true,
    this.scrollStyle = ScrollStyle.glide,
    this.reduceMotion = false,
    this.blurBehind = true,
    this.overlaySize = const (560.0, 232.0),
    this.overlayPositions = const {},
    // Voice & following
    this.microphoneId,
    this.questionInputId,
    this.noiseSuppression = true,
    this.language = 'en-US',
    this.alsoRecognize = const [],
    this.advanceMode = AdvanceMode.voice,
    this.advanceThreshold = 0.8,
    this.sensitivity = Sensitivity.medium,
    this.holdDuringAdLib = true,
    this.allowSectionJumps = true,
    this.wordsPerMinute = 148,
    this.paceSamples = const [],
    // Answers
    this.grounding = Grounding.scriptFirst,
    this.showSources = true,
    this.answerLength = AnswerLength.headlinePlus3,
    this.answerLanguage = AnswerLanguage.sameAsQuestion,
    this.tone = AnswerTone.matchScript,
    this.captureMode = CaptureMode.toggle,
    this.silenceSeconds = 1.2,
    this.predraft = true,
    this.ttsVoice,
    // Shortcuts
    this.chord = const {ShortcutModifier.control, ShortcutModifier.alt},
    this.bindings = const {},
    // Integrations
    this.aiModel = defaultAiModel,
    // Privacy
    this.excludeFromCapture = true,
    this.historyRetentionDays = 30,
    this.onboarded = false,
    this.welcomeDone = false,
  });

  final AppThemeMode appTheme;
  final AppLanguage uiLanguage;
  final OverlayThemeMode overlayTheme;
  final ReadingSize readingSize;
  final int linesShown;
  final double overlayOpacity;
  final OverlayPlacement placement;
  final OverlayLayout layout;
  final bool rememberPositionPerDisplay;
  final ScrollStyle scrollStyle;
  final bool reduceMotion;
  final bool blurBehind;
  final (double, double) overlaySize;

  /// Last overlay position per display id, as (x, y) in logical pixels.
  final Map<String, (double, double)> overlayPositions;

  final String? microphoneId;

  /// Input used while capturing a question. Null means the microphone; a
  /// loopback device (BlackHole, "Stereo Mix") captures a call's audio.
  final String? questionInputId;
  final bool noiseSuppression;
  final String language;
  final List<String> alsoRecognize;
  final AdvanceMode advanceMode;

  /// "Move on when I have said" — fraction of a beat.
  final double advanceThreshold;
  final Sensitivity sensitivity;
  final bool holdDuringAdLib;
  final bool allowSectionJumps;
  final int wordsPerMinute;

  /// Measured wpm from recent rehearsals, newest last.
  final List<int> paceSamples;

  final Grounding grounding;
  final bool showSources;
  final AnswerLength answerLength;
  final AnswerLanguage answerLanguage;
  final AnswerTone tone;
  final CaptureMode captureMode;
  final double silenceSeconds;
  final bool predraft;
  final String? ttsVoice;

  final Set<ShortcutModifier> chord;

  /// Overrides of [LiveAction.defaultKey], by action name → USB HID usage.
  final Map<String, int> bindings;

  /// DeepSeek model id. The list comes from `GET /models`; ids have changed
  /// more than once, so nothing else in the app hardcodes them.
  final String aiModel;

  final bool excludeFromCapture;
  final int historyRetentionDays;
  final bool onboarded;

  /// The first-run welcome (models → first script) was finished or skipped.
  final bool welcomeDone;

  Shortcut shortcutFor(LiveAction action) => Shortcut(chord, bindings[action.name] ?? action.defaultKey.usbHidUsage);

  PhysicalKeyboardKey keyFor(LiveAction action) =>
      PhysicalKeyboardKey(bindings[action.name] ?? action.defaultKey.usbHidUsage);

  AppSettings copyWith({
    AppThemeMode? appTheme,
    AppLanguage? uiLanguage,
    OverlayThemeMode? overlayTheme,
    ReadingSize? readingSize,
    int? linesShown,
    double? overlayOpacity,
    OverlayPlacement? placement,
    OverlayLayout? layout,
    bool? rememberPositionPerDisplay,
    ScrollStyle? scrollStyle,
    bool? reduceMotion,
    bool? blurBehind,
    (double, double)? overlaySize,
    Map<String, (double, double)>? overlayPositions,
    String? microphoneId,
    String? questionInputId,
    bool clearQuestionInput = false,
    bool? noiseSuppression,
    String? language,
    List<String>? alsoRecognize,
    AdvanceMode? advanceMode,
    double? advanceThreshold,
    Sensitivity? sensitivity,
    bool? holdDuringAdLib,
    bool? allowSectionJumps,
    int? wordsPerMinute,
    List<int>? paceSamples,
    Grounding? grounding,
    bool? showSources,
    AnswerLength? answerLength,
    AnswerLanguage? answerLanguage,
    AnswerTone? tone,
    CaptureMode? captureMode,
    double? silenceSeconds,
    bool? predraft,
    String? ttsVoice,
    Set<ShortcutModifier>? chord,
    Map<String, int>? bindings,
    String? aiModel,
    bool? excludeFromCapture,
    int? historyRetentionDays,
    bool? onboarded,
    bool? welcomeDone,
  }) => AppSettings(
    appTheme: appTheme ?? this.appTheme,
    uiLanguage: uiLanguage ?? this.uiLanguage,
    overlayTheme: overlayTheme ?? this.overlayTheme,
    readingSize: readingSize ?? this.readingSize,
    linesShown: linesShown ?? this.linesShown,
    overlayOpacity: overlayOpacity ?? this.overlayOpacity,
    placement: placement ?? this.placement,
    layout: layout ?? this.layout,
    rememberPositionPerDisplay: rememberPositionPerDisplay ?? this.rememberPositionPerDisplay,
    scrollStyle: scrollStyle ?? this.scrollStyle,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    blurBehind: blurBehind ?? this.blurBehind,
    overlaySize: overlaySize ?? this.overlaySize,
    overlayPositions: overlayPositions ?? this.overlayPositions,
    microphoneId: microphoneId ?? this.microphoneId,
    questionInputId: clearQuestionInput ? null : (questionInputId ?? this.questionInputId),
    noiseSuppression: noiseSuppression ?? this.noiseSuppression,
    language: language ?? this.language,
    alsoRecognize: alsoRecognize ?? this.alsoRecognize,
    advanceMode: advanceMode ?? this.advanceMode,
    advanceThreshold: advanceThreshold ?? this.advanceThreshold,
    sensitivity: sensitivity ?? this.sensitivity,
    holdDuringAdLib: holdDuringAdLib ?? this.holdDuringAdLib,
    allowSectionJumps: allowSectionJumps ?? this.allowSectionJumps,
    wordsPerMinute: wordsPerMinute ?? this.wordsPerMinute,
    paceSamples: paceSamples ?? this.paceSamples,
    grounding: grounding ?? this.grounding,
    showSources: showSources ?? this.showSources,
    answerLength: answerLength ?? this.answerLength,
    answerLanguage: answerLanguage ?? this.answerLanguage,
    tone: tone ?? this.tone,
    captureMode: captureMode ?? this.captureMode,
    silenceSeconds: silenceSeconds ?? this.silenceSeconds,
    predraft: predraft ?? this.predraft,
    ttsVoice: ttsVoice ?? this.ttsVoice,
    chord: chord ?? this.chord,
    bindings: bindings ?? this.bindings,
    aiModel: aiModel ?? this.aiModel,
    excludeFromCapture: excludeFromCapture ?? this.excludeFromCapture,
    historyRetentionDays: historyRetentionDays ?? this.historyRetentionDays,
    onboarded: onboarded ?? this.onboarded,
    welcomeDone: welcomeDone ?? this.welcomeDone,
  );

  Map<String, Object?> toJson() => {
    'appTheme': appTheme.name,
    'uiLanguage': uiLanguage.name,
    'overlayTheme': overlayTheme.name,
    'readingSize': readingSize.name,
    'linesShown': linesShown,
    'overlayOpacity': overlayOpacity,
    'placement': placement.name,
    'layout': layout.name,
    'rememberPositionPerDisplay': rememberPositionPerDisplay,
    'scrollStyle': scrollStyle.name,
    'reduceMotion': reduceMotion,
    'blurBehind': blurBehind,
    'overlaySize': [overlaySize.$1, overlaySize.$2],
    'overlayPositions': {
      for (final e in overlayPositions.entries) e.key: [e.value.$1, e.value.$2],
    },
    'microphoneId': microphoneId,
    'questionInputId': questionInputId,
    'noiseSuppression': noiseSuppression,
    'language': language,
    'alsoRecognize': alsoRecognize,
    'advanceMode': advanceMode.name,
    'advanceThreshold': advanceThreshold,
    'sensitivity': sensitivity.name,
    'holdDuringAdLib': holdDuringAdLib,
    'allowSectionJumps': allowSectionJumps,
    'wordsPerMinute': wordsPerMinute,
    'paceSamples': paceSamples,
    'grounding': grounding.name,
    'showSources': showSources,
    'answerLength': answerLength.name,
    'answerLanguage': answerLanguage.name,
    'tone': tone.name,
    'captureMode': captureMode.name,
    'silenceSeconds': silenceSeconds,
    'predraft': predraft,
    'ttsVoice': ttsVoice,
    'chord': chord.map((m) => m.name).toList(),
    'bindings': bindings,
    'aiModel': aiModel,
    'excludeFromCapture': excludeFromCapture,
    'historyRetentionDays': historyRetentionDays,
    'onboarded': onboarded,
    'welcomeDone': welcomeDone,
  };

  /// Tolerant of missing and unknown keys so settings survive app updates.
  factory AppSettings.fromJson(Map<dynamic, dynamic> j) {
    const d = AppSettings();
    T e<T extends Enum>(List<T> values, Object? name, T fallback) => values.asNameMap()[name] ?? fallback;
    double n(Object? v, double fallback) => (v as num?)?.toDouble() ?? fallback;
    final size = j['overlaySize'] as List?;
    return AppSettings(
      appTheme: e(AppThemeMode.values, j['appTheme'], d.appTheme),
      uiLanguage: e(AppLanguage.values, j['uiLanguage'], d.uiLanguage),
      overlayTheme: e(OverlayThemeMode.values, j['overlayTheme'], d.overlayTheme),
      readingSize: e(ReadingSize.values, j['readingSize'], d.readingSize),
      linesShown: j['linesShown'] as int? ?? d.linesShown,
      overlayOpacity: n(j['overlayOpacity'], d.overlayOpacity),
      placement: e(OverlayPlacement.values, j['placement'], d.placement),
      layout: e(OverlayLayout.values, j['layout'], d.layout),
      rememberPositionPerDisplay: j['rememberPositionPerDisplay'] as bool? ?? d.rememberPositionPerDisplay,
      scrollStyle: e(ScrollStyle.values, j['scrollStyle'], d.scrollStyle),
      reduceMotion: j['reduceMotion'] as bool? ?? d.reduceMotion,
      blurBehind: j['blurBehind'] as bool? ?? d.blurBehind,
      overlaySize: size == null ? d.overlaySize : ((size[0] as num).toDouble(), (size[1] as num).toDouble()),
      overlayPositions: {
        for (final entry in ((j['overlayPositions'] as Map?) ?? const {}).entries)
          entry.key as String: (
            ((entry.value as List)[0] as num).toDouble(),
            ((entry.value as List)[1] as num).toDouble(),
          ),
      },
      microphoneId: j['microphoneId'] as String?,
      questionInputId: j['questionInputId'] as String?,
      noiseSuppression: j['noiseSuppression'] as bool? ?? d.noiseSuppression,
      language: j['language'] as String? ?? d.language,
      alsoRecognize: [...(j['alsoRecognize'] as List? ?? const []).cast<String>()],
      advanceMode: e(AdvanceMode.values, j['advanceMode'], d.advanceMode),
      advanceThreshold: n(j['advanceThreshold'], d.advanceThreshold),
      sensitivity: e(Sensitivity.values, j['sensitivity'], d.sensitivity),
      holdDuringAdLib: j['holdDuringAdLib'] as bool? ?? d.holdDuringAdLib,
      allowSectionJumps: j['allowSectionJumps'] as bool? ?? d.allowSectionJumps,
      wordsPerMinute: j['wordsPerMinute'] as int? ?? d.wordsPerMinute,
      paceSamples: [...(j['paceSamples'] as List? ?? const []).cast<int>()],
      grounding: e(Grounding.values, j['grounding'], d.grounding),
      showSources: j['showSources'] as bool? ?? d.showSources,
      answerLength: e(AnswerLength.values, j['answerLength'], d.answerLength),
      answerLanguage: e(AnswerLanguage.values, j['answerLanguage'], d.answerLanguage),
      tone: e(AnswerTone.values, j['tone'], d.tone),
      captureMode: e(CaptureMode.values, j['captureMode'], d.captureMode),
      silenceSeconds: n(j['silenceSeconds'], d.silenceSeconds),
      predraft: j['predraft'] as bool? ?? d.predraft,
      ttsVoice: j['ttsVoice'] as String?,
      chord: {
        for (final m in (j['chord'] as List? ?? const ['control', 'alt'])) ?ShortcutModifier.values.asNameMap()[m],
      },
      bindings: {
        for (final entry in ((j['bindings'] as Map?) ?? const {}).entries) entry.key as String: entry.value as int,
      },
      // Settings saved with another provider (Anthropic, OpenAI…) migrate
      // to DeepSeek: their model ids mean nothing here.
      aiModel: switch (j['aiModel']) {
        final String m when m.startsWith('deepseek') => m,
        _ => d.aiModel,
      },
      excludeFromCapture: j['excludeFromCapture'] as bool? ?? d.excludeFromCapture,
      historyRetentionDays: j['historyRetentionDays'] as int? ?? d.historyRetentionDays,
      onboarded: j['onboarded'] as bool? ?? d.onboarded,
      welcomeDone: j['welcomeDone'] as bool? ?? d.welcomeDone,
    );
  }
}

import 'package:flutter/services.dart' show PhysicalKeyboardKey;

import '../../core/design/typography.dart';
import 'shortcut.dart';

enum AppThemeMode { dark, light, auto }

/// Interface language. `system` follows the OS.
enum AppLanguage { system, en, es }

enum OverlayThemeMode { dark, light, matchApp }

/// Text only: no background at all, glyphs carry an outline and a shadow.
/// Panel: the translucent card.
enum OverlayStyle { textOnly, panel }

/// Text-only overlay text color: [auto] follows what is behind the overlay
/// (sampled on-device every 800 ms while live), [light] and [dark] are fixed,
/// [custom] uses the chosen text and outline colors.
enum OverlayTextColor { auto, light, dark, custom }

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

/// Which display "Ask about screen" captures.
enum ScreenTarget { overlayDisplay, cursorDisplay }

/// Agent mode supervision: confirm every action, or run on its own and
/// still confirm anything that submits, sends, pays, deletes or buys.
enum AgentAutonomy { confirmEach, auto }

/// Questionnaires on screen: fill at once, or show the answers first.
enum FormFillMode { fillAutomatically, showFirst }

enum FormAnswerLanguage { sameAsForm, appLanguage }

enum FormAnswerStyle { short, detailed }

const defaultAiModel = 'deepseek-flash';

/// Every preference Sotto keeps. Secrets (API keys) are NOT stored here —
/// they live in the OS keychain, see `SecretStore`.
class AppSettings {
  const AppSettings({
    // Appearance
    this.appTheme = AppThemeMode.dark,
    this.uiLanguage = AppLanguage.system,
    this.overlayTheme = OverlayThemeMode.dark,
    this.overlayStyle = OverlayStyle.textOnly,
    this.overlayTextColor = OverlayTextColor.auto,
    this.textColor = 0xFFFFFFFF,
    this.outlineColor,
    this.outlineWidth = 2.0,
    this.shadowStrength = 0.6,
    this.readingSize = ReadingSize.m,
    this.linesShown = 5,
    this.overlayOpacity = 0.8,
    this.placement = OverlayPlacement.topCenter,
    this.layout = OverlayLayout.auto,
    this.rememberPositionPerDisplay = true,
    this.scrollStyle = ScrollStyle.glide,
    this.reduceMotion = false,
    this.blurBehind = true,
    this.overlaySize = const (480.0, 120.0),
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
    this.visionModel = defaultAiModel,
    // Privacy
    this.excludeFromCapture = true,
    this.screenAwareness = false,
    this.screenTarget = ScreenTarget.overlayDisplay,
    this.attachSlideToAnswers = false,
    this.agentEnabled = false,
    this.agentAutonomy = AgentAutonomy.confirmEach,
    this.formsEnabled = false,
    this.formsMode = FormFillMode.fillAutomatically,
    this.formsLanguage = FormAnswerLanguage.sameAsForm,
    this.formsStyle = FormAnswerStyle.short,
    this.formsInstructions = '',
    this.chatAutoSend = false,
    this.chatContextMessages = 20,
    this.historyRetentionDays = 30,
    this.onboarded = false,
    this.welcomeDone = false,
  });

  final AppThemeMode appTheme;
  final AppLanguage uiLanguage;
  final OverlayThemeMode overlayTheme;
  final OverlayStyle overlayStyle;

  final OverlayTextColor overlayTextColor;

  /// Text-only colors, as ARGB. A null outline contrasts with the text.
  final int textColor;
  final int? outlineColor;
  final double outlineWidth;
  final double shadowStrength;
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

  /// Bumped when saved overlay geometry can't be trusted any more.
  static const overlayGeometryVersion = 2;

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

  /// Model used when a request carries a screenshot: [aiModel] if it reads
  /// images, else one that does (from `GET /models`).
  final String visionModel;

  final bool excludeFromCapture;

  /// Opt-in: screenshots may be sent to DeepSeek, only when asked
  /// ("Ask about screen", or a question with [attachSlideToAnswers]).
  final bool screenAwareness;
  final ScreenTarget screenTarget;
  final bool attachSlideToAnswers;

  /// Opt-in: the agent may move the mouse and type. Off by default.
  final bool agentEnabled;
  final AgentAutonomy agentAutonomy;

  /// Opt-in: answer questionnaires on screen with the model's own knowledge
  /// (not the script) and fill them in. Off by default.
  final bool formsEnabled;
  final FormFillMode formsMode;
  final FormAnswerLanguage formsLanguage;
  final FormAnswerStyle formsStyle;

  /// Context the model may use for questionnaires (name, role…).
  final String formsInstructions;

  /// Chat: dictated text is sent at once instead of landing in the input.
  final bool chatAutoSend;

  /// Chat: how many recent messages go with each request.
  final int chatContextMessages;

  /// 0: history off — Q&A and questionnaire logs aren't kept.
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
    OverlayStyle? overlayStyle,
    OverlayTextColor? overlayTextColor,
    int? textColor,
    int? outlineColor,
    bool autoOutline = false,
    double? outlineWidth,
    double? shadowStrength,
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
    String? visionModel,
    bool? excludeFromCapture,
    bool? screenAwareness,
    ScreenTarget? screenTarget,
    bool? attachSlideToAnswers,
    bool? agentEnabled,
    AgentAutonomy? agentAutonomy,
    bool? formsEnabled,
    FormFillMode? formsMode,
    FormAnswerLanguage? formsLanguage,
    FormAnswerStyle? formsStyle,
    String? formsInstructions,
    bool? chatAutoSend,
    int? chatContextMessages,
    int? historyRetentionDays,
    bool? onboarded,
    bool? welcomeDone,
  }) => AppSettings(
    appTheme: appTheme ?? this.appTheme,
    uiLanguage: uiLanguage ?? this.uiLanguage,
    overlayTheme: overlayTheme ?? this.overlayTheme,
    overlayStyle: overlayStyle ?? this.overlayStyle,
    overlayTextColor: overlayTextColor ?? this.overlayTextColor,
    textColor: textColor ?? this.textColor,
    outlineColor: autoOutline ? null : (outlineColor ?? this.outlineColor),
    outlineWidth: outlineWidth ?? this.outlineWidth,
    shadowStrength: shadowStrength ?? this.shadowStrength,
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
    visionModel: visionModel ?? this.visionModel,
    excludeFromCapture: excludeFromCapture ?? this.excludeFromCapture,
    screenAwareness: screenAwareness ?? this.screenAwareness,
    screenTarget: screenTarget ?? this.screenTarget,
    attachSlideToAnswers: attachSlideToAnswers ?? this.attachSlideToAnswers,
    agentEnabled: agentEnabled ?? this.agentEnabled,
    agentAutonomy: agentAutonomy ?? this.agentAutonomy,
    formsEnabled: formsEnabled ?? this.formsEnabled,
    formsMode: formsMode ?? this.formsMode,
    formsLanguage: formsLanguage ?? this.formsLanguage,
    formsStyle: formsStyle ?? this.formsStyle,
    formsInstructions: formsInstructions ?? this.formsInstructions,
    chatAutoSend: chatAutoSend ?? this.chatAutoSend,
    chatContextMessages: chatContextMessages ?? this.chatContextMessages,
    historyRetentionDays: historyRetentionDays ?? this.historyRetentionDays,
    onboarded: onboarded ?? this.onboarded,
    welcomeDone: welcomeDone ?? this.welcomeDone,
  );

  Map<String, Object?> toJson() => {
    'appTheme': appTheme.name,
    'uiLanguage': uiLanguage.name,
    'overlayTheme': overlayTheme.name,
    'overlayStyle': overlayStyle.name,
    'overlayTextColor': overlayTextColor.name,
    'textColor': textColor,
    'outlineColor': outlineColor,
    'outlineWidth': outlineWidth,
    'shadowStrength': shadowStrength,
    'readingSize': readingSize.name,
    'linesShown': linesShown,
    'overlayOpacity': overlayOpacity,
    'placement': placement.name,
    'layout': layout.name,
    'rememberPositionPerDisplay': rememberPositionPerDisplay,
    'scrollStyle': scrollStyle.name,
    'reduceMotion': reduceMotion,
    'blurBehind': blurBehind,
    'overlayGeometryVersion': overlayGeometryVersion,
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
    'visionModel': visionModel,
    'excludeFromCapture': excludeFromCapture,
    'screenAwareness': screenAwareness,
    'screenTarget': screenTarget.name,
    'attachSlideToAnswers': attachSlideToAnswers,
    'agentEnabled': agentEnabled,
    'agentAutonomy': agentAutonomy.name,
    'formsEnabled': formsEnabled,
    'formsMode': formsMode.name,
    'formsLanguage': formsLanguage.name,
    'formsStyle': formsStyle.name,
    'formsInstructions': formsInstructions,
    'chatAutoSend': chatAutoSend,
    'chatContextMessages': chatContextMessages,
    'historyRetentionDays': historyRetentionDays,
    'onboarded': onboarded,
    'welcomeDone': welcomeDone,
  };

  /// Tolerant of missing and unknown keys so settings survive app updates.
  factory AppSettings.fromJson(Map<dynamic, dynamic> j) {
    const d = AppSettings();
    T e<T extends Enum>(List<T> values, Object? name, T fallback) => values.asNameMap()[name] ?? fallback;
    double n(Object? v, double fallback) => (v as num?)?.toDouble() ?? fallback;
    // Geometry saved before version 2 may hold a maximised overlay's frame
    // (the full-screen bug): start again from the default strip.
    final geometryOk = j['overlayGeometryVersion'] == overlayGeometryVersion;
    final size = geometryOk ? j['overlaySize'] as List? : null;
    return AppSettings(
      appTheme: e(AppThemeMode.values, j['appTheme'], d.appTheme),
      uiLanguage: e(AppLanguage.values, j['uiLanguage'], d.uiLanguage),
      overlayTheme: e(OverlayThemeMode.values, j['overlayTheme'], d.overlayTheme),
      overlayStyle: e(OverlayStyle.values, j['overlayStyle'], d.overlayStyle),
      // Colors picked before this setting existed stay in use.
      overlayTextColor: e(
        OverlayTextColor.values,
        j['overlayTextColor'],
        (j['textColor'] ?? d.textColor) != d.textColor || j['outlineColor'] != null
            ? OverlayTextColor.custom
            : d.overlayTextColor,
      ),
      textColor: j['textColor'] as int? ?? d.textColor,
      outlineColor: j['outlineColor'] as int?,
      outlineWidth: n(j['outlineWidth'], d.outlineWidth),
      shadowStrength: n(j['shadowStrength'], d.shadowStrength),
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
        for (final entry in ((geometryOk ? j['overlayPositions'] as Map? : null) ?? const {}).entries)
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
      visionModel: switch (j['visionModel']) {
        final String m when m.startsWith('deepseek') => m,
        _ => d.visionModel,
      },
      excludeFromCapture: j['excludeFromCapture'] as bool? ?? d.excludeFromCapture,
      screenAwareness: j['screenAwareness'] as bool? ?? d.screenAwareness,
      screenTarget: e(ScreenTarget.values, j['screenTarget'], d.screenTarget),
      attachSlideToAnswers: j['attachSlideToAnswers'] as bool? ?? d.attachSlideToAnswers,
      agentEnabled: j['agentEnabled'] as bool? ?? d.agentEnabled,
      agentAutonomy: e(AgentAutonomy.values, j['agentAutonomy'], d.agentAutonomy),
      formsEnabled: j['formsEnabled'] as bool? ?? d.formsEnabled,
      formsMode: e(FormFillMode.values, j['formsMode'], d.formsMode),
      formsLanguage: e(FormAnswerLanguage.values, j['formsLanguage'], d.formsLanguage),
      formsStyle: e(FormAnswerStyle.values, j['formsStyle'], d.formsStyle),
      formsInstructions: j['formsInstructions'] as String? ?? d.formsInstructions,
      chatAutoSend: j['chatAutoSend'] as bool? ?? d.chatAutoSend,
      chatContextMessages: j['chatContextMessages'] as int? ?? d.chatContextMessages,
      historyRetentionDays: j['historyRetentionDays'] as int? ?? d.historyRetentionDays,
      onboarded: j['onboarded'] as bool? ?? d.onboarded,
      welcomeDone: j['welcomeDone'] as bool? ?? d.welcomeDone,
    );
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en'), Locale('es')];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Sotto'**
  String get appTitle;

  /// No description provided for @statusOrganizing.
  ///
  /// In en, this message translates to:
  /// **'Organizing…'**
  String get statusOrganizing;

  /// No description provided for @statusRehearsedTimes.
  ///
  /// In en, this message translates to:
  /// **'Rehearsed ×{count}'**
  String statusRehearsedTimes(int count);

  /// No description provided for @statusRehearsed.
  ///
  /// In en, this message translates to:
  /// **'Rehearsed'**
  String get statusRehearsed;

  /// No description provided for @statusStructured.
  ///
  /// In en, this message translates to:
  /// **'Structured'**
  String get statusStructured;

  /// No description provided for @statusDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get statusDraft;

  /// No description provided for @timeJustNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get timeJustNow;

  /// No description provided for @timeMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min ago'**
  String timeMinutesAgo(int minutes);

  /// No description provided for @timeHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{hours} h ago'**
  String timeHoursAgo(int hours);

  /// No description provided for @timeEditedMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'Edited {minutes} min ago'**
  String timeEditedMinutesAgo(int minutes);

  /// No description provided for @timeEditedHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'Edited {hours} h ago'**
  String timeEditedHoursAgo(int hours);

  /// No description provided for @timeYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get timeYesterday;

  /// No description provided for @timeToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get timeToday;

  /// No description provided for @actionGoLive.
  ///
  /// In en, this message translates to:
  /// **'Go live or end session'**
  String get actionGoLive;

  /// No description provided for @actionGoLiveSub.
  ///
  /// In en, this message translates to:
  /// **'Starts from the section chosen in pre-flight'**
  String get actionGoLiveSub;

  /// No description provided for @actionPause.
  ///
  /// In en, this message translates to:
  /// **'Pause or resume following'**
  String get actionPause;

  /// No description provided for @actionPauseSub.
  ///
  /// In en, this message translates to:
  /// **'Freezes the script; your place is kept'**
  String get actionPauseSub;

  /// No description provided for @actionNextBeat.
  ///
  /// In en, this message translates to:
  /// **'Next beat'**
  String get actionNextBeat;

  /// No description provided for @actionNextBeatSub.
  ///
  /// In en, this message translates to:
  /// **'One breath forward — works while following'**
  String get actionNextBeatSub;

  /// No description provided for @actionPrevBeat.
  ///
  /// In en, this message translates to:
  /// **'Previous beat'**
  String get actionPrevBeat;

  /// No description provided for @actionPrevBeatSub.
  ///
  /// In en, this message translates to:
  /// **'Also holds following for 3 seconds'**
  String get actionPrevBeatSub;

  /// No description provided for @actionNextSection.
  ///
  /// In en, this message translates to:
  /// **'Next section'**
  String get actionNextSection;

  /// No description provided for @actionPrevSection.
  ///
  /// In en, this message translates to:
  /// **'Previous section'**
  String get actionPrevSection;

  /// No description provided for @actionAsk.
  ///
  /// In en, this message translates to:
  /// **'Ask a question'**
  String get actionAsk;

  /// No description provided for @actionAskSub.
  ///
  /// In en, this message translates to:
  /// **'Listens to the room until it goes quiet'**
  String get actionAskSub;

  /// No description provided for @actionSend.
  ///
  /// In en, this message translates to:
  /// **'Send answer to chat'**
  String get actionSend;

  /// No description provided for @actionSendSub.
  ///
  /// In en, this message translates to:
  /// **'Hold for half a second, so it can\'t fire by accident'**
  String get actionSendSub;

  /// No description provided for @actionReadAloud.
  ///
  /// In en, this message translates to:
  /// **'Read answer aloud'**
  String get actionReadAloud;

  /// No description provided for @actionReadAloudSub.
  ///
  /// In en, this message translates to:
  /// **'Plays in your headphones only'**
  String get actionReadAloudSub;

  /// No description provided for @actionDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss answer'**
  String get actionDismiss;

  /// No description provided for @actionDismissSub.
  ///
  /// In en, this message translates to:
  /// **'Returns to the script where you left it'**
  String get actionDismissSub;

  /// No description provided for @actionHistory.
  ///
  /// In en, this message translates to:
  /// **'Questions history'**
  String get actionHistory;

  /// No description provided for @actionHide.
  ///
  /// In en, this message translates to:
  /// **'Hide overlay instantly'**
  String get actionHide;

  /// No description provided for @actionHideSub.
  ///
  /// In en, this message translates to:
  /// **'No animation. Press again to bring it back.'**
  String get actionHideSub;

  /// No description provided for @actionClickThrough.
  ///
  /// In en, this message translates to:
  /// **'Click-through'**
  String get actionClickThrough;

  /// No description provided for @actionClickThroughSub.
  ///
  /// In en, this message translates to:
  /// **'The overlay stops catching the mouse'**
  String get actionClickThroughSub;

  /// No description provided for @actionTextBigger.
  ///
  /// In en, this message translates to:
  /// **'Text size up'**
  String get actionTextBigger;

  /// No description provided for @actionTextSmaller.
  ///
  /// In en, this message translates to:
  /// **'Text size down'**
  String get actionTextSmaller;

  /// No description provided for @actionMoveDisplay.
  ///
  /// In en, this message translates to:
  /// **'Move to next display'**
  String get actionMoveDisplay;

  /// No description provided for @actionMoveDisplaySub.
  ///
  /// In en, this message translates to:
  /// **'Remembers a position per display'**
  String get actionMoveDisplaySub;

  /// No description provided for @keySpace.
  ///
  /// In en, this message translates to:
  /// **'Space'**
  String get keySpace;

  /// No description provided for @modShiftShort.
  ///
  /// In en, this message translates to:
  /// **'Shift'**
  String get modShiftShort;

  /// No description provided for @modShift.
  ///
  /// In en, this message translates to:
  /// **'Shift'**
  String get modShift;

  /// No description provided for @modOption.
  ///
  /// In en, this message translates to:
  /// **'Option'**
  String get modOption;

  /// No description provided for @modCommand.
  ///
  /// In en, this message translates to:
  /// **'Command'**
  String get modCommand;

  /// No description provided for @untitledScript.
  ///
  /// In en, this message translates to:
  /// **'Untitled script'**
  String get untitledScript;

  /// No description provided for @sectionOpening.
  ///
  /// In en, this message translates to:
  /// **'Opening'**
  String get sectionOpening;

  /// No description provided for @sectionFallback.
  ///
  /// In en, this message translates to:
  /// **'Section'**
  String get sectionFallback;

  /// No description provided for @newSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'New section'**
  String get newSectionTitle;

  /// No description provided for @cueSlide.
  ///
  /// In en, this message translates to:
  /// **'SLIDE'**
  String get cueSlide;

  /// No description provided for @cuePause.
  ///
  /// In en, this message translates to:
  /// **'PAUSE'**
  String get cuePause;

  /// No description provided for @cueDemo.
  ///
  /// In en, this message translates to:
  /// **'DEMO'**
  String get cueDemo;

  /// No description provided for @cueNote.
  ///
  /// In en, this message translates to:
  /// **'NOTE'**
  String get cueNote;

  /// No description provided for @copyTitle.
  ///
  /// In en, this message translates to:
  /// **'{title} copy'**
  String copyTitle(String title);

  /// No description provided for @importUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Sotto can import .docx, .pdf, .md and .txt files.'**
  String get importUnsupported;

  /// No description provided for @importNoText.
  ///
  /// In en, this message translates to:
  /// **'{name} has no text Sotto can read.'**
  String importNoText(String name);

  /// No description provided for @importNoBody.
  ///
  /// In en, this message translates to:
  /// **'This .docx file has no document body.'**
  String get importNoBody;

  /// No description provided for @pastedScript.
  ///
  /// In en, this message translates to:
  /// **'Pasted script'**
  String get pastedScript;

  /// No description provided for @pastedText.
  ///
  /// In en, this message translates to:
  /// **'Pasted text'**
  String get pastedText;

  /// No description provided for @dialogImportScript.
  ///
  /// In en, this message translates to:
  /// **'Import a script'**
  String get dialogImportScript;

  /// No description provided for @llmRejected.
  ///
  /// In en, this message translates to:
  /// **'The request was rejected'**
  String get llmRejected;

  /// No description provided for @llmBadKey.
  ///
  /// In en, this message translates to:
  /// **'{provider} rejected the API key. Check it in Settings → Integrations.'**
  String llmBadKey(String provider);

  /// No description provided for @llmNoModel.
  ///
  /// In en, this message translates to:
  /// **'Model not found. Check the model name in Settings → Integrations.'**
  String get llmNoModel;

  /// No description provided for @llmRateLimit.
  ///
  /// In en, this message translates to:
  /// **'{provider} is rate-limiting requests. Try again in a moment.'**
  String llmRateLimit(String provider);

  /// No description provided for @llmServerError.
  ///
  /// In en, this message translates to:
  /// **'{provider} is having trouble right now ({status}).'**
  String llmServerError(String provider, int status);

  /// No description provided for @llmFailed.
  ///
  /// In en, this message translates to:
  /// **'Request failed ({status})'**
  String llmFailed(int status);

  /// No description provided for @llmRefusal.
  ///
  /// In en, this message translates to:
  /// **'The model declined to answer this question.'**
  String get llmRefusal;

  /// No description provided for @llmTimeout.
  ///
  /// In en, this message translates to:
  /// **'{provider} did not respond in time.'**
  String llmTimeout(String provider);

  /// No description provided for @llmOffline.
  ///
  /// In en, this message translates to:
  /// **'No connection to {provider}. Answers need the internet; the script still follows your voice offline.'**
  String llmOffline(String provider);

  /// No description provided for @llmUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Could not reach {provider}: {error}'**
  String llmUnreachable(String provider, String error);

  /// No description provided for @llmGenericError.
  ///
  /// In en, this message translates to:
  /// **'{provider} returned an error.'**
  String llmGenericError(String provider);

  /// No description provided for @modelStreamingEn.
  ///
  /// In en, this message translates to:
  /// **'English · streaming'**
  String get modelStreamingEn;

  /// No description provided for @modelStreamingEnDesc.
  ///
  /// In en, this message translates to:
  /// **'Follows your voice word by word'**
  String get modelStreamingEnDesc;

  /// No description provided for @modelStreamingEnLight.
  ///
  /// In en, this message translates to:
  /// **'English · streaming (light)'**
  String get modelStreamingEnLight;

  /// No description provided for @modelStreamingEnLightDesc.
  ///
  /// In en, this message translates to:
  /// **'For older or low-power machines'**
  String get modelStreamingEnLightDesc;

  /// No description provided for @modelWhisperBase.
  ///
  /// In en, this message translates to:
  /// **'Whisper base'**
  String get modelWhisperBase;

  /// No description provided for @modelWhisperBaseDesc.
  ///
  /// In en, this message translates to:
  /// **'Question transcripts in 99 languages; also follows non-English scripts'**
  String get modelWhisperBaseDesc;

  /// No description provided for @modelWhisperTurbo.
  ///
  /// In en, this message translates to:
  /// **'Whisper large-v3 turbo'**
  String get modelWhisperTurbo;

  /// No description provided for @modelWhisperTurboDesc.
  ///
  /// In en, this message translates to:
  /// **'Most accurate question transcripts; needs a fast machine'**
  String get modelWhisperTurboDesc;

  /// No description provided for @modelDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed ({status}).'**
  String modelDownloadFailed(int status);

  /// No description provided for @modelIncomplete.
  ///
  /// In en, this message translates to:
  /// **'The model archive was incomplete.'**
  String get modelIncomplete;

  /// No description provided for @modelOffline.
  ///
  /// In en, this message translates to:
  /// **'No internet connection. Models download once, then work offline.'**
  String get modelOffline;

  /// No description provided for @engineUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get engineUnavailable;

  /// No description provided for @engineOnDeviceStreaming.
  ///
  /// In en, this message translates to:
  /// **'On-device · streaming'**
  String get engineOnDeviceStreaming;

  /// No description provided for @engineOnDeviceWhisper.
  ///
  /// In en, this message translates to:
  /// **'On-device · Whisper'**
  String get engineOnDeviceWhisper;

  /// No description provided for @engineModelsMissing.
  ///
  /// In en, this message translates to:
  /// **'Speech models are not installed yet. Download them in Settings → Voice & following.'**
  String get engineModelsMissing;

  /// No description provided for @sttEngineFailed.
  ///
  /// In en, this message translates to:
  /// **'Speech engine failed to start: {error}'**
  String sttEngineFailed(String error);

  /// No description provided for @sttNoModel.
  ///
  /// In en, this message translates to:
  /// **'No transcription model installed.'**
  String get sttNoModel;

  /// No description provided for @sttStopped.
  ///
  /// In en, this message translates to:
  /// **'Speech engine stopped.'**
  String get sttStopped;

  /// No description provided for @micPermission.
  ///
  /// In en, this message translates to:
  /// **'Sotto needs microphone access. Allow it in System Settings → Privacy.'**
  String get micPermission;

  /// No description provided for @noticeShortcutsTaken.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 shortcut is taken by another app} other{{count} shortcuts are taken by another app}}'**
  String noticeShortcutsTaken(int count);

  /// No description provided for @noticeNoSpeechForQuestions.
  ///
  /// In en, this message translates to:
  /// **'Questions need a speech engine — see Settings → Voice & following.'**
  String get noticeNoSpeechForQuestions;

  /// No description provided for @noticeNoQuestion.
  ///
  /// In en, this message translates to:
  /// **'Didn\'t catch a question'**
  String get noticeNoQuestion;

  /// No description provided for @answerNeedsKey.
  ///
  /// In en, this message translates to:
  /// **'Add an API key in Settings → Integrations to draft answers.'**
  String get answerNeedsKey;

  /// No description provided for @noticeCopiedForChat.
  ///
  /// In en, this message translates to:
  /// **'Copied — paste into the meeting chat'**
  String get noticeCopiedForChat;

  /// No description provided for @noticeAnswerCopied.
  ///
  /// In en, this message translates to:
  /// **'Answer copied'**
  String get noticeAnswerCopied;

  /// No description provided for @readyNoMic.
  ///
  /// In en, this message translates to:
  /// **'No microphone'**
  String get readyNoMic;

  /// No description provided for @readyHotkeysOnly.
  ///
  /// In en, this message translates to:
  /// **'Hotkeys only'**
  String get readyHotkeysOnly;

  /// No description provided for @readyAdvanceManual.
  ///
  /// In en, this message translates to:
  /// **'Advance: manual'**
  String get readyAdvanceManual;

  /// No description provided for @readyOnDevice.
  ///
  /// In en, this message translates to:
  /// **'On-device · {langs}'**
  String readyOnDevice(String langs);

  /// No description provided for @readyDownloadModels.
  ///
  /// In en, this message translates to:
  /// **'Download speech models in Voice & following'**
  String get readyDownloadModels;

  /// No description provided for @readyHotkeys.
  ///
  /// In en, this message translates to:
  /// **'Hotkeys {chord}'**
  String readyHotkeys(String chord);

  /// No description provided for @readyTakenByOther.
  ///
  /// In en, this message translates to:
  /// **'{count} taken by another app'**
  String readyTakenByOther(int count);

  /// No description provided for @readyNoKey.
  ///
  /// In en, this message translates to:
  /// **'No API key'**
  String get readyNoKey;

  /// No description provided for @readyAddKey.
  ///
  /// In en, this message translates to:
  /// **'Add one in Integrations to draft answers'**
  String get readyAddKey;

  /// No description provided for @readyShareWindow.
  ///
  /// In en, this message translates to:
  /// **'Share a window'**
  String get readyShareWindow;

  /// No description provided for @readyShareWarning.
  ///
  /// In en, this message translates to:
  /// **'Sharing your entire screen can capture the overlay on macOS 15+'**
  String get readyShareWarning;

  /// No description provided for @sourceQaPrep.
  ///
  /// In en, this message translates to:
  /// **'Q&A prep'**
  String get sourceQaPrep;

  /// No description provided for @sourceGeneral.
  ///
  /// In en, this message translates to:
  /// **'General knowledge · verify'**
  String get sourceGeneral;

  /// No description provided for @notInYourNotes.
  ///
  /// In en, this message translates to:
  /// **'Not in your notes.'**
  String get notInYourNotes;

  /// No description provided for @sidebarShow.
  ///
  /// In en, this message translates to:
  /// **'Show sidebar'**
  String get sidebarShow;

  /// No description provided for @sidebarHide.
  ///
  /// In en, this message translates to:
  /// **'Hide sidebar'**
  String get sidebarHide;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navAllScripts.
  ///
  /// In en, this message translates to:
  /// **'All scripts'**
  String get navAllScripts;

  /// No description provided for @navSessions.
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get navSessions;

  /// No description provided for @navArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get navArchive;

  /// No description provided for @navCollections.
  ///
  /// In en, this message translates to:
  /// **'Collections'**
  String get navCollections;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @newCollection.
  ///
  /// In en, this message translates to:
  /// **'New collection'**
  String get newCollection;

  /// No description provided for @collectionName.
  ///
  /// In en, this message translates to:
  /// **'Collection name'**
  String get collectionName;

  /// No description provided for @liveReadiness.
  ///
  /// In en, this message translates to:
  /// **'Live readiness'**
  String get liveReadiness;

  /// No description provided for @readinessCount.
  ///
  /// In en, this message translates to:
  /// **'{passed} of {total}'**
  String readinessCount(int passed, int total);

  /// No description provided for @dropHintDrop.
  ///
  /// In en, this message translates to:
  /// **'Drop a '**
  String get dropHintDrop;

  /// No description provided for @dropHintOr.
  ///
  /// In en, this message translates to:
  /// **' or '**
  String get dropHintOr;

  /// No description provided for @dropHintPaste.
  ///
  /// In en, this message translates to:
  /// **' anywhere, or paste with  '**
  String get dropHintPaste;

  /// No description provided for @dropHintOrganize.
  ///
  /// In en, this message translates to:
  /// **'  — Sotto organizes it into sections, beats and cues.'**
  String get dropHintOrganize;

  /// No description provided for @browseFiles.
  ///
  /// In en, this message translates to:
  /// **'Browse files'**
  String get browseFiles;

  /// No description provided for @import.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get import;

  /// No description provided for @newScript.
  ///
  /// In en, this message translates to:
  /// **'New script'**
  String get newScript;

  /// No description provided for @upNext.
  ///
  /// In en, this message translates to:
  /// **'Up next'**
  String get upNext;

  /// No description provided for @recentScripts.
  ///
  /// In en, this message translates to:
  /// **'Recent scripts'**
  String get recentScripts;

  /// No description provided for @filterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get filterAll;

  /// No description provided for @filterDrafts.
  ///
  /// In en, this message translates to:
  /// **'Drafts'**
  String get filterDrafts;

  /// No description provided for @filterReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get filterReady;

  /// No description provided for @gridView.
  ///
  /// In en, this message translates to:
  /// **'Grid view'**
  String get gridView;

  /// No description provided for @listView.
  ///
  /// In en, this message translates to:
  /// **'List view'**
  String get listView;

  /// No description provided for @emptyNoScriptsHere.
  ///
  /// In en, this message translates to:
  /// **'No scripts here yet'**
  String get emptyNoScriptsHere;

  /// No description provided for @emptyWriteOrDrop.
  ///
  /// In en, this message translates to:
  /// **'Write one, paste one, or drop a file anywhere in this window.'**
  String get emptyWriteOrDrop;

  /// No description provided for @inMinutes.
  ///
  /// In en, this message translates to:
  /// **'in {minutes} min'**
  String inMinutes(int minutes);

  /// No description provided for @inHours.
  ///
  /// In en, this message translates to:
  /// **'in {hours} h'**
  String inHours(int hours);

  /// No description provided for @sectionsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 section} other{{count} sections}}'**
  String sectionsCount(int count);

  /// No description provided for @atYourPace.
  ///
  /// In en, this message translates to:
  /// **'{duration} at your pace ({wpm} wpm)'**
  String atYourPace(String duration, int wpm);

  /// No description provided for @rehearsedTimes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{rehearsed once} =2{rehearsed twice} other{rehearsed {count} times}}'**
  String rehearsedTimes(int count);

  /// No description provided for @prepDocsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 prep document} other{{count} prep documents}}'**
  String prepDocsCount(int count);

  /// No description provided for @goLive.
  ///
  /// In en, this message translates to:
  /// **'Go live'**
  String get goLive;

  /// No description provided for @rehearse.
  ///
  /// In en, this message translates to:
  /// **'Rehearse'**
  String get rehearse;

  /// No description provided for @notRehearsedYet.
  ///
  /// In en, this message translates to:
  /// **'Not rehearsed yet'**
  String get notRehearsedYet;

  /// No description provided for @lastRehearsal.
  ///
  /// In en, this message translates to:
  /// **'Last rehearsal {duration}'**
  String lastRehearsal(String duration);

  /// No description provided for @deleteCollection.
  ///
  /// In en, this message translates to:
  /// **'Delete collection'**
  String get deleteCollection;

  /// No description provided for @emptyNothingArchived.
  ///
  /// In en, this message translates to:
  /// **'Nothing archived'**
  String get emptyNothingArchived;

  /// No description provided for @emptyNoScripts.
  ///
  /// In en, this message translates to:
  /// **'No scripts yet'**
  String get emptyNoScripts;

  /// No description provided for @emptyNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get emptyNoMatches;

  /// No description provided for @emptyArchivedHint.
  ///
  /// In en, this message translates to:
  /// **'Archived scripts stay searchable here and never appear in Up next.'**
  String get emptyArchivedHint;

  /// No description provided for @emptyNoMatchesHint.
  ///
  /// In en, this message translates to:
  /// **'Nothing in titles or script text matches \"{query}\".'**
  String emptyNoMatchesHint(String query);

  /// No description provided for @scriptsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 script} other{{count} scripts}}'**
  String scriptsCount(int count);

  /// No description provided for @noCollection.
  ///
  /// In en, this message translates to:
  /// **'No collection'**
  String get noCollection;

  /// No description provided for @importedFinding.
  ///
  /// In en, this message translates to:
  /// **'Imported from {source}. Finding sections, beats and cues…'**
  String importedFinding(String source);

  /// No description provided for @importedFromText.
  ///
  /// In en, this message translates to:
  /// **'text'**
  String get importedFromText;

  /// No description provided for @emptyScript.
  ///
  /// In en, this message translates to:
  /// **'Empty script'**
  String get emptyScript;

  /// No description provided for @menuOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get menuOpen;

  /// No description provided for @menuDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get menuDuplicate;

  /// No description provided for @menuMoveToCollection.
  ///
  /// In en, this message translates to:
  /// **'Move to collection'**
  String get menuMoveToCollection;

  /// No description provided for @menuSchedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule…'**
  String get menuSchedule;

  /// No description provided for @menuExportMarkdown.
  ///
  /// In en, this message translates to:
  /// **'Export as Markdown'**
  String get menuExportMarkdown;

  /// No description provided for @menuArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get menuArchive;

  /// No description provided for @menuUnarchive.
  ///
  /// In en, this message translates to:
  /// **'Unarchive'**
  String get menuUnarchive;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @exportScript.
  ///
  /// In en, this message translates to:
  /// **'Export script'**
  String get exportScript;

  /// No description provided for @deleteScriptTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete “{title}”?'**
  String deleteScriptTitle(String title);

  /// No description provided for @deleteScriptBody.
  ///
  /// In en, this message translates to:
  /// **'Its Q&A history is deleted too. This can’t be undone.'**
  String get deleteScriptBody;

  /// No description provided for @emptyNoSessions.
  ///
  /// In en, this message translates to:
  /// **'No sessions yet'**
  String get emptyNoSessions;

  /// No description provided for @emptyNoSessionsHint.
  ///
  /// In en, this message translates to:
  /// **'Every live run and rehearsal lands here with its timing, so your pace keeps getting more accurate.'**
  String get emptyNoSessionsHint;

  /// No description provided for @rehearsal.
  ///
  /// In en, this message translates to:
  /// **'Rehearsal'**
  String get rehearsal;

  /// No description provided for @liveSession.
  ///
  /// In en, this message translates to:
  /// **'Live session'**
  String get liveSession;

  /// No description provided for @liveChip.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get liveChip;

  /// No description provided for @wpmValue.
  ///
  /// In en, this message translates to:
  /// **'{wpm} wpm'**
  String wpmValue(int wpm);

  /// No description provided for @questionsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 question} other{{count} questions}}'**
  String questionsCount(int count);

  /// No description provided for @deleteSession.
  ///
  /// In en, this message translates to:
  /// **'Delete session'**
  String get deleteSession;

  /// No description provided for @overlayPreview.
  ///
  /// In en, this message translates to:
  /// **'Overlay preview'**
  String get overlayPreview;

  /// No description provided for @followCursor.
  ///
  /// In en, this message translates to:
  /// **'Follow cursor'**
  String get followCursor;

  /// No description provided for @layoutTicker.
  ///
  /// In en, this message translates to:
  /// **'Ticker'**
  String get layoutTicker;

  /// No description provided for @layoutStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get layoutStandard;

  /// No description provided for @layoutColumn.
  ///
  /// In en, this message translates to:
  /// **'Column'**
  String get layoutColumn;

  /// No description provided for @layoutRail.
  ///
  /// In en, this message translates to:
  /// **'Rail'**
  String get layoutRail;

  /// No description provided for @layoutAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get layoutAuto;

  /// No description provided for @beatPosition.
  ///
  /// In en, this message translates to:
  /// **'Beat {section}.{beat} · {duration}'**
  String beatPosition(int section, int beat, String duration);

  /// No description provided for @noMoreCues.
  ///
  /// In en, this message translates to:
  /// **'No more cues'**
  String get noMoreCues;

  /// No description provided for @nextCueIn.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Next cue: {cue} in 1 beat} other{Next cue: {cue} in {count} beats}}'**
  String nextCueIn(int count, String cue);

  /// No description provided for @listenForWords.
  ///
  /// In en, this message translates to:
  /// **'Listen for these words'**
  String get listenForWords;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @hintWordsExplain.
  ///
  /// In en, this message translates to:
  /// **'Names and numbers from this script are sent to speech recognition as hints.'**
  String get hintWordsExplain;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @hintWordPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'A name or number, then Enter'**
  String get hintWordPlaceholder;

  /// No description provided for @deliveryCheck.
  ///
  /// In en, this message translates to:
  /// **'Delivery check'**
  String get deliveryCheck;

  /// No description provided for @markAsReady.
  ///
  /// In en, this message translates to:
  /// **'Mark as ready'**
  String get markAsReady;

  /// No description provided for @checkCuesOrdered.
  ///
  /// In en, this message translates to:
  /// **'Cues are in reading order'**
  String get checkCuesOrdered;

  /// No description provided for @checkCuesBackwards.
  ///
  /// In en, this message translates to:
  /// **'Slide cues jump backwards'**
  String get checkCuesBackwards;

  /// No description provided for @checkBeatsFit.
  ///
  /// In en, this message translates to:
  /// **'Every beat fits in one breath'**
  String get checkBeatsFit;

  /// No description provided for @checkLongBeats.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 long beat — over 28 words} other{{count} long beats — over 28 words}}'**
  String checkLongBeats(int count);

  /// No description provided for @checkNumbersSpoken.
  ///
  /// In en, this message translates to:
  /// **'Numbers written the way you say them'**
  String get checkNumbersSpoken;

  /// No description provided for @checkNumbersAbbreviated.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 beat with abbreviated numbers (write “48.2 million”, not “48.2M”)} other{{count} beats with abbreviated numbers (write “48.2 million”, not “48.2M”)}}'**
  String checkNumbersAbbreviated(int count);

  /// No description provided for @checkEmptyBeats.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 empty beat} other{{count} empty beats}}'**
  String checkEmptyBeats(int count);

  /// No description provided for @scriptMissing.
  ///
  /// In en, this message translates to:
  /// **'This script no longer exists.'**
  String get scriptMissing;

  /// No description provided for @backToLibrary.
  ///
  /// In en, this message translates to:
  /// **'Back to library'**
  String get backToLibrary;

  /// No description provided for @library.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get library;

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// No description provided for @editing.
  ///
  /// In en, this message translates to:
  /// **'Editing…'**
  String get editing;

  /// No description provided for @tabWrite.
  ///
  /// In en, this message translates to:
  /// **'Write'**
  String get tabWrite;

  /// No description provided for @tabQaPrep.
  ///
  /// In en, this message translates to:
  /// **'Q&A prep'**
  String get tabQaPrep;

  /// No description provided for @tabRehearsals.
  ///
  /// In en, this message translates to:
  /// **'Rehearsals'**
  String get tabRehearsals;

  /// No description provided for @structure.
  ///
  /// In en, this message translates to:
  /// **'Structure'**
  String get structure;

  /// No description provided for @organizeAgain.
  ///
  /// In en, this message translates to:
  /// **'Organize again — sections, beats and cues'**
  String get organizeAgain;

  /// No description provided for @addSection.
  ///
  /// In en, this message translates to:
  /// **'Add section'**
  String get addSection;

  /// No description provided for @timing.
  ///
  /// In en, this message translates to:
  /// **'Timing'**
  String get timing;

  /// No description provided for @plannedDuration.
  ///
  /// In en, this message translates to:
  /// **'{duration} planned'**
  String plannedDuration(String duration);

  /// No description provided for @setTarget.
  ///
  /// In en, this message translates to:
  /// **'set target'**
  String get setTarget;

  /// No description provided for @targetDuration.
  ///
  /// In en, this message translates to:
  /// **'{duration} target'**
  String targetDuration(String duration);

  /// No description provided for @paceNote.
  ///
  /// In en, this message translates to:
  /// **'At {wpm} wpm.'**
  String paceNote(int wpm);

  /// No description provided for @paceNoteMeasured.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{At {wpm} wpm, measured over 1 rehearsal.} other{At {wpm} wpm, measured over {count} rehearsals.}}'**
  String paceNoteMeasured(int count, int wpm);

  /// No description provided for @targetLength.
  ///
  /// In en, this message translates to:
  /// **'Target length'**
  String get targetLength;

  /// No description provided for @durationPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'m:ss — empty to clear'**
  String get durationPlaceholder;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @deleteSection.
  ///
  /// In en, this message translates to:
  /// **'Delete section'**
  String get deleteSection;

  /// No description provided for @timeForSection.
  ///
  /// In en, this message translates to:
  /// **'Time for “{title}”'**
  String timeForSection(String title);

  /// No description provided for @wordsAtPace.
  ///
  /// In en, this message translates to:
  /// **'{words} words · {duration} at {wpm} wpm'**
  String wordsAtPace(int words, String duration, int wpm);

  /// No description provided for @beatWords.
  ///
  /// In en, this message translates to:
  /// **'Beat {section}.{beat} · {words} words'**
  String beatWords(int section, int beat, int words);

  /// No description provided for @sectionHeader.
  ///
  /// In en, this message translates to:
  /// **'Section {index} of {count} · {duration} · starts at {start}'**
  String sectionHeader(int index, int count, String duration, String start);

  /// No description provided for @sectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Section title'**
  String get sectionTitle;

  /// No description provided for @addBeat.
  ///
  /// In en, this message translates to:
  /// **'+  Add a beat'**
  String get addBeat;

  /// No description provided for @transitionTo.
  ///
  /// In en, this message translates to:
  /// **'→  Transition to  '**
  String get transitionTo;

  /// No description provided for @beatHint.
  ///
  /// In en, this message translates to:
  /// **'One breath of text. Type [SLIDE 3] or [PAUSE] for a cue.'**
  String get beatHint;

  /// No description provided for @cueMenuSlide.
  ///
  /// In en, this message translates to:
  /// **'Slide'**
  String get cueMenuSlide;

  /// No description provided for @cueMenuSlideNext.
  ///
  /// In en, this message translates to:
  /// **'Slide number +1'**
  String get cueMenuSlideNext;

  /// No description provided for @cueMenuSlidePrev.
  ///
  /// In en, this message translates to:
  /// **'Slide number −1'**
  String get cueMenuSlidePrev;

  /// No description provided for @cueMenuPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get cueMenuPause;

  /// No description provided for @cueMenuDemo.
  ///
  /// In en, this message translates to:
  /// **'Demo'**
  String get cueMenuDemo;

  /// No description provided for @cueMenuRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove cue'**
  String get cueMenuRemove;

  /// No description provided for @addCue.
  ///
  /// In en, this message translates to:
  /// **'Add a cue'**
  String get addCue;

  /// No description provided for @longBeat.
  ///
  /// In en, this message translates to:
  /// **'Long beat · {words} words. '**
  String longBeat(int words);

  /// No description provided for @longBeatPause.
  ///
  /// In en, this message translates to:
  /// **'Consider a pause for a natural breath.'**
  String get longBeatPause;

  /// No description provided for @longBeatSplitAfter.
  ///
  /// In en, this message translates to:
  /// **'Split after “{word}” for a natural breath?'**
  String longBeatSplitAfter(String word);

  /// No description provided for @ignore.
  ///
  /// In en, this message translates to:
  /// **'Ignore'**
  String get ignore;

  /// No description provided for @split.
  ///
  /// In en, this message translates to:
  /// **'Split'**
  String get split;

  /// No description provided for @keyPoints.
  ///
  /// In en, this message translates to:
  /// **'Key points'**
  String get keyPoints;

  /// No description provided for @keyPointsNote.
  ///
  /// In en, this message translates to:
  /// **'Shown in Column layout and rehearsal'**
  String get keyPointsNote;

  /// No description provided for @keyPointsHint.
  ///
  /// In en, this message translates to:
  /// **'One per line — the few things this section must land'**
  String get keyPointsHint;

  /// No description provided for @addPrepDocument.
  ///
  /// In en, this message translates to:
  /// **'Add a prep document'**
  String get addPrepDocument;

  /// No description provided for @pastedNotes.
  ///
  /// In en, this message translates to:
  /// **'Pasted notes {number}'**
  String pastedNotes(int number);

  /// No description provided for @suggestNeedsKey.
  ///
  /// In en, this message translates to:
  /// **'Add an API key in Settings → Integrations to suggest questions.'**
  String get suggestNeedsKey;

  /// No description provided for @noQuestionsReturned.
  ///
  /// In en, this message translates to:
  /// **'The model returned no questions.'**
  String get noQuestionsReturned;

  /// No description provided for @likelyQuestions.
  ///
  /// In en, this message translates to:
  /// **'Likely questions'**
  String get likelyQuestions;

  /// No description provided for @suggestWithAi.
  ///
  /// In en, this message translates to:
  /// **'Suggest with AI'**
  String get suggestWithAi;

  /// No description provided for @addQuestion.
  ///
  /// In en, this message translates to:
  /// **'Add question'**
  String get addQuestion;

  /// No description provided for @likelyQuestionsNote.
  ///
  /// In en, this message translates to:
  /// **'When a live question matches one of these, its answer appears instantly — no model call.'**
  String get likelyQuestionsNote;

  /// No description provided for @noPreparedQuestions.
  ///
  /// In en, this message translates to:
  /// **'No prepared questions yet. Add the ones you dread most.'**
  String get noPreparedQuestions;

  /// No description provided for @prepDocuments.
  ///
  /// In en, this message translates to:
  /// **'Prep documents'**
  String get prepDocuments;

  /// No description provided for @paste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get paste;

  /// No description provided for @addFile.
  ///
  /// In en, this message translates to:
  /// **'Add file'**
  String get addFile;

  /// No description provided for @prepDocumentsNote.
  ///
  /// In en, this message translates to:
  /// **'Answers can cite these. They stay on this computer; only excerpts relevant to a question are sent.'**
  String get prepDocumentsNote;

  /// No description provided for @noPrepDocuments.
  ///
  /// In en, this message translates to:
  /// **'Board memos, contracts, FAQs — anything you might be asked about.'**
  String get noPrepDocuments;

  /// No description provided for @dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// No description provided for @questionHint.
  ///
  /// In en, this message translates to:
  /// **'The question, as someone might ask it'**
  String get questionHint;

  /// No description provided for @deleteQuestion.
  ///
  /// In en, this message translates to:
  /// **'Delete question'**
  String get deleteQuestion;

  /// No description provided for @answerHint.
  ///
  /// In en, this message translates to:
  /// **'Your answer. The first sentence becomes the headline.'**
  String get answerHint;

  /// No description provided for @wordsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 word} other{{count} words}}'**
  String wordsCount(int count);

  /// No description provided for @removeDocument.
  ///
  /// In en, this message translates to:
  /// **'Remove document'**
  String get removeDocument;

  /// No description provided for @noRehearsalsYet.
  ///
  /// In en, this message translates to:
  /// **'No rehearsals yet'**
  String get noRehearsalsYet;

  /// No description provided for @noRehearsalsHint.
  ///
  /// In en, this message translates to:
  /// **'Rehearse with the real overlay. Sotto times every section and learns your pace.'**
  String get noRehearsalsHint;

  /// No description provided for @rehearseNow.
  ///
  /// In en, this message translates to:
  /// **'Rehearse now'**
  String get rehearseNow;

  /// No description provided for @latestRehearsal.
  ///
  /// In en, this message translates to:
  /// **'Latest rehearsal'**
  String get latestRehearsal;

  /// No description provided for @latestSession.
  ///
  /// In en, this message translates to:
  /// **'Latest session'**
  String get latestSession;

  /// No description provided for @ofPlanned.
  ///
  /// In en, this message translates to:
  /// **' of {duration} planned'**
  String ofPlanned(String duration);

  /// No description provided for @allRuns.
  ///
  /// In en, this message translates to:
  /// **'All runs'**
  String get allRuns;

  /// No description provided for @questionsAsked.
  ///
  /// In en, this message translates to:
  /// **'Questions asked'**
  String get questionsAsked;

  /// No description provided for @pfMicrophone.
  ///
  /// In en, this message translates to:
  /// **'Microphone'**
  String get pfMicrophone;

  /// No description provided for @pfMicReady.
  ///
  /// In en, this message translates to:
  /// **'{device} · ready'**
  String pfMicReady(String device);

  /// No description provided for @pfNoInput.
  ///
  /// In en, this message translates to:
  /// **'No input device found'**
  String get pfNoInput;

  /// No description provided for @pfVoiceFollowing.
  ///
  /// In en, this message translates to:
  /// **'Voice following'**
  String get pfVoiceFollowing;

  /// No description provided for @pfTunedTo.
  ///
  /// In en, this message translates to:
  /// **'{engine} · tuned to {wpm} wpm'**
  String pfTunedTo(String engine, int wpm);

  /// No description provided for @pfOverlay.
  ///
  /// In en, this message translates to:
  /// **'Overlay'**
  String get pfOverlay;

  /// No description provided for @pfOverlayDetail.
  ///
  /// In en, this message translates to:
  /// **'{placement} · {opacity}% · text {size}'**
  String pfOverlayDetail(String placement, int opacity, String size);

  /// No description provided for @pfScreenSharing.
  ///
  /// In en, this message translates to:
  /// **'Screen sharing'**
  String get pfScreenSharing;

  /// No description provided for @pfShareProtected.
  ///
  /// In en, this message translates to:
  /// **'Sotto hides itself from captures where the OS allows it. On macOS 15 and later, sharing your entire screen can still capture the overlay — share only the slides window.'**
  String get pfShareProtected;

  /// No description provided for @pfShareUnprotected.
  ///
  /// In en, this message translates to:
  /// **'Capture protection is off. Share only the slides window.'**
  String get pfShareUnprotected;

  /// No description provided for @pfAnswers.
  ///
  /// In en, this message translates to:
  /// **'Answers'**
  String get pfAnswers;

  /// No description provided for @pfGrounded.
  ///
  /// In en, this message translates to:
  /// **'Grounded in this script'**
  String get pfGrounded;

  /// No description provided for @pfPlusPrepDocs.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{ + 1 prep document} other{ + {count} prep documents}}'**
  String pfPlusPrepDocs(int count);

  /// No description provided for @pfQuestionLanguage.
  ///
  /// In en, this message translates to:
  /// **' · answers in the question’s language'**
  String get pfQuestionLanguage;

  /// No description provided for @pfMeetingChat.
  ///
  /// In en, this message translates to:
  /// **'Meeting chat'**
  String get pfMeetingChat;

  /// No description provided for @pfMeetingChatDetail.
  ///
  /// In en, this message translates to:
  /// **'Hold to copy an answer, then paste it into Zoom, Teams or Meet'**
  String get pfMeetingChatDetail;

  /// No description provided for @pfChoose.
  ///
  /// In en, this message translates to:
  /// **'Choose'**
  String get pfChoose;

  /// No description provided for @pfSetUp.
  ///
  /// In en, this message translates to:
  /// **'Set up'**
  String get pfSetUp;

  /// No description provided for @pfAdjust.
  ///
  /// In en, this message translates to:
  /// **'Adjust'**
  String get pfAdjust;

  /// No description provided for @pfAddKey.
  ///
  /// In en, this message translates to:
  /// **'Add key'**
  String get pfAddKey;

  /// No description provided for @pfSummary.
  ///
  /// In en, this message translates to:
  /// **'{duration} · {sections}'**
  String pfSummary(String duration, String sections);

  /// No description provided for @pfChecksPassed.
  ///
  /// In en, this message translates to:
  /// **' · {passed} of {total} checks passed'**
  String pfChecksPassed(int passed, int total);

  /// No description provided for @closeEsc.
  ///
  /// In en, this message translates to:
  /// **'Close  esc'**
  String get closeEsc;

  /// No description provided for @startFrom.
  ///
  /// In en, this message translates to:
  /// **'Start from'**
  String get startFrom;

  /// No description provided for @goLiveInstead.
  ///
  /// In en, this message translates to:
  /// **'Go live instead'**
  String get goLiveInstead;

  /// No description provided for @rehearseInstead.
  ///
  /// In en, this message translates to:
  /// **'Rehearse instead'**
  String get rehearseInstead;

  /// No description provided for @hintNextBeat.
  ///
  /// In en, this message translates to:
  /// **'next beat'**
  String get hintNextBeat;

  /// No description provided for @hintAsk.
  ///
  /// In en, this message translates to:
  /// **'ask'**
  String get hintAsk;

  /// No description provided for @hintHide.
  ///
  /// In en, this message translates to:
  /// **'hide instantly'**
  String get hintHide;

  /// No description provided for @placeUnderCamera.
  ///
  /// In en, this message translates to:
  /// **'Under the camera'**
  String get placeUnderCamera;

  /// No description provided for @placeTopLeft.
  ///
  /// In en, this message translates to:
  /// **'Top left'**
  String get placeTopLeft;

  /// No description provided for @placeTopRight.
  ///
  /// In en, this message translates to:
  /// **'Top right'**
  String get placeTopRight;

  /// No description provided for @placeLeftEdge.
  ///
  /// In en, this message translates to:
  /// **'Left edge'**
  String get placeLeftEdge;

  /// No description provided for @placeCentered.
  ///
  /// In en, this message translates to:
  /// **'Centered'**
  String get placeCentered;

  /// No description provided for @placeRightEdge.
  ///
  /// In en, this message translates to:
  /// **'Right edge'**
  String get placeRightEdge;

  /// No description provided for @placeBottomLeft.
  ///
  /// In en, this message translates to:
  /// **'Bottom left'**
  String get placeBottomLeft;

  /// No description provided for @placeBottomCentre.
  ///
  /// In en, this message translates to:
  /// **'Bottom centre'**
  String get placeBottomCentre;

  /// No description provided for @placeBottomRight.
  ///
  /// In en, this message translates to:
  /// **'Bottom right'**
  String get placeBottomRight;

  /// No description provided for @questions.
  ///
  /// In en, this message translates to:
  /// **'Questions'**
  String get questions;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @historyEmpty.
  ///
  /// In en, this message translates to:
  /// **'Questions you answer this session appear here.'**
  String get historyEmpty;

  /// No description provided for @outcomeCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied for chat'**
  String get outcomeCopied;

  /// No description provided for @outcomeReadAloud.
  ///
  /// In en, this message translates to:
  /// **'Read aloud'**
  String get outcomeReadAloud;

  /// No description provided for @outcomeDismissed.
  ///
  /// In en, this message translates to:
  /// **'Dismissed'**
  String get outcomeDismissed;

  /// No description provided for @outcomeShown.
  ///
  /// In en, this message translates to:
  /// **'Shown'**
  String get outcomeShown;

  /// No description provided for @showAgain.
  ///
  /// In en, this message translates to:
  /// **'Show again'**
  String get showAgain;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @paused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get paused;

  /// No description provided for @hotkeysOnly.
  ///
  /// In en, this message translates to:
  /// **'Hotkeys only'**
  String get hotkeysOnly;

  /// No description provided for @followingYourVoice.
  ///
  /// In en, this message translates to:
  /// **'Following your voice'**
  String get followingYourVoice;

  /// No description provided for @standby.
  ///
  /// In en, this message translates to:
  /// **'Standby'**
  String get standby;

  /// No description provided for @onPace.
  ///
  /// In en, this message translates to:
  /// **'On pace'**
  String get onPace;

  /// No description provided for @ahead.
  ///
  /// In en, this message translates to:
  /// **'Ahead'**
  String get ahead;

  /// No description provided for @behind.
  ///
  /// In en, this message translates to:
  /// **'Behind'**
  String get behind;

  /// No description provided for @holding.
  ///
  /// In en, this message translates to:
  /// **'Holding'**
  String get holding;

  /// No description provided for @resume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resume;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @hideInstantly.
  ///
  /// In en, this message translates to:
  /// **'Hide instantly'**
  String get hideInstantly;

  /// No description provided for @endSession.
  ///
  /// In en, this message translates to:
  /// **'End session'**
  String get endSession;

  /// No description provided for @listening.
  ///
  /// In en, this message translates to:
  /// **'Listening'**
  String get listening;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @askAway.
  ///
  /// In en, this message translates to:
  /// **'Ask away — Sotto is listening to the room.'**
  String get askAway;

  /// No description provided for @transcribingQuestion.
  ///
  /// In en, this message translates to:
  /// **'Transcribing the question'**
  String get transcribingQuestion;

  /// No description provided for @draftingFrom.
  ///
  /// In en, this message translates to:
  /// **'Drafting from'**
  String get draftingFrom;

  /// No description provided for @noAnswerDrafted.
  ///
  /// In en, this message translates to:
  /// **'No answer drafted'**
  String get noAnswerDrafted;

  /// No description provided for @provNotInNotes.
  ///
  /// In en, this message translates to:
  /// **'Not in your notes'**
  String get provNotInNotes;

  /// No description provided for @provFromPrep.
  ///
  /// In en, this message translates to:
  /// **'From your Q&A prep'**
  String get provFromPrep;

  /// No description provided for @provFromScript.
  ///
  /// In en, this message translates to:
  /// **'From your script and prep notes'**
  String get provFromScript;

  /// No description provided for @provGeneral.
  ///
  /// In en, this message translates to:
  /// **'Includes general knowledge — verify'**
  String get provGeneral;

  /// No description provided for @predraftedInstant.
  ///
  /// In en, this message translates to:
  /// **'pre-drafted · instant'**
  String get predraftedInstant;

  /// No description provided for @draftedIn.
  ///
  /// In en, this message translates to:
  /// **'drafted in {seconds} s'**
  String draftedIn(String seconds);

  /// No description provided for @copyForChat.
  ///
  /// In en, this message translates to:
  /// **'Copy for chat'**
  String get copyForChat;

  /// No description provided for @readAloud.
  ///
  /// In en, this message translates to:
  /// **'Read aloud'**
  String get readAloud;

  /// No description provided for @draftAgain.
  ///
  /// In en, this message translates to:
  /// **'Draft again'**
  String get draftAgain;

  /// No description provided for @copyAnswer.
  ///
  /// In en, this message translates to:
  /// **'Copy answer'**
  String get copyAnswer;

  /// No description provided for @upNextOverlay.
  ///
  /// In en, this message translates to:
  /// **'→  Up next · '**
  String get upNextOverlay;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @gettingReady.
  ///
  /// In en, this message translates to:
  /// **'Getting ready…'**
  String get gettingReady;

  /// No description provided for @choosePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Choose…'**
  String get choosePlaceholder;

  /// No description provided for @setShortcuts.
  ///
  /// In en, this message translates to:
  /// **'Shortcuts'**
  String get setShortcuts;

  /// No description provided for @setAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get setAppearance;

  /// No description provided for @setVoice.
  ///
  /// In en, this message translates to:
  /// **'Voice & following'**
  String get setVoice;

  /// No description provided for @setAnswers.
  ///
  /// In en, this message translates to:
  /// **'Answers'**
  String get setAnswers;

  /// No description provided for @setGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get setGeneral;

  /// No description provided for @setIntegrations.
  ///
  /// In en, this message translates to:
  /// **'Integrations'**
  String get setIntegrations;

  /// No description provided for @setPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy & data'**
  String get setPrivacy;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @groupLive.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get groupLive;

  /// No description provided for @groupApp.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get groupApp;

  /// No description provided for @versionBuild.
  ///
  /// In en, this message translates to:
  /// **'Sotto 1.0 (build 1)'**
  String get versionBuild;

  /// No description provided for @searchSettings.
  ///
  /// In en, this message translates to:
  /// **'Search settings'**
  String get searchSettings;

  /// No description provided for @resetToDefaults.
  ///
  /// In en, this message translates to:
  /// **'Reset to defaults'**
  String get resetToDefaults;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @shortcutsDescription.
  ///
  /// In en, this message translates to:
  /// **'They work everywhere while you are live — even when Zoom or your slides have focus. Every shortcut shares one chord, so you only learn the letter.'**
  String get shortcutsDescription;

  /// No description provided for @filterShortcuts.
  ///
  /// In en, this message translates to:
  /// **'Filter shortcuts'**
  String get filterShortcuts;

  /// No description provided for @groupOverlay.
  ///
  /// In en, this message translates to:
  /// **'Overlay'**
  String get groupOverlay;

  /// No description provided for @chord.
  ///
  /// In en, this message translates to:
  /// **'Chord'**
  String get chord;

  /// No description provided for @sottoChord.
  ///
  /// In en, this message translates to:
  /// **'Sotto chord'**
  String get sottoChord;

  /// No description provided for @sottoChordSub.
  ///
  /// In en, this message translates to:
  /// **'Shared by every shortcut'**
  String get sottoChordSub;

  /// No description provided for @altGrLayouts.
  ///
  /// In en, this message translates to:
  /// **'AltGr layouts'**
  String get altGrLayouts;

  /// No description provided for @altGrLayoutsSub.
  ///
  /// In en, this message translates to:
  /// **'On layouts that type characters with Ctrl + Alt (Spanish, German, Polish…), pick Ctrl + Shift so shortcuts never swallow “@” or “€”.'**
  String get altGrLayoutsSub;

  /// No description provided for @sysPrevInputSource.
  ///
  /// In en, this message translates to:
  /// **'Select the previous input source'**
  String get sysPrevInputSource;

  /// No description provided for @sysMoveSpaces.
  ///
  /// In en, this message translates to:
  /// **'Move between Spaces'**
  String get sysMoveSpaces;

  /// No description provided for @sysSecurityOptions.
  ///
  /// In en, this message translates to:
  /// **'Security options'**
  String get sysSecurityOptions;

  /// No description provided for @conflictAlreadyUsed.
  ///
  /// In en, this message translates to:
  /// **'Already used by “{action}”'**
  String conflictAlreadyUsed(String action);

  /// No description provided for @conflictSystem.
  ///
  /// In en, this message translates to:
  /// **'Used by {os}: {meaning}'**
  String conflictSystem(String os, String meaning);

  /// No description provided for @conflictOtherApp.
  ///
  /// In en, this message translates to:
  /// **'Taken by another app'**
  String get conflictOtherApp;

  /// No description provided for @pressAKey.
  ///
  /// In en, this message translates to:
  /// **'Press a key…'**
  String get pressAKey;

  /// No description provided for @changeShortcutFor.
  ///
  /// In en, this message translates to:
  /// **'Change shortcut for {action}'**
  String changeShortcutFor(String action);

  /// No description provided for @pressToToggle.
  ///
  /// In en, this message translates to:
  /// **'Press to toggle'**
  String get pressToToggle;

  /// No description provided for @holdToTalk.
  ///
  /// In en, this message translates to:
  /// **'Hold to talk'**
  String get holdToTalk;

  /// No description provided for @hold.
  ///
  /// In en, this message translates to:
  /// **'hold'**
  String get hold;

  /// No description provided for @useAnyway.
  ///
  /// In en, this message translates to:
  /// **'Use anyway'**
  String get useAnyway;

  /// No description provided for @chooseAnother.
  ///
  /// In en, this message translates to:
  /// **'Choose another'**
  String get chooseAnother;

  /// No description provided for @appearanceDescription.
  ///
  /// In en, this message translates to:
  /// **'How the overlay looks and where it lives. Every change previews live on the right.'**
  String get appearanceDescription;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @app.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get app;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get themeAuto;

  /// No description provided for @overlayThemeSub.
  ///
  /// In en, this message translates to:
  /// **'Dark disappears into slides and video.'**
  String get overlayThemeSub;

  /// No description provided for @matchApp.
  ///
  /// In en, this message translates to:
  /// **'Match app'**
  String get matchApp;

  /// No description provided for @readability.
  ///
  /// In en, this message translates to:
  /// **'Readability'**
  String get readability;

  /// No description provided for @textSize.
  ///
  /// In en, this message translates to:
  /// **'Text size'**
  String get textSize;

  /// No description provided for @linesShown.
  ///
  /// In en, this message translates to:
  /// **'Lines shown'**
  String get linesShown;

  /// No description provided for @linesShownSub.
  ///
  /// In en, this message translates to:
  /// **'Before and after the line you are saying'**
  String get linesShownSub;

  /// No description provided for @opacity.
  ///
  /// In en, this message translates to:
  /// **'Opacity'**
  String get opacity;

  /// No description provided for @opacitySub.
  ///
  /// In en, this message translates to:
  /// **'Below 70%, a plate appears behind the current line.'**
  String get opacitySub;

  /// No description provided for @placement.
  ///
  /// In en, this message translates to:
  /// **'Placement'**
  String get placement;

  /// No description provided for @position.
  ///
  /// In en, this message translates to:
  /// **'Position'**
  String get position;

  /// No description provided for @positionSub.
  ///
  /// In en, this message translates to:
  /// **'Keep your eyes near the lens'**
  String get positionSub;

  /// No description provided for @layout.
  ///
  /// In en, this message translates to:
  /// **'Layout'**
  String get layout;

  /// No description provided for @layoutSub.
  ///
  /// In en, this message translates to:
  /// **'Chosen automatically from the window size'**
  String get layoutSub;

  /// No description provided for @rememberPosition.
  ///
  /// In en, this message translates to:
  /// **'Remember position per display'**
  String get rememberPosition;

  /// No description provided for @preview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get preview;

  /// No description provided for @bgDarkSlide.
  ///
  /// In en, this message translates to:
  /// **'Dark slide'**
  String get bgDarkSlide;

  /// No description provided for @bgLightSlide.
  ///
  /// In en, this message translates to:
  /// **'Light slide'**
  String get bgLightSlide;

  /// No description provided for @bgVideoCall.
  ///
  /// In en, this message translates to:
  /// **'Video call'**
  String get bgVideoCall;

  /// No description provided for @writeToPreview.
  ///
  /// In en, this message translates to:
  /// **'Write a script to preview it here.'**
  String get writeToPreview;

  /// No description provided for @metricCurrentLine.
  ///
  /// In en, this message translates to:
  /// **'Current line, worst case'**
  String get metricCurrentLine;

  /// No description provided for @metricNextLine.
  ///
  /// In en, this message translates to:
  /// **'Next line, worst case'**
  String get metricNextLine;

  /// No description provided for @metricLineLength.
  ///
  /// In en, this message translates to:
  /// **'Line length at this size'**
  String get metricLineLength;

  /// No description provided for @motion.
  ///
  /// In en, this message translates to:
  /// **'Motion'**
  String get motion;

  /// No description provided for @scrolling.
  ///
  /// In en, this message translates to:
  /// **'Scrolling'**
  String get scrolling;

  /// No description provided for @scrollingSub.
  ///
  /// In en, this message translates to:
  /// **'Glide eases between beats; Step jumps.'**
  String get scrollingSub;

  /// No description provided for @scrollGlide.
  ///
  /// In en, this message translates to:
  /// **'Glide'**
  String get scrollGlide;

  /// No description provided for @scrollStep.
  ///
  /// In en, this message translates to:
  /// **'Step'**
  String get scrollStep;

  /// No description provided for @reduceMotion.
  ///
  /// In en, this message translates to:
  /// **'Reduce motion'**
  String get reduceMotion;

  /// No description provided for @reduceMotionSub.
  ///
  /// In en, this message translates to:
  /// **'Also follows your system setting'**
  String get reduceMotionSub;

  /// No description provided for @blurBehind.
  ///
  /// In en, this message translates to:
  /// **'Blur behind the overlay'**
  String get blurBehind;

  /// No description provided for @blurBehindSub.
  ///
  /// In en, this message translates to:
  /// **'Softens busy slides. Uses the system’s vibrancy on macOS and acrylic on Windows 11.'**
  String get blurBehindSub;

  /// No description provided for @voiceDescription.
  ///
  /// In en, this message translates to:
  /// **'How Sotto listens to you while you present. On-device recognition keeps your voice on this computer.'**
  String get voiceDescription;

  /// No description provided for @stopTest.
  ///
  /// In en, this message translates to:
  /// **'Stop test'**
  String get stopTest;

  /// No description provided for @testWithScript.
  ///
  /// In en, this message translates to:
  /// **'Test with this script'**
  String get testWithScript;

  /// No description provided for @noMicrophoneFound.
  ///
  /// In en, this message translates to:
  /// **'No microphone found'**
  String get noMicrophoneFound;

  /// No description provided for @inputLevel.
  ///
  /// In en, this message translates to:
  /// **'Input level'**
  String get inputLevel;

  /// No description provided for @inputLevelSub.
  ///
  /// In en, this message translates to:
  /// **'Speak normally — aim for the green zone'**
  String get inputLevelSub;

  /// No description provided for @noiseSuppression.
  ///
  /// In en, this message translates to:
  /// **'Noise suppression'**
  String get noiseSuppression;

  /// No description provided for @noiseSuppressionSub.
  ///
  /// In en, this message translates to:
  /// **'Filters fans, keyboards and echo from speakers'**
  String get noiseSuppressionSub;

  /// No description provided for @questionsComeFrom.
  ///
  /// In en, this message translates to:
  /// **'Questions come from'**
  String get questionsComeFrom;

  /// No description provided for @questionsComeFromSub.
  ///
  /// In en, this message translates to:
  /// **'In a video call, choose a loopback device (BlackHole, Stereo Mix) to capture the meeting’s audio'**
  String get questionsComeFromSub;

  /// No description provided for @sameAsMicrophone.
  ///
  /// In en, this message translates to:
  /// **'Same as microphone'**
  String get sameAsMicrophone;

  /// No description provided for @recognition.
  ///
  /// In en, this message translates to:
  /// **'Recognition'**
  String get recognition;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @alsoRecognize.
  ///
  /// In en, this message translates to:
  /// **'Also recognize'**
  String get alsoRecognize;

  /// No description provided for @alsoRecognizeSub.
  ///
  /// In en, this message translates to:
  /// **'For presenters who switch languages mid-talk'**
  String get alsoRecognizeSub;

  /// No description provided for @addLanguage.
  ///
  /// In en, this message translates to:
  /// **'Add a language'**
  String get addLanguage;

  /// No description provided for @engine.
  ///
  /// In en, this message translates to:
  /// **'Engine'**
  String get engine;

  /// No description provided for @engineOnDeviceSub.
  ///
  /// In en, this message translates to:
  /// **'sherpa-onnx on this computer · no audio leaves it'**
  String get engineOnDeviceSub;

  /// No description provided for @following.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get following;

  /// No description provided for @advance.
  ///
  /// In en, this message translates to:
  /// **'Advance'**
  String get advance;

  /// No description provided for @followMyVoice.
  ///
  /// In en, this message translates to:
  /// **'Follow my voice'**
  String get followMyVoice;

  /// No description provided for @timed.
  ///
  /// In en, this message translates to:
  /// **'Timed'**
  String get timed;

  /// No description provided for @manual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get manual;

  /// No description provided for @moveOnWhenSaid.
  ///
  /// In en, this message translates to:
  /// **'Move on when I have said'**
  String get moveOnWhenSaid;

  /// No description provided for @moveOnWhenSaidSub.
  ///
  /// In en, this message translates to:
  /// **'Lower feels faster; higher never moves early'**
  String get moveOnWhenSaidSub;

  /// No description provided for @sensitivity.
  ///
  /// In en, this message translates to:
  /// **'Sensitivity'**
  String get sensitivity;

  /// No description provided for @sensitivitySub.
  ///
  /// In en, this message translates to:
  /// **'High follows paraphrasing, but may jump on ad-libs'**
  String get sensitivitySub;

  /// No description provided for @low.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get low;

  /// No description provided for @medium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get medium;

  /// No description provided for @high.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get high;

  /// No description provided for @holdStill.
  ///
  /// In en, this message translates to:
  /// **'Hold still while I ad-lib'**
  String get holdStill;

  /// No description provided for @holdStillSub.
  ///
  /// In en, this message translates to:
  /// **'Waits for you to return to the script'**
  String get holdStillSub;

  /// No description provided for @allowJumps.
  ///
  /// In en, this message translates to:
  /// **'Allow jumps between sections'**
  String get allowJumps;

  /// No description provided for @allowJumpsSub.
  ///
  /// In en, this message translates to:
  /// **'If you skip ahead, the overlay follows'**
  String get allowJumpsSub;

  /// No description provided for @ready.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get ready;

  /// No description provided for @needsSetup.
  ///
  /// In en, this message translates to:
  /// **'Needs setup'**
  String get needsSetup;

  /// No description provided for @onDeviceModels.
  ///
  /// In en, this message translates to:
  /// **'On-device models'**
  String get onDeviceModels;

  /// No description provided for @onDeviceModelsFooter.
  ///
  /// In en, this message translates to:
  /// **'Downloaded once from the sherpa-onnx project, then used offline. Follow English live with a streaming model; Whisper transcribes questions and follows other languages.'**
  String get onDeviceModelsFooter;

  /// No description provided for @installed.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get installed;

  /// No description provided for @removeModel.
  ///
  /// In en, this message translates to:
  /// **'Remove model'**
  String get removeModel;

  /// No description provided for @unpacking.
  ///
  /// In en, this message translates to:
  /// **'Unpacking'**
  String get unpacking;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// No description provided for @noSpeechEngine.
  ///
  /// In en, this message translates to:
  /// **'No speech engine is available.'**
  String get noSpeechEngine;

  /// No description provided for @liveCheck.
  ///
  /// In en, this message translates to:
  /// **'Live check'**
  String get liveCheck;

  /// No description provided for @whatSottoHears.
  ///
  /// In en, this message translates to:
  /// **'What Sotto hears'**
  String get whatSottoHears;

  /// No description provided for @listeningLower.
  ///
  /// In en, this message translates to:
  /// **'listening'**
  String get listeningLower;

  /// No description provided for @listeningLag.
  ///
  /// In en, this message translates to:
  /// **'listening · {ms} ms since last word'**
  String listeningLag(int ms);

  /// No description provided for @idle.
  ///
  /// In en, this message translates to:
  /// **'idle'**
  String get idle;

  /// No description provided for @checkWriteFirst.
  ///
  /// In en, this message translates to:
  /// **'Write a script first — the check follows your own words.'**
  String get checkWriteFirst;

  /// No description provided for @checkPressTest.
  ///
  /// In en, this message translates to:
  /// **'Press “Test with this script” and read “{title}” aloud.'**
  String checkPressTest(String title);

  /// No description provided for @heard.
  ///
  /// In en, this message translates to:
  /// **'Heard'**
  String get heard;

  /// No description provided for @positionConfidence.
  ///
  /// In en, this message translates to:
  /// **'Position confidence'**
  String get positionConfidence;

  /// No description provided for @beatProgress.
  ///
  /// In en, this message translates to:
  /// **'Beat progress'**
  String get beatProgress;

  /// No description provided for @holdingWaiting.
  ///
  /// In en, this message translates to:
  /// **'Holding — waiting for you to return to the script'**
  String get holdingWaiting;

  /// No description provided for @yourPace.
  ///
  /// In en, this message translates to:
  /// **'Your pace'**
  String get yourPace;

  /// No description provided for @wpm.
  ///
  /// In en, this message translates to:
  /// **'wpm'**
  String get wpm;

  /// No description provided for @paceDefault.
  ///
  /// In en, this message translates to:
  /// **'default · rehearse to calibrate'**
  String get paceDefault;

  /// No description provided for @paceFromRehearsals.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{from 1 rehearsal} other{from {count} rehearsals}}'**
  String paceFromRehearsals(int count);

  /// No description provided for @recalibrate.
  ///
  /// In en, this message translates to:
  /// **'Recalibrate'**
  String get recalibrate;

  /// No description provided for @slower.
  ///
  /// In en, this message translates to:
  /// **'Slower'**
  String get slower;

  /// No description provided for @faster.
  ///
  /// In en, this message translates to:
  /// **'Faster'**
  String get faster;

  /// No description provided for @answersDescription.
  ///
  /// In en, this message translates to:
  /// **'How live answers are drafted, grounded and delivered. Sotto drafts; you decide what the room hears.'**
  String get answersDescription;

  /// No description provided for @grounding.
  ///
  /// In en, this message translates to:
  /// **'Grounding'**
  String get grounding;

  /// No description provided for @groundingScriptOnly.
  ///
  /// In en, this message translates to:
  /// **'My script and prep documents only'**
  String get groundingScriptOnly;

  /// No description provided for @groundingScriptOnlySub.
  ///
  /// In en, this message translates to:
  /// **'Safest. Says “Not in your notes” when it can’t answer.'**
  String get groundingScriptOnlySub;

  /// No description provided for @groundingScriptFirst.
  ///
  /// In en, this message translates to:
  /// **'Script first, general knowledge when needed'**
  String get groundingScriptFirst;

  /// No description provided for @groundingScriptFirstSub.
  ///
  /// In en, this message translates to:
  /// **'Anything outside your material is labeled “verify”.'**
  String get groundingScriptFirstSub;

  /// No description provided for @showSources.
  ///
  /// In en, this message translates to:
  /// **'Show sources under every answer'**
  String get showSources;

  /// No description provided for @style.
  ///
  /// In en, this message translates to:
  /// **'Style'**
  String get style;

  /// No description provided for @length.
  ///
  /// In en, this message translates to:
  /// **'Length'**
  String get length;

  /// No description provided for @lengthSub.
  ///
  /// In en, this message translates to:
  /// **'Talking points are faster to say than paragraphs'**
  String get lengthSub;

  /// No description provided for @headline.
  ///
  /// In en, this message translates to:
  /// **'Headline'**
  String get headline;

  /// No description provided for @headlinePlus3.
  ///
  /// In en, this message translates to:
  /// **'Headline + 3'**
  String get headlinePlus3;

  /// No description provided for @detailed.
  ///
  /// In en, this message translates to:
  /// **'Detailed'**
  String get detailed;

  /// No description provided for @sameAsQuestion.
  ///
  /// In en, this message translates to:
  /// **'Same as the question'**
  String get sameAsQuestion;

  /// No description provided for @sameAsScript.
  ///
  /// In en, this message translates to:
  /// **'Same as the script'**
  String get sameAsScript;

  /// No description provided for @tone.
  ///
  /// In en, this message translates to:
  /// **'Tone'**
  String get tone;

  /// No description provided for @matchScript.
  ///
  /// In en, this message translates to:
  /// **'Match the script'**
  String get matchScript;

  /// No description provided for @conversational.
  ///
  /// In en, this message translates to:
  /// **'Conversational'**
  String get conversational;

  /// No description provided for @formal.
  ///
  /// In en, this message translates to:
  /// **'Formal'**
  String get formal;

  /// No description provided for @listeningForQuestions.
  ///
  /// In en, this message translates to:
  /// **'Listening for questions'**
  String get listeningForQuestions;

  /// No description provided for @capture.
  ///
  /// In en, this message translates to:
  /// **'Capture'**
  String get capture;

  /// No description provided for @captureSub.
  ///
  /// In en, this message translates to:
  /// **'Only while you ask it to — never in the background'**
  String get captureSub;

  /// No description provided for @stopAfterSilence.
  ///
  /// In en, this message translates to:
  /// **'Stop after silence of'**
  String get stopAfterSilence;

  /// No description provided for @predraft.
  ///
  /// In en, this message translates to:
  /// **'Pre-draft likely questions'**
  String get predraft;

  /// No description provided for @predraftSub.
  ///
  /// In en, this message translates to:
  /// **'From Q&A prep — matched answers appear instantly'**
  String get predraftSub;

  /// No description provided for @delivery.
  ///
  /// In en, this message translates to:
  /// **'Delivery'**
  String get delivery;

  /// No description provided for @voice.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get voice;

  /// No description provided for @systemDefault.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get systemDefault;

  /// No description provided for @copyForChatAsks.
  ///
  /// In en, this message translates to:
  /// **'Copy for chat asks for'**
  String get copyForChatAsks;

  /// No description provided for @holdKeyHalfSecond.
  ///
  /// In en, this message translates to:
  /// **'Hold {keys} (0.5 s)'**
  String holdKeyHalfSecond(String keys);

  /// No description provided for @copyThenPaste.
  ///
  /// In en, this message translates to:
  /// **'Copy, then paste'**
  String get copyThenPaste;

  /// No description provided for @copyThenPasteSub.
  ///
  /// In en, this message translates to:
  /// **'Holding the send key places the answer on your clipboard as plain text. Paste it into the Zoom, Teams or Meet chat with one keystroke. Nothing is posted on your behalf.'**
  String get copyThenPasteSub;

  /// No description provided for @whatLeaves.
  ///
  /// In en, this message translates to:
  /// **'What leaves this computer'**
  String get whatLeaves;

  /// No description provided for @leavesAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio — yours and the room’s are transcribed on this computer.'**
  String get leavesAudio;

  /// No description provided for @leavesQuestion.
  ///
  /// In en, this message translates to:
  /// **'The text of the question and the excerpts used to answer it.'**
  String get leavesQuestion;

  /// No description provided for @leavesNothingElse.
  ///
  /// In en, this message translates to:
  /// **'Nothing else: no script, no history, no account.'**
  String get leavesNothingElse;

  /// No description provided for @generalDescription.
  ///
  /// In en, this message translates to:
  /// **'Language, pace, storage and defaults. Everything Sotto keeps lives on this computer.'**
  String get generalDescription;

  /// No description provided for @interface.
  ///
  /// In en, this message translates to:
  /// **'Interface'**
  String get interface;

  /// No description provided for @interfaceLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get interfaceLanguage;

  /// No description provided for @interfaceLanguageSub.
  ///
  /// In en, this message translates to:
  /// **'System follows your computer’s language'**
  String get interfaceLanguageSub;

  /// No description provided for @langSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get langSystem;

  /// No description provided for @pace.
  ///
  /// In en, this message translates to:
  /// **'Pace'**
  String get pace;

  /// No description provided for @wordsPerMinute.
  ///
  /// In en, this message translates to:
  /// **'Words per minute'**
  String get wordsPerMinute;

  /// No description provided for @wordsPerMinuteSub.
  ///
  /// In en, this message translates to:
  /// **'Used for timing until rehearsals calibrate it'**
  String get wordsPerMinuteSub;

  /// No description provided for @storage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get storage;

  /// No description provided for @dataFolder.
  ///
  /// In en, this message translates to:
  /// **'Data folder'**
  String get dataFolder;

  /// No description provided for @copyPath.
  ///
  /// In en, this message translates to:
  /// **'Copy path'**
  String get copyPath;

  /// No description provided for @format.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get format;

  /// No description provided for @formatSub.
  ///
  /// In en, this message translates to:
  /// **'Scripts, settings, sessions and Q&A history are stored in a local database. API keys are stored in the system keychain.'**
  String get formatSub;

  /// No description provided for @resetAllSettings.
  ///
  /// In en, this message translates to:
  /// **'Reset all settings'**
  String get resetAllSettings;

  /// No description provided for @resetAllSettingsSub.
  ///
  /// In en, this message translates to:
  /// **'Scripts, sessions and API keys are kept'**
  String get resetAllSettingsSub;

  /// No description provided for @aboutSotto.
  ///
  /// In en, this message translates to:
  /// **'About Sotto'**
  String get aboutSotto;

  /// No description provided for @aboutSottoBody.
  ///
  /// In en, this message translates to:
  /// **'From sotto voce — under the voice. A live presentation assistant that keeps your script under the camera, follows your voice line by line, and drafts an answer when the room asks a question.'**
  String get aboutSottoBody;

  /// No description provided for @versionLine.
  ///
  /// In en, this message translates to:
  /// **'Version 1.0 · build 1'**
  String get versionLine;

  /// No description provided for @typefaces.
  ///
  /// In en, this message translates to:
  /// **'Typefaces: Geist, Geist Mono, Atkinson Hyperlegible Next (SIL OFL)'**
  String get typefaces;

  /// No description provided for @addKeyFirst.
  ///
  /// In en, this message translates to:
  /// **'Add a key first.'**
  String get addKeyFirst;

  /// No description provided for @connectedFirstToken.
  ///
  /// In en, this message translates to:
  /// **'Connected · first token in {seconds} s'**
  String connectedFirstToken(String seconds);

  /// No description provided for @inKeychain.
  ///
  /// In en, this message translates to:
  /// **'In keychain'**
  String get inKeychain;

  /// No description provided for @integrationsDescription.
  ///
  /// In en, this message translates to:
  /// **'Answers are drafted by DeepSeek. Add your API key; it is stored in the system keychain and sent to DeepSeek only when a question is asked.'**
  String get integrationsDescription;

  /// No description provided for @apiKey.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get apiKey;

  /// No description provided for @model.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get model;

  /// No description provided for @testConnection.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get testConnection;

  /// No description provided for @test.
  ///
  /// In en, this message translates to:
  /// **'Test'**
  String get test;

  /// No description provided for @privacyDescription.
  ///
  /// In en, this message translates to:
  /// **'Privacy by construction: presenter audio stays on this computer, room audio is captured only on the chord, and only text is sent to answer a question — plus one screenshot when you ask about your screen, if you turn that on.'**
  String get privacyDescription;

  /// No description provided for @hideFromCapture.
  ///
  /// In en, this message translates to:
  /// **'Hide the overlay from screen capture'**
  String get hideFromCapture;

  /// No description provided for @hideFromCaptureSub.
  ///
  /// In en, this message translates to:
  /// **'Uses the OS protection where available. On macOS 15+, sharing your entire screen can still capture it — share a window instead.'**
  String get hideFromCaptureSub;

  /// No description provided for @retention.
  ///
  /// In en, this message translates to:
  /// **'Retention'**
  String get retention;

  /// No description provided for @keepHistoryFor.
  ///
  /// In en, this message translates to:
  /// **'Keep Q&A history for'**
  String get keepHistoryFor;

  /// No description provided for @daysCount.
  ///
  /// In en, this message translates to:
  /// **'{count} days'**
  String daysCount(int count);

  /// No description provided for @aYear.
  ///
  /// In en, this message translates to:
  /// **'A year'**
  String get aYear;

  /// No description provided for @deleteQaHistory.
  ///
  /// In en, this message translates to:
  /// **'Delete Q&A history'**
  String get deleteQaHistory;

  /// No description provided for @deleteQaHistoryConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete Q&A history?'**
  String get deleteQaHistoryConfirm;

  /// No description provided for @deleteQaHistoryBody.
  ///
  /// In en, this message translates to:
  /// **'Every recorded question and answer is removed.'**
  String get deleteQaHistoryBody;

  /// No description provided for @dangerZone.
  ///
  /// In en, this message translates to:
  /// **'Danger zone'**
  String get dangerZone;

  /// No description provided for @removeApiKeys.
  ///
  /// In en, this message translates to:
  /// **'Remove API keys'**
  String get removeApiKeys;

  /// No description provided for @removeApiKeysSub.
  ///
  /// In en, this message translates to:
  /// **'Deletes every key Sotto stored in the keychain'**
  String get removeApiKeysSub;

  /// No description provided for @removeApiKeysConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove API keys?'**
  String get removeApiKeysConfirm;

  /// No description provided for @removeApiKeysBody.
  ///
  /// In en, this message translates to:
  /// **'Answers stop working until you add a key again.'**
  String get removeApiKeysBody;

  /// No description provided for @deleteAllData.
  ///
  /// In en, this message translates to:
  /// **'Delete all local data'**
  String get deleteAllData;

  /// No description provided for @deleteAllDataSub.
  ///
  /// In en, this message translates to:
  /// **'Scripts, collections, sessions and Q&A history'**
  String get deleteAllDataSub;

  /// No description provided for @deleteEverything.
  ///
  /// In en, this message translates to:
  /// **'Delete everything'**
  String get deleteEverything;

  /// No description provided for @deleteAllDataConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete all local data?'**
  String get deleteAllDataConfirm;

  /// No description provided for @deleteAllDataBody.
  ///
  /// In en, this message translates to:
  /// **'This removes every script and session from this computer. It can’t be undone.'**
  String get deleteAllDataBody;

  /// No description provided for @privVoice.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get privVoice;

  /// No description provided for @privVoiceBody.
  ///
  /// In en, this message translates to:
  /// **'Presenter audio never leaves this computer: speech runs on-device.'**
  String get privVoiceBody;

  /// No description provided for @privRoom.
  ///
  /// In en, this message translates to:
  /// **'Room audio'**
  String get privRoom;

  /// No description provided for @privRoomBody.
  ///
  /// In en, this message translates to:
  /// **'Captured only on the chord, shown in red, transcribed locally.'**
  String get privRoomBody;

  /// No description provided for @privAnswers.
  ///
  /// In en, this message translates to:
  /// **'Answers'**
  String get privAnswers;

  /// No description provided for @privAnswersBody.
  ///
  /// In en, this message translates to:
  /// **'Only the question text and the excerpts used are sent to DeepSeek.'**
  String get privAnswersBody;

  /// No description provided for @privModels.
  ///
  /// In en, this message translates to:
  /// **'Speech models'**
  String get privModels;

  /// No description provided for @privModelsBody.
  ///
  /// In en, this message translates to:
  /// **'Downloaded once from the sherpa-onnx project on GitHub.'**
  String get privModelsBody;

  /// No description provided for @privConsent.
  ///
  /// In en, this message translates to:
  /// **'Consent'**
  String get privConsent;

  /// No description provided for @privConsentBody.
  ///
  /// In en, this message translates to:
  /// **'Recording laws vary. Consider telling the room that Q&A assist is on.'**
  String get privConsentBody;

  /// No description provided for @llmNoBalance.
  ///
  /// In en, this message translates to:
  /// **'Your DeepSeek balance is empty. Top up at platform.deepseek.com.'**
  String get llmNoBalance;

  /// No description provided for @integrationsDescriptionBuiltIn.
  ///
  /// In en, this message translates to:
  /// **'Answers are drafted by DeepSeek with the key built into this copy of Sotto. You can override it with your own key.'**
  String get integrationsDescriptionBuiltIn;

  /// No description provided for @deepseekFooter.
  ///
  /// In en, this message translates to:
  /// **'Only the question and the excerpts used to answer it are sent.'**
  String get deepseekFooter;

  /// No description provided for @apiKeyOverrideSub.
  ///
  /// In en, this message translates to:
  /// **'Optional. Leave empty to use the built-in key.'**
  String get apiKeyOverrideSub;

  /// No description provided for @builtInKey.
  ///
  /// In en, this message translates to:
  /// **'Built-in key'**
  String get builtInKey;

  /// No description provided for @modelsLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading models…'**
  String get modelsLoading;

  /// No description provided for @modelsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load the model list: {error}'**
  String modelsLoadFailed(String error);

  /// No description provided for @deepseekPlatform.
  ///
  /// In en, this message translates to:
  /// **'Account, balance and keys'**
  String get deepseekPlatform;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @beatsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 beat} other{{count} beats}}'**
  String beatsCount(int count);

  /// No description provided for @cuesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{no cues} =1{1 cue} other{{count} cues}}'**
  String cuesCount(int count);

  /// No description provided for @readAloudTitle.
  ///
  /// In en, this message translates to:
  /// **'Read aloud'**
  String get readAloudTitle;

  /// No description provided for @readAloudHeadphones.
  ///
  /// In en, this message translates to:
  /// **'Plays through the system output — wear headphones so the room never hears it.'**
  String get readAloudHeadphones;

  /// No description provided for @welcomeStep.
  ///
  /// In en, this message translates to:
  /// **'WELCOME · {step} OF {total}'**
  String welcomeStep(int step, int total);

  /// No description provided for @welcomeSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip for now'**
  String get welcomeSkip;

  /// No description provided for @welcomeNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get welcomeNext;

  /// No description provided for @welcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get welcomeBack;

  /// No description provided for @welcomeUseExample.
  ///
  /// In en, this message translates to:
  /// **'Start with the example'**
  String get welcomeUseExample;

  /// No description provided for @welcomeModelsTitle.
  ///
  /// In en, this message translates to:
  /// **'Download the voice models'**
  String get welcomeModelsTitle;

  /// No description provided for @welcomeModelsBody.
  ///
  /// In en, this message translates to:
  /// **'Sotto follows your voice on this computer. These models are downloaded once and then work offline; your audio never leaves the device.'**
  String get welcomeModelsBody;

  /// No description provided for @welcomeModelsFooter.
  ///
  /// In en, this message translates to:
  /// **'Downloads keep going in the background. Without models, the overlay still advances with hotkeys or a timer.'**
  String get welcomeModelsFooter;

  /// No description provided for @welcomeScriptTitle.
  ///
  /// In en, this message translates to:
  /// **'Bring in your first script'**
  String get welcomeScriptTitle;

  /// No description provided for @welcomeScriptBody.
  ///
  /// In en, this message translates to:
  /// **'Sotto organizes it into sections, one-breath beats and cues. You can also start with the example talk in your library.'**
  String get welcomeScriptBody;

  /// No description provided for @welcomeImportFile.
  ///
  /// In en, this message translates to:
  /// **'Import a file'**
  String get welcomeImportFile;

  /// No description provided for @welcomeImportFileSub.
  ///
  /// In en, this message translates to:
  /// **'.docx, .pdf, .md or .txt'**
  String get welcomeImportFileSub;

  /// No description provided for @welcomePaste.
  ///
  /// In en, this message translates to:
  /// **'Paste text'**
  String get welcomePaste;

  /// No description provided for @welcomePasteSub.
  ///
  /// In en, this message translates to:
  /// **'From the clipboard'**
  String get welcomePasteSub;

  /// No description provided for @welcomeWrite.
  ///
  /// In en, this message translates to:
  /// **'Write from scratch'**
  String get welcomeWrite;

  /// No description provided for @welcomeWriteSub.
  ///
  /// In en, this message translates to:
  /// **'A blank script'**
  String get welcomeWriteSub;

  /// No description provided for @overlayStyle.
  ///
  /// In en, this message translates to:
  /// **'Overlay style'**
  String get overlayStyle;

  /// No description provided for @overlayStyleTextOnly.
  ///
  /// In en, this message translates to:
  /// **'Text only'**
  String get overlayStyleTextOnly;

  /// No description provided for @overlayStylePanel.
  ///
  /// In en, this message translates to:
  /// **'Panel'**
  String get overlayStylePanel;

  /// No description provided for @overlayStyleTextOnlySub.
  ///
  /// In en, this message translates to:
  /// **'No background — just outlined words over your slides'**
  String get overlayStyleTextOnlySub;

  /// No description provided for @overlayStylePanelSub.
  ///
  /// In en, this message translates to:
  /// **'A translucent card behind the text'**
  String get overlayStylePanelSub;

  /// No description provided for @overlayStyleTextOnlyFooter.
  ///
  /// In en, this message translates to:
  /// **'Controls and the status strip appear when you hover the overlay or use a shortcut, then fade after 2 seconds.'**
  String get overlayStyleTextOnlyFooter;

  /// No description provided for @textColor.
  ///
  /// In en, this message translates to:
  /// **'Text color'**
  String get textColor;

  /// No description provided for @outlineColor.
  ///
  /// In en, this message translates to:
  /// **'Outline'**
  String get outlineColor;

  /// No description provided for @outlineAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto — contrasts with the text'**
  String get outlineAuto;

  /// No description provided for @outlineAutoSub.
  ///
  /// In en, this message translates to:
  /// **'Auto: dark around light text, light around dark text'**
  String get outlineAutoSub;

  /// No description provided for @outlineWidth.
  ///
  /// In en, this message translates to:
  /// **'Outline width'**
  String get outlineWidth;

  /// No description provided for @shadowStrength.
  ///
  /// In en, this message translates to:
  /// **'Shadow'**
  String get shadowStrength;

  /// No description provided for @modelReadsImages.
  ///
  /// In en, this message translates to:
  /// **'reads screenshots'**
  String get modelReadsImages;

  /// No description provided for @sourceScreen.
  ///
  /// In en, this message translates to:
  /// **'Your screen'**
  String get sourceScreen;

  /// No description provided for @actionAskScreen.
  ///
  /// In en, this message translates to:
  /// **'Ask about the screen'**
  String get actionAskScreen;

  /// No description provided for @actionAskScreenSub.
  ///
  /// In en, this message translates to:
  /// **'Takes one screenshot, then listens for your question'**
  String get actionAskScreenSub;

  /// No description provided for @noticeScreenOff.
  ///
  /// In en, this message translates to:
  /// **'Screen awareness is off — turn it on in Settings → Privacy'**
  String get noticeScreenOff;

  /// No description provided for @noticeScreenPermission.
  ///
  /// In en, this message translates to:
  /// **'Sotto needs Screen Recording permission — see Settings → Privacy'**
  String get noticeScreenPermission;

  /// No description provided for @defaultScreenQuestion.
  ///
  /// In en, this message translates to:
  /// **'What is on my screen right now, and what should I say about it?'**
  String get defaultScreenQuestion;

  /// No description provided for @capturingScreen.
  ///
  /// In en, this message translates to:
  /// **'Capturing screen'**
  String get capturingScreen;

  /// No description provided for @screenshotAttached.
  ///
  /// In en, this message translates to:
  /// **'Screenshot attached — sent to DeepSeek with your question'**
  String get screenshotAttached;

  /// No description provided for @screenAwareness.
  ///
  /// In en, this message translates to:
  /// **'Screen awareness'**
  String get screenAwareness;

  /// No description provided for @screenAwarenessFooter.
  ///
  /// In en, this message translates to:
  /// **'Screenshots are taken only when you ask, scaled down, sent to DeepSeek with your question and never saved. Sotto\'s own overlay never appears in them. A red “Capturing screen” light shows each time.'**
  String get screenAwarenessFooter;

  /// No description provided for @screenAwarenessToggle.
  ///
  /// In en, this message translates to:
  /// **'Let Sotto look at my screen when I ask'**
  String get screenAwarenessToggle;

  /// No description provided for @screenAwarenessToggleSub.
  ///
  /// In en, this message translates to:
  /// **'Off by default. Screenshots are sent to DeepSeek.'**
  String get screenAwarenessToggleSub;

  /// No description provided for @screenTarget.
  ///
  /// In en, this message translates to:
  /// **'Capture'**
  String get screenTarget;

  /// No description provided for @screenTargetOverlay.
  ///
  /// In en, this message translates to:
  /// **'The display with the overlay'**
  String get screenTargetOverlay;

  /// No description provided for @screenTargetCursor.
  ///
  /// In en, this message translates to:
  /// **'The display under the pointer'**
  String get screenTargetCursor;

  /// No description provided for @attachSlide.
  ///
  /// In en, this message translates to:
  /// **'Show the slide with audience questions'**
  String get attachSlide;

  /// No description provided for @attachSlideSub.
  ///
  /// In en, this message translates to:
  /// **'Each question also sends one screenshot of what is on screen'**
  String get attachSlideSub;

  /// No description provided for @screenPermissionMissing.
  ///
  /// In en, this message translates to:
  /// **'Screen Recording permission needed'**
  String get screenPermissionMissing;

  /// No description provided for @screenPermissionMissingSub.
  ///
  /// In en, this message translates to:
  /// **'System Settings → Privacy & Security → Screen Recording → Sotto'**
  String get screenPermissionMissingSub;

  /// No description provided for @openSystemSettings.
  ///
  /// In en, this message translates to:
  /// **'Open System Settings'**
  String get openSystemSettings;

  /// No description provided for @privScreen.
  ///
  /// In en, this message translates to:
  /// **'Screenshots'**
  String get privScreen;

  /// No description provided for @privScreenOffBody.
  ///
  /// In en, this message translates to:
  /// **'Off. Sotto never looks at your screen.'**
  String get privScreenOffBody;

  /// No description provided for @privScreenOnBody.
  ///
  /// In en, this message translates to:
  /// **'Only when you ask: one screenshot goes to DeepSeek with the question. Never saved.'**
  String get privScreenOnBody;

  /// No description provided for @readyScreenOk.
  ///
  /// In en, this message translates to:
  /// **'On — one screenshot per question you ask about the screen'**
  String get readyScreenOk;

  /// No description provided for @actionAgentTask.
  ///
  /// In en, this message translates to:
  /// **'Agent task'**
  String get actionAgentTask;

  /// No description provided for @actionAgentTaskSub.
  ///
  /// In en, this message translates to:
  /// **'Say a task; the agent does it on screen, step by step'**
  String get actionAgentTaskSub;

  /// No description provided for @actionAgentStop.
  ///
  /// In en, this message translates to:
  /// **'Stop the agent'**
  String get actionAgentStop;

  /// No description provided for @actionAgentStopSub.
  ///
  /// In en, this message translates to:
  /// **'Emergency stop — cancels at once and lets go of every key'**
  String get actionAgentStopSub;

  /// No description provided for @agentOff.
  ///
  /// In en, this message translates to:
  /// **'Agent mode is off — turn it on in Settings → Privacy'**
  String get agentOff;

  /// No description provided for @agentUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Agent mode works on Windows for now.'**
  String get agentUnsupported;

  /// No description provided for @agentNeedsAccessibility.
  ///
  /// In en, this message translates to:
  /// **'Sotto needs Accessibility permission to control the mouse and keyboard — see Settings → Privacy.'**
  String get agentNeedsAccessibility;

  /// No description provided for @agentListening.
  ///
  /// In en, this message translates to:
  /// **'Describe the task'**
  String get agentListening;

  /// No description provided for @agentStarting.
  ///
  /// In en, this message translates to:
  /// **'Looking at the screen…'**
  String get agentStarting;

  /// No description provided for @agentThinking.
  ///
  /// In en, this message translates to:
  /// **'Deciding the next step…'**
  String get agentThinking;

  /// No description provided for @agentWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for you'**
  String get agentWaiting;

  /// No description provided for @agentActing.
  ///
  /// In en, this message translates to:
  /// **'Working…'**
  String get agentActing;

  /// No description provided for @agentInControl.
  ///
  /// In en, this message translates to:
  /// **'AGENT IN CONTROL'**
  String get agentInControl;

  /// No description provided for @agentStep.
  ///
  /// In en, this message translates to:
  /// **'step {step}/{max}'**
  String agentStep(int step, int max);

  /// No description provided for @agentStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get agentStop;

  /// No description provided for @agentStopHint.
  ///
  /// In en, this message translates to:
  /// **'Emergency stop: {keys} — works everywhere'**
  String agentStopHint(String keys);

  /// No description provided for @agentCouldNotStart.
  ///
  /// In en, this message translates to:
  /// **'Could not start'**
  String get agentCouldNotStart;

  /// No description provided for @agentCompleted.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get agentCompleted;

  /// No description provided for @agentStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped — nothing else will run'**
  String get agentStopped;

  /// No description provided for @agentDeclined.
  ///
  /// In en, this message translates to:
  /// **'Stopped at your request'**
  String get agentDeclined;

  /// No description provided for @agentLimit.
  ///
  /// In en, this message translates to:
  /// **'Stopped after {max} steps'**
  String agentLimit(int max);

  /// No description provided for @agentFailed.
  ///
  /// In en, this message translates to:
  /// **'Stopped by an error'**
  String get agentFailed;

  /// No description provided for @agentNext.
  ///
  /// In en, this message translates to:
  /// **'NEXT ACTION'**
  String get agentNext;

  /// No description provided for @agentConfirmSensitive.
  ///
  /// In en, this message translates to:
  /// **'CONFIRM — {reason}'**
  String agentConfirmSensitive(String reason);

  /// No description provided for @agentRun.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get agentRun;

  /// No description provided for @agentStopTask.
  ///
  /// In en, this message translates to:
  /// **'Stop task'**
  String get agentStopTask;

  /// No description provided for @agentCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Let the agent do it'**
  String get agentCardTitle;

  /// No description provided for @agentCardBody.
  ///
  /// In en, this message translates to:
  /// **'Describe a task — “fill this form with my details from the prep docs”. The agent works on screen, one step at a time, and asks before anything that submits, sends, pays or deletes.'**
  String get agentCardBody;

  /// No description provided for @agentTaskPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'What should the agent do?'**
  String get agentTaskPlaceholder;

  /// No description provided for @agentRunTask.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get agentRunTask;

  /// No description provided for @agentMode.
  ///
  /// In en, this message translates to:
  /// **'Agent mode'**
  String get agentMode;

  /// No description provided for @agentModeFooter.
  ///
  /// In en, this message translates to:
  /// **'The agent sends screenshots to DeepSeek and moves the mouse and keyboard, at most 25 steps per task. It never types into password fields or handles payment data, always asks before submitting, sending, paying, deleting or buying, shows an amber frame while in control, and logs every action in the session. {keys} stops it at once, from anywhere.'**
  String agentModeFooter(String keys);

  /// No description provided for @agentToggle.
  ///
  /// In en, this message translates to:
  /// **'Let Sotto control my mouse and keyboard'**
  String get agentToggle;

  /// No description provided for @agentToggleSub.
  ///
  /// In en, this message translates to:
  /// **'Off by default. Only for tasks you start.'**
  String get agentToggleSub;

  /// No description provided for @agentAutonomy.
  ///
  /// In en, this message translates to:
  /// **'Supervision'**
  String get agentAutonomy;

  /// No description provided for @agentConfirmEach.
  ///
  /// In en, this message translates to:
  /// **'Confirm each action'**
  String get agentConfirmEach;

  /// No description provided for @agentAuto.
  ///
  /// In en, this message translates to:
  /// **'Run automatically'**
  String get agentAuto;

  /// No description provided for @agentConfirmEachSub.
  ///
  /// In en, this message translates to:
  /// **'Enter runs the shown action, Esc stops'**
  String get agentConfirmEachSub;

  /// No description provided for @agentAutoSub.
  ///
  /// In en, this message translates to:
  /// **'Still asks before anything that submits, sends, pays, deletes or buys'**
  String get agentAutoSub;

  /// No description provided for @accessibilityMissing.
  ///
  /// In en, this message translates to:
  /// **'Accessibility permission needed'**
  String get accessibilityMissing;

  /// No description provided for @accessibilityMissingSub.
  ///
  /// In en, this message translates to:
  /// **'System Settings → Privacy & Security → Accessibility → Sotto'**
  String get accessibilityMissingSub;

  /// No description provided for @sessionAgentTask.
  ///
  /// In en, this message translates to:
  /// **'Agent: {task}'**
  String sessionAgentTask(String task);

  /// No description provided for @sessionAgentActions.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 action} other{{count} actions}}'**
  String sessionAgentActions(int count);

  /// No description provided for @readyAgentOk.
  ///
  /// In en, this message translates to:
  /// **'On — confirm each action'**
  String get readyAgentOk;

  /// No description provided for @readyAgentAuto.
  ///
  /// In en, this message translates to:
  /// **'On — runs automatically, asks before irreversible steps'**
  String get readyAgentAuto;

  /// No description provided for @agentDoClick.
  ///
  /// In en, this message translates to:
  /// **'Click “{target}” at {at}'**
  String agentDoClick(String target, String at);

  /// No description provided for @agentDoDoubleClick.
  ///
  /// In en, this message translates to:
  /// **'Double-click “{target}” at {at}'**
  String agentDoDoubleClick(String target, String at);

  /// No description provided for @agentDoRightClick.
  ///
  /// In en, this message translates to:
  /// **'Right-click “{target}” at {at}'**
  String agentDoRightClick(String target, String at);

  /// No description provided for @agentDoMove.
  ///
  /// In en, this message translates to:
  /// **'Move the pointer to {at}'**
  String agentDoMove(String at);

  /// No description provided for @agentDoType.
  ///
  /// In en, this message translates to:
  /// **'Type “{text}” into {target}'**
  String agentDoType(String text, String target);

  /// No description provided for @agentDoKeys.
  ///
  /// In en, this message translates to:
  /// **'Press {keys}'**
  String agentDoKeys(String keys);

  /// No description provided for @agentDoScrollDown.
  ///
  /// In en, this message translates to:
  /// **'Scroll down'**
  String get agentDoScrollDown;

  /// No description provided for @agentDoScrollUp.
  ///
  /// In en, this message translates to:
  /// **'Scroll up'**
  String get agentDoScrollUp;

  /// No description provided for @agentDoWait.
  ///
  /// In en, this message translates to:
  /// **'Wait {ms} ms'**
  String agentDoWait(int ms);

  /// No description provided for @agentDoScreenshot.
  ///
  /// In en, this message translates to:
  /// **'Look at the screen again'**
  String get agentDoScreenshot;

  /// No description provided for @agentDoDone.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get agentDoDone;

  /// No description provided for @agentWhyPassword.
  ///
  /// In en, this message translates to:
  /// **'the focused field is a password field'**
  String get agentWhyPassword;

  /// No description provided for @agentWhySecret.
  ///
  /// In en, this message translates to:
  /// **'it looks like a password or security-code field'**
  String get agentWhySecret;

  /// No description provided for @agentWhyPayment.
  ///
  /// In en, this message translates to:
  /// **'it looks like a payment field'**
  String get agentWhyPayment;

  /// No description provided for @agentWhyCard.
  ///
  /// In en, this message translates to:
  /// **'the text looks like a card number'**
  String get agentWhyCard;

  /// No description provided for @agentWhyIrreversible.
  ///
  /// In en, this message translates to:
  /// **'it may submit, send, pay or delete'**
  String get agentWhyIrreversible;

  /// No description provided for @agentWhySubmitKey.
  ///
  /// In en, this message translates to:
  /// **'it may submit or delete'**
  String get agentWhySubmitKey;

  /// No description provided for @agentWhyOutside.
  ///
  /// In en, this message translates to:
  /// **'outside the screenshot'**
  String get agentWhyOutside;

  /// No description provided for @privAgent.
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get privAgent;

  /// No description provided for @privAgentOffBody.
  ///
  /// In en, this message translates to:
  /// **'Off. Sotto never moves your mouse or types.'**
  String get privAgentOffBody;

  /// No description provided for @privAgentOnBody.
  ///
  /// In en, this message translates to:
  /// **'Only for tasks you start: one screenshot per step goes to DeepSeek; every action is logged in the session.'**
  String get privAgentOnBody;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

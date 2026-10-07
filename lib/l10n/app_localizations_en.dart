// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Sotto';

  @override
  String get statusOrganizing => 'Refining…';

  @override
  String statusRehearsedTimes(int count) {
    return 'Rehearsed ×$count';
  }

  @override
  String get statusRehearsed => 'Rehearsed';

  @override
  String get statusStructured => 'Structured';

  @override
  String get statusDraft => 'Draft';

  @override
  String get timeJustNow => 'Just now';

  @override
  String timeMinutesAgo(int minutes) {
    return '$minutes min ago';
  }

  @override
  String timeHoursAgo(int hours) {
    return '$hours h ago';
  }

  @override
  String timeEditedMinutesAgo(int minutes) {
    return 'Edited $minutes min ago';
  }

  @override
  String timeEditedHoursAgo(int hours) {
    return 'Edited $hours h ago';
  }

  @override
  String get timeYesterday => 'Yesterday';

  @override
  String get timeToday => 'Today';

  @override
  String get actionGoLive => 'Go live or end session';

  @override
  String get actionGoLiveSub => 'Starts from the section chosen in pre-flight';

  @override
  String get actionPause => 'Pause or resume following';

  @override
  String get actionPauseSub => 'Freezes the script; your place is kept';

  @override
  String get actionNextBeat => 'Next beat';

  @override
  String get actionNextBeatSub => 'One breath forward — works while following';

  @override
  String get actionPrevBeat => 'Previous beat';

  @override
  String get actionPrevBeatSub => 'Also holds following for 3 seconds';

  @override
  String get actionNextSection => 'Next section';

  @override
  String get actionPrevSection => 'Previous section';

  @override
  String get actionAsk => 'Ask a question';

  @override
  String get actionAskSub => 'Listens to the room until it goes quiet';

  @override
  String get actionSend => 'Send answer to chat';

  @override
  String get actionSendSub => 'Hold for half a second, so it can\'t fire by accident';

  @override
  String get actionReadAloud => 'Read answer aloud';

  @override
  String get actionReadAloudSub => 'Plays in your headphones only';

  @override
  String get actionDismiss => 'Dismiss answer';

  @override
  String get actionDismissSub => 'Returns to the script where you left it';

  @override
  String get actionHistory => 'Questions history';

  @override
  String get actionHide => 'Hide overlay instantly';

  @override
  String get actionHideSub => 'No animation. Press again to bring it back.';

  @override
  String get actionClickThrough => 'Click-through';

  @override
  String get actionClickThroughSub => 'The overlay stops catching the mouse';

  @override
  String get actionTextBigger => 'Text size up';

  @override
  String get actionTextSmaller => 'Text size down';

  @override
  String get actionMoveDisplay => 'Move to next display';

  @override
  String get actionMoveDisplaySub => 'Remembers a position per display';

  @override
  String get keySpace => 'Space';

  @override
  String get modShiftShort => 'Shift';

  @override
  String get modShift => 'Shift';

  @override
  String get modOption => 'Option';

  @override
  String get modCommand => 'Command';

  @override
  String get untitledScript => 'Untitled script';

  @override
  String get sectionOpening => 'Opening';

  @override
  String get sectionFallback => 'Section';

  @override
  String get newSectionTitle => 'New section';

  @override
  String get cueSlide => 'SLIDE';

  @override
  String get cuePause => 'PAUSE';

  @override
  String get cueDemo => 'DEMO';

  @override
  String get cueNote => 'NOTE';

  @override
  String copyTitle(String title) {
    return '$title copy';
  }

  @override
  String get importUnsupported => 'Sotto can import .docx, .pdf, .md and .txt files.';

  @override
  String importNoText(String name) {
    return '$name has no text Sotto can read.';
  }

  @override
  String get importNoBody => 'This .docx file has no document body.';

  @override
  String get pastedScript => 'Pasted script';

  @override
  String get pastedText => 'Pasted text';

  @override
  String get dialogImportScript => 'Import a script';

  @override
  String get llmRejected => 'The request was rejected';

  @override
  String llmBadKey(String provider) {
    return '$provider rejected the API key. Check it in Settings → Integrations.';
  }

  @override
  String get llmNoModel => 'Model not found. Check the model name in Settings → Integrations.';

  @override
  String llmRateLimit(String provider) {
    return '$provider is rate-limiting requests. Try again in a moment.';
  }

  @override
  String llmServerError(String provider, int status) {
    return '$provider is having trouble right now ($status).';
  }

  @override
  String llmFailed(int status) {
    return 'Request failed ($status)';
  }

  @override
  String get llmRefusal => 'The model declined to answer this question.';

  @override
  String llmTimeout(String provider) {
    return '$provider did not respond — check your connection';
  }

  @override
  String llmOffline(String provider) {
    return 'No connection to $provider. Answers need the internet; the script still follows your voice offline.';
  }

  @override
  String llmUnreachable(String provider, String error) {
    return 'Could not reach $provider: $error';
  }

  @override
  String llmGenericError(String provider) {
    return '$provider returned an error.';
  }

  @override
  String get modelStreamingEn => 'English · streaming';

  @override
  String get modelStreamingEnDesc => 'Follows your voice word by word';

  @override
  String get modelStreamingEnLight => 'English · streaming (light)';

  @override
  String get modelStreamingEnLightDesc => 'For older or low-power machines';

  @override
  String get modelWhisperBase => 'Whisper base';

  @override
  String get modelWhisperBaseDesc => 'Question transcripts in 99 languages; also follows non-English scripts';

  @override
  String get modelWhisperTurbo => 'Whisper large-v3 turbo';

  @override
  String get modelWhisperTurboDesc => 'Most accurate question transcripts; needs a fast machine';

  @override
  String modelDownloadFailed(int status) {
    return 'Download failed ($status).';
  }

  @override
  String get modelIncomplete => 'The model archive was incomplete.';

  @override
  String get modelOffline => 'No internet connection. Models download once, then work offline.';

  @override
  String get engineUnavailable => 'Unavailable';

  @override
  String get engineOnDeviceStreaming => 'On-device · streaming';

  @override
  String get engineOnDeviceWhisper => 'On-device · Whisper';

  @override
  String get engineModelsMissing =>
      'Speech models are not installed yet. Download them in Settings → Voice & following.';

  @override
  String sttEngineFailed(String error) {
    return 'Speech engine failed to start: $error';
  }

  @override
  String get sttNoModel => 'No transcription model installed.';

  @override
  String get sttStopped => 'Speech engine stopped.';

  @override
  String get micPermission => 'Sotto needs microphone access. Allow it in System Settings → Privacy.';

  @override
  String noticeShortcutsTaken(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count shortcuts are taken by another app',
      one: '1 shortcut is taken by another app',
    );
    return '$_temp0';
  }

  @override
  String get noticeNoSpeechForQuestions => 'Questions need a speech engine — see Settings → Voice & following.';

  @override
  String get noticeNoQuestion => 'Didn\'t catch a question';

  @override
  String get answerNeedsKey => 'Add an API key in Settings → Integrations to draft answers.';

  @override
  String get noticeCopiedForChat => 'Copied — paste into the meeting chat';

  @override
  String get noticeAnswerCopied => 'Answer copied';

  @override
  String get readyNoMic => 'No microphone';

  @override
  String get readyHotkeysOnly => 'Hotkeys only';

  @override
  String get readyAdvanceManual => 'Advance: manual';

  @override
  String readyOnDevice(String langs) {
    return 'On-device · $langs';
  }

  @override
  String get readyDownloadModels => 'Download speech models in Voice & following';

  @override
  String readyHotkeys(String chord) {
    return 'Hotkeys $chord';
  }

  @override
  String readyTakenByOther(int count) {
    return '$count taken by another app';
  }

  @override
  String get readyNoKey => 'No API key';

  @override
  String get readyAddKey => 'Add one in Integrations to draft answers';

  @override
  String get readyShareWindow => 'Share a window';

  @override
  String get readyShareWarning => 'Sharing your entire screen can capture the overlay on macOS 15+';

  @override
  String get sourceQaPrep => 'Q&A prep';

  @override
  String get sourceGeneral => 'General knowledge · verify';

  @override
  String get notInYourNotes => 'Not in your notes.';

  @override
  String get sidebarShow => 'Show sidebar';

  @override
  String get sidebarHide => 'Hide sidebar';

  @override
  String get search => 'Search';

  @override
  String get navHome => 'Home';

  @override
  String get navAllScripts => 'All scripts';

  @override
  String get navSessions => 'Sessions';

  @override
  String get navArchive => 'Archive';

  @override
  String get navCollections => 'Collections';

  @override
  String get navSettings => 'Settings';

  @override
  String get newCollection => 'New collection';

  @override
  String get collectionName => 'Collection name';

  @override
  String get liveReadiness => 'Live readiness';

  @override
  String readinessCount(int passed, int total) {
    return '$passed of $total';
  }

  @override
  String get dropHintDrop => 'Drop a ';

  @override
  String get dropHintOr => ' or ';

  @override
  String get dropHintPaste => ' anywhere, or paste with  ';

  @override
  String get dropHintOrganize => '  — Sotto organizes it into sections, beats and cues.';

  @override
  String get browseFiles => 'Browse files';

  @override
  String get import => 'Import';

  @override
  String get newScript => 'New script';

  @override
  String get upNext => 'Up next';

  @override
  String get recentScripts => 'Recent scripts';

  @override
  String get filterAll => 'All';

  @override
  String get filterDrafts => 'Drafts';

  @override
  String get filterReady => 'Ready';

  @override
  String get gridView => 'Grid view';

  @override
  String get listView => 'List view';

  @override
  String get emptyNoScriptsHere => 'No scripts here yet';

  @override
  String get emptyWriteOrDrop => 'Write one, paste one, or drop a file anywhere in this window.';

  @override
  String inMinutes(int minutes) {
    return 'in $minutes min';
  }

  @override
  String inHours(int hours) {
    return 'in $hours h';
  }

  @override
  String sectionsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count sections', one: '1 section');
    return '$_temp0';
  }

  @override
  String atYourPace(String duration, int wpm) {
    return '$duration at your pace ($wpm wpm)';
  }

  @override
  String rehearsedTimes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'rehearsed $count times',
      two: 'rehearsed twice',
      one: 'rehearsed once',
    );
    return '$_temp0';
  }

  @override
  String prepDocsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count prep documents',
      one: '1 prep document',
    );
    return '$_temp0';
  }

  @override
  String get goLive => 'Go live';

  @override
  String get rehearse => 'Rehearse';

  @override
  String get notRehearsedYet => 'Not rehearsed yet';

  @override
  String lastRehearsal(String duration) {
    return 'Last rehearsal $duration';
  }

  @override
  String get deleteCollection => 'Delete collection';

  @override
  String get emptyNothingArchived => 'Nothing archived';

  @override
  String get emptyNoScripts => 'No scripts yet';

  @override
  String get emptyNoMatches => 'No matches';

  @override
  String get emptyArchivedHint => 'Archived scripts stay searchable here and never appear in Up next.';

  @override
  String emptyNoMatchesHint(String query) {
    return 'Nothing in titles or script text matches \"$query\".';
  }

  @override
  String scriptsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count scripts', one: '1 script');
    return '$_temp0';
  }

  @override
  String get noCollection => 'No collection';

  @override
  String importedFinding(String source) {
    return 'Imported from $source. Finding sections, beats and cues…';
  }

  @override
  String get importedFromText => 'text';

  @override
  String get emptyScript => 'Empty script';

  @override
  String get menuOpen => 'Open';

  @override
  String get menuDuplicate => 'Duplicate';

  @override
  String get menuMoveToCollection => 'Move to collection';

  @override
  String get menuSchedule => 'Schedule…';

  @override
  String get menuExportMarkdown => 'Export as Markdown';

  @override
  String get menuArchive => 'Archive';

  @override
  String get menuUnarchive => 'Unarchive';

  @override
  String get delete => 'Delete';

  @override
  String get cancel => 'Cancel';

  @override
  String get exportScript => 'Export script';

  @override
  String deleteScriptTitle(String title) {
    return 'Delete “$title”?';
  }

  @override
  String get deleteScriptBody => 'Its Q&A history is deleted too. This can’t be undone.';

  @override
  String get emptyNoSessions => 'No sessions yet';

  @override
  String get emptyNoSessionsHint =>
      'Every live run and rehearsal lands here with its timing, so your pace keeps getting more accurate.';

  @override
  String get rehearsal => 'Rehearsal';

  @override
  String get liveSession => 'Live session';

  @override
  String get liveChip => 'Live';

  @override
  String wpmValue(int wpm) {
    return '$wpm wpm';
  }

  @override
  String questionsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count questions', one: '1 question');
    return '$_temp0';
  }

  @override
  String get deleteSession => 'Delete session';

  @override
  String get overlayPreview => 'Overlay preview';

  @override
  String get followCursor => 'Follow cursor';

  @override
  String get layoutTicker => 'Ticker';

  @override
  String get layoutStandard => 'Standard';

  @override
  String get layoutColumn => 'Column';

  @override
  String get layoutRail => 'Rail';

  @override
  String get layoutAuto => 'Auto';

  @override
  String beatPosition(int section, int beat, String duration) {
    return 'Beat $section.$beat · $duration';
  }

  @override
  String get noMoreCues => 'No more cues';

  @override
  String nextCueIn(int count, String cue) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Next cue: $cue in $count beats',
      one: 'Next cue: $cue in 1 beat',
    );
    return '$_temp0';
  }

  @override
  String get listenForWords => 'Listen for these words';

  @override
  String get add => 'Add';

  @override
  String get hintWordsExplain => 'Names and numbers from this script are sent to speech recognition as hints.';

  @override
  String get remove => 'Remove';

  @override
  String get hintWordPlaceholder => 'A name or number, then Enter';

  @override
  String get deliveryCheck => 'Delivery check';

  @override
  String get markAsReady => 'Mark as ready';

  @override
  String get checkCuesOrdered => 'Cues are in reading order';

  @override
  String get checkCuesBackwards => 'Slide cues jump backwards';

  @override
  String get checkBeatsFit => 'Every beat fits in one breath';

  @override
  String checkLongBeats(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count long beats — over 28 words',
      one: '1 long beat — over 28 words',
    );
    return '$_temp0';
  }

  @override
  String get checkNumbersSpoken => 'Numbers written the way you say them';

  @override
  String checkNumbersAbbreviated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count beats with abbreviated numbers (write “48.2 million”, not “48.2M”)',
      one: '1 beat with abbreviated numbers (write “48.2 million”, not “48.2M”)',
    );
    return '$_temp0';
  }

  @override
  String checkEmptyBeats(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count empty beats', one: '1 empty beat');
    return '$_temp0';
  }

  @override
  String get scriptMissing => 'This script no longer exists.';

  @override
  String get backToLibrary => 'Back to library';

  @override
  String get library => 'Library';

  @override
  String get saved => 'Saved';

  @override
  String get editing => 'Editing…';

  @override
  String get tabWrite => 'Write';

  @override
  String get tabQaPrep => 'Q&A prep';

  @override
  String get tabRehearsals => 'Rehearsals';

  @override
  String get structure => 'Structure';

  @override
  String get organizeAgain => 'Organize again — sections, beats and cues';

  @override
  String get addSection => 'Add section';

  @override
  String get timing => 'Timing';

  @override
  String plannedDuration(String duration) {
    return '$duration planned';
  }

  @override
  String get setTarget => 'set target';

  @override
  String targetDuration(String duration) {
    return '$duration target';
  }

  @override
  String paceNote(int wpm) {
    return 'At $wpm wpm.';
  }

  @override
  String paceNoteMeasured(int count, int wpm) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'At $wpm wpm, measured over $count rehearsals.',
      one: 'At $wpm wpm, measured over 1 rehearsal.',
    );
    return '$_temp0';
  }

  @override
  String get targetLength => 'Target length';

  @override
  String get durationPlaceholder => 'm:ss — empty to clear';

  @override
  String get save => 'Save';

  @override
  String get deleteSection => 'Delete section';

  @override
  String timeForSection(String title) {
    return 'Time for “$title”';
  }

  @override
  String wordsAtPace(int words, String duration, int wpm) {
    return '$words words · $duration at $wpm wpm';
  }

  @override
  String beatWords(int section, int beat, int words) {
    return 'Beat $section.$beat · $words words';
  }

  @override
  String sectionHeader(int index, int count, String duration, String start) {
    return 'Section $index of $count · $duration · starts at $start';
  }

  @override
  String get sectionTitle => 'Section title';

  @override
  String get addBeat => '+  Add a beat';

  @override
  String get transitionTo => '→  Transition to  ';

  @override
  String get beatHint => 'One breath of text. Type [SLIDE 3] or [PAUSE] for a cue.';

  @override
  String get cueMenuSlide => 'Slide';

  @override
  String get cueMenuSlideNext => 'Slide number +1';

  @override
  String get cueMenuSlidePrev => 'Slide number −1';

  @override
  String get cueMenuPause => 'Pause';

  @override
  String get cueMenuDemo => 'Demo';

  @override
  String get cueMenuRemove => 'Remove cue';

  @override
  String get addCue => 'Add a cue';

  @override
  String longBeat(int words) {
    return 'Long beat · $words words. ';
  }

  @override
  String get longBeatPause => 'Consider a pause for a natural breath.';

  @override
  String longBeatSplitAfter(String word) {
    return 'Split after “$word” for a natural breath?';
  }

  @override
  String get ignore => 'Ignore';

  @override
  String get split => 'Split';

  @override
  String get keyPoints => 'Key points';

  @override
  String get keyPointsNote => 'Shown in Column layout and rehearsal';

  @override
  String get keyPointsHint => 'One per line — the few things this section must land';

  @override
  String get addPrepDocument => 'Add a prep document';

  @override
  String pastedNotes(int number) {
    return 'Pasted notes $number';
  }

  @override
  String get suggestNeedsKey => 'Add an API key in Settings → Integrations to suggest questions.';

  @override
  String get noQuestionsReturned => 'The model returned no questions.';

  @override
  String get likelyQuestions => 'Likely questions';

  @override
  String get suggestWithAi => 'Suggest with AI';

  @override
  String get addQuestion => 'Add question';

  @override
  String get likelyQuestionsNote =>
      'When a live question matches one of these, its answer appears instantly — no model call.';

  @override
  String get noPreparedQuestions => 'No prepared questions yet. Add the ones you dread most.';

  @override
  String get prepDocuments => 'Prep documents';

  @override
  String get paste => 'Paste';

  @override
  String get addFile => 'Add file';

  @override
  String get prepDocumentsNote =>
      'Answers can cite these. They stay on this computer; only excerpts relevant to a question are sent.';

  @override
  String get noPrepDocuments => 'Board memos, contracts, FAQs — anything you might be asked about.';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get questionHint => 'The question, as someone might ask it';

  @override
  String get deleteQuestion => 'Delete question';

  @override
  String get answerHint => 'Your answer. The first sentence becomes the headline.';

  @override
  String wordsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count words', one: '1 word');
    return '$_temp0';
  }

  @override
  String get removeDocument => 'Remove document';

  @override
  String get noRehearsalsYet => 'No rehearsals yet';

  @override
  String get noRehearsalsHint => 'Rehearse with the real overlay. Sotto times every section and learns your pace.';

  @override
  String get rehearseNow => 'Rehearse now';

  @override
  String get latestRehearsal => 'Latest rehearsal';

  @override
  String get latestSession => 'Latest session';

  @override
  String ofPlanned(String duration) {
    return ' of $duration planned';
  }

  @override
  String get allRuns => 'All runs';

  @override
  String get questionsAsked => 'Questions asked';

  @override
  String get pfMicrophone => 'Microphone';

  @override
  String pfMicReady(String device) {
    return '$device · ready';
  }

  @override
  String get pfNoInput => 'No input device found';

  @override
  String get pfVoiceFollowing => 'Voice following';

  @override
  String pfTunedTo(String engine, int wpm) {
    return '$engine · tuned to $wpm wpm';
  }

  @override
  String get pfOverlay => 'Overlay';

  @override
  String pfOverlayDetail(String placement, int opacity, String size) {
    return '$placement · $opacity% · text $size';
  }

  @override
  String get pfScreenSharing => 'Screen sharing';

  @override
  String get pfShareProtected =>
      'Sotto hides itself from captures where the OS allows it. On macOS 15 and later, sharing your entire screen can still capture the overlay — share only the slides window.';

  @override
  String get pfShareUnprotected => 'Capture protection is off. Share only the slides window.';

  @override
  String get pfAnswers => 'Answers';

  @override
  String get pfGrounded => 'Grounded in this script';

  @override
  String pfPlusPrepDocs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: ' + $count prep documents',
      one: ' + 1 prep document',
    );
    return '$_temp0';
  }

  @override
  String get pfQuestionLanguage => ' · answers in the question’s language';

  @override
  String get pfMeetingChat => 'Meeting chat';

  @override
  String get pfMeetingChatDetail => 'Hold to copy an answer, then paste it into Zoom, Teams or Meet';

  @override
  String get pfChoose => 'Choose';

  @override
  String get pfSetUp => 'Set up';

  @override
  String get pfAdjust => 'Adjust';

  @override
  String get pfAddKey => 'Add key';

  @override
  String pfSummary(String duration, String sections) {
    return '$duration · $sections';
  }

  @override
  String pfChecksPassed(int passed, int total) {
    return ' · $passed of $total checks passed';
  }

  @override
  String get closeEsc => 'Close  esc';

  @override
  String get startFrom => 'Start from';

  @override
  String get goLiveInstead => 'Go live instead';

  @override
  String get rehearseInstead => 'Rehearse instead';

  @override
  String get hintNextBeat => 'next beat';

  @override
  String get hintAsk => 'ask';

  @override
  String get hintHide => 'hide instantly';

  @override
  String get placeUnderCamera => 'Under the camera';

  @override
  String get placeTopLeft => 'Top left';

  @override
  String get placeTopRight => 'Top right';

  @override
  String get placeLeftEdge => 'Left edge';

  @override
  String get placeCentered => 'Centered';

  @override
  String get placeRightEdge => 'Right edge';

  @override
  String get placeBottomLeft => 'Bottom left';

  @override
  String get placeBottomCentre => 'Bottom centre';

  @override
  String get placeBottomRight => 'Bottom right';

  @override
  String get questions => 'Questions';

  @override
  String get close => 'Close';

  @override
  String get historyEmpty => 'Questions you answer this session appear here.';

  @override
  String get outcomeCopied => 'Copied for chat';

  @override
  String get outcomeReadAloud => 'Read aloud';

  @override
  String get outcomeDismissed => 'Dismissed';

  @override
  String get outcomeShown => 'Shown';

  @override
  String get showAgain => 'Show again';

  @override
  String get copy => 'Copy';

  @override
  String get paused => 'Paused';

  @override
  String get hotkeysOnly => 'Hotkeys only';

  @override
  String get followingYourVoice => 'Following your voice';

  @override
  String get standby => 'Standby';

  @override
  String get onPace => 'On pace';

  @override
  String get ahead => 'Ahead';

  @override
  String get behind => 'Behind';

  @override
  String get holding => 'Holding';

  @override
  String get resume => 'Resume';

  @override
  String get pause => 'Pause';

  @override
  String get hideInstantly => 'Hide instantly';

  @override
  String get endSession => 'End session';

  @override
  String get listening => 'Listening';

  @override
  String get done => 'Done';

  @override
  String get askAway => 'Ask away — Sotto is listening to the room.';

  @override
  String get transcribingQuestion => 'Transcribing the question';

  @override
  String get draftingFrom => 'Drafting from';

  @override
  String get noAnswerDrafted => 'No answer drafted';

  @override
  String get provNotInNotes => 'Not in your notes';

  @override
  String get provFromPrep => 'From your Q&A prep';

  @override
  String get provFromScript => 'From your script and prep notes';

  @override
  String get provGeneral => 'Includes general knowledge — verify';

  @override
  String get predraftedInstant => 'pre-drafted · instant';

  @override
  String draftedIn(String seconds) {
    return 'drafted in $seconds s';
  }

  @override
  String get copyForChat => 'Copy for chat';

  @override
  String get readAloud => 'Read aloud';

  @override
  String get draftAgain => 'Draft again';

  @override
  String get copyAnswer => 'Copy answer';

  @override
  String get upNextOverlay => '→  Up next · ';

  @override
  String get next => 'Next';

  @override
  String get gettingReady => 'Getting ready…';

  @override
  String get choosePlaceholder => 'Choose…';

  @override
  String get setShortcuts => 'Shortcuts';

  @override
  String get setAppearance => 'Appearance';

  @override
  String get setVoice => 'Voice & following';

  @override
  String get setAnswers => 'Answers';

  @override
  String get setGeneral => 'General';

  @override
  String get setIntegrations => 'Integrations';

  @override
  String get setPrivacy => 'Privacy & data';

  @override
  String get settings => 'Settings';

  @override
  String get groupLive => 'Live';

  @override
  String get groupApp => 'App';

  @override
  String get versionBuild => 'Sotto 1.0 (build 1)';

  @override
  String get searchSettings => 'Search settings';

  @override
  String get resetToDefaults => 'Reset to defaults';

  @override
  String get reset => 'Reset';

  @override
  String get shortcutsDescription =>
      'They work everywhere while you are live — even when Zoom or your slides have focus. Every shortcut shares one chord, so you only learn the letter.';

  @override
  String get filterShortcuts => 'Filter shortcuts';

  @override
  String get groupOverlay => 'Overlay';

  @override
  String get chord => 'Chord';

  @override
  String get sottoChord => 'Sotto chord';

  @override
  String get sottoChordSub => 'Shared by every shortcut';

  @override
  String get altGrLayouts => 'AltGr layouts';

  @override
  String get altGrLayoutsSub =>
      'On layouts that type characters with Ctrl + Alt (Spanish, German, Polish…), pick Ctrl + Shift so shortcuts never swallow “@” or “€”.';

  @override
  String get sysPrevInputSource => 'Select the previous input source';

  @override
  String get sysMoveSpaces => 'Move between Spaces';

  @override
  String get sysSecurityOptions => 'Security options';

  @override
  String conflictAlreadyUsed(String action) {
    return 'Already used by “$action”';
  }

  @override
  String conflictSystem(String os, String meaning) {
    return 'Used by $os: $meaning';
  }

  @override
  String get conflictOtherApp => 'Taken by another app';

  @override
  String get pressAKey => 'Press a key…';

  @override
  String changeShortcutFor(String action) {
    return 'Change shortcut for $action';
  }

  @override
  String get pressToToggle => 'Press to toggle';

  @override
  String get holdToTalk => 'Hold to talk';

  @override
  String get hold => 'hold';

  @override
  String get useAnyway => 'Use anyway';

  @override
  String get chooseAnother => 'Choose another';

  @override
  String get appearanceDescription =>
      'How the overlay looks and where it lives. Every change previews live on the right.';

  @override
  String get theme => 'Theme';

  @override
  String get app => 'App';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeLight => 'Light';

  @override
  String get themeAuto => 'Auto';

  @override
  String get overlayThemeSub => 'Dark disappears into slides and video.';

  @override
  String get matchApp => 'Match app';

  @override
  String get readability => 'Readability';

  @override
  String get textSize => 'Text size';

  @override
  String get linesShown => 'Lines shown';

  @override
  String get linesShownSub => 'Before and after the line you are saying';

  @override
  String get opacity => 'Opacity';

  @override
  String get opacitySub => 'Below 70%, a plate appears behind the current line.';

  @override
  String get placement => 'Placement';

  @override
  String get position => 'Position';

  @override
  String get positionSub => 'Keep your eyes near the lens';

  @override
  String get layout => 'Layout';

  @override
  String get layoutSub => 'Chosen automatically from the window size';

  @override
  String get rememberPosition => 'Remember position per display';

  @override
  String get preview => 'Preview';

  @override
  String get bgDarkSlide => 'Dark slide';

  @override
  String get bgLightSlide => 'Light slide';

  @override
  String get bgVideoCall => 'Video call';

  @override
  String get writeToPreview => 'Write a script to preview it here.';

  @override
  String get metricCurrentLine => 'Current line, worst case';

  @override
  String get metricNextLine => 'Next line, worst case';

  @override
  String get metricLineLength => 'Line length at this size';

  @override
  String get motion => 'Motion';

  @override
  String get scrolling => 'Scrolling';

  @override
  String get scrollingSub => 'Glide eases between beats; Step jumps.';

  @override
  String get scrollGlide => 'Glide';

  @override
  String get scrollStep => 'Step';

  @override
  String get reduceMotion => 'Reduce motion';

  @override
  String get reduceMotionSub => 'Also follows your system setting';

  @override
  String get blurBehind => 'Blur behind the overlay';

  @override
  String get blurBehindSub => 'Softens busy slides. Uses the system’s vibrancy on macOS and acrylic on Windows 11.';

  @override
  String get voiceDescription =>
      'How Sotto listens to you while you present. On-device recognition keeps your voice on this computer.';

  @override
  String get stopTest => 'Stop test';

  @override
  String get testWithScript => 'Test with this script';

  @override
  String get noMicrophoneFound => 'No microphone found';

  @override
  String get inputLevel => 'Input level';

  @override
  String get inputLevelSub => 'Speak normally — aim for the green zone';

  @override
  String get noiseSuppression => 'Noise suppression';

  @override
  String get noiseSuppressionSub => 'Filters fans, keyboards and echo from speakers';

  @override
  String get questionsComeFrom => 'Questions come from';

  @override
  String get questionsComeFromSub =>
      'In a video call, choose a loopback device (BlackHole, Stereo Mix) to capture the meeting’s audio';

  @override
  String get sameAsMicrophone => 'Same as microphone';

  @override
  String get recognition => 'Recognition';

  @override
  String get language => 'Language';

  @override
  String get alsoRecognize => 'Also recognize';

  @override
  String get alsoRecognizeSub => 'For presenters who switch languages mid-talk';

  @override
  String get addLanguage => 'Add a language';

  @override
  String get engine => 'Engine';

  @override
  String get engineOnDeviceSub => 'sherpa-onnx on this computer · no audio leaves it';

  @override
  String get following => 'Following';

  @override
  String get advance => 'Advance';

  @override
  String get followMyVoice => 'Follow my voice';

  @override
  String get timed => 'Timed';

  @override
  String get manual => 'Manual';

  @override
  String get moveOnWhenSaid => 'Move on when I have said';

  @override
  String get moveOnWhenSaidSub => 'Lower feels faster; higher never moves early';

  @override
  String get sensitivity => 'Sensitivity';

  @override
  String get sensitivitySub => 'High follows paraphrasing, but may jump on ad-libs';

  @override
  String get low => 'Low';

  @override
  String get medium => 'Medium';

  @override
  String get high => 'High';

  @override
  String get holdStill => 'Hold still while I ad-lib';

  @override
  String get holdStillSub => 'Waits for you to return to the script';

  @override
  String get allowJumps => 'Allow jumps between sections';

  @override
  String get allowJumpsSub => 'If you skip ahead, the overlay follows';

  @override
  String get ready => 'Ready';

  @override
  String get needsSetup => 'Needs setup';

  @override
  String get onDeviceModels => 'On-device models';

  @override
  String get onDeviceModelsFooter =>
      'Downloaded once from the sherpa-onnx project, then used offline. Follow English live with a streaming model; Whisper transcribes questions and follows other languages.';

  @override
  String get installed => 'Installed';

  @override
  String get removeModel => 'Remove model';

  @override
  String get unpacking => 'Unpacking';

  @override
  String get retry => 'Retry';

  @override
  String get download => 'Download';

  @override
  String get noSpeechEngine => 'No speech engine is available.';

  @override
  String get liveCheck => 'Live check';

  @override
  String get whatSottoHears => 'What Sotto hears';

  @override
  String get listeningLower => 'listening';

  @override
  String listeningLag(int ms) {
    return 'listening · $ms ms since last word';
  }

  @override
  String get idle => 'idle';

  @override
  String get checkWriteFirst => 'Write a script first — the check follows your own words.';

  @override
  String checkPressTest(String title) {
    return 'Press “Test with this script” and read “$title” aloud.';
  }

  @override
  String get heard => 'Heard';

  @override
  String get positionConfidence => 'Position confidence';

  @override
  String get beatProgress => 'Beat progress';

  @override
  String get holdingWaiting => 'Holding — waiting for you to return to the script';

  @override
  String get yourPace => 'Your pace';

  @override
  String get wpm => 'wpm';

  @override
  String get paceDefault => 'default · rehearse to calibrate';

  @override
  String paceFromRehearsals(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'from $count rehearsals',
      one: 'from 1 rehearsal',
    );
    return '$_temp0';
  }

  @override
  String get recalibrate => 'Recalibrate';

  @override
  String get slower => 'Slower';

  @override
  String get faster => 'Faster';

  @override
  String get answersDescription =>
      'How live answers are drafted, grounded and delivered. Sotto drafts; you decide what the room hears.';

  @override
  String get grounding => 'Grounding';

  @override
  String get groundingScriptOnly => 'My script and prep documents only';

  @override
  String get groundingScriptOnlySub => 'Safest. Says “Not in your notes” when it can’t answer.';

  @override
  String get groundingScriptFirst => 'Script first, general knowledge when needed';

  @override
  String get groundingScriptFirstSub => 'Anything outside your material is labeled “verify”.';

  @override
  String get showSources => 'Show sources under every answer';

  @override
  String get style => 'Style';

  @override
  String get length => 'Length';

  @override
  String get lengthSub => 'Talking points are faster to say than paragraphs';

  @override
  String get headline => 'Headline';

  @override
  String get headlinePlus3 => 'Headline + 3';

  @override
  String get detailed => 'Detailed';

  @override
  String get sameAsQuestion => 'Same as the question';

  @override
  String get sameAsScript => 'Same as the script';

  @override
  String get tone => 'Tone';

  @override
  String get matchScript => 'Match the script';

  @override
  String get conversational => 'Conversational';

  @override
  String get formal => 'Formal';

  @override
  String get listeningForQuestions => 'Listening for questions';

  @override
  String get capture => 'Capture';

  @override
  String get captureSub => 'Only while you ask it to — never in the background';

  @override
  String get stopAfterSilence => 'Stop after silence of';

  @override
  String get predraft => 'Pre-draft likely questions';

  @override
  String get predraftSub => 'From Q&A prep — matched answers appear instantly';

  @override
  String get delivery => 'Delivery';

  @override
  String get voice => 'Voice';

  @override
  String get systemDefault => 'System default';

  @override
  String get copyForChatAsks => 'Copy for chat asks for';

  @override
  String holdKeyHalfSecond(String keys) {
    return 'Hold $keys (0.5 s)';
  }

  @override
  String get copyThenPaste => 'Copy, then paste';

  @override
  String get copyThenPasteSub =>
      'Holding the send key places the answer on your clipboard as plain text. Paste it into the Zoom, Teams or Meet chat with one keystroke. Nothing is posted on your behalf.';

  @override
  String get whatLeaves => 'What leaves this computer';

  @override
  String get leavesAudio => 'Audio — yours and the room’s are transcribed on this computer.';

  @override
  String get leavesQuestion => 'The text of the question and the excerpts used to answer it.';

  @override
  String get leavesNothingElse => 'Nothing else: no script, no history, no account.';

  @override
  String get generalDescription =>
      'Language, pace, storage and defaults. Everything Sotto keeps lives on this computer.';

  @override
  String get interface => 'Interface';

  @override
  String get interfaceLanguage => 'Language';

  @override
  String get interfaceLanguageSub => 'System follows your computer’s language';

  @override
  String get langSystem => 'System';

  @override
  String get pace => 'Pace';

  @override
  String get wordsPerMinute => 'Words per minute';

  @override
  String get wordsPerMinuteSub => 'Used for timing until rehearsals calibrate it';

  @override
  String get storage => 'Storage';

  @override
  String get dataFolder => 'Data folder';

  @override
  String get copyPath => 'Copy path';

  @override
  String get format => 'Format';

  @override
  String get formatSub =>
      'Scripts, settings, sessions and Q&A history are stored in a local database. API keys are stored in the system keychain.';

  @override
  String get resetAllSettings => 'Reset all settings';

  @override
  String get resetAllSettingsSub => 'Scripts, sessions and API keys are kept';

  @override
  String get aboutSotto => 'About Sotto';

  @override
  String get aboutSottoBody =>
      'From sotto voce — under the voice. A live presentation assistant that keeps your script under the camera, follows your voice line by line, and drafts an answer when the room asks a question.';

  @override
  String get versionLine => 'Version 1.0 · build 1';

  @override
  String get typefaces => 'Typefaces: Geist, Geist Mono, Atkinson Hyperlegible Next (SIL OFL)';

  @override
  String get addKeyFirst => 'Add a key first.';

  @override
  String connectedFirstToken(String seconds) {
    return 'Connected · first token in $seconds s';
  }

  @override
  String get inKeychain => 'In keychain';

  @override
  String get integrationsDescription =>
      'Answers are drafted by DeepSeek. Add your API key; it is stored in the system keychain and sent to DeepSeek only when a question is asked.';

  @override
  String get apiKey => 'API key';

  @override
  String get model => 'Model';

  @override
  String get testConnection => 'Test connection';

  @override
  String get test => 'Test';

  @override
  String get privacyDescription =>
      'Privacy by construction: presenter audio stays on this computer, room audio is captured only on the chord, and only text is sent to answer a question — plus one screenshot when you ask about your screen, if you turn that on.';

  @override
  String get hideFromCapture => 'Hide the overlay from screen capture';

  @override
  String get hideFromCaptureSub =>
      'Uses the OS protection where available. On macOS 15+, sharing your entire screen can still capture it — share a window instead.';

  @override
  String get retention => 'Retention';

  @override
  String get keepHistoryFor => 'Keep Q&A history for';

  @override
  String daysCount(int count) {
    return '$count days';
  }

  @override
  String get aYear => 'A year';

  @override
  String get deleteQaHistory => 'Delete Q&A history';

  @override
  String get deleteQaHistoryConfirm => 'Delete Q&A history?';

  @override
  String get deleteQaHistoryBody => 'Every recorded question and answer is removed.';

  @override
  String get dangerZone => 'Danger zone';

  @override
  String get removeApiKeys => 'Remove API keys';

  @override
  String get removeApiKeysSub => 'Deletes every key Sotto stored in the keychain';

  @override
  String get removeApiKeysConfirm => 'Remove API keys?';

  @override
  String get removeApiKeysBody => 'Answers stop working until you add a key again.';

  @override
  String get deleteAllData => 'Delete all local data';

  @override
  String get deleteAllDataSub => 'Scripts, collections, sessions and Q&A history';

  @override
  String get deleteEverything => 'Delete everything';

  @override
  String get deleteAllDataConfirm => 'Delete all local data?';

  @override
  String get deleteAllDataBody => 'This removes every script and session from this computer. It can’t be undone.';

  @override
  String get privVoice => 'Voice';

  @override
  String get privVoiceBody => 'Presenter audio never leaves this computer: speech runs on-device.';

  @override
  String get privRoom => 'Room audio';

  @override
  String get privRoomBody => 'Captured only on the chord, shown in red, transcribed locally.';

  @override
  String get privAnswers => 'Answers';

  @override
  String get privAnswersBody => 'Only the question text and the excerpts used are sent to DeepSeek.';

  @override
  String get privModels => 'Speech models';

  @override
  String get privModelsBody => 'Downloaded once from the sherpa-onnx project on GitHub.';

  @override
  String get privConsent => 'Consent';

  @override
  String get privConsentBody => 'Recording laws vary. Consider telling the room that Q&A assist is on.';

  @override
  String get llmNoBalance => 'Your DeepSeek balance is empty. Top up at platform.deepseek.com.';

  @override
  String get integrationsDescriptionBuiltIn =>
      'Answers are drafted by DeepSeek with the key built into this copy of Sotto. You can override it with your own key.';

  @override
  String get deepseekFooter => 'Only the question and the excerpts used to answer it are sent.';

  @override
  String get apiKeyOverrideSub => 'Optional. Leave empty to use the built-in key.';

  @override
  String get builtInKey => 'Built-in key';

  @override
  String get modelsLoading => 'Loading models…';

  @override
  String modelsLoadFailed(String error) {
    return 'Could not load the model list: $error';
  }

  @override
  String get deepseekPlatform => 'Account, balance and keys';

  @override
  String get open => 'Open';

  @override
  String beatsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count beats', one: '1 beat');
    return '$_temp0';
  }

  @override
  String cuesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cues',
      one: '1 cue',
      zero: 'no cues',
    );
    return '$_temp0';
  }

  @override
  String get readAloudTitle => 'Read aloud';

  @override
  String get readAloudHeadphones => 'Plays through the system output — wear headphones so the room never hears it.';

  @override
  String welcomeStep(int step, int total) {
    return 'WELCOME · $step OF $total';
  }

  @override
  String get welcomeSkip => 'Skip for now';

  @override
  String get welcomeNext => 'Next';

  @override
  String get welcomeBack => 'Back';

  @override
  String get welcomeUseExample => 'Start with the example';

  @override
  String get welcomeModelsTitle => 'Download the voice models';

  @override
  String get welcomeModelsBody =>
      'Sotto follows your voice on this computer. These models are downloaded once and then work offline; your audio never leaves the device.';

  @override
  String get welcomeModelsFooter =>
      'Downloads keep going in the background. Without models, the overlay still advances with hotkeys or a timer.';

  @override
  String get welcomeScriptTitle => 'Bring in your first script';

  @override
  String get welcomeScriptBody =>
      'Sotto organizes it into sections, one-breath beats and cues. You can also start with the example talk in your library.';

  @override
  String get welcomeImportFile => 'Import a file';

  @override
  String get welcomeImportFileSub => '.docx, .pdf, .md or .txt';

  @override
  String get welcomePaste => 'Paste text';

  @override
  String get welcomePasteSub => 'From the clipboard';

  @override
  String get welcomeWrite => 'Write from scratch';

  @override
  String get welcomeWriteSub => 'A blank script';

  @override
  String get overlayStyle => 'Overlay style';

  @override
  String get overlayStyleTextOnly => 'Text only';

  @override
  String get overlayStylePanel => 'Panel';

  @override
  String get overlayStyleTextOnlySub => 'No background — just outlined words over your slides';

  @override
  String get overlayStylePanelSub => 'A translucent card behind the text';

  @override
  String get overlayStyleTextOnlyFooter =>
      'Controls and the status strip appear when you hover the overlay or use a shortcut, then fade after 2 seconds.';

  @override
  String get textColor => 'Text color';

  @override
  String get outlineColor => 'Outline';

  @override
  String get outlineAuto => 'Auto — contrasts with the text';

  @override
  String get outlineAutoSub => 'Auto: dark around light text, light around dark text';

  @override
  String get outlineWidth => 'Outline width';

  @override
  String get shadowStrength => 'Shadow';

  @override
  String get modelReadsImages => 'reads screenshots';

  @override
  String get sourceScreen => 'Your screen';

  @override
  String get actionAskScreen => 'Ask about the screen';

  @override
  String get actionAskScreenSub => 'Takes one screenshot, then listens for your question';

  @override
  String get noticeScreenOff => 'Screen awareness is off — turn it on in Settings → Privacy';

  @override
  String get noticeScreenPermission => 'Sotto needs Screen Recording permission — see Settings → Privacy';

  @override
  String get defaultScreenQuestion => 'What is on my screen right now, and what should I say about it?';

  @override
  String get capturingScreen => 'Capturing screen';

  @override
  String get screenshotAttached => 'Screenshot attached — sent to DeepSeek with your question';

  @override
  String get screenAwareness => 'Screen awareness';

  @override
  String get screenAwarenessFooter =>
      'Screenshots are taken only when you ask, scaled down, sent to DeepSeek with your question and never saved. Sotto\'s own overlay never appears in them. A red “Capturing screen” light shows each time.';

  @override
  String get screenAwarenessToggle => 'Let Sotto look at my screen when I ask';

  @override
  String get screenAwarenessToggleSub => 'Off by default. Screenshots are sent to DeepSeek.';

  @override
  String get screenTarget => 'Capture';

  @override
  String get screenTargetOverlay => 'The display with the overlay';

  @override
  String get screenTargetCursor => 'The display under the pointer';

  @override
  String get attachSlide => 'Show the slide with audience questions';

  @override
  String get attachSlideSub => 'Each question also sends one screenshot of what is on screen';

  @override
  String get screenPermissionMissing => 'Screen Recording permission needed';

  @override
  String get screenPermissionMissingSub => 'System Settings → Privacy & Security → Screen Recording → Sotto';

  @override
  String get openSystemSettings => 'Open System Settings';

  @override
  String get privScreen => 'Screenshots';

  @override
  String get privScreenOffBody => 'Off. Sotto never looks at your screen.';

  @override
  String get privScreenOnBody => 'Only when you ask: one screenshot goes to DeepSeek with the question. Never saved.';

  @override
  String get readyScreenOk => 'On — one screenshot per question you ask about the screen';

  @override
  String get actionAgentTask => 'Agent task';

  @override
  String get actionAgentTaskSub => 'Say a task; the agent does it on screen, step by step';

  @override
  String get actionAgentStop => 'Stop the agent';

  @override
  String get actionAgentStopSub => 'Emergency stop — cancels at once and lets go of every key';

  @override
  String get agentOff => 'Agent mode is off — turn it on in Settings → Privacy';

  @override
  String get agentUnsupported => 'Agent mode works on Windows and macOS.';

  @override
  String get agentNeedsAccessibility =>
      'Sotto needs Accessibility permission to control the mouse and keyboard — see Settings → Privacy.';

  @override
  String get agentListening => 'Describe the task';

  @override
  String get agentStarting => 'Looking at the screen…';

  @override
  String get agentThinking => 'Deciding the next step…';

  @override
  String get agentWaiting => 'Waiting for you';

  @override
  String get agentActing => 'Working…';

  @override
  String get agentInControl => 'AGENT IN CONTROL';

  @override
  String agentStep(int step, int max) {
    return 'step $step/$max';
  }

  @override
  String get agentStop => 'Stop';

  @override
  String agentStopHint(String keys) {
    return 'Emergency stop: $keys — works everywhere';
  }

  @override
  String get agentCouldNotStart => 'Could not start';

  @override
  String get agentCompleted => 'Done';

  @override
  String get agentStopped => 'Stopped — nothing else will run';

  @override
  String get agentDeclined => 'Stopped at your request';

  @override
  String agentLimit(int max) {
    return 'Stopped after $max steps';
  }

  @override
  String get agentFailed => 'Stopped by an error';

  @override
  String get agentNext => 'NEXT ACTION';

  @override
  String agentConfirmSensitive(String reason) {
    return 'CONFIRM — $reason';
  }

  @override
  String get agentRun => 'Run';

  @override
  String get agentStopTask => 'Stop task';

  @override
  String get agentCardTitle => 'Let the agent do it';

  @override
  String get agentCardBody =>
      'Describe a task — “fill this form with my details from the prep docs”. The agent works on screen, one step at a time, and asks before anything that submits, sends, pays or deletes.';

  @override
  String get agentTaskPlaceholder => 'What should the agent do?';

  @override
  String get agentRunTask => 'Start';

  @override
  String get agentMode => 'Agent mode';

  @override
  String agentModeFooter(String keys) {
    return 'The agent sends screenshots to DeepSeek and moves the mouse and keyboard, at most 25 steps per task. It never types into password fields or handles payment data, always asks before submitting, sending, paying, deleting or buying, shows an amber frame while in control, and logs every action in the session. $keys stops it at once, from anywhere.';
  }

  @override
  String get agentToggle => 'Let Sotto control my mouse and keyboard';

  @override
  String get agentToggleSub => 'Off by default. Only for tasks you start.';

  @override
  String get agentAutonomy => 'Supervision';

  @override
  String get agentConfirmEach => 'Confirm each action';

  @override
  String get agentAuto => 'Run automatically';

  @override
  String get agentConfirmEachSub => 'Enter runs the shown action, Esc stops';

  @override
  String get agentAutoSub => 'Still asks before anything that submits, sends, pays, deletes or buys';

  @override
  String get accessibilityMissing => 'Accessibility permission needed';

  @override
  String get accessibilityMissingSub => 'System Settings → Privacy & Security → Accessibility → Sotto';

  @override
  String sessionAgentTask(String task) {
    return 'Agent: $task';
  }

  @override
  String sessionAgentActions(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count actions', one: '1 action');
    return '$_temp0';
  }

  @override
  String get readyAgentOk => 'On — confirm each action';

  @override
  String get readyAgentAuto => 'On — runs automatically, asks before irreversible steps';

  @override
  String agentDoClick(String target, String at) {
    return 'Click “$target” at $at';
  }

  @override
  String agentDoDoubleClick(String target, String at) {
    return 'Double-click “$target” at $at';
  }

  @override
  String agentDoRightClick(String target, String at) {
    return 'Right-click “$target” at $at';
  }

  @override
  String agentDoMove(String at) {
    return 'Move the pointer to $at';
  }

  @override
  String agentDoType(String text, String target) {
    return 'Type “$text” into $target';
  }

  @override
  String agentDoKeys(String keys) {
    return 'Press $keys';
  }

  @override
  String get agentDoScrollDown => 'Scroll down';

  @override
  String get agentDoScrollUp => 'Scroll up';

  @override
  String agentDoWait(int ms) {
    return 'Wait $ms ms';
  }

  @override
  String get agentDoScreenshot => 'Look at the screen again';

  @override
  String get agentDoDone => 'Finish';

  @override
  String get agentWhyPassword => 'the focused field is a password field';

  @override
  String get agentWhySecret => 'it looks like a password or security-code field';

  @override
  String get agentWhyPayment => 'it looks like a payment field';

  @override
  String get agentWhyCard => 'the text looks like a card number';

  @override
  String get agentWhyIrreversible => 'it may submit, send, pay or delete';

  @override
  String get agentWhySubmitKey => 'it may submit or delete';

  @override
  String get agentWhyOutside => 'outside the screenshot';

  @override
  String get privAgent => 'Agent';

  @override
  String get privAgentOffBody => 'Off. Sotto never moves your mouse or types.';

  @override
  String get privAgentOnBody =>
      'Only for tasks you start: one screenshot per step goes to DeepSeek; every action is logged in the session.';

  @override
  String refiningProgress(int done, int total) {
    return 'Refining… $done/$total';
  }

  @override
  String get refiningHint => 'You can read and edit now — parts you change are kept as you left them.';

  @override
  String refinedKeptEdits(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count parts', one: '1 part');
    return 'Kept your edits in $_temp0';
  }

  @override
  String refineStopped(String reason) {
    return 'Refining stopped — $reason The quick organization stays.';
  }

  @override
  String get formsOff => 'Questionnaires on screen are off. Turn them on in Settings → Answers.';

  @override
  String get formsUnsupported => 'Filling questionnaires needs Windows or macOS.';

  @override
  String get formsNoWindow => 'Click the questionnaire\'s window first, then press the shortcut.';

  @override
  String get formsReadFailed => 'Couldn\'t read the form in front. Click into it and try again.';

  @override
  String get formsBadReply => 'DeepSeek\'s answer couldn\'t be read. Try again.';

  @override
  String get formsWhySensitive => 'password or payment field — never filled';

  @override
  String get formsWhyNoMatch => 'the answer isn\'t one of the options';

  @override
  String get formsWhyNoField => 'field not found';

  @override
  String get formsWhyNoAnswer => 'no answer';

  @override
  String get formsSessionTitle => 'Questionnaire on screen';

  @override
  String get formsReading => 'Reading the form…';

  @override
  String get formsThinking => 'Answering the questions…';

  @override
  String get formsReview => 'Check the answers — edit any, then Enter to fill';

  @override
  String formsAnswering(int done, int total) {
    return 'Answering $done/$total…';
  }

  @override
  String get formsVerifying => 'Checking every answer stuck…';

  @override
  String formsNextPage(String label) {
    return 'Page filled — Enter for “$label”';
  }

  @override
  String get formsDoneSubmit => 'Done — review and submit';

  @override
  String get formsSubmitted => 'Submitted.';

  @override
  String get formsStopped => 'Stopped. Nothing more was typed.';

  @override
  String get formsFailed => 'Couldn\'t fill this form.';

  @override
  String formsReady(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count answers filled',
      one: '1 answer filled',
    );
    return '$_temp0 — review and submit when ready';
  }

  @override
  String get formsFilling => 'Sotto is filling';

  @override
  String formsPage(int page) {
    return 'Page $page';
  }

  @override
  String get formsFillThese => 'Fill these';

  @override
  String get formsGoNext => 'Next page';

  @override
  String formsSubmit(String label) {
    return 'Click “$label”';
  }

  @override
  String get formsIllSubmit => 'I\'ll submit it';

  @override
  String get actionFillForm => 'Fill questionnaire on screen';

  @override
  String get actionFillFormSub => 'Reads the form in front, answers it and fills it in';

  @override
  String get actionOpenChat => 'Chat';

  @override
  String get actionOpenChatSub => 'Opens the assistant chat in the overlay';

  @override
  String get actionPushToTalk => 'Talk to chat (hold)';

  @override
  String get actionPushToTalkSub => 'Hold to dictate a chat message';

  @override
  String get formsGroup => 'Questionnaires on screen';

  @override
  String get formsEnable => 'Answer questionnaires on screen';

  @override
  String formsEnableSub(String keys) {
    return '$keys reads the form in front, answers with DeepSeek\'s own knowledge (not your script) and fills it in.';
  }

  @override
  String get formsMode => 'Mode';

  @override
  String get formsModeAuto => 'Fill automatically';

  @override
  String get formsModeFirst => 'Show me the answers first';

  @override
  String get formsLanguage => 'Answer language';

  @override
  String get formsLangSame => 'Same as the questionnaire';

  @override
  String get formsLangApp => 'App language';

  @override
  String get formsStyle => 'Open answers';

  @override
  String get formsStyleShort => 'Short';

  @override
  String get formsStyleDetailed => 'Detailed';

  @override
  String get formsInstructions => 'Extra instructions';

  @override
  String get formsInstructionsSub => 'Optional context for the answers — your name, role, preferences.';

  @override
  String get formsInstructionsHint => 'e.g. My name is Ana Ruiz, product manager at Acme. Prefer concise answers.';

  @override
  String get formsPrivacy =>
      'Screenshots of the questionnaire are sent to DeepSeek and never saved. Nothing is stored unless history is on: then each filled answer is logged in Sessions.';

  @override
  String formsSubmitNote(String keys) {
    return 'Sotto never submits on its own: auto-fill stops before Submit, and a fill you start waits for Enter. $keys stops at once.';
  }

  @override
  String get historyOff => 'Don\'t keep';

  @override
  String sessionFormRun(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count answers', one: '1 answer');
    return 'Questionnaire · $_temp0';
  }

  @override
  String get formsDialogTitle => 'Questionnaire';

  @override
  String get navChat => 'Chat';

  @override
  String get chatNew => 'New chat';

  @override
  String get chatNoConversations => 'No conversations yet.';

  @override
  String get chatRename => 'Rename';

  @override
  String get chatUntitled => 'Untitled chat';

  @override
  String get chatEmptyTitle => 'Ask anything';

  @override
  String get chatEmptyBody =>
      'Extra questions before or during a talk. Attach your screen, or let it read your script. Thinking is off by default for fast replies — turn on Think deeper when it\'s worth the wait.';

  @override
  String get chatPanelEmpty => 'Type or hold the talk key to ask. Zoom keeps the keyboard until you click the input.';

  @override
  String get chatCopy => 'Copy';

  @override
  String get chatReadAloud => 'Read aloud';

  @override
  String get chatScreenAttached => 'screen attached';

  @override
  String get chatThinking => 'Thinking…';

  @override
  String get chatListening => 'Listening… release to stop';

  @override
  String get chatTranscribing => 'Transcribing…';

  @override
  String chatPlaceholder(String keys) {
    return 'Message — Enter to send, Shift+Enter for a new line · hold $keys to talk';
  }

  @override
  String chatDictate(String keys) {
    return 'Dictate (hold $keys)';
  }

  @override
  String get chatStopDictation => 'Stop dictating';

  @override
  String get chatAttachScreen => 'Attach screen — sends a screenshot with the next message';

  @override
  String get chatStop => 'Stop generating';

  @override
  String get chatSend => 'Send';

  @override
  String get chatThinkDeeper => 'Think deeper';

  @override
  String get chatUseScript => 'Use my script';

  @override
  String chatUseScriptNamed(String title) {
    return 'Use my script · $title';
  }

  @override
  String get chatGroup => 'Chat';

  @override
  String get chatAutoSend => 'Send dictation at once';

  @override
  String get chatAutoSendSub => 'Off: the transcript lands in the input so you can edit it first.';

  @override
  String get chatContext => 'Messages sent as context';

  @override
  String get chatContextSub => 'The most recent ones; older messages are trimmed.';

  @override
  String get chatPrivacy =>
      'Chats are stored on this computer and kept for your history period. Screenshots you attach go to DeepSeek and are never saved.';

  @override
  String get formsNeedsAccessibility =>
      'Sotto needs Accessibility permission to read and fill forms. Allow Sotto in System Settings → Privacy & Security → Accessibility, then press the shortcut again.';

  @override
  String get formsCouldNotFill => 'could not fill — please fill it yourself';

  @override
  String get overlayTextColor => 'Overlay text color';

  @override
  String get overlayTextColorAuto => 'Auto';

  @override
  String get overlayTextColorLight => 'Always light';

  @override
  String get overlayTextColorDark => 'Always dark';

  @override
  String get overlayTextColorCustom => 'Custom';

  @override
  String get overlayTextColorAutoSub =>
      'Dark text on light slides, light text on dark ones — checked on this computer every 0.8 s, never sent anywhere';

  @override
  String get overlayTextColorFixedSub => 'Fixed; the background isn\'t checked';

  @override
  String get overlayTextColorCustomSub => 'Your own text and outline colors';

  @override
  String get maxOverlayHeight => 'Max overlay height';

  @override
  String get maxOverlayHeightSub =>
      'The overlay grows and shrinks with the lines showing, up to this share of the screen. Drag its edge to set a height for the session.';

  @override
  String get autofillOn => 'Auto-fill ON';

  @override
  String get autofillPaused => 'Paused';

  @override
  String get autofillPause => 'Pause';

  @override
  String get autofillResume => 'Resume';

  @override
  String get autofillStop => 'Stop';

  @override
  String get autofillHoldToStop => 'Hold 1 s to stop';

  @override
  String get autofillStopNow => 'Stop now';

  @override
  String autofillFilling(int done, int total, String question) {
    return 'Filling… $done/$total — $question';
  }

  @override
  String get autofillDone => 'Done — review and submit yourself';

  @override
  String get autofillOpenSotto => 'Open Sotto';

  @override
  String get autofillLog => 'Log';

  @override
  String get autofillLogEmpty => 'Answers will appear here, with why each was chosen.';

  @override
  String autofillCountdown(int seconds) {
    return 'Switch to the form… $seconds';
  }

  @override
  String get autofillWatching => 'Watching for questionnaires';

  @override
  String get autofillIndicator => 'Sotto is filling';

  @override
  String get autofillToggle => 'Auto-fill forms';

  @override
  String get autofillToggleSub =>
      'Watches the window in front and fills the forms that appear — sign-ups, surveys, applications. Screenshots go to DeepSeek. Never presses Submit.';

  @override
  String get formsScrollTitle => 'Scroll to find more questions';

  @override
  String get formsScrollSub => 'Scrolls down, up to 10 times a page, while new questions keep appearing';

  @override
  String get qtText => 'Text';

  @override
  String get qtLongText => 'Long text';

  @override
  String get qtMultipleChoice => 'Multiple choice';

  @override
  String get qtTrueFalse => 'True / False';

  @override
  String get qtCheckboxes => 'Checkboxes';

  @override
  String get qtDropdown => 'Dropdown';

  @override
  String get qtScale => 'Scale';

  @override
  String get qtMatching => 'Matching';

  @override
  String get qtOrdering => 'Ordering';

  @override
  String get qtImageChoice => 'Image choice';

  @override
  String get qtReadOnly => 'Read only — answer shown';

  @override
  String get showChat => 'Show chat';

  @override
  String get showChatSub =>
      'Adds Chat to the sidebar and turns on its shortcuts (open chat, push to talk). Off by default: it stays out of the way.';

  @override
  String get chatAutoClose => 'Close the chat panel after';

  @override
  String get chatAutoCloseSub => 'In the overlay, after this long with no activity — never while a reply is arriving';

  @override
  String get chatAutoCloseNever => 'Never';

  @override
  String get navForms => 'Forms';

  @override
  String get setForms => 'Forms';

  @override
  String get formsDescription =>
      'Filling ordinary forms on screen — registrations, surveys, job applications, contact forms: automatically as they appear, or when you ask. Graded tests and exams are left alone.';

  @override
  String get showFormsNav => 'Show Forms in sidebar';

  @override
  String get showFormsNavSub => 'The page with auto-fill, its status and recent fills';

  @override
  String get formsStatusOff => 'Off';

  @override
  String get formsStatusWatching => 'Watching';

  @override
  String formsStatusFilling(int done, int total) {
    return 'Filling… $done/$total';
  }

  @override
  String get formsStatusOffSub => 'Turn on auto-fill above, or fill what\'s on screen once.';

  @override
  String get formsStatusWatchingSub => 'Switch to a form: Sotto fills it and stops before Submit.';

  @override
  String get formsStatusPausedSub => 'Nothing is watched or filled until you resume.';

  @override
  String get formsFillNow => 'Fill what\'s on screen now';

  @override
  String formsFillNowSub(String keys) {
    return 'Then switch to the form within 3 seconds — same as $keys.';
  }

  @override
  String get formsRecent => 'Recent fills';

  @override
  String get formsRecentEmpty => 'Nothing filled yet.';

  @override
  String get formsHistoryOff => 'History is off (Privacy → Don\'t keep): fills aren\'t kept.';

  @override
  String formsFieldsFilled(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fields filled',
      one: '1 field filled',
    );
    return '$_temp0';
  }

  @override
  String get formsOutcomeCompleted => 'Completed';

  @override
  String get formsOutcomeStopped => 'Stopped';

  @override
  String get formsOutcomeError => 'Error';

  @override
  String get formsClearHistory => 'Clear fill history';

  @override
  String get formsClearHistorySub => 'Deletes every questionnaire record; live sessions keep the rest.';

  @override
  String get formsHistoryCleared => 'Fill history cleared.';

  @override
  String get formsPrivacyNote =>
      'Each fill sends a screenshot of the window in front, and its form fields, to DeepSeek. Screenshots are never saved. Password and payment fields are never read or filled.';

  @override
  String get formsOpenSettings => 'Forms settings';

  @override
  String get formsAutofillGroup => 'Auto-fill';

  @override
  String get formsAnswersGroup => 'Answers';

  @override
  String get formsHistoryGroup => 'History';

  @override
  String get formsBrowserNote =>
      'Chrome / Edge: to read pages precisely, start the browser with --remote-debugging-port=9222. Otherwise Sotto reads the screen. Firefox: always from the screen.';

  @override
  String get formsBrowserNoteLink => 'How to set it up';

  @override
  String hoverOverlayStyle(String style) {
    return 'Overlay style: $style';
  }

  @override
  String hoverTextColor(String color) {
    return 'Text color: $color';
  }

  @override
  String get hoverAutoFillOn => 'Auto-fill is on — turn off';

  @override
  String get hoverAutoFillOff => 'Auto-fill is off — turn on';

  @override
  String get hoverOpenChat => 'Open chat';

  @override
  String get hoverCloseChat => 'Close chat';

  @override
  String get hoverEndSessionHold => 'Hold 1 s to end session';
}

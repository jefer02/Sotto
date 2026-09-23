import 'package:collection/collection.dart';

import '../../core/utils/ids.dart';
import '../../l10n/l10n.dart';

/// Product vocabulary (Naming board):
/// * Script — what you import or write.
/// * Section — a chapter with a time budget.
/// * Beat — one breath of text; the unit Sotto advances by.
/// * Cue — a stage direction: slide, pause, demo.

enum ScriptStatus { draft, organizing, structured, ready }

enum CueType { slide, pause, demo, note }

class Cue {
  const Cue(this.type, [this.label]);

  final CueType type;
  final String? label;

  /// What the chip shows, in the interface language ("SLIDE 7" / "DIAPOSITIVA 7").
  String get display {
    final l = L10n.current;
    return switch (type) {
      CueType.slide => '${l.cueSlide}${label == null ? '' : ' $label'}',
      CueType.pause => l.cuePause,
      CueType.demo => l.cueDemo,
      CueType.note => (label ?? l.cueNote).toUpperCase(),
    };
  }

  /// Round-trips through the plain-text form `[SLIDE 7]`. Always English, so
  /// exported scripts read the same whatever the interface language.
  String get token => switch (type) {
    CueType.slide => '[SLIDE${label == null ? '' : ' $label'}]',
    CueType.pause => '[PAUSE]',
    CueType.demo => '[DEMO]',
    CueType.note => '[${'NOTE ${label ?? ''}'.trim()}]',
  };

  Map<String, Object?> toJson() => {'type': type.name, 'label': label};

  factory Cue.fromJson(Map<dynamic, dynamic> j) =>
      Cue(CueType.values.byName(j['type'] as String), j['label'] as String?);

  static final _pattern = RegExp(
    r'^\s*\[(SLIDE|DIAPOSITIVA|DIAPO|PAUSE|PAUSA|DEMO|NOTE|NOTA)\s*([^\]]*)\]\s*',
    caseSensitive: false,
  );

  /// English and Spanish cue words, typed in the editor or found on import.
  static CueType typeOf(String word) => switch (word.toLowerCase()) {
    'slide' || 'diapositiva' || 'diapo' => CueType.slide,
    'pause' || 'pausa' => CueType.pause,
    'demo' => CueType.demo,
    _ => CueType.note,
  };

  /// Splits a leading cue token off a line: "[SLIDE 7] Gross margin…".
  static (Cue?, String) parseLeading(String line) {
    final m = _pattern.firstMatch(line);
    if (m == null) return (null, line);
    final type = typeOf(m.group(1)!);
    final label = m.group(2)!.trim();
    return (Cue(type, label.isEmpty ? null : label), line.substring(m.end));
  }

  @override
  bool operator ==(Object other) => other is Cue && other.type == type && other.label == label;

  @override
  int get hashCode => Object.hash(type, label);
}

class Beat {
  const Beat({required this.id, required this.text, this.cue});

  final String id;

  /// Script text. `**bold**` marks emphasis — the only emphasis live mode
  /// allows (no italics, no underline).
  final String text;
  final Cue? cue;

  Beat copyWith({String? text, Cue? cue, bool clearCue = false}) =>
      Beat(id: id, text: text ?? this.text, cue: clearCue ? null : (cue ?? this.cue));

  String get plainText => text.replaceAll('**', '');

  int get wordCount => plainText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

  Map<String, Object?> toJson() => {'id': id, 'text': text, 'cue': cue?.toJson()};

  factory Beat.fromJson(Map<dynamic, dynamic> j) => Beat(
    id: j['id'] as String,
    text: j['text'] as String,
    cue: j['cue'] == null ? null : Cue.fromJson(j['cue'] as Map),
  );

  factory Beat.create(String text, {Cue? cue}) => Beat(id: newId(), text: text, cue: cue);
}

class Section {
  const Section({
    required this.id,
    required this.title,
    required this.beats,
    this.budgetSeconds,
    this.keyPoints = const [],
  });

  final String id;
  final String title;
  final List<Beat> beats;

  /// Planned time; null means "derive from words at the presenter's pace".
  final int? budgetSeconds;

  /// Shown in the Column layout and in rehearsal.
  final List<String> keyPoints;

  int get wordCount => beats.fold(0, (a, b) => a + b.wordCount);

  int get cueCount => beats.where((b) => b.cue != null).length;

  int estimatedSeconds(int wpm) => budgetSeconds ?? (wordCount * 60 / wpm).round();

  Section copyWith({
    String? title,
    List<Beat>? beats,
    int? budgetSeconds,
    bool clearBudget = false,
    List<String>? keyPoints,
  }) => Section(
    id: id,
    title: title ?? this.title,
    beats: beats ?? this.beats,
    budgetSeconds: clearBudget ? null : (budgetSeconds ?? this.budgetSeconds),
    keyPoints: keyPoints ?? this.keyPoints,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'budget': budgetSeconds,
    'keyPoints': keyPoints,
    'beats': beats.map((b) => b.toJson()).toList(),
  };

  factory Section.fromJson(Map<dynamic, dynamic> j) => Section(
    id: j['id'] as String,
    title: j['title'] as String,
    budgetSeconds: j['budget'] as int?,
    keyPoints: [...(j['keyPoints'] as List? ?? const []).cast<String>()],
    beats: [for (final b in (j['beats'] as List? ?? const [])) Beat.fromJson(b as Map)],
  );

  factory Section.create(String title, {List<Beat>? beats}) =>
      Section(id: newId(), title: title, beats: beats ?? [Beat.create('')]);
}

/// Supporting material the answer drafter may ground in.
class PrepDoc {
  const PrepDoc({required this.id, required this.name, required this.text});

  final String id;
  final String name;
  final String text;

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'text': text};

  factory PrepDoc.fromJson(Map<dynamic, dynamic> j) =>
      PrepDoc(id: j['id'] as String, name: j['name'] as String, text: j['text'] as String);
}

/// A likely question with a pre-drafted answer; matched answers are instant.
class PrepQuestion {
  const PrepQuestion({required this.id, required this.question, required this.answer});

  final String id;
  final String question;
  final String answer;

  PrepQuestion copyWith({String? question, String? answer}) =>
      PrepQuestion(id: id, question: question ?? this.question, answer: answer ?? this.answer);

  Map<String, Object?> toJson() => {'id': id, 'q': question, 'a': answer};

  factory PrepQuestion.fromJson(Map<dynamic, dynamic> j) =>
      PrepQuestion(id: j['id'] as String, question: j['q'] as String, answer: j['a'] as String);
}

class Script {
  const Script({
    required this.id,
    required this.title,
    required this.sections,
    required this.createdAt,
    required this.updatedAt,
    this.collectionId,
    this.status = ScriptStatus.draft,
    this.prepDocs = const [],
    this.prepQuestions = const [],
    this.hintWords = const [],
    this.rehearsalCount = 0,
    this.targetSeconds,
    this.sourceName,
    this.archived = false,
    this.scheduledAt,
    this.meetingLabel,
  });

  final String id;
  final String title;
  final List<Section> sections;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? collectionId;
  final ScriptStatus status;
  final List<PrepDoc> prepDocs;
  final List<PrepQuestion> prepQuestions;

  /// Names and numbers sent to speech recognition as hints.
  final List<String> hintWords;
  final int rehearsalCount;
  final int? targetSeconds;

  /// Original file name when imported ("H2 roadmap.docx").
  final String? sourceName;
  final bool archived;

  /// When the talk is scheduled — drives the "Up next" card.
  final DateTime? scheduledAt;
  final String? meetingLabel;

  Iterable<Beat> get allBeats => sections.expand((s) => s.beats);

  int get beatCount => sections.fold(0, (a, s) => a + s.beats.length);

  int get cueCount => sections.fold(0, (a, s) => a + s.cueCount);

  int get wordCount => sections.fold(0, (a, s) => a + s.wordCount);

  int estimatedSeconds(int wpm) => sections.fold(0, (a, s) => a + s.estimatedSeconds(wpm));

  String get excerpt {
    final first = allBeats.map((b) => b.plainText.trim()).where((t) => t.isNotEmpty).take(2);
    return first.join(' ');
  }

  Section? sectionById(String id) => sections.firstWhereOrNull((s) => s.id == id);

  Script copyWith({
    String? title,
    List<Section>? sections,
    DateTime? updatedAt,
    String? collectionId,
    bool clearCollection = false,
    ScriptStatus? status,
    List<PrepDoc>? prepDocs,
    List<PrepQuestion>? prepQuestions,
    List<String>? hintWords,
    int? rehearsalCount,
    int? targetSeconds,
    bool clearTarget = false,
    String? sourceName,
    bool? archived,
    DateTime? scheduledAt,
    bool clearSchedule = false,
    String? meetingLabel,
  }) => Script(
    id: id,
    title: title ?? this.title,
    sections: sections ?? this.sections,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now(),
    collectionId: clearCollection ? null : (collectionId ?? this.collectionId),
    status: status ?? this.status,
    prepDocs: prepDocs ?? this.prepDocs,
    prepQuestions: prepQuestions ?? this.prepQuestions,
    hintWords: hintWords ?? this.hintWords,
    rehearsalCount: rehearsalCount ?? this.rehearsalCount,
    targetSeconds: clearTarget ? null : (targetSeconds ?? this.targetSeconds),
    sourceName: sourceName ?? this.sourceName,
    archived: archived ?? this.archived,
    scheduledAt: clearSchedule ? null : (scheduledAt ?? this.scheduledAt),
    meetingLabel: clearSchedule ? null : (meetingLabel ?? this.meetingLabel),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'sections': sections.map((s) => s.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'collectionId': collectionId,
    'status': status.name,
    'prepDocs': prepDocs.map((d) => d.toJson()).toList(),
    'prepQuestions': prepQuestions.map((q) => q.toJson()).toList(),
    'hintWords': hintWords,
    'rehearsalCount': rehearsalCount,
    'targetSeconds': targetSeconds,
    'sourceName': sourceName,
    'archived': archived,
    'scheduledAt': scheduledAt?.toIso8601String(),
    'meetingLabel': meetingLabel,
  };

  factory Script.fromJson(Map<dynamic, dynamic> j) => Script(
    id: j['id'] as String,
    title: j['title'] as String,
    sections: [for (final s in (j['sections'] as List)) Section.fromJson(s as Map)],
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: DateTime.parse(j['updatedAt'] as String),
    collectionId: j['collectionId'] as String?,
    status: ScriptStatus.values.asNameMap()[j['status']] ?? ScriptStatus.draft,
    prepDocs: [for (final d in (j['prepDocs'] as List? ?? const [])) PrepDoc.fromJson(d as Map)],
    prepQuestions: [for (final q in (j['prepQuestions'] as List? ?? const [])) PrepQuestion.fromJson(q as Map)],
    hintWords: [...(j['hintWords'] as List? ?? const []).cast<String>()],
    rehearsalCount: j['rehearsalCount'] as int? ?? 0,
    targetSeconds: j['targetSeconds'] as int?,
    sourceName: j['sourceName'] as String?,
    archived: j['archived'] as bool? ?? false,
    scheduledAt: j['scheduledAt'] == null ? null : DateTime.parse(j['scheduledAt'] as String),
    meetingLabel: j['meetingLabel'] as String?,
  );

  factory Script.blank({String? title, String? collectionId}) {
    final now = DateTime.now();
    return Script(
      id: newId(),
      title: title ?? L10n.current.untitledScript,
      sections: [Section.create(L10n.current.sectionOpening)],
      createdAt: now,
      updatedAt: now,
      collectionId: collectionId,
    );
  }
}

class Collection {
  const Collection({required this.id, required this.name});

  final String id;
  final String name;

  Map<String, Object?> toJson() => {'id': id, 'name': name};

  factory Collection.fromJson(Map<dynamic, dynamic> j) => Collection(id: j['id'] as String, name: j['name'] as String);
}

/// One step an agent took, for the presenter to review afterwards.
class AgentLogRecord {
  const AgentLogRecord({required this.at, required this.action, required this.outcome, this.note = ''});
  final DateTime at;
  final String action;

  /// done, blocked, declined, failed or skipped.
  final String outcome;
  final String note;

  Map<String, Object?> toJson() => {'at': at.toIso8601String(), 'action': action, 'outcome': outcome, 'note': note};

  factory AgentLogRecord.fromJson(Map<dynamic, dynamic> j) => AgentLogRecord(
    at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
    action: j['action'] as String? ?? '',
    outcome: j['outcome'] as String? ?? '',
    note: j['note'] as String? ?? '',
  );
}

/// One agent task inside a session: what was asked and every action taken.
class AgentRunRecord {
  const AgentRunRecord({required this.task, required this.status, this.summary = '', this.log = const []});
  final String task;

  /// completed, stopped, declined, limit or failed.
  final String status;
  final String summary;
  final List<AgentLogRecord> log;

  Map<String, Object?> toJson() => {
    'task': task,
    'status': status,
    'summary': summary,
    'log': [for (final e in log) e.toJson()],
  };

  factory AgentRunRecord.fromJson(Map<dynamic, dynamic> j) => AgentRunRecord(
    task: j['task'] as String? ?? '',
    status: j['status'] as String? ?? '',
    summary: j['summary'] as String? ?? '',
    log: [for (final e in (j['log'] as List? ?? const [])) AgentLogRecord.fromJson(e as Map)],
  );
}

/// One question Sotto answered on a questionnaire, and what happened.
class FormFieldRecord {
  const FormFieldRecord({required this.question, required this.answer, required this.status, this.note = ''});
  final String question;
  final String answer;

  /// filled, failed, skipped or blocked.
  final String status;
  final String note;

  Map<String, Object?> toJson() => {'q': question, 'a': answer, 'status': status, 'note': note};

  factory FormFieldRecord.fromJson(Map<dynamic, dynamic> j) => FormFieldRecord(
    question: j['q'] as String? ?? '',
    answer: j['a'] as String? ?? '',
    status: j['status'] as String? ?? '',
    note: j['note'] as String? ?? '',
  );
}

/// One questionnaire filled on screen.
class FormRunRecord {
  const FormRunRecord({required this.status, this.pages = 1, this.fields = const []});

  /// submitted, ready (waiting for the presenter to submit), stopped or failed.
  final String status;
  final int pages;
  final List<FormFieldRecord> fields;

  Map<String, Object?> toJson() => {
    'status': status,
    'pages': pages,
    'fields': [for (final f in fields) f.toJson()],
  };

  factory FormRunRecord.fromJson(Map<dynamic, dynamic> j) => FormRunRecord(
    status: j['status'] as String? ?? '',
    pages: j['pages'] as int? ?? 1,
    fields: [for (final f in (j['fields'] as List? ?? const [])) FormFieldRecord.fromJson(f as Map)],
  );
}

/// One live run or rehearsal, stored for the Sessions list, pace
/// calibration and the "Last rehearsal 18:24 · +0:24" line. Agent tasks run
/// outside a live session get a record of their own, with only [agentRuns].
class SessionRecord {
  const SessionRecord({
    required this.id,
    required this.scriptId,
    required this.scriptTitle,
    required this.startedAt,
    required this.endedAt,
    required this.rehearsal,
    this.sectionSeconds = const {},
    this.wordsSpoken = 0,
    this.questionCount = 0,
    this.plannedSeconds,
    this.agentRuns = const [],
    this.formRuns = const [],
  });

  final String id;
  final String scriptId;
  final String scriptTitle;
  final DateTime startedAt;
  final DateTime endedAt;
  final bool rehearsal;

  /// Seconds spent per section id.
  final Map<String, int> sectionSeconds;
  final int wordsSpoken;
  final int questionCount;
  final int? plannedSeconds;

  /// Agent tasks run during the session, with every action they took.
  final List<AgentRunRecord> agentRuns;

  /// Questionnaires filled during the session, every field logged.
  final List<FormRunRecord> formRuns;

  /// A session that was only an agent task or a questionnaire (no live run).
  bool get agentOnly => (agentRuns.isNotEmpty || formRuns.isNotEmpty) && wordsSpoken == 0 && sectionSeconds.isEmpty;

  int get durationSeconds => endedAt.difference(startedAt).inSeconds;

  int? get wordsPerMinute =>
      durationSeconds < 30 || wordsSpoken == 0 ? null : (wordsSpoken * 60 / durationSeconds).round();

  Map<String, Object?> toJson() => {
    'id': id,
    'scriptId': scriptId,
    'scriptTitle': scriptTitle,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt.toIso8601String(),
    'rehearsal': rehearsal,
    'sectionSeconds': sectionSeconds,
    'wordsSpoken': wordsSpoken,
    'questionCount': questionCount,
    'plannedSeconds': plannedSeconds,
    'agentRuns': [for (final r in agentRuns) r.toJson()],
    'formRuns': [for (final r in formRuns) r.toJson()],
  };

  factory SessionRecord.fromJson(Map<dynamic, dynamic> j) => SessionRecord(
    id: j['id'] as String,
    scriptId: j['scriptId'] as String,
    scriptTitle: j['scriptTitle'] as String? ?? '',
    startedAt: DateTime.parse(j['startedAt'] as String),
    endedAt: DateTime.parse(j['endedAt'] as String),
    rehearsal: j['rehearsal'] as bool? ?? false,
    sectionSeconds: {
      for (final e in ((j['sectionSeconds'] as Map?) ?? const {}).entries) e.key as String: e.value as int,
    },
    wordsSpoken: j['wordsSpoken'] as int? ?? 0,
    questionCount: j['questionCount'] as int? ?? 0,
    plannedSeconds: j['plannedSeconds'] as int?,
    agentRuns: [for (final r in (j['agentRuns'] as List? ?? const [])) AgentRunRecord.fromJson(r as Map)],
    formRuns: [for (final r in (j['formRuns'] as List? ?? const [])) FormRunRecord.fromJson(r as Map)],
  );
}

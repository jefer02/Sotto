/// One live run or rehearsal, stored for the Sessions list, pace
/// calibration and the "Last rehearsal 18:24 · +0:24" line.
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
  );
}

enum SourceKind { section, prep, general }

/// Where part of an answer came from: `§3 Revenue & margin`, `Prep Carrier
/// contracts.pdf`, or general knowledge (labelled "verify").
class SourceRef {
  const SourceRef({required this.kind, required this.label, this.code});

  final SourceKind kind;
  final String label;

  /// Short tungsten code: "§3", "Prep".
  final String? code;

  Map<String, Object?> toJson() => {'kind': kind.name, 'label': label, 'code': code};

  factory SourceRef.fromJson(Map<dynamic, dynamic> j) => SourceRef(
    kind: SourceKind.values.asNameMap()[j['kind']] ?? SourceKind.general,
    label: j['label'] as String,
    code: j['code'] as String?,
  );
}

/// A talking point: a bold lead ("60% of volume") and the rest of the line.
class AnswerPoint {
  const AnswerPoint({required this.lead, required this.rest});

  final String lead;
  final String rest;

  String get text => rest.isEmpty ? lead : '$lead $rest';

  Map<String, Object?> toJson() => {'lead': lead, 'rest': rest};

  factory AnswerPoint.fromJson(Map<dynamic, dynamic> j) =>
      AnswerPoint(lead: j['lead'] as String? ?? '', rest: j['rest'] as String? ?? '');
}

enum AnswerOutcome { shown, sentToChat, readAloud, dismissed }

class QaEntry {
  const QaEntry({
    required this.id,
    required this.scriptId,
    required this.askedAt,
    required this.question,
    required this.headline,
    this.sessionId,
    this.points = const [],
    this.sources = const [],
    this.grounded = true,
    this.draftMillis,
    this.outcome = AnswerOutcome.shown,
    this.sessionElapsedSeconds,
    this.predrafted = false,
  });

  final String id;
  final String scriptId;
  final String? sessionId;
  final DateTime askedAt;
  final String question;
  final String headline;
  final List<AnswerPoint> points;
  final List<SourceRef> sources;

  /// False when any part leaned on general knowledge.
  final bool grounded;
  final int? draftMillis;
  final AnswerOutcome outcome;

  /// Timer value when the question came in ("12:04").
  final int? sessionElapsedSeconds;
  final bool predrafted;

  String get plainAnswer => [headline, for (final p in points) '• ${p.text}'].join('\n');

  QaEntry copyWith({AnswerOutcome? outcome}) => QaEntry(
    id: id,
    scriptId: scriptId,
    sessionId: sessionId,
    askedAt: askedAt,
    question: question,
    headline: headline,
    points: points,
    sources: sources,
    grounded: grounded,
    draftMillis: draftMillis,
    outcome: outcome ?? this.outcome,
    sessionElapsedSeconds: sessionElapsedSeconds,
    predrafted: predrafted,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'scriptId': scriptId,
    'sessionId': sessionId,
    'askedAt': askedAt.toIso8601String(),
    'question': question,
    'headline': headline,
    'points': points.map((p) => p.toJson()).toList(),
    'sources': sources.map((s) => s.toJson()).toList(),
    'grounded': grounded,
    'draftMillis': draftMillis,
    'outcome': outcome.name,
    'elapsed': sessionElapsedSeconds,
    'predrafted': predrafted,
  };

  factory QaEntry.fromJson(Map<dynamic, dynamic> j) => QaEntry(
    id: j['id'] as String,
    scriptId: j['scriptId'] as String,
    sessionId: j['sessionId'] as String?,
    askedAt: DateTime.parse(j['askedAt'] as String),
    question: j['question'] as String,
    headline: j['headline'] as String,
    points: [for (final p in (j['points'] as List? ?? const [])) AnswerPoint.fromJson(p as Map)],
    sources: [for (final s in (j['sources'] as List? ?? const [])) SourceRef.fromJson(s as Map)],
    grounded: j['grounded'] as bool? ?? true,
    draftMillis: j['draftMillis'] as int?,
    outcome: AnswerOutcome.values.asNameMap()[j['outcome']] ?? AnswerOutcome.shown,
    sessionElapsedSeconds: j['elapsed'] as int?,
    predrafted: j['predrafted'] as bool? ?? false,
  );
}

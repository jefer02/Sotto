/// One recognizer update. [committed] are words the recognizer won't
/// change any more (the most recent ones, newest last); [committedTotal]
/// counts every word committed since the last clear, so a listener can tell
/// which of them are new. [partial] is the open utterance, which the next
/// update may still rewrite.
///
/// A streaming recognizer also says which partial words are final and when
/// each word began; segmented Whisper can't, and leaves them null.
class HeardUpdate {
  const HeardUpdate({
    this.committed = const [],
    this.committedTotal = 0,
    this.partial = '',
    this.stable,
    this.tentative,
    this.times,
    this.clock,
  });

  factory HeardUpdate.fromJson(Map<String, Object?> j) => HeardUpdate(
    committed: [for (final w in j['committed']! as List) w as String],
    committedTotal: j['total']! as int,
    partial: j['partial']! as String,
    stable: j['stable'] as int?,
    tentative: j['tentative'] as int?,
    times: switch (j['times']) {
      final List<Object?> t => [for (final x in t) (x! as num).toDouble()],
      _ => null,
    },
    clock: (j['clock'] as num?)?.toDouble(),
  );

  final List<String> committed;
  final int committedTotal;
  final String partial;

  /// How many leading words of [partial] the recognizer will not change any
  /// more. Null: unknown — the listener judges stability itself.
  final int? stable;

  /// How many partial words after the [stable] ones were heard whole but
  /// may still be revised (the open last word): following may show them at
  /// once when they are exactly the script's next words, and lets the final
  /// words confirm or correct that. Null: none offered.
  final int? tentative;

  /// When each word of [committed] followed by [partial] began, in seconds
  /// of audio on the recognizer's clock. Null when unknown.
  final List<double>? times;

  /// Seconds of audio the recognizer had heard when it sent this update.
  final double? clock;

  /// The words of [partial].
  List<String> get partialWords => partial.split(' ').where((w) => w.isNotEmpty).toList();

  /// The transcript tail as one string: committed words, then the partial.
  String get text => [...committed, if (partial.isNotEmpty) partial].join(' ');

  Map<String, Object?> toJson() => {
    'committed': committed,
    'total': committedTotal,
    'partial': partial,
    if (stable != null) 'stable': stable,
    if (tentative != null) 'tentative': tentative,
    if (times != null) 'times': [for (final t in times!) double.parse(t.toStringAsFixed(3))],
    if (clock != null) 'clock': double.parse(clock!.toStringAsFixed(3)),
  };
}

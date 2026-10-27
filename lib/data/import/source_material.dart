// What Sotto read from a presentation, PDF or document — the material a
// script is generated from (`services/ai/script_generator.dart`). Plain
// data, so readers can build it on a background isolate and send it back.

/// The kind of file a [SourceMaterial] came from.
enum SourceKind { pptx, odp, pdf, docx, markdown, text, image }

/// A line of slide or page text, with its outline level (0 = top).
class SourceLine {
  const SourceLine(this.text, [this.level = 0]);

  final String text;
  final int level;

  Map<String, Object?> toJson() => {'t': text, 'l': level};

  factory SourceLine.fromJson(Map<dynamic, dynamic> j) => SourceLine(j['t'] as String, (j['l'] as num?)?.toInt() ?? 0);
}

/// One slide or page — or, for a document, one heading's part.
class SourceUnit {
  const SourceUnit({
    required this.number,
    this.title,
    this.body = const [],
    this.notes = '',
    this.ocrText = '',
    this.altText = const [],
  });

  /// The slide's number in the deck (hidden slides count, as in
  /// PowerPoint), the page number, or the part's position in a document.
  final int number;
  final String? title;
  final List<SourceLine> body;

  /// Speaker notes.
  final String notes;

  /// Text read off the rendered page or image, on this computer.
  final String ocrText;

  /// Descriptions of the slide's pictures.
  final List<String> altText;

  bool get isEmpty =>
      (title ?? '').trim().isEmpty && body.isEmpty && notes.trim().isEmpty && ocrText.trim().isEmpty && altText.isEmpty;

  int get wordCount => _words([title ?? '', for (final l in body) l.text, ocrText, ...altText].join(' '));

  int get notesWords => _words(notes);

  Map<String, Object?> toJson() => {
    'n': number,
    'title': title,
    'body': [for (final l in body) l.toJson()],
    'notes': notes,
    'ocr': ocrText,
    'alt': altText,
  };

  factory SourceUnit.fromJson(Map<dynamic, dynamic> j) => SourceUnit(
    number: (j['n'] as num).toInt(),
    title: j['title'] as String?,
    body: [for (final l in (j['body'] as List? ?? const [])) SourceLine.fromJson(l as Map)],
    notes: j['notes'] as String? ?? '',
    ocrText: j['ocr'] as String? ?? '',
    altText: [...(j['alt'] as List? ?? const []).cast<String>()],
  );
}

/// Everything read from one file.
class SourceMaterial {
  const SourceMaterial({
    required this.name,
    required this.kind,
    required this.units,
    this.hidden = const [],
    this.ocrUnits = 0,
  });

  /// The file name ("Q3 review.pptx").
  final String name;
  final SourceKind kind;

  /// In presentation order, hidden slides left out.
  final List<SourceUnit> units;

  /// Numbers of the hidden slides that were skipped.
  final List<int> hidden;

  /// Pages or images whose text came from OCR.
  final int ocrUnits;

  bool get isSlides => kind == SourceKind.pptx || kind == SourceKind.odp;
  bool get isPaged => kind == SourceKind.pdf;

  int get wordCount => units.fold(0, (a, u) => a + u.wordCount);
  int get notesWords => units.fold(0, (a, u) => a + u.notesWords);

  /// Slides with speaker notes.
  int get unitsWithNotes => units.where((u) => u.notes.trim().isNotEmpty).length;

  bool get isEmpty => units.every((u) => u.isEmpty);

  /// The deck's own title: the first slide's title, else the file name
  /// without its extension.
  String get title {
    final first = units.map((u) => u.title?.trim() ?? '').firstWhere((t) => t.isNotEmpty, orElse: () => '');
    if (first.isNotEmpty && first.length <= 80) return first;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'kind': kind.name,
    'units': [for (final u in units) u.toJson()],
    'hidden': hidden,
    'ocr': ocrUnits,
  };

  factory SourceMaterial.fromJson(Map<dynamic, dynamic> j) => SourceMaterial(
    name: j['name'] as String,
    kind: SourceKind.values.byName(j['kind'] as String),
    units: [for (final u in (j['units'] as List)) SourceUnit.fromJson(u as Map)],
    hidden: [...(j['hidden'] as List? ?? const []).cast<int>()],
    ocrUnits: (j['ocr'] as num?)?.toInt() ?? 0,
  );
}

int _words(String s) {
  final t = s.trim();
  return t.isEmpty ? 0 : t.split(RegExp(r'\s+')).length;
}

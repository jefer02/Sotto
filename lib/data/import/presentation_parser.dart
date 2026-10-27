import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'source_material.dart';

// Presentations (.pptx OOXML, .odp ODF) and documents → [SourceMaterial].
// Pure and synchronous, so the reader runs them on `Isolate.run`.
//
// Cost: one pass over each XML part read (presentation, its relationships,
// every slide, its relationships and its notes) — O(B) time in their
// uncompressed size B; memory holds one part's DOM at a time plus the text
// kept, O(largest part + T). Media is never decompressed.

/// Why a file could not be read; the reader words it on the main isolate.
enum MaterialProblem {
  /// Not a format Sotto reads (.key, .pages…).
  unsupported,

  /// An old binary Office file (.ppt, .doc) or a password-protected one.
  legacyFormat,
  tooLarge,
  tooManyUnits,

  /// Not a valid file of its kind.
  corrupted,

  /// Nothing to read in it.
  empty,
}

class MaterialException implements Exception {
  const MaterialException(this.problem, {this.detail});

  final MaterialProblem problem;

  /// The file name, an extension or a count, depending on [problem].
  final String? detail;

  @override
  String toString() => 'MaterialException(${problem.name}${detail == null ? '' : ': $detail'})';
}

/// How much a file may ask of the reader. Archive sizes are the ones the
/// central directory declares, checked before anything is decompressed —
/// and the archive package never inflates an entry past its declared size,
/// so a zip bomb stops at these limits.
class ReadLimits {
  const ReadLimits({
    this.maxFileBytes = 100 * 1024 * 1024,
    this.maxUnits = 300,
    this.maxEntries = 10000,
    this.maxPartBytes = 16 * 1024 * 1024,
    this.maxPartsBytes = 96 * 1024 * 1024,
    this.maxImagePixels = 40 * 1000 * 1000,
  });

  final int maxFileBytes;

  /// Slides or pages.
  final int maxUnits;

  /// Entries in an archive.
  final int maxEntries;

  /// One XML part, uncompressed.
  final int maxPartBytes;

  /// All the XML parts read from one archive, uncompressed.
  final int maxPartsBytes;

  /// A picture to read text from.
  final int maxImagePixels;
}

/// Old binary Office files and encrypted OOXML are OLE compound files.
bool isOleCompound(Uint8List bytes) =>
    bytes.length >= 8 && bytes[0] == 0xD0 && bytes[1] == 0xCF && bytes[2] == 0x11 && bytes[3] == 0xE0;

/// A zip opened for reading only a few named parts, within [ReadLimits].
class _SafeZip {
  _SafeZip(Uint8List bytes, this.limits) {
    if (isOleCompound(bytes)) throw const MaterialException(MaterialProblem.legacyFormat);
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const MaterialException(MaterialProblem.corrupted);
    }
    if (archive.length > limits.maxEntries) throw const MaterialException(MaterialProblem.tooLarge);
    for (final f in archive) {
      // Only parts with plain relative names are looked up: nothing here
      // is ever written to disk, and "../" or absolute names have no place
      // in a presentation.
      if (f.isFile && _safeName(f.name)) _files[f.name] = f;
    }
  }

  final ReadLimits limits;
  final _files = <String, ArchiveFile>{};
  var _read = 0;

  static bool _safeName(String name) =>
      name.isNotEmpty &&
      !name.startsWith('/') &&
      !name.contains('\\') &&
      !name.contains(':') &&
      !name.split('/').any((s) => s == '..' || s == '.');

  bool has(String name) => _files.containsKey(name);

  /// The part's text, or null when it doesn't exist.
  String? text(String name) {
    final f = _files[name];
    if (f == null) return null;
    if (f.size > limits.maxPartBytes || _read + f.size > limits.maxPartsBytes) {
      throw const MaterialException(MaterialProblem.tooLarge);
    }
    _read += f.size;
    try {
      final bytes = f.readBytes();
      if (bytes == null) return null;
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      throw const MaterialException(MaterialProblem.corrupted);
    }
  }

  XmlDocument? xml(String name) {
    final t = text(name);
    if (t == null) return null;
    try {
      return XmlDocument.parse(t);
    } on XmlException {
      throw const MaterialException(MaterialProblem.corrupted);
    }
  }
}

// ─────────────────────────────── XML helpers ───────────────────────────────

/// Elements are matched on their local name: generators agree on the
/// namespaces but not always on the prefixes.
XmlElement? _child(XmlElement e, String local) {
  for (final c in e.childElements) {
    if (c.name.local == local) return c;
  }
  return null;
}

Iterable<XmlElement> _children(XmlElement e, String local) => e.childElements.where((c) => c.name.local == local);

Iterable<XmlElement> _descendants(XmlNode e, String local) => e.descendantElements.where((c) => c.name.local == local);

/// An attribute by local name; [prefixed] picks the namespaced one
/// (`r:id`) over the plain one (`id`).
String? _attr(XmlElement e, String local, {bool prefixed = false}) {
  for (final a in e.attributes) {
    if (a.name.local == local && (a.name.prefix != null) == prefixed) return a.value;
  }
  return null;
}

String _squash(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// [target] relative to the folder [base] (both inside the package), or
/// null when it would leave the package.
String? resolvePart(String base, String target) {
  final parts = target.startsWith('/') ? <String>[] : base.split('/').where((s) => s.isNotEmpty).toList();
  for (final seg in target.split('/')) {
    if (seg.isEmpty || seg == '.') continue;
    if (seg == '..') {
      if (parts.isEmpty) return null;
      parts.removeLast();
    } else {
      parts.add(seg);
    }
  }
  return parts.isEmpty ? null : parts.join('/');
}

String _dirOf(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? '' : path.substring(0, i);
}

/// Relationship id → target part, for [part]'s `_rels` file.
Map<String, ({String target, String type})> _relationships(_SafeZip zip, String part) {
  final dir = _dirOf(part);
  final file = part.substring(dir.isEmpty ? 0 : dir.length + 1);
  final doc = zip.xml('${dir.isEmpty ? '' : '$dir/'}_rels/$file.rels');
  if (doc == null) return const {};
  final out = <String, ({String target, String type})>{};
  for (final r in _descendants(doc, 'Relationship')) {
    final id = _attr(r, 'Id');
    final target = _attr(r, 'Target');
    if (id == null || target == null || _attr(r, 'TargetMode') == 'External') continue;
    final resolved = resolvePart(dir, target);
    if (resolved != null) out[id] = (target: resolved, type: _attr(r, 'Type') ?? '');
  }
  return out;
}

// ─────────────────────────────── PowerPoint ───────────────────────────────

/// A .pptx: slides in the order `ppt/presentation.xml` lists them
/// (`p:sldIdLst`, resolved through its relationships) — never by file name,
/// which reordering slides doesn't change. Per slide: the title
/// placeholder, every other text frame paragraph by paragraph with its
/// outline level, table rows, pictures' alt text (`descr`) and the speaker
/// notes. Hidden slides (`show="0"`) are skipped and reported.
SourceMaterial parsePptx(String name, Uint8List bytes, {ReadLimits limits = const ReadLimits()}) {
  final zip = _SafeZip(bytes, limits);
  const presentation = 'ppt/presentation.xml';
  final doc = zip.xml(presentation);
  if (doc == null) throw const MaterialException(MaterialProblem.corrupted);
  final rels = _relationships(zip, presentation);
  final ids = [
    for (final list in _descendants(doc, 'sldIdLst'))
      for (final s in _children(list, 'sldId')) _attr(s, 'id', prefixed: true),
  ];
  if (ids.length > limits.maxUnits) {
    throw MaterialException(MaterialProblem.tooManyUnits, detail: '${ids.length}');
  }

  final units = <SourceUnit>[];
  final hidden = <int>[];
  for (var i = 0; i < ids.length; i++) {
    final number = i + 1;
    final part = rels[ids[i]]?.target;
    final slide = part == null ? null : zip.xml(part);
    if (slide == null) continue; // a dangling entry: PowerPoint skips it too
    final root = slide.rootElement;
    final show = _attr(root, 'show');
    if (show == '0' || show == 'false') {
      hidden.add(number);
      continue;
    }
    final read = _SlideText();
    final tree = _descendants(root, 'spTree').firstOrNull;
    if (tree != null) read.walk(tree);
    var notes = '';
    for (final r in _relationships(zip, part!).values) {
      if (!r.type.endsWith('/notesSlide')) continue;
      final notesDoc = zip.xml(r.target);
      if (notesDoc != null) notes = _notesText(notesDoc.rootElement);
    }
    units.add(SourceUnit(number: number, title: read.title, body: read.body, notes: notes, altText: read.alt));
  }
  return SourceMaterial(name: name, kind: SourceKind.pptx, units: units, hidden: hidden);
}

class _SlideText {
  String? title;
  final body = <SourceLine>[];
  final alt = <String>[];

  void walk(XmlElement tree) {
    for (final e in tree.childElements) {
      switch (e.name.local) {
        case 'sp':
          _shape(e);
        case 'grpSp':
          walk(e);
        case 'graphicFrame':
          _altOf(e, 'nvGraphicFramePr');
          _table(e);
        case 'pic':
          _altOf(e, 'nvPicPr');
      }
    }
  }

  void _shape(XmlElement sp) {
    final ph = _descendants(sp, 'ph').firstOrNull;
    final type = ph == null ? null : _attr(ph, 'type');
    // Slide number, date, header and footer placeholders aren't content.
    if (const {'sldNum', 'dt', 'ftr', 'hdr'}.contains(type)) return;
    final txBody = _child(sp, 'txBody');
    if (txBody == null) return;
    final lines = [
      for (final p in _children(txBody, 'p'))
        if (_paragraph(p) case final text when text.isNotEmpty) SourceLine(text, _level(p)),
    ];
    if (lines.isEmpty) return;
    if ((type == 'title' || type == 'ctrTitle') && title == null) {
      title = lines.map((l) => l.text).join(' ');
    } else {
      body.addAll(lines);
    }
  }

  void _table(XmlElement frame) {
    for (final row in _descendants(frame, 'tr')) {
      final cells = [
        for (final tc in _children(row, 'tc'))
          _squash([for (final p in _descendants(tc, 'p')) _paragraph(p)].join(' ')),
      ].where((c) => c.isNotEmpty);
      if (cells.isNotEmpty) body.add(SourceLine(cells.join(' | ')));
    }
  }

  void _altOf(XmlElement e, String nv) {
    final props = _child(e, nv);
    final c = props == null ? null : _child(props, 'cNvPr');
    if (c == null) return;
    final text = _squash(_attr(c, 'descr') ?? '');
    if (text.isNotEmpty) alt.add(text);
  }
}

/// A DrawingML paragraph's text: its runs, fields and breaks.
String _paragraph(XmlElement p) {
  final out = StringBuffer();
  for (final d in p.descendantElements) {
    switch (d.name.local) {
      case 't':
        out.write(d.innerText);
      case 'br' || 'tab':
        out.write(' ');
    }
  }
  return _squash(out.toString());
}

int _level(XmlElement p) {
  final pr = _child(p, 'pPr');
  return int.tryParse(pr == null ? '' : _attr(pr, 'lvl') ?? '')?.clamp(0, 8) ?? 0;
}

/// The notes placeholder's text (not the slide image or its number).
String _notesText(XmlElement root) {
  final out = <String>[];
  for (final sp in _descendants(root, 'sp')) {
    final ph = _descendants(sp, 'ph').firstOrNull;
    if (ph == null || _attr(ph, 'type') != 'body') continue;
    final txBody = _child(sp, 'txBody');
    if (txBody == null) continue;
    out.addAll(_children(txBody, 'p').map(_paragraph).where((t) => t.isNotEmpty));
  }
  return out.join('\n');
}

// ─────────────────────────────── OpenDocument ───────────────────────────────

/// An .odp: `draw:page`s in document order; title frames by
/// `presentation:class`, lists with their nesting depth, image
/// descriptions, and the notes page. Hidden pages are skipped and reported.
SourceMaterial parseOdp(String name, Uint8List bytes, {ReadLimits limits = const ReadLimits()}) {
  final zip = _SafeZip(bytes, limits);
  final doc = zip.xml('content.xml');
  if (doc == null) throw const MaterialException(MaterialProblem.corrupted);
  // Page styles that hide their page.
  final hiddenStyles = {
    for (final st in _descendants(doc, 'style'))
      if (_descendants(st, 'drawing-page-properties').any((p) => _attr(p, 'visibility', prefixed: true) == 'hidden'))
        ?_attr(st, 'name', prefixed: true),
  };
  final pages = _descendants(doc, 'page').toList();
  if (pages.length > limits.maxUnits) {
    throw MaterialException(MaterialProblem.tooManyUnits, detail: '${pages.length}');
  }
  final units = <SourceUnit>[];
  final hidden = <int>[];
  for (var i = 0; i < pages.length; i++) {
    final page = pages[i];
    final number = i + 1;
    if (_attr(page, 'visibility', prefixed: true) == 'hidden' ||
        hiddenStyles.contains(_attr(page, 'style-name', prefixed: true))) {
      hidden.add(number);
      continue;
    }
    String? title;
    final body = <SourceLine>[];
    final alt = <String>[];
    var notes = '';
    for (final e in page.childElements) {
      if (e.name.local == 'notes') {
        notes = [
          for (final f in _descendants(e, 'frame'))
            if (_attr(f, 'class', prefixed: true) == 'notes') ..._odfLines(f).map((l) => l.text),
        ].join('\n');
        continue;
      }
      bool box(XmlElement x) => x.name.local == 'frame' || x.name.local == 'custom-shape';
      for (final frame in [if (box(e)) e, ...e.descendantElements.where(box)]) {
        final cls = _attr(frame, 'class', prefixed: true);
        if (const {'page-number', 'date-time', 'footer', 'header'}.contains(cls)) continue;
        if (_child(frame, 'image') != null) {
          final desc = _squash([for (final d in _children(frame, 'desc')) d.innerText].join(' '));
          final t = _squash([for (final d in _children(frame, 'title')) d.innerText].join(' '));
          if (desc.isNotEmpty || t.isNotEmpty) alt.add(desc.isNotEmpty ? desc : t);
          continue;
        }
        final lines = _odfLines(frame);
        if (lines.isEmpty) continue;
        if (cls == 'title' && title == null) {
          title = lines.map((l) => l.text).join(' ');
        } else {
          body.addAll(lines);
        }
      }
    }
    units.add(SourceUnit(number: number, title: title, body: body, notes: notes, altText: alt));
  }
  return SourceMaterial(name: name, kind: SourceKind.odp, units: units, hidden: hidden);
}

/// Paragraphs and headings under [frame], with their list depth.
List<SourceLine> _odfLines(XmlElement frame) {
  final out = <SourceLine>[];
  for (final p in frame.descendantElements) {
    if (p.name.local != 'p' && p.name.local != 'h') continue;
    // Nested paragraphs (a list inside a cell) are read with their parent.
    if (p.ancestorElements.any((a) => a.name.local == 'p' || a.name.local == 'h')) continue;
    final depth = p.ancestorElements.takeWhile((a) => !identical(a, frame)).where((a) => a.name.local == 'list');
    final text = _squash(_odfText(p));
    if (text.isNotEmpty) out.add(SourceLine(text, depth.isEmpty ? 0 : depth.length - 1));
  }
  return out;
}

String _odfText(XmlElement e) {
  final out = StringBuffer();
  for (final n in e.children) {
    if (n is XmlText) {
      out.write(n.value);
    } else if (n is XmlElement) {
      switch (n.name.local) {
        case 's' || 'tab' || 'line-break':
          out.write(' ');
        default:
          out.write(_odfText(n));
      }
    }
  }
  return out.toString();
}

// ─────────────────────────────── Documents ───────────────────────────────

/// A document's text (as the script importer reads .docx / .md / .txt) cut
/// into parts at its headings: each heading starts a part, paragraphs are
/// lines, and "-" / "*" / "1." bullets keep their indentation as a level.
SourceMaterial documentMaterial(String name, SourceKind kind, String text) {
  final units = <SourceUnit>[];
  String? title;
  var body = <SourceLine>[];
  void close() {
    if (title != null || body.isNotEmpty) {
      units.add(SourceUnit(number: units.length + 1, title: title, body: body));
    }
    title = null;
    body = <SourceLine>[];
  }

  final heading = RegExp(r'^\s{0,3}#{1,6}\s+(.+?)\s*#*\s*$');
  final bullet = RegExp(r'^(\s*)(?:[-*•]|\d+[.)])\s+(.+)$');
  final paragraph = StringBuffer();
  void flushParagraph() {
    final t = _squash(paragraph.toString());
    if (t.isNotEmpty) body.add(SourceLine(t));
    paragraph.clear();
  }

  for (final raw in const LineSplitter().convert(text)) {
    final h = heading.firstMatch(raw);
    if (h != null) {
      flushParagraph();
      close();
      title = _squash(h.group(1)!.replaceAll(RegExp(r'[*_`]'), ''));
      continue;
    }
    final b = bullet.firstMatch(raw);
    if (b != null) {
      flushParagraph();
      body.add(SourceLine(_squash(b.group(2)!), (b.group(1)!.replaceAll('\t', '  ').length ~/ 2).clamp(0, 8)));
      continue;
    }
    if (raw.trim().isEmpty) {
      flushParagraph();
    } else {
      paragraph
        ..write(' ')
        ..write(raw);
    }
  }
  flushParagraph();
  close();
  return SourceMaterial(name: name, kind: kind, units: units);
}

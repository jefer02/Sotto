import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../../l10n/l10n.dart';
import 'presentation_parser.dart';
import 'script_importer.dart';
import 'source_material.dart';

export 'presentation_parser.dart' show MaterialException, MaterialProblem, ReadLimits;

/// Reads the text on a picture, on this computer (Windows.Media.Ocr,
/// macOS Vision). Null when it can't (no OCR on this platform).
abstract interface class ImageOcr {
  /// [bgra]: [width] × [height] pixels, 4 bytes each, blue first.
  Future<String?> read(Uint8List bgra, int width, int height);
}

/// A page drawn to pixels for OCR.
class RenderedPage {
  const RenderedPage(this.bgra, this.width, this.height);
  final Uint8List bgra;
  final int width;
  final int height;
}

/// An open PDF, page by page. Behind an interface so tests can stand in
/// for PDFium.
abstract interface class PdfPages {
  int get count;

  /// The page's text layer (0-based [index]).
  Future<String> text(int index);

  /// The page drawn so its long side is [maxSide] pixels.
  Future<RenderedPage?> render(int index, {int maxSide});

  Future<void> close();
}

abstract interface class PdfSource {
  Future<PdfPages> open(String path);
}

/// PDFium through pdfrx, on its own worker isolate.
class PdfrxSource implements PdfSource {
  const PdfrxSource();

  @override
  Future<PdfPages> open(String path) async {
    await pdfrxFlutterInitialize();
    return _PdfrxPages(await PdfDocument.openFile(path));
  }
}

class _PdfrxPages implements PdfPages {
  _PdfrxPages(this._doc);
  final PdfDocument _doc;

  @override
  int get count => _doc.pages.length;

  @override
  Future<String> text(int index) async => (await _doc.pages[index].loadText())?.fullText ?? '';

  @override
  Future<RenderedPage?> render(int index, {int maxSide = 2000}) async {
    final page = _doc.pages[index];
    final k = maxSide / (page.width > page.height ? page.width : page.height);
    final w = (page.width * k).round();
    final h = (page.height * k).round();
    final image = await page.render(fullWidth: w.toDouble(), fullHeight: h.toDouble(), backgroundColor: 0xFFFFFFFF);
    if (image == null) return null;
    try {
      return RenderedPage(Uint8List.fromList(image.pixels), image.width, image.height);
    } finally {
      image.dispose();
    }
  }

  @override
  Future<void> close() => _doc.dispose();
}

/// Presentations, PDFs, documents and pictures → [SourceMaterial], all on
/// this computer and off the UI thread: archives and XML on `Isolate.run`,
/// PDFs on pdfrx's worker isolate, pictures decoded on `Isolate.run`, and
/// text read off scanned pages and pictures by the system's OCR.
///
/// Cost: O(B) in the file's bytes for parsing (see `presentation_parser.dart`),
/// plus, per page without a text layer, rendering and OCR — O(pixels) each,
/// at most 2000 px a side.
class MaterialReader {
  MaterialReader({this.ocr, this.pdf = const PdfrxSource(), this.limits = const ReadLimits()});

  final ImageOcr? ocr;
  final PdfSource pdf;
  final ReadLimits limits;

  static const slideExtensions = ['pptx', 'odp'];
  static const imageExtensions = ['png', 'jpg', 'jpeg'];
  static const extensions = [...slideExtensions, 'pdf', 'docx', 'md', 'markdown', 'txt', ...imageExtensions];

  /// Formats people try that Sotto can't read; the message says what to
  /// export instead.
  static const _exportFirst = ['ppt', 'pps', 'ppsx', 'key', 'doc', 'pages', 'odt', 'rtf'];

  /// A page with fewer letters than this in its text layer is scanned:
  /// its text is read off the rendered page.
  static const scannedBelow = 24;

  Future<SourceMaterial> read(String path) async {
    final watch = Stopwatch()..start();
    try {
      final m = await _read(path);
      _log(
        '${m.name} (${m.kind.name}): ${m.units.length} units, ${m.hidden.length} hidden, ${m.wordCount} words, '
        'notes on ${m.unitsWithNotes}, OCR on ${m.ocrUnits} in ${watch.elapsedMilliseconds} ms',
      );
      return m;
    } on MaterialException catch (e) {
      _log('${p.basename(path)}: $e after ${watch.elapsedMilliseconds} ms');
      rethrow;
    }
  }

  /// Debug builds only: what reading took, for reports from real use.
  static void _log(String message) {
    if (kDebugMode) debugPrint('material: $message');
  }

  /// Reads [bgra] with [ocr], logging pixels, characters and time.
  Future<String?> _ocr(String what, Uint8List bgra, int width, int height) async {
    final watch = Stopwatch()..start();
    final text = await ocr?.read(bgra, width, height);
    _log(
      'OCR $what: $width x $height px, ${text?.trim().length ?? 0} chars recognized in '
      '${watch.elapsedMilliseconds} ms${ocr == null ? ' (no OCR on this platform)' : ''}',
    );
    return text;
  }

  Future<SourceMaterial> _read(String path) async {
    final name = p.basename(path);
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    if (!extensions.contains(ext)) {
      throw MaterialException(MaterialProblem.unsupported, detail: ext.isEmpty ? name : '.$ext');
    }
    final file = File(path);
    final length = await file.length();
    if (length > limits.maxFileBytes) throw const MaterialException(MaterialProblem.tooLarge);
    final SourceMaterial material;
    if (ext == 'pdf') {
      material = await _pdf(name, path);
    } else {
      material = await readBytes(name, await file.readAsBytes());
    }
    if (material.isEmpty) throw MaterialException(MaterialProblem.empty, detail: name);
    return material;
  }

  /// Every format but PDF, from its bytes.
  Future<SourceMaterial> readBytes(String name, Uint8List bytes) async {
    final ext = p.extension(name).toLowerCase().replaceFirst('.', '');
    final limits = this.limits;
    switch (ext) {
      case 'pptx':
        return Isolate.run(() => parsePptx(name, bytes, limits: limits));
      case 'odp':
        return Isolate.run(() => parseOdp(name, bytes, limits: limits));
      case 'docx' || 'md' || 'markdown' || 'txt':
        if (ext == 'docx' && isOleCompound(bytes)) throw const MaterialException(MaterialProblem.legacyFormat);
        final kind = switch (ext) {
          'docx' => SourceKind.docx,
          'txt' => SourceKind.text,
          _ => SourceKind.markdown,
        };
        return Isolate.run(() {
          final String? text;
          try {
            text = ScriptImporter.parseText(ext, bytes);
          } catch (_) {
            throw const MaterialException(MaterialProblem.corrupted);
          }
          if (text == null) throw const MaterialException(MaterialProblem.corrupted);
          return documentMaterial(name, kind, text);
        });
      case 'png' || 'jpg' || 'jpeg':
        return _image(name, bytes);
      default:
        throw MaterialException(MaterialProblem.unsupported, detail: '.$ext');
    }
  }

  Future<SourceMaterial> _pdf(String name, String path) async {
    final PdfPages doc;
    try {
      doc = await pdf.open(path);
    } catch (_) {
      throw const MaterialException(MaterialProblem.corrupted);
    }
    try {
      if (doc.count > limits.maxUnits) {
        throw MaterialException(MaterialProblem.tooManyUnits, detail: '${doc.count}');
      }
      final pages = <String>[];
      final scanned = <int, String>{};
      for (var i = 0; i < doc.count; i++) {
        final text = await doc.text(i);
        pages.add(text);
        if (text.replaceAll(RegExp(r'[^\p{L}]', unicode: true), '').length >= scannedBelow || ocr == null) continue;
        final rendering = Stopwatch()..start();
        final page = await doc.render(i, maxSide: 2000);
        _log('$name page ${i + 1}: no text layer, rendered in ${rendering.elapsedMilliseconds} ms');
        if (page == null) continue;
        final read = await _ocr('$name page ${i + 1}', page.bgra, page.width, page.height);
        if (read != null && read.trim().isNotEmpty) scanned[i] = read;
      }
      return await Isolate.run(() => pdfMaterial(name, pages, scanned));
    } finally {
      await doc.close();
    }
  }

  Future<SourceMaterial> _image(String name, Uint8List bytes) async {
    final maxPixels = limits.maxImagePixels;
    final decoded = await Isolate.run(() {
      final decoder = img.findDecoderForData(bytes);
      final info = decoder?.startDecode(bytes);
      if (decoder == null || info == null) throw const MaterialException(MaterialProblem.corrupted);
      if (info.width * info.height > maxPixels) throw const MaterialException(MaterialProblem.tooLarge);
      final image = decoder.decode(bytes);
      if (image == null) throw const MaterialException(MaterialProblem.corrupted);
      final rgba = image.convert(numChannels: 4, format: img.Format.uint8);
      return RenderedPage(rgba.getBytes(order: img.ChannelOrder.bgra), rgba.width, rgba.height);
    });
    final text = await _ocr(name, decoded.bgra, decoded.width, decoded.height) ?? '';
    return SourceMaterial(
      name: name,
      kind: SourceKind.image,
      units: [if (text.trim().isNotEmpty) SourceUnit(number: 1, ocrText: text.trim())],
      ocrUnits: 1,
    );
  }

  /// What a [MaterialException] means, in the interface language.
  static String describe(MaterialException e) {
    final l = L10n.current;
    return switch (e.problem) {
      MaterialProblem.unsupported when _exportFirst.contains(e.detail?.replaceFirst('.', '')) => l.materialExportFirst(
        e.detail ?? '',
      ),
      MaterialProblem.unsupported => l.materialUnsupported(e.detail ?? ''),
      MaterialProblem.legacyFormat => l.materialLegacy,
      MaterialProblem.tooLarge => l.materialTooLarge,
      MaterialProblem.tooManyUnits => l.materialTooManyPages(
        int.tryParse(e.detail ?? '') ?? 0,
        const ReadLimits().maxUnits,
      ),
      MaterialProblem.corrupted => l.materialCorrupted,
      MaterialProblem.empty => l.materialEmpty,
    };
  }
}

/// A PDF's pages as units: each page's text layer (or, for a scanned page,
/// what OCR read) with wrapped lines rejoined into paragraphs; a short
/// first line becomes the page's title. Pure, for `Isolate.run`. O(n) in
/// the text.
SourceMaterial pdfMaterial(String name, List<String> pages, Map<int, String> scanned) {
  final units = <SourceUnit>[];
  for (var i = 0; i < pages.length; i++) {
    final ocrText = scanned[i];
    final source = ocrText ?? pages[i];
    final lines = source.replaceAll('\r\n', '\n').split('\n').map((l) => l.trim()).toList();
    // A short first line without closing punctuation, with text under it,
    // is the page's title.
    String? title;
    final first = lines.indexWhere((l) => l.isNotEmpty);
    if (first >= 0 &&
        lines[first].length <= 90 &&
        !RegExp(r'[.!?,;:]$').hasMatch(lines[first]) &&
        lines.skip(first + 1).any((l) => l.isNotEmpty)) {
      title = lines[first];
      lines.removeAt(first);
    }
    // Wrapped lines rejoin; a blank line or a line ending a sentence
    // closes the paragraph.
    final paragraphs = <String>[];
    final current = StringBuffer();
    void close() {
      final t = current.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      if (t.isNotEmpty) paragraphs.add(t);
      current.clear();
    }

    for (final line in lines) {
      if (line.isEmpty) {
        close();
        continue;
      }
      current
        ..write(' ')
        ..write(line);
      if (RegExp(r'[.!?:]["”’)]?$').hasMatch(line)) close();
    }
    close();
    final unit = ocrText != null
        ? SourceUnit(number: i + 1, title: title, ocrText: paragraphs.join('\n'))
        : SourceUnit(number: i + 1, title: title, body: [for (final t in paragraphs) SourceLine(t)]);
    if (!unit.isEmpty) units.add(unit);
  }
  return SourceMaterial(name: name, kind: SourceKind.pdf, units: units, ocrUnits: scanned.length);
}

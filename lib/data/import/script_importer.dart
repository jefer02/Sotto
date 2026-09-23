import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:xml/xml.dart';

import '../../l10n/l10n.dart';

class ImportResult {
  const ImportResult({required this.title, required this.text, required this.sourceName});

  final String title;

  /// Plain text; headings are rendered as Markdown `#` lines so the
  /// structurer can find sections.
  final String text;
  final String sourceName;
}

class ImportException implements Exception {
  ImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// .txt and .md natively, .docx by reading the OOXML body, .pdf through
/// PDFium (pdfrx). Everything runs locally.
abstract final class ScriptImporter {
  static const supportedExtensions = ['txt', 'md', 'markdown', 'docx', 'pdf'];

  static Future<ImportResult> fromFile(String path) async {
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    final name = p.basename(path);
    final title = p.basenameWithoutExtension(path);
    final bytes = await File(path).readAsBytes();
    final text = switch (ext) {
      'txt' || 'md' || 'markdown' => _decodeText(bytes),
      'docx' => _docxText(bytes),
      'pdf' => await _pdfText(path),
      _ => throw ImportException(L10n.current.importUnsupported),
    };
    if (text.trim().isEmpty) {
      throw ImportException(L10n.current.importNoText(name));
    }
    return ImportResult(title: _titleFrom(text) ?? title, text: text, sourceName: name);
  }

  static ImportResult fromPaste(String text) =>
      ImportResult(title: _titleFrom(text) ?? L10n.current.pastedScript, text: text, sourceName: L10n.current.pastedText);

  static String _decodeText(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }

  /// A leading "# Title" becomes the script title.
  static String? _titleFrom(String text) {
    final first = text.trimLeft().split('\n').first.trim();
    final m = RegExp(r'^#\s+(.+)$').firstMatch(first);
    return m?.group(1)?.trim();
  }

  static String _docxText(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final entry = archive.findFile('word/document.xml');
    if (entry == null) throw ImportException(L10n.current.importNoBody);
    final doc = XmlDocument.parse(utf8.decode(entry.content as List<int>));
    final out = StringBuffer();

    for (final para in doc.findAllElements('w:p')) {
      final style = para.findAllElements('w:pStyle').map((e) => e.getAttribute('w:val') ?? '').firstOrNull ?? '';
      final buf = StringBuffer();
      for (final node in para.descendants.whereType<XmlElement>()) {
        switch (node.name.qualified) {
          case 'w:t':
            final bold = node.parent?.findElements('w:rPr').firstOrNull?.findElements('w:b').isNotEmpty ?? false;
            final t = node.innerText;
            buf.write(bold && t.trim().isNotEmpty ? '**$t**' : t);
          case 'w:tab':
            buf.write(' ');
          case 'w:br':
            buf.write('\n');
        }
      }
      final text = buf.toString().replaceAll('****', '');
      // Word stores localized style ids ("Heading1", "Titre1", "berschrift1").
      final level = RegExp(r'(?:heading|titre|berschrift|tulo)\s*(\d)', caseSensitive: false).firstMatch(style);
      if (style.toLowerCase() == 'title') {
        out.writeln('# ${text.trim()}\n');
      } else if (level != null && text.trim().isNotEmpty) {
        out.writeln('${'#' * (int.parse(level.group(1)!) + 1).clamp(2, 6)} ${text.trim()}\n');
      } else {
        out.writeln(text);
        out.writeln();
      }
    }
    return out.toString();
  }

  static Future<String> _pdfText(String path) async {
    await pdfrxFlutterInitialize();
    final doc = await PdfDocument.openFile(path);
    try {
      final out = StringBuffer();
      for (final page in doc.pages) {
        final text = await page.loadText();
        if (text != null) {
          // PDF text arrives with hard line breaks; rejoin wrapped lines but
          // keep blank-line paragraph breaks.
          final joined = text.fullText
              .replaceAll('\r\n', '\n')
              .replaceAll(RegExp(r'(?<![.!?:])\n(?!\n)'), ' ')
              .replaceAll(RegExp(r'[ \t]+'), ' ');
          out.writeln(joined.trim());
          out.writeln();
        }
      }
      return out.toString();
    } finally {
      await doc.dispose();
    }
  }
}

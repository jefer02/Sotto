// Builds small but real .pptx / .odp packages for the extraction tests, so
// each fixture's quirk is visible in code: slide parts named out of order,
// hidden slides, notes, nested bullets, pictures with alt text.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

const _p = 'http://schemas.openxmlformats.org/presentationml/2006/main';
const _a = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const _r = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _rels = 'http://schemas.openxmlformats.org/package/2006/relationships';
const _slideType = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide';
const _notesType = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesSlide';

String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// A slide: its title, bullets as (text, level), notes, pictures' alt text.
class FixtureSlide {
  const FixtureSlide({
    this.title,
    this.bullets = const [],
    this.notes,
    this.pictures = const [],
    this.hidden = false,
    this.footer,
  });

  final String? title;
  final List<(String, int)> bullets;
  final String? notes;
  final List<String> pictures;
  final bool hidden;

  /// Text in a footer placeholder, which isn't content.
  final String? footer;
}

/// A .pptx whose slide parts are named [fileNumbers] (slide{n}.xml) while
/// `presentation.xml` lists them in [slides] order.
Uint8List buildPptx(List<FixtureSlide> slides, {List<int>? fileNumbers, Map<String, String> extra = const {}}) {
  final numbers = fileNumbers ?? [for (var i = 0; i < slides.length; i++) i + 1];
  final archive = Archive();
  void add(String name, String text) {
    final bytes = utf8.encode(text);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add(
    '[Content_Types].xml',
    '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>',
  );
  final ids = StringBuffer();
  final presRels = StringBuffer();
  for (var i = 0; i < slides.length; i++) {
    final n = numbers[i];
    // Relationship ids deliberately not in slide order either.
    final rid = 'rId${100 - i}';
    ids.write('<p:sldId id="${256 + i}" r:id="$rid"/>');
    presRels.write('<Relationship Id="$rid" Type="$_slideType" Target="slides/slide$n.xml"/>');
    final s = slides[i];
    final shapes = StringBuffer();
    if (s.title != null) {
      shapes.write(
        '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Title"/><p:cNvSpPr/><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr>'
        '<p:txBody><a:bodyPr/><a:p><a:r><a:t>${_esc(s.title!)}</a:t></a:r></a:p></p:txBody></p:sp>',
      );
    }
    if (s.bullets.isNotEmpty) {
      shapes.write(
        '<p:sp><p:nvSpPr><p:cNvPr id="3" name="Body"/><p:cNvSpPr/><p:nvPr><p:ph idx="1"/></p:nvPr></p:nvSpPr><p:txBody><a:bodyPr/>',
      );
      for (final (text, level) in s.bullets) {
        // Two runs per paragraph, as PowerPoint writes formatted text.
        final mid = text.length ~/ 2;
        shapes.write(
          '<a:p>${level > 0 ? '<a:pPr lvl="$level"/>' : ''}<a:r><a:t>${_esc(text.substring(0, mid))}</a:t></a:r>'
          '<a:r><a:rPr b="1"/><a:t>${_esc(text.substring(mid))}</a:t></a:r></a:p>',
        );
      }
      shapes.write('</p:txBody></p:sp>');
    }
    for (final alt in s.pictures) {
      shapes.write(
        '<p:pic><p:nvPicPr><p:cNvPr id="4" name="Picture" descr="${_esc(alt)}"/><p:cNvPicPr/><p:nvPr/></p:nvPicPr>'
        '<p:blipFill/><p:spPr/></p:pic>',
      );
    }
    if (s.footer != null) {
      shapes.write(
        '<p:sp><p:nvSpPr><p:cNvPr id="5" name="Footer"/><p:cNvSpPr/><p:nvPr><p:ph type="ftr"/></p:nvPr></p:nvSpPr>'
        '<p:txBody><a:bodyPr/><a:p><a:r><a:t>${_esc(s.footer!)}</a:t></a:r></a:p></p:txBody></p:sp>',
      );
    }
    add(
      'ppt/slides/slide$n.xml',
      '<?xml version="1.0"?><p:sld xmlns:p="$_p" xmlns:a="$_a" xmlns:r="$_r"${s.hidden ? ' show="0"' : ''}>'
          '<p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>'
          '$shapes</p:spTree></p:cSld></p:sld>',
    );
    final slideRels = StringBuffer();
    if (s.notes != null) {
      slideRels.write('<Relationship Id="rId9" Type="$_notesType" Target="../notesSlides/notesSlide$n.xml"/>');
      add(
        'ppt/notesSlides/notesSlide$n.xml',
        '<?xml version="1.0"?><p:notes xmlns:p="$_p" xmlns:a="$_a"><p:cSld><p:spTree>'
            '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Image"/><p:cNvSpPr/><p:nvPr><p:ph type="sldImg"/></p:nvPr></p:nvSpPr></p:sp>'
            '<p:sp><p:nvSpPr><p:cNvPr id="3" name="Notes"/><p:cNvSpPr/><p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr>'
            '<p:txBody><a:bodyPr/>${[for (final line in s.notes!.split('\n')) '<a:p><a:r><a:t>${_esc(line)}</a:t></a:r></a:p>'].join()}</p:txBody></p:sp>'
            '<p:sp><p:nvSpPr><p:cNvPr id="4" name="Number"/><p:cNvSpPr/><p:nvPr><p:ph type="sldNum"/></p:nvPr></p:nvSpPr>'
            '<p:txBody><a:bodyPr/><a:p><a:r><a:t>$n</a:t></a:r></a:p></p:txBody></p:sp>'
            '</p:spTree></p:cSld></p:notes>',
      );
    }
    add(
      'ppt/slides/_rels/slide$n.xml.rels',
      '<?xml version="1.0"?><Relationships xmlns="$_rels">$slideRels</Relationships>',
    );
  }
  add(
    'ppt/presentation.xml',
    '<?xml version="1.0"?><p:presentation xmlns:p="$_p" xmlns:r="$_r"><p:sldIdLst>$ids</p:sldIdLst></p:presentation>',
  );
  add(
    'ppt/_rels/presentation.xml.rels',
    '<?xml version="1.0"?><Relationships xmlns="$_rels">$presRels</Relationships>',
  );
  extra.forEach(add);
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

/// A minimal .odp: a title and a nested list per page, notes, one hidden
/// page through its style.
Uint8List buildOdp(List<FixtureSlide> slides) {
  const office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
  const draw = 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0';
  const text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
  const pres = 'urn:oasis:names:tc:opendocument:xmlns:presentation:1.0';
  const style = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
  const svg = 'urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0';
  final pages = StringBuffer();
  for (var i = 0; i < slides.length; i++) {
    final s = slides[i];
    pages.write('<draw:page draw:name="p${i + 1}" draw:style-name="${s.hidden ? 'dpHidden' : 'dp1'}">');
    if (s.title != null) {
      pages.write(
        '<draw:frame presentation:class="title"><draw:text-box><text:p>${_esc(s.title!)}</text:p></draw:text-box></draw:frame>',
      );
    }
    if (s.bullets.isNotEmpty) {
      pages.write('<draw:frame presentation:class="outline"><draw:text-box>');
      for (final (t, level) in s.bullets) {
        pages
          ..write('<text:list><text:list-item>' * (level + 1))
          ..write('<text:p>${_esc(t)}</text:p>')
          ..write('</text:list-item></text:list>' * (level + 1));
      }
      pages.write('</draw:text-box></draw:frame>');
    }
    for (final alt in s.pictures) {
      pages.write('<draw:frame><draw:image/><svg:desc>${_esc(alt)}</svg:desc></draw:frame>');
    }
    if (s.notes != null) {
      pages.write(
        '<presentation:notes><draw:frame presentation:class="notes"><draw:text-box>'
        '<text:p>${_esc(s.notes!)}</text:p></draw:text-box></draw:frame></presentation:notes>',
      );
    }
    pages.write('</draw:page>');
  }
  final content =
      '<?xml version="1.0"?><office:document-content xmlns:office="$office" xmlns:draw="$draw" xmlns:text="$text" '
      'xmlns:presentation="$pres" xmlns:style="$style" xmlns:svg="$svg"><office:automatic-styles>'
      '<style:style style:name="dp1" style:family="drawing-page"><style:drawing-page-properties presentation:visibility="visible"/></style:style>'
      '<style:style style:name="dpHidden" style:family="drawing-page"><style:drawing-page-properties presentation:visibility="hidden"/></style:style>'
      '</office:automatic-styles><office:body><office:presentation>$pages</office:presentation></office:body>'
      '</office:document-content>';
  final archive = Archive();
  final bytes = utf8.encode(content);
  archive.addFile(ArchiveFile('content.xml', bytes.length, bytes));
  final mime = utf8.encode('application/vnd.oasis.opendocument.presentation');
  archive.addFile(ArchiveFile('mimetype', mime.length, mime));
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

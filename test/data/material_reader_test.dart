// Reading presentations, PDFs, documents and pictures into SourceMaterial:
// slide order from presentation.xml (not file names), notes, hidden slides,
// nested bullets, alt text, safe archive handling, and the OCR path for
// scanned pages — behind fakes for PDFium and the system OCR.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sotto/data/import/material_reader.dart';
import 'package:sotto/data/import/presentation_parser.dart';
import 'package:sotto/data/import/source_material.dart';
import 'package:sotto/l10n/l10n.dart';

import '../fixtures/materials/pptx_builder.dart';

/// Five slides whose parts are named slide3, slide1, slide5, slide2,
/// slide4 — the deck's order is only in presentation.xml.
final _deck = [
  const FixtureSlide(
    title: 'Q3 at a glance',
    bullets: [('Revenue grew 12%', 0), ('New logos in Mexico', 1), ('Monterrey and Guadalajara', 2)],
    notes: 'Open with the 12% and pause.\nThen thank the team.',
    footer: 'Confidential',
  ),
  const FixtureSlide(title: 'Margin', bullets: [('Gross margin 48.2%', 0)]),
  const FixtureSlide(title: 'Backup numbers', bullets: [('Not for the talk', 0)], hidden: true),
  const FixtureSlide(pictures: ['Bar chart: revenue by quarter, Q1 to Q3, rising']),
  const FixtureSlide(title: 'Next steps', bullets: [('Second warehouse', 0)], notes: 'Ask for the budget.'),
];

class _FakeOcr implements ImageOcr {
  _FakeOcr(this.text);
  final String? text;
  final calls = <(int, int)>[];

  @override
  Future<String?> read(Uint8List bgra, int width, int height) async {
    expect(bgra.length, width * height * 4);
    calls.add((width, height));
    return text;
  }
}

/// Stands in for PDFium: a page per entry; an empty string is a scan.
class _FakePdf implements PdfSource {
  _FakePdf(this.pages);
  final List<String> pages;
  final rendered = <int>[];

  @override
  Future<PdfPages> open(String path) async => _FakePages(this);
}

class _FakePages implements PdfPages {
  _FakePages(this.pdf);
  final _FakePdf pdf;

  @override
  int get count => pdf.pages.length;

  @override
  Future<String> text(int index) async => pdf.pages[index];

  @override
  Future<RenderedPage?> render(int index, {int maxSide = 2000}) async {
    pdf.rendered.add(index);
    return RenderedPage(Uint8List(40 * 30 * 4), 40, 30);
  }

  @override
  Future<void> close() async {}
}

void main() {
  late Directory tmp;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    L10n.current = lookupAppLocalizations(const Locale('en'));
    tmp = Directory.systemTemp.createTempSync('sotto_material');
  });

  tearDownAll(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  File write(String name, List<int> bytes) => File('${tmp.path}/$name')..writeAsBytesSync(bytes);

  group('PowerPoint', () {
    final bytes = buildPptx(_deck, fileNumbers: [3, 1, 5, 2, 4]);
    final m = parsePptx('Q3 review.pptx', bytes);

    test('slides come in presentation.xml order, not by file name', () {
      expect(m.units.map((u) => u.number), [1, 2, 4, 5]);
      expect(m.units.map((u) => u.title), ['Q3 at a glance', 'Margin', null, 'Next steps']);
    });

    test('a hidden slide is skipped and reported', () {
      expect(m.hidden, [3]);
      expect(m.units.any((u) => u.title == 'Backup numbers'), isFalse);
    });

    test('nested bullets keep their levels; runs join; footers are not content', () {
      final first = m.units.first;
      expect(first.body.map((l) => (l.text, l.level)), [
        ('Revenue grew 12%', 0),
        ('New logos in Mexico', 1),
        ('Monterrey and Guadalajara', 2),
      ]);
      expect(first.body.any((l) => l.text.contains('Confidential')), isFalse);
    });

    test('speaker notes come from the notes placeholder only', () {
      expect(m.units.first.notes, 'Open with the 12% and pause.\nThen thank the team.');
      expect(m.units.last.notes, 'Ask for the budget.');
      expect(m.units[1].notes, isEmpty);
      expect(m.unitsWithNotes, 2);
    });

    test('a slide with only a picture is read from its alt text', () {
      final picture = m.units[2];
      expect(picture.body, isEmpty);
      expect(picture.altText, ['Bar chart: revenue by quarter, Q1 to Q3, rising']);
      expect(picture.isEmpty, isFalse);
    });

    test('the deck is titled from its first slide', () {
      expect(m.title, 'Q3 at a glance');
      expect(m.isSlides, isTrue);
    });

    test('a damaged file read off the UI thread still says why', () async {
      final bytes = buildPptx(_deck);
      await expectLater(
        MaterialReader().read(write('cut.pptx', bytes.sublist(0, bytes.length ~/ 2)).path),
        throwsA(isA<MaterialException>().having((e) => e.problem, 'problem', MaterialProblem.corrupted)),
      );
    });

    test('through the reader, off the UI thread', () async {
      final read = await MaterialReader().read(write('deck.pptx', bytes).path);
      expect(read.units.map((u) => u.number), [1, 2, 4, 5]);
      expect(read.hidden, [3]);
    });
  });

  group('safe archives', () {
    test('a corrupted file says so', () {
      final bytes = buildPptx(_deck);
      final cut = Uint8List.sublistView(bytes, 0, bytes.length ~/ 2);
      expect(
        () => parsePptx('broken.pptx', cut),
        throwsA(isA<MaterialException>().having((e) => e.problem, 'problem', MaterialProblem.corrupted)),
      );
      expect(
        () => parsePptx('noise.pptx', Uint8List.fromList(List.generate(500, (i) => i * 7 % 256))),
        throwsA(isA<MaterialException>().having((e) => e.problem, 'problem', MaterialProblem.corrupted)),
      );
    });

    test('a zip that is not a presentation is corrupted, not a crash', () {
      final archive = Archive()..addFile(ArchiveFile('hello.txt', 2, utf8.encode('hi')));
      expect(
        () => parsePptx('x.pptx', Uint8List.fromList(ZipEncoder().encodeBytes(archive))),
        throwsA(isA<MaterialException>().having((e) => e.problem, 'problem', MaterialProblem.corrupted)),
      );
    });

    test('old binary Office files and protected files ask to be saved again', () {
      final ole = Uint8List.fromList([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, ...List.filled(64, 0)]);
      expect(
        () => parsePptx('old.pptx', ole),
        throwsA(isA<MaterialException>().having((e) => e.problem, 'problem', MaterialProblem.legacyFormat)),
      );
    });

    test('a part bigger than the limits is refused before it is inflated', () {
      // 2 MB of spaces compresses to a few KB: a small zip bomb.
      final huge = '<?xml version="1.0"?><p:sld>${' ' * (2 * 1024 * 1024)}</p:sld>';
      final bytes = buildPptx(_deck, extra: {'ppt/slides/slide1.xml': huge});
      expect(bytes.length, lessThan(200 * 1024));
      expect(
        () => parsePptx('bomb.pptx', bytes, limits: const ReadLimits(maxPartBytes: 1024 * 1024)),
        throwsA(isA<MaterialException>().having((e) => e.problem, 'problem', MaterialProblem.tooLarge)),
      );
    });

    test('too many slides', () {
      final bytes = buildPptx(List.filled(6, const FixtureSlide(title: 'x')));
      expect(
        () => parsePptx('long.pptx', bytes, limits: const ReadLimits(maxUnits: 5)),
        throwsA(isA<MaterialException>().having((e) => e.problem, 'problem', MaterialProblem.tooManyUnits)),
      );
    });

    test('relationships never leave the package', () {
      expect(resolvePart('ppt/slides', '../notesSlides/notesSlide1.xml'), 'ppt/notesSlides/notesSlide1.xml');
      expect(resolvePart('ppt', 'slides/slide2.xml'), 'ppt/slides/slide2.xml');
      expect(resolvePart('ppt/slides', '/ppt/media/a.png'), 'ppt/media/a.png');
      expect(resolvePart('ppt/slides', '../../../etc/passwd'), isNull);
      // An entry named with ../ is never looked up, even if a part points at it.
      final bytes = buildPptx(_deck, extra: {'../evil.xml': '<x/>'});
      expect(parsePptx('d.pptx', bytes).units, hasLength(4));
    });
  });

  test('OpenDocument: titles, list depth, notes, pictures, a hidden page', () {
    final m = parseOdp('deck.odp', buildOdp(_deck));
    expect(m.units.map((u) => u.number), [1, 2, 4, 5]);
    expect(m.hidden, [3]);
    expect(m.units.first.title, 'Q3 at a glance');
    expect(m.units.first.body.map((l) => l.level), [0, 1, 2]);
    expect(m.units.first.notes, contains('Open with the 12%'));
    expect(m.units[2].altText, ['Bar chart: revenue by quarter, Q1 to Q3, rising']);
  });

  test('documents are cut at headings, bullets keep their indentation', () {
    final m = documentMaterial('notes.md', SourceKind.markdown, '''
# Opening
Thanks for coming.
It's been a big quarter.

- Revenue
  - Mexico
## Next
Second warehouse.''');
    expect(m.units.map((u) => u.title), ['Opening', 'Next']);
    expect(m.units.first.body.map((l) => (l.text, l.level)), [
      ("Thanks for coming. It's been a big quarter.", 0),
      ('Revenue', 0),
      ('Mexico', 1),
    ]);
  });

  group('PDF', () {
    test('text pages are read from their text layer; a scanned page through OCR', () async {
      final pdf = _FakePdf([
        'Quarterly review\nRevenue grew twelve percent in the third quarter.\n\nMargins held steady.',
        '', // scanned: no text layer
        'Next steps\nOpen the second warehouse.',
      ]);
      final ocr = _FakeOcr('Pipeline and risks\nThree deals slipped to Q4.');
      final reader = MaterialReader(pdf: pdf, ocr: ocr);
      final m = await reader.read(write('review.pdf', [0x25, 0x50, 0x44, 0x46]).path);
      expect(pdf.rendered, [1], reason: 'only the scanned page is rendered');
      expect(ocr.calls, [(40, 30)]);
      expect(m.ocrUnits, 1);
      expect(m.units, hasLength(3));
      expect(m.units[0].title, 'Quarterly review');
      expect(m.units[0].body.map((l) => l.text), [
        'Revenue grew twelve percent in the third quarter.',
        'Margins held steady.',
      ]);
      expect(m.units[1].ocrText, contains('Three deals slipped to Q4.'));
      expect(m.units[1].number, 2);
    });

    test('a scanned page OCR cannot read is left out; a PDF with nothing at all says so', () async {
      final reader = MaterialReader(pdf: _FakePdf(['', '']), ocr: _FakeOcr(null));
      await expectLater(
        reader.read(write('scan.pdf', [0x25]).path),
        throwsA(isA<MaterialException>().having((e) => e.problem, 'problem', MaterialProblem.empty)),
      );
    });
  });

  test('pictures are read with OCR', () async {
    final picture = img.Image(width: 24, height: 16);
    final ocr = _FakeOcr('Agenda\nResults\nQ&A');
    final m = await MaterialReader(ocr: ocr).read(write('slide.png', img.encodePng(picture)).path);
    expect(ocr.calls, [(24, 16)]);
    expect(m.kind, SourceKind.image);
    expect(m.units.single.ocrText, 'Agenda\nResults\nQ&A');
  });

  group('unsupported files explain what to do', () {
    for (final (name, expected) in [
      ('talk.key', 'Export it as PowerPoint (.pptx) or PDF'),
      ('old.ppt', 'Export it as PowerPoint (.pptx) or PDF'),
      ('song.mp3', 'Add a presentation (.pptx, .odp), a PDF'),
    ]) {
      test(name, () async {
        try {
          await MaterialReader().read(write(name, [1, 2, 3]).path);
          fail('read $name');
        } on MaterialException catch (e) {
          expect(MaterialReader.describe(e), contains(expected));
        }
      });
    }
  });
}

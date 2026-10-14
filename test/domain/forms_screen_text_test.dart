// The screen as text and numbered marks: what the model is shown (marks
// drawn on the screenshot), what it gets when it can't read images (the
// same marks as text — and never an image), drop-down options found
// without asking it, and fields only the screen can fill that never come
// on screen ending up in the manual-answers list.
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/domain/agent/coordinates.dart';
import 'package:sotto/domain/agent/safety.dart';
import 'package:sotto/domain/forms/form_filler.dart';
import 'package:sotto/domain/forms/form_model.dart';
import 'package:sotto/domain/forms/form_runner.dart';
import 'package:sotto/domain/forms/manual_answers.dart';
import 'package:sotto/domain/forms/screen_text.dart';
import 'package:sotto/features/questionnaire/questionnaire_controller.dart';
import 'package:sotto/l10n/l10n.dart';
import 'package:sotto/services/ai/deepseek_models.dart';
import 'package:sotto/services/ai/llm_client.dart';
import 'package:sotto/services/ai/questionnaire_service.dart';

const _mapper = CoordinateMapper(imageWidth: 1300, imageHeight: 731, screen: Rect.fromLTWH(0, 0, 1920, 1080), scale: 1);

/// The text OCR found on a survey page (screenshot pixels).
const _ocr = [
  OcrLine('Sotto form fixture', Rect.fromLTWH(51, 18, 79, 7)), // the tab: outside the page
  OcrLine('What is your full name?', Rect.fromLTWH(256, 324, 145, 14)),
  OcrLine('How often do you use the app?', Rect.fromLTWH(256, 420, 190, 14)),
  OcrLine('Daily', Rect.fromLTWH(280, 444, 30, 12)),
  OcrLine('Weekly', Rect.fromLTWH(280, 464, 40, 12)),
  OcrLine('Ana Ruiz', Rect.fromLTWH(262, 352, 50, 12)),
  OcrLine('Dominican Republic Mexico', Rect.fromLTWH(600, 500, 160, 12), [
    OcrWord('Dominican', Rect.fromLTWH(600, 500, 60, 12)),
    OcrWord('Republic', Rect.fromLTWH(664, 500, 50, 12)),
    OcrWord('Mexico', Rect.fromLTWH(720, 500, 40, 12)),
  ]),
];

/// The browser's page, without its toolbar (screenshot pixels).
const _page = Rect.fromLTWH(0, 80, 1300, 651);

Uint8List _jpeg() => img.encodeJpg(img.Image(width: 1300, height: 731), quality: 80);
String _dataUrl() => 'data:image/jpeg;base64,${base64Encode(_jpeg())}';

/// DeepSeek: replies with [reply] and keeps every request. With
/// [refusesImages], any request carrying an image fails with HTTP 400, the
/// way a model that can't read images answers.
class _Llm extends LlmClient {
  _Llm(this.reply, {this.refusesImages = false});
  final String Function(String user) reply;
  final bool refusesImages;
  final requests = <({String user, List<String> images})>[];

  @override
  Stream<String> stream({
    required String system,
    required String user,
    int maxTokens = 4096,
    DeepSeekTaskProfile profile = DeepSeekTaskProfile.answers,
    List<String> images = const [],
    bool json = false,
  }) async* {
    requests.add((user: user, images: images));
    if (refusesImages && images.isNotEmpty) throw LlmException('image_url is not supported', statusCode: 400);
    yield reply(user);
  }

  @override
  void close() {}
}

const _nameField = FormField(
  key: 'n',
  role: FieldRole.text,
  label: 'What is your full name?',
  bounds: Rect.fromLTWH(380, 510, 900, 60),
  elementId: 'n',
  patterns: {'value'},
);

ScreenFrame _frame() => ScreenFrame(_dataUrl(), _mapper, ocr: _ocr)..page = const Rect.fromLTWH(0, 118, 1920, 962);

/// A screen answer that names text mark [mark] ("Weekly").
String _weekly(String user) {
  final marks = RegExp(r'\[\{"mark".*\]').firstMatch(user)?.group(0);
  final weekly = (jsonDecode(marks!) as List).cast<Map<String, Object?>>().firstWhere((m) => m['text'] == 'Weekly');
  return jsonEncode({
    'questionnaire': true,
    'answers': [
      {'field_id': 'f1', 'question_text': 'What is your full name?', 'answer': 'Ana Ruiz'},
      {
        'field_id': 'screen',
        'question_text': 'How often do you use the app?',
        'question_type': 'multiple_choice',
        'kind': 'radio',
        'answer': 'Weekly',
        'mark': weekly['mark'],
      },
    ],
  });
}

void main() {
  setUpAll(() => L10n.current = lookupAppLocalizations(const Locale('en')));

  group('marks', () {
    test('fields keep their numbers; text on the page is numbered after them, the toolbar is left out', () {
      final marks = ScreenMarks.build(
        fields: {'f1': const Rect.fromLTWH(256, 345, 600, 30), 'f2': null},
        lines: _ocr,
        page: _page,
      );
      expect(marks.first.number, 1);
      expect(marks.first.isField, isTrue);
      final text = marks.where((m) => !m.isField).toList();
      expect(text.map((m) => m.text), isNot(contains('Sotto form fixture')));
      // Text inside the field ("Ana Ruiz" typed in it) is the field's.
      expect(text.map((m) => m.text), isNot(contains('Ana Ruiz')));
      expect(text.first.number, 2);
      expect(text.map((m) => m.text).first, 'What is your full name?');
      final asJson = jsonDecode(ScreenMarks.json(marks)) as List;
      expect(asJson, hasLength(text.length));
      expect((asJson.first as Map)['box'], [256, 324, 145, 14]);
    });

    test('drawn on the screenshot, still a JPEG of the same size', () {
      final marks = ScreenMarks.build(fields: const {}, lines: _ocr, page: _page);
      final drawn = img.decodeJpg(ScreenMarks.draw(_jpeg(), marks))!;
      expect((drawn.width, drawn.height), (1300, 731));
      // An orange mark frames "Weekly".
      final p = drawn.getPixel(280, 464);
      expect(p.r, greaterThan(150));
      expect(p.b, lessThan(100));
    });

    test('an option found in the text on screen, by its line or its words', () {
      expect(ScreenMarks.locate(_ocr, 'weekly'), const Rect.fromLTWH(280, 464, 40, 12).center);
      expect(ScreenMarks.locate(_ocr, 'Dominican Republic'), const Rect.fromLTWH(600, 500, 114, 12).center);
      expect(ScreenMarks.locate(_ocr, 'Chile'), isNull);
      expect(ScreenMarks.textAt(_ocr, const Offset(285, 357)), 'Ana Ruiz');
    });

    test('OCR text from the native side', () {
      final lines = OcrLine.parse(
        '{"lines":[{"text":"Weekly","box":[280,464,40,12],"words":[[280,464,40,12,"Weekly"]]}]}',
      );
      expect(lines.single.text, 'Weekly');
      expect(lines.single.words.single.box, const Rect.fromLTWH(280, 464, 40, 12));
      expect(OcrLine.parse('not json'), isEmpty);
      expect(OcrLine.parse(null), isEmpty);
    });
  });

  group('which model reads images', () {
    test('from GET /models; unknown counts as yes', () {
      const models = [DeepSeekModel('deepseek-flash', images: true), DeepSeekModel('deepseek-v4-pro')];
      expect(visionReadsImages(models, 'deepseek-flash'), isTrue);
      expect(visionReadsImages(models, 'deepseek-v4-pro'), isFalse);
      expect(visionReadsImages(const [], 'anything'), isTrue);
    });
  });

  group('the model, with and without images', () {
    DeepSeekFormVision vision(_Llm llm, {bool images = true}) => DeepSeekFormVision(
      QuestionnaireService(llm),
      settings: const AppSettings(),
      appLanguageName: 'English',
      images: images,
    );

    test('images: the marks are drawn on the screenshot and the answer names one', () async {
      final llm = _Llm(_weekly);
      final v = vision(llm);
      final reply = await v.answer(_frame(), {'f1': _nameField});

      final sent = llm.requests.single;
      expect(sent.images, hasLength(1));
      expect(sent.images.single, isNot(_frame().image), reason: 'the marks are drawn on it');
      expect(sent.user, contains('Marks drawn on the screenshot'));
      expect(sent.user, isNot(contains('Sotto form fixture')), reason: 'only the page is marked');
      final weekly = reply.answers.firstWhere((a) => a.fieldId == 'screen');
      expect(weekly.point, const Rect.fromLTWH(280, 464, 40, 12).center);
      expect(v.requests, 1);
    });

    test('a model that refuses the image gets the same marks as text — and no image again', () async {
      final llm = _Llm(_weekly, refusesImages: true);
      final v = vision(llm);
      final reply = await v.answer(_frame(), {'f1': _nameField});

      expect(llm.requests.map((r) => r.images.length), [1, 0]);
      expect(llm.requests.last.user, contains('There is no screenshot'));
      expect(reply.answers.firstWhere((a) => a.fieldId == 'screen').point, isNotNull);
      expect(v.images, isFalse);

      // From now on, nothing with an image: option lookups and value checks
      // come from the text on screen.
      expect(await v.locateOption(_frame(), 'Weekly'), const Rect.fromLTWH(280, 464, 40, 12).center);
      expect(await v.readValues(_frame(), [const VisualCheck(0, 'Name', 'text', Offset(285, 357))]), {0: 'Ana Ruiz'});
      await v.answer(_frame(), {'f1': _nameField});
      expect(llm.requests.skip(1).every((r) => r.images.isEmpty), isTrue);
    });

    test('images off from the start: never an image, whatever is asked', () async {
      final llm = _Llm(_weekly);
      final v = vision(llm, images: false);
      await v.answer(_frame(), {'f1': _nameField});
      expect(await v.locateOption(_frame(), 'Chile'), isNull, reason: 'not on screen, and no image to ask about');
      await v.readValues(_frame(), [const VisualCheck(0, 'Often', 'radio', Offset(285, 470))]);
      expect(llm.requests, hasLength(1));
      expect(llm.requests.every((r) => r.images.isEmpty), isTrue);
    });

    test('an option on screen is found without asking the model, even with images', () async {
      final llm = _Llm((_) => '{"point":[1,1]}');
      final v = vision(llm);
      expect(await v.locateOption(_frame(), 'Weekly'), isNotNull);
      expect(llm.requests, isEmpty);
    });
  });

  group('a field only the screen can fill', () {
    // A text box with no accessible action (no "value"): only clicking and
    // typing fill it.
    FormSnapshot page({required bool below}) => FormSnapshot(
      fields: FormSnapshot.signed([
        const FormField(
          key: 'n',
          role: FieldRole.text,
          label: 'What is your full name?',
          bounds: Rect.fromLTWH(380, 300, 900, 50),
          elementId: 'n',
          patterns: {'value'},
        ),
        FormField(
          key: 'lang',
          role: FieldRole.text,
          label: 'Which language do you present in most?',
          bounds: below ? const Rect.fromLTWH(380, 2400, 900, 50) : const Rect.fromLTWH(380, 600, 900, 50),
          elementId: 'lang',
          offscreen: below,
        ),
      ]),
    );

    test('never on screen: answered anyway, left in the manual-answers list', () async {
      final driver = _Driver([page(below: true)]);
      final vision = _Vision();
      final result = await FormRunner(driver: driver, vision: vision, host: _Host(), texts: _Texts(), auto: true).run();

      expect(vision.calls, 1, reason: 'asked once, from its label');
      expect(driver.clicks, isEmpty, reason: 'nothing clicked off screen');
      final lang = result.fields.singleWhere((f) => f.question.startsWith('Which language'));
      expect((lang.status, lang.answer, lang.note), (ItemStatus.skipped, 'Spanish', 'offscreen'));

      final items = QuestionnaireController.finishedItems(result.fields);
      final manual = QuestionnaireState(phase: FormPhase.finished, items: items).manualAnswers;
      final row = manual.singleWhere((a) => a.question.startsWith('Which language'));
      expect(row.manual, isTrue);
      expect(row.copyText, 'Spanish');
      expect(ManualAnswers.needed(manual), 1);
    });

    test('scrolled into view: filled with the answer it already had — no second question', () async {
      final driver = _Driver([page(below: true), page(below: false)]);
      final vision = _Vision();
      final result = await FormRunner(driver: driver, vision: vision, host: _Host(), texts: _Texts(), auto: true).run();

      expect(vision.calls, 1);
      expect(driver.scrolls, 1);
      expect(driver.typed, contains('Spanish'));
      final lang = result.fields.singleWhere((f) => f.question.startsWith('Which language'));
      expect(lang.status, ItemStatus.filled);
    });
  });
}

/// Pages in order: each scroll shows the next.
class _Driver implements FormDriver {
  _Driver(this.pages);
  final List<FormSnapshot> pages;
  var scrolls = 0;
  final clicks = <Offset>[];
  final typed = <String>[];
  final values = <String, String>{};

  static const screen = Rect.fromLTWH(0, 0, 1920, 1080);

  @override
  Future<ScreenFrame> capture() async => ScreenFrame(
    'data:image/jpeg;base64,',
    const CoordinateMapper(imageWidth: 1920, imageHeight: 1080, screen: screen, scale: 1),
  );

  @override
  Future<FormSnapshot> read() async {
    final p = pages[scrolls.clamp(0, pages.length - 1)];
    return FormSnapshot(
      fields: [
        for (final f in p.fields)
          FormField(
            key: f.key,
            role: f.role,
            label: f.label,
            bounds: f.bounds,
            elementId: f.elementId,
            patterns: f.patterns,
            offscreen: f.offscreen,
            value: values[f.key] ?? '',
            signature: f.signature,
          ),
      ],
    );
  }

  @override
  Future<bool> setValue(String id, String text) async {
    values[id] = text;
    return true;
  }

  @override
  Future<ElementState?> state(String id) async => values.containsKey(id) ? ElementState(value: values[id]) : null;

  String? _focus;

  @override
  Future<void> click(Offset p) async {
    expect(screen.contains(p), isTrue);
    clicks.add(p);
    for (final f in pages[scrolls.clamp(0, pages.length - 1)].fields) {
      if (f.bounds.contains(p)) _focus = f.key;
    }
  }

  @override
  Future<void> typeKeys(String text, Duration interval) async {
    typed.add(text);
    if (_focus != null) values[_focus!] = text;
  }

  @override
  Future<bool?> canScrollDown({String? anchor}) async => scrolls < pages.length - 1;

  @override
  Future<void> scrollDown({String? anchor, required Offset fallback}) async => scrolls++;

  @override
  Future<bool> select(String id) async => false;
  @override
  Future<bool> toggle(String id, bool on) async => false;
  @override
  Future<bool> choose(String id, String label) async => false;
  @override
  Future<bool> invoke(String id) async => false;
  @override
  Future<bool> setRange(String id, double value) async => false;
  @override
  Future<bool> focusElement(String id) async => false;
  @override
  bool get canInput => true;
  @override
  Future<void> selectAll() async {}
  @override
  Future<void> pressKey(String key) async {}
  @override
  Future<void> scroll(Offset p, int notches) async {}
  @override
  Future<void> drag(Offset from, Offset to) async {}
  @override
  Future<FocusInfo?> focused() async => null;
  @override
  Future<void> pause(Duration d) async {}
}

class _Vision implements FormVision {
  var calls = 0;

  @override
  Future<FormReply> answer(ScreenFrame frame, Map<String, FormField> ids) async {
    calls++;
    return FormReply([
      for (final MapEntry(key: id, value: f) in ids.entries)
        FieldAnswer(fieldId: id, question: f.label, answer: f.label.contains('language') ? 'Spanish' : 'Ana Ruiz'),
    ]);
  }

  @override
  Future<Offset?> locateOption(ScreenFrame frame, String label) async => null;

  @override
  Future<Map<int, String>> readValues(ScreenFrame frame, List<VisualCheck> checks) async => const {};
}

class _Host implements FormRunHost {
  @override
  bool get cancelled => false;
  @override
  void phase(FormPhase phase, {int? page, String? label}) {}
  @override
  void planned(FillPlan plan) {}
  @override
  void progress(int step, ItemStatus status, {String? note}) {}
  @override
  Future<bool> confirm(FormPhase phase, {String? label}) async => false;
  @override
  FillPlan edited(FillPlan plan, Map<String, FormField> ids, Offset? Function(Offset) toScreen) => plan;
}

class _Texts implements FormRunTexts {
  @override
  String couldNotFill() => 'could not fill';
  @override
  String blocked(SafetyReason reason) => 'blocked';
  @override
  String skipped(SkipReason reason) => reason.name;
}

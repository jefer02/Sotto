import 'dart:convert';
import 'dart:isolate';
import 'dart:ui' show Offset, Rect;

import '../../data/models/settings.dart';
import '../../domain/agent/coordinates.dart';
import '../../domain/forms/form_filler.dart';
import '../../domain/forms/form_model.dart';
import '../../domain/forms/form_runner.dart';
import '../../domain/forms/screen_text.dart';
import 'llm_client.dart';

/// Answers the questionnaire on screen with the model's own knowledge — not
/// the script or prep documents. It gets the screenshot and the fields the
/// accessibility tree found (bounds in screenshot pixels) and replies with
/// JSON only ([DeepSeekTaskProfile.questionnaire]: low-effort thinking).
///
/// When the tree shows nothing — browser content on macOS often doesn't —
/// the screenshot is all there is: the model then reports each question with
/// its kind and its box, and the Next / Submit buttons it sees.
class QuestionnaireService {
  QuestionnaireService(this.client);

  final LlmClient client;

  static const system = '''
You fill in an ordinary form on the user's screen — a registration, survey, job application, contact form or similar — for the user, from the user's instructions (their details and preferences) and common sense. You get a screenshot and the list of form fields the accessibility tree (or the page's DOM) found, with their boxes in screenshot pixels. The list may be empty: many pages don't expose their controls, and then the screenshot is all there is.

Return only JSON, exactly this shape:
{"questionnaire":true,"answers":[{"field_id":"f1","question_text":"the question as shown","question_type":"multiple_choice","answer":"…","answer_letter":"B","confidence":0.9,"reasoning_summary":"one short line on why"}],"next":{"label":"Next","box":[x,y,w,h]},"submit":{"label":"Submit","box":[x,y,w,h]}}

question_type is one of: text, long_text, multiple_choice, true_false, checkboxes, dropdown, scale, matching, ordering, image_choice, read_only.

Rules:
- One entry per question you can answer; leave out the ones you should not or cannot answer.
- reasoning_summary: at most 15 words, in the answer language — the user reads it to see why.
- multiple_choice / dropdown / radio fields: "answer" is the chosen option's full text, copied verbatim; "answer_letter" is its letter (A, B, C…) when the options are lettered or in a list — give both.
- true_false: "answer" is "True" or "False" (or the option's text as shown, e.g. "Verdadero"); answer_letter A for the first option, B for the second.
- checkboxes (select all that apply): "answer" is a list of the option labels to check (it may be empty).
- a single checkbox field: "answer" is "yes" or "no".
- text / long_text: "answer" is the text to type.
- A field with a "range" (a slider or number box): "answer" is the number, within min–max.
- Fields marked "offscreen" are further down the page, not on the screenshot: answer them from their label, help and options.
- Numbered marks: when the screenshot has numbered boxes drawn on it — or, with no screenshot, the screen's text comes as numbered marks — a "screen" answer gives "mark": N instead of "box" whenever a mark is the thing to click: an option's text (radio, checkbox, scale, image choice), an option in an open list. A text box or drop-down with no mark of its own still gets its "box"; with no screenshot, it usually sits just below or right of its question's mark.
- Every question on the screenshot that is NOT in the field list: add {"field_id":"screen", "question_text":…, "question_type":…, "kind":…, "answer":…, "answer_letter":…, "confidence":…, "reasoning_summary":…, "box":[x,y,w,h]} in screenshot pixels, where kind and box are:
  - "text" (one-line input) or "textarea" (multi-line): box = the input itself; answer = the text to type.
  - "dropdown": box = the closed drop-down; answer = the option label exactly as it will appear in the list.
  - "radio": for multiple_choice, true_false, scale (1–5, 1–10, stars, Likert) and image_choice — box = exactly the one option to click (its circle / letter / star / image and label); answer = that option's text.
  - "checkbox": one entry per box to tick that is not ticked yet; box = that checkbox and its label; answer = its label.
  - matching (drag A onto B): kind "drag", "answer" lists the pairs in words, and "drags":[{"from":[x,y,w,h],"to":[x,y,w,h]},…] — one per item to drag, from the item to its match.
  - ordering / ranking: kind "drag", "answer" lists the right order, and "drags" moves the items into it, one drag per move, top position first; each "to" is the slot the item goes to, as the list looks after the previous moves.
  - read_only: the question is only text (a PDF, a read-only page) with nothing to fill — kind "read_only", no box; "answer" is the answer to show the user.
- Skip questions already answered on the screenshot.
- "next" / "submit": the button that goes to the next page, and the one that sends the form, if you see them (omit otherwise). Never click them yourself.
- No form on screen at all: {"questionnaire":false,"answers":[]}.
- A graded test, quiz or exam (questions with right and wrong answers that assess the user's knowledge) is not a form to fill: return {"questionnaire":false,"answers":[]} and answer nothing.
- Multiple-choice questions in a form ("Which best describes you: A) Student B) Employee C) Freelancer D) Other") are answered from the user's instructions; leave them out when the instructions don't say.
- Never answer passwords, security codes, payment or billing details, or ID numbers. Personal details (name, email, phone, address…) only when the user's instructions give them; otherwise leave the field out.
- confidence is 0–1: how sure you are the answer is right.
- JSON only: no prose, no markdown.''';

  /// The field list as the model sees it: its type, label, help, options
  /// (with their letters and boxes), range and what it holds now. A field
  /// that isn't on the screenshot (scrolled away, another display) has no
  /// box: it is marked "offscreen".
  static String fieldsJson(Map<String, FormField> ids, CoordinateMapper mapper) {
    List<int>? box(Rect r) {
      final b = mapper.toImage(r);
      if (b.isEmpty || b.width < 1 || b.height < 1) return null;
      return [b.left.round(), b.top.round(), b.width.round(), b.height.round()];
    }

    return jsonEncode([
      for (final MapEntry(key: id, value: f) in ids.entries)
        {
          'field_id': id,
          'type': f.role.name,
          'question_type': QuestionTypes.classify(f).wire,
          'label': f.label,
          if (f.help.isNotEmpty) 'help': f.help,
          if (f.options.isNotEmpty && f.role != FieldRole.checkbox)
            'options': [
              for (var i = 0; i < f.options.length; i++)
                {
                  if (i < 26) 'letter': String.fromCharCode(65 + i),
                  'label': f.options[i].label,
                  if (!f.offscreen && !f.options[i].bounds.isEmpty) 'box': ?box(f.options[i].bounds),
                },
            ],
          if (f.range case final r?)
            'range': {
              'min': RangeSpec.format(r.min),
              'max': RangeSpec.format(r.max),
              if (r.step > 0) 'step': RangeSpec.format(r.step),
            },
          if (f.value.isNotEmpty) 'current': f.value,
          if (f.offscreen || box(f.bounds) == null) 'offscreen': true else 'box': box(f.bounds),
        },
    ]);
  }

  /// [marks]: the numbered marks — drawn on the screenshot, or with
  /// [image] false (no screenshot is sent) the screen's text as a list.
  static String user({
    required Map<String, FormField> ids,
    required CoordinateMapper mapper,
    required AppSettings settings,
    required String appLanguageName,
    List<ScreenMark> marks = const [],
    bool image = true,
  }) {
    final language = settings.formsLanguage == FormAnswerLanguage.sameAsForm
        ? 'the language of the questionnaire'
        : appLanguageName;
    final style = settings.formsStyle == FormAnswerStyle.short
        ? 'Keep open answers short: a few words or one sentence.'
        : 'Give open answers in full: two to four sentences.';
    final extra = settings.formsInstructions.trim();
    return '''
Answer in $language. $style
${extra.isEmpty ? 'The user gave no instructions.' : 'The user\'s instructions:\n"""\n$extra\n"""'}

${image ? 'Screenshot' : 'Screen (no screenshot; positions in the same pixels)'}: ${mapper.imageWidth}×${mapper.imageHeight} px.
Fields:
${ids.isEmpty ? '[] (none exposed: read every question off the ${image ? 'screenshot' : 'screen text'})' : fieldsJson(ids, mapper)}${_marks(marks, image)}''';
  }

  static String _marks(List<ScreenMark> marks, bool image) {
    final text = marks.where((m) => !m.isField).toList();
    if (text.isEmpty) return '';
    final head = image
        ? 'Marks drawn on the screenshot: blue boxes are the fields above (mark N is field fN), orange boxes are lines of text on screen:'
        : 'There is no screenshot. The text on the screen, read on this computer, as numbered marks (boxes in screen pixels):';
    return '\n$head\n${ScreenMarks.json(text)}';
  }

  /// [screenshot] null: a text-only request — no image is sent.
  Future<String> _ask(String system, String user, String? screenshot, {int maxTokens = 6000}) => client.complete(
    system: system,
    user: user,
    maxTokens: maxTokens,
    profile: DeepSeekTaskProfile.questionnaire,
    images: [?screenshot],
    json: true,
  );

  /// [screenshot] null: the screen goes as text ([marks]) and no image is
  /// sent at all.
  Future<FormReply> answer({
    required String? screenshot,
    required Map<String, FormField> ids,
    required CoordinateMapper mapper,
    required AppSettings settings,
    required String appLanguageName,
    List<ScreenMark> marks = const [],
  }) async {
    final u = user(
      ids: ids,
      mapper: mapper,
      settings: settings,
      appLanguageName: appLanguageName,
      marks: marks,
      image: screenshot != null,
    );
    for (var attempt = 0; ; attempt++) {
      try {
        return FormReply.parse(await _ask(system, u, screenshot));
      } on FormatException {
        if (attempt >= 1) rethrow;
      }
    }
  }

  static const locateSystem = '''
A drop-down list is open on the screenshot. Find the option the user wants and return only JSON: {"point":[x,y]} — the centre of that option in screenshot pixels — or {"point":null} if it isn't visible.''';

  /// Where option [label] of the open drop-down is, in screenshot pixels.
  Future<Offset?> locateOption({
    required String screenshot,
    required CoordinateMapper mapper,
    required String label,
  }) async {
    final raw = await _ask(
      locateSystem,
      'Screenshot: ${mapper.imageWidth}×${mapper.imageHeight} px.\nOption: "$label"',
      screenshot,
      maxTokens: 1500,
    );
    final j = jsonDecode(raw.substring(raw.indexOf('{'), raw.lastIndexOf('}') + 1));
    final p = j is Map ? j['point'] : null;
    if (p is! List || p.length != 2 || p.any((v) => v is! num)) return null;
    return Offset((p[0] as num).toDouble(), (p[1] as num).toDouble());
  }

  static const readSystem = '''
Read form controls on the screenshot. For each check, look at the control at its point and return only JSON: {"values":[{"id":0,"shown":"…"}]} — for text, textarea and dropdown the exact text it shows now ("" if empty); for radio and checkbox "checked" or "unchecked".''';

  /// What each control shows now, by check id.
  Future<Map<int, String>> readValues({
    required String screenshot,
    required CoordinateMapper mapper,
    required List<VisualCheck> checks,
  }) async {
    final list = jsonEncode([
      for (final c in checks)
        {
          'id': c.id,
          'question': c.question,
          'kind': c.kind,
          'point': [c.point.dx.round(), c.point.dy.round()],
        },
    ]);
    final raw = await _ask(
      readSystem,
      'Screenshot: ${mapper.imageWidth}×${mapper.imageHeight} px.\nChecks:\n$list',
      screenshot,
      maxTokens: 3000,
    );
    final j = jsonDecode(raw.substring(raw.indexOf('{'), raw.lastIndexOf('}') + 1));
    final values = j is Map ? j['values'] : null;
    return {
      if (values is List)
        for (final v in values.whereType<Map<Object?, Object?>>())
          if (v['id'] is num) (v['id']! as num).toInt(): '${v['shown'] ?? ''}',
    };
  }
}

/// [FormVision] over [QuestionnaireService], with numbered marks: the
/// fields and the text read on screen (OCR, on this computer) drawn on the
/// screenshot, so the model names a mark instead of guessing coordinates.
///
/// [images] false — the model in use can't read images, or it refused
/// one — sends no image at all: the same marks go as text. Drop-down
/// options are looked up in the OCR text first, without asking the model.
class DeepSeekFormVision implements FormVision {
  DeepSeekFormVision(this.service, {required this.settings, required this.appLanguageName, this.images = true});

  final QuestionnaireService service;
  final AppSettings settings;
  final String appLanguageName;

  /// Whether screenshots go to the model. Turns false for good on the first
  /// image the model refuses.
  bool images;

  /// Requests made to the model: answers, option lookups, value checks.
  int requests = 0;

  /// The model refused the request as sent (an image it can't read): retry
  /// as text. Network trouble and bad keys are not that.
  static bool refusedImage(Object e) => e is LlmException && const {400, 415, 422}.contains(e.statusCode);

  static Rect? _box(CoordinateMapper mapper, FormField f) {
    if (f.offscreen) return null;
    final b = mapper.toImage(f.bounds);
    return b.isEmpty ? null : b;
  }

  /// [frame]'s screenshot with [marks] drawn on it (off the UI isolate).
  static Future<String> marked(String dataUrl, List<ScreenMark> marks) async {
    final comma = dataUrl.indexOf(',');
    final jpeg = base64Decode(dataUrl.substring(comma + 1));
    final drawn = await Isolate.run(() => ScreenMarks.draw(jpeg, marks));
    return 'data:image/jpeg;base64,${base64Encode(drawn)}';
  }

  /// Answers that name a mark get its centre as their point.
  static FormReply _resolve(FormReply reply, List<ScreenMark> marks) {
    final byNumber = {for (final m in marks) m.number: m};
    return FormReply(
      [
        for (final a in reply.answers)
          if (a.mark != null && byNumber[a.mark] != null && a.point == null)
            a.copyWith(point: byNumber[a.mark]!.box.center)
          else
            a,
      ],
      next: reply.next,
      submit: reply.submit,
      questionnaire: reply.questionnaire,
    );
  }

  @override
  Future<FormReply> answer(ScreenFrame frame, Map<String, FormField> ids) async {
    final page = frame.page == null ? null : frame.mapper.toImage(frame.page!);
    final marks = ScreenMarks.build(
      fields: {for (final MapEntry(:key, :value) in ids.entries) key: _box(frame.mapper, value)},
      lines: frame.ocr,
      page: page == null || page.isEmpty ? null : page,
    );
    Future<FormReply> ask(String? screenshot) async {
      requests++;
      return _resolve(
        await service.answer(
          screenshot: screenshot,
          ids: ids,
          mapper: frame.mapper,
          settings: settings,
          appLanguageName: appLanguageName,
          marks: marks,
        ),
        marks,
      );
    }

    if (images) {
      try {
        return await ask(marks.isEmpty ? frame.image : await marked(frame.image, marks));
      } on LlmException catch (e) {
        if (!refusedImage(e)) rethrow;
        images = false;
      }
    }
    return ask(null);
  }

  @override
  Future<Offset?> locateOption(ScreenFrame frame, String label) async {
    final seen = ScreenMarks.locate(frame.ocr, label);
    if (seen != null || !images) return seen;
    try {
      requests++;
      return await service.locateOption(screenshot: frame.image, mapper: frame.mapper, label: label);
    } on LlmException catch (e) {
      if (!refusedImage(e)) rethrow;
      images = false;
      return null;
    }
  }

  @override
  Future<Map<int, String>> readValues(ScreenFrame frame, List<VisualCheck> checks) async {
    if (images) {
      try {
        requests++;
        return await service.readValues(screenshot: frame.image, mapper: frame.mapper, checks: checks);
      } on LlmException catch (e) {
        if (!refusedImage(e)) rethrow;
        images = false;
      }
    }
    // Without images: what OCR reads at each control. A radio's or a
    // checkbox's state can't be read as text — those stay unknown.
    return {
      for (final c in checks)
        if (const {'text', 'textarea', 'dropdown', 'select', 'short_text', 'long_text'}.contains(c.kind))
          c.id: ?ScreenMarks.textAt(frame.ocr, c.point),
    };
  }
}

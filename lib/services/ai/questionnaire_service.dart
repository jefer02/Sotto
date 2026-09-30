import 'dart:convert';
import 'dart:ui' show Offset;

import '../../data/models/settings.dart';
import '../../domain/agent/coordinates.dart';
import '../../domain/forms/form_filler.dart';
import '../../domain/forms/form_model.dart';
import '../../domain/forms/form_runner.dart';
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
You fill in a questionnaire or form that is on the user's screen, answering from your own general knowledge and the user's instructions. You get a screenshot and the list of form fields the accessibility tree found (with their boxes in screenshot pixels). The list may be empty: many browsers don't expose their pages, and then the screenshot is all there is.

Return only JSON, exactly this shape:
{"answers":[{"field_id":"f1","question":"the question as shown","answer":"…","confidence":0.9}],"next":{"label":"Next","box":[x,y,w,h]},"submit":{"label":"Submit","box":[x,y,w,h]}}

Rules:
- One entry per field you can answer; leave out fields you should not or cannot answer.
- radio and combo: "answer" is exactly one of that field's options, copied verbatim.
- checkboxes: "answer" is a list of the option labels to check (it may be empty).
- checkbox (a single one): "answer" is "yes" or "no".
- text: "answer" is the text to type.
- Every question on the screenshot that is NOT in the field list: add {"field_id":"screen","question":"…","kind":…,"answer":"…","box":[x,y,w,h]} in screenshot pixels, where kind is:
  - "text" (one-line input) or "textarea" (multi-line): box = the input itself; answer = the text to type.
  - "dropdown": box = the closed drop-down; answer = the option label exactly as it will appear in the list.
  - "radio": box = the one option to choose (its circle and label); answer = that option's label.
  - "checkbox": one entry per box to tick that is not ticked yet; box = that checkbox and its label; answer = its label.
- Skip questions already answered on the screenshot.
- "next" / "submit": the button that goes to the next page, and the one that sends the form, if you see them (omit otherwise). Never click them yourself.
- Never answer passwords, security codes, payment or bank details, or ID numbers. Personal details (name, email, phone, address…) only when the user's instructions give them; otherwise leave the field out.
- confidence is 0–1: how sure you are the answer is right.
- JSON only: no prose, no markdown.''';

  /// The field list as the model sees it.
  static String fieldsJson(Map<String, FormField> ids, CoordinateMapper mapper) => jsonEncode([
    for (final MapEntry(key: id, value: f) in ids.entries)
      {
        'field_id': id,
        'type': f.role.name,
        'label': f.label,
        if (f.options.isNotEmpty && f.role != FieldRole.checkbox) 'options': [for (final o in f.options) o.label],
        if (f.value.isNotEmpty) 'current': f.value,
        'box': () {
          final r = mapper.toImage(f.bounds);
          return [r.left.round(), r.top.round(), r.width.round(), r.height.round()];
        }(),
      },
  ]);

  static String user({
    required Map<String, FormField> ids,
    required CoordinateMapper mapper,
    required AppSettings settings,
    required String appLanguageName,
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

Screenshot: ${mapper.imageWidth}×${mapper.imageHeight} px.
Fields:
${ids.isEmpty ? '[] (none exposed: read every question off the screenshot)' : fieldsJson(ids, mapper)}''';
  }

  Future<String> _ask(String system, String user, String screenshot, {int maxTokens = 6000}) => client.complete(
    system: system,
    user: user,
    maxTokens: maxTokens,
    profile: DeepSeekTaskProfile.questionnaire,
    images: [screenshot],
    json: true,
  );

  Future<FormReply> answer({
    required String screenshot,
    required Map<String, FormField> ids,
    required CoordinateMapper mapper,
    required AppSettings settings,
    required String appLanguageName,
  }) async {
    final u = user(ids: ids, mapper: mapper, settings: settings, appLanguageName: appLanguageName);
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

/// [FormVision] over [QuestionnaireService].
class DeepSeekFormVision implements FormVision {
  DeepSeekFormVision(this.service, {required this.settings, required this.appLanguageName});

  final QuestionnaireService service;
  final AppSettings settings;
  final String appLanguageName;

  @override
  Future<FormReply> answer(ScreenFrame frame, Map<String, FormField> ids) => service.answer(
    screenshot: frame.image,
    ids: ids,
    mapper: frame.mapper,
    settings: settings,
    appLanguageName: appLanguageName,
  );

  @override
  Future<Offset?> locateOption(ScreenFrame frame, String label) =>
      service.locateOption(screenshot: frame.image, mapper: frame.mapper, label: label);

  @override
  Future<Map<int, String>> readValues(ScreenFrame frame, List<VisualCheck> checks) =>
      service.readValues(screenshot: frame.image, mapper: frame.mapper, checks: checks);
}

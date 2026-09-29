import 'dart:convert';

import '../../data/models/settings.dart';
import '../../domain/agent/coordinates.dart';
import '../../domain/forms/form_filler.dart';
import '../../domain/forms/form_model.dart';
import 'llm_client.dart';

/// Answers the questionnaire on screen with the model's own knowledge — not
/// the script or prep documents. It gets the screenshot and the fields the
/// accessibility tree found (bounds in screenshot pixels) and replies with
/// JSON only ([DeepSeekTaskProfile.questionnaire]: low-effort thinking).
class QuestionnaireService {
  QuestionnaireService(this.client);

  final LlmClient client;

  static const system = '''
You fill in a questionnaire or form that is on the user's screen, answering from your own general knowledge and the user's instructions. You get a screenshot and the list of form fields found on it (with their boxes in screenshot pixels).

Return only JSON, exactly this shape:
{"answers":[{"field_id":"f1","question":"the question as shown","answer":"…","confidence":0.9}]}

Rules:
- One entry per field you can answer; leave out fields you should not or cannot answer.
- radio and combo: "answer" is exactly one of that field's options, copied verbatim.
- checkboxes: "answer" is a list of the option labels to check (it may be empty).
- checkbox (a single one): "answer" is "yes" or "no".
- text: "answer" is the text to type.
- Never answer passwords, security codes, payment or bank details, or ID numbers. Personal details (name, email, phone, address…) only when the user's instructions give them; otherwise leave the field out.
- If a question on the screenshot has no field in the list, add {"field_id":"screen","question":"…","answer":"…","point":[x,y],"kind":"text" or "choice"} where point is where to click in screenshot pixels (for "choice", the option to click).
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
${fieldsJson(ids, mapper)}''';
  }

  Future<List<FieldAnswer>> answer({
    required String screenshot,
    required Map<String, FormField> ids,
    required CoordinateMapper mapper,
    required AppSettings settings,
    required String appLanguageName,
  }) async {
    final u = user(ids: ids, mapper: mapper, settings: settings, appLanguageName: appLanguageName);
    for (var attempt = 0; ; attempt++) {
      final raw = await client.complete(
        system: system,
        user: u,
        maxTokens: 6000,
        profile: DeepSeekTaskProfile.questionnaire,
        images: [screenshot],
        json: true,
      );
      try {
        return FieldAnswer.parseAll(raw);
      } on FormatException {
        if (attempt >= 1) rethrow;
      }
    }
  }
}

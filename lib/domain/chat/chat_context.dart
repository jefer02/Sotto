import '../../data/models/chat.dart';

/// Builds what one chat request sends: the system prompt, then the last
/// [maxMessages] messages, trimmed to [maxChars] so a long conversation
/// never grows past the context window. The newest user message always
/// goes; failed or empty replies never do.
abstract final class ChatContext {
  static const system = '''
You are Sotto's assistant, helping a presenter before and during their talks. Be direct and concise; use short paragraphs and Markdown (bold, lists, code blocks) when it helps. Answer in the language the user writes in.''';

  /// The messages that fit, oldest first.
  static List<ChatMessage> window(List<ChatMessage> messages, {int maxMessages = 20, int maxChars = 24000}) {
    final usable = [
      for (final m in messages)
        if (m.error == null && m.text.trim().isNotEmpty) m,
    ];
    var picked = usable.length > maxMessages ? usable.sublist(usable.length - maxMessages) : usable;
    // Oldest go first until it fits; the newest message always stays.
    var total = picked.fold<int>(0, (a, m) => a + m.text.length);
    var drop = 0;
    while (total > maxChars && drop < picked.length - 1) {
      total -= picked[drop].text.length;
      drop++;
    }
    picked = picked.sublist(drop);
    // A conversation sent to the API starts with the user.
    while (picked.length > 1 && picked.first.role == ChatRole.assistant) {
      picked = picked.sublist(1);
    }
    return picked;
  }

  /// One very long message keeps its start and end.
  static String clip(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    final half = maxChars ~/ 2;
    return '${text.substring(0, half)}\n…\n${text.substring(text.length - half)}';
  }

  /// The request body's `messages`. [screenshot] (a JPEG data URL) goes
  /// with the newest user message only. With [thinking], each assistant
  /// message carries its `reasoning_content` back, as DeepSeek asks.
  static List<Map<String, Object?>> build(
    Conversation c, {
    int maxMessages = 20,
    int maxChars = 24000,
    String? screenshot,
    String? scriptContext,
    bool thinking = false,
  }) {
    final picked = window(c.messages, maxMessages: maxMessages, maxChars: maxChars);
    final lastUser = picked.lastIndexWhere((m) => m.role == ChatRole.user);
    return [
      {
        'role': 'system',
        'content': scriptContext == null || scriptContext.trim().isEmpty
            ? system
            : '$system\n\nThe presenter\'s script, for context:\n"""\n${clip(scriptContext, 12000)}\n"""',
      },
      for (var i = 0; i < picked.length; i++)
        if (picked[i].role == ChatRole.user)
          {
            'role': 'user',
            'content': i == lastUser && screenshot != null
                ? [
                    {'type': 'text', 'text': clip(picked[i].text, maxChars)},
                    {
                      'type': 'image_url',
                      'image_url': {'url': screenshot},
                    },
                  ]
                : clip(picked[i].text, maxChars),
          }
        else
          {
            'role': 'assistant',
            'content': clip(picked[i].text, maxChars),
            if (thinking && picked[i].reasoning.isNotEmpty) 'reasoning_content': picked[i].reasoning,
          },
    ];
  }
}

/// Puts dictated [transcript] into [text] at [caret] (or at the end), with
/// a space on either side only where one is needed. Returns the new text
/// and where the caret goes.
(String, int) insertDictation(String text, String transcript, {int? caret}) {
  final t = transcript.trim();
  if (t.isEmpty) return (text, caret ?? text.length);
  final at = (caret == null || caret < 0 || caret > text.length) ? text.length : caret;
  final before = text.substring(0, at);
  final after = text.substring(at);
  final lead = before.isEmpty || RegExp(r'\s$').hasMatch(before) ? '' : ' ';
  final trail = after.isEmpty || RegExp(r'^[\s.,;:!?)]').hasMatch(after) ? '' : ' ';
  final inserted = '$lead$t$trail';
  return ('$before$inserted$after', at + lead.length + t.length);
}

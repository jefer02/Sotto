/// DeepSeek's thinking effort (`thinking.reasoning_effort`).
enum ReasoningEffort { low, high, max }

/// How much DeepSeek thinks for each kind of request — the one place that
/// decides it.
///
/// DeepSeek V4 thinks at high effort unless told otherwise, which adds long
/// delays and billed reasoning tokens. Organizing a script, live answers
/// and chat don't need it; reading a questionnaire or driving the mouse
/// benefits from a little. Request shape (api-docs.deepseek.com,
/// create-chat-completion):
///
///     "thinking": {"type": "disabled"}
///     "thinking": {"type": "enabled", "reasoning_effort": "low"}
///
/// With thinking on, a multi-turn conversation must send each assistant
/// message's `reasoning_content` back (with `tools` DeepSeek returns 400
/// otherwise) — the agent and chat do.
class DeepSeekTaskProfile {
  const DeepSeekTaskProfile._(this.name, [this.effort]);

  final String name;

  /// Null: thinking disabled.
  final ReasoningEffort? effort;

  bool get thinking => effort != null;

  static const organize = DeepSeekTaskProfile._('organize');
  static const answers = DeepSeekTaskProfile._('answers');
  static const questionnaire = DeepSeekTaskProfile._('questionnaire', ReasoningEffort.low);
  static const agent = DeepSeekTaskProfile._('agent', ReasoningEffort.low);
  static const _chat = DeepSeekTaskProfile._('chat');
  static const _chatDeep = DeepSeekTaskProfile._('chat', ReasoningEffort.high);

  /// Off by default; a conversation's "Think deeper" turns it on.
  static DeepSeekTaskProfile chat({bool thinkDeeper = false}) => thinkDeeper ? _chatDeep : _chat;

  /// The request-body fields for this profile.
  Map<String, Object?> get requestFields => {
    'thinking': effort == null ? {'type': 'disabled'} : {'type': 'enabled', 'reasoning_effort': effort!.name},
  };
}

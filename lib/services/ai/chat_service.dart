import '../../data/models/chat.dart';
import '../../domain/chat/chat_context.dart';
import 'llm_client.dart';

/// The assistant chat over DeepSeek: streamed, thinking off unless the
/// conversation asks to "Think deeper".
class ChatService {
  ChatService(this.client);

  final LlmClient client;

  /// [formContext]: the forms panel's chat — the form Sotto read, under
  /// [ChatContext.formRules].
  Stream<LlmDelta> reply(
    Conversation c, {
    int maxMessages = 20,
    String? screenshot,
    String? scriptContext,
    String? formContext,
  }) => client.streamMessages(
    messages: ChatContext.build(
      c,
      maxMessages: maxMessages,
      screenshot: screenshot,
      scriptContext: scriptContext,
      formContext: formContext,
      thinking: c.thinkDeeper,
    ),
    profile: DeepSeekTaskProfile.chat(thinkDeeper: c.thinkDeeper),
    // Reasoning counts against max_tokens.
    maxTokens: c.thinkDeeper ? 12000 : 4096,
    vision: screenshot != null,
  );
}

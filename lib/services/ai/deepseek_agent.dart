import '../../domain/agent/agent_action.dart';
import '../../domain/agent/agent_loop.dart';
import 'llm_client.dart';

/// [AgentModel] over DeepSeek function calling.
///
/// Screenshots go in user messages (the only role that may carry images);
/// tool results go in `tool` messages. Only the newest screenshot is kept
/// as an image — older ones become a text placeholder, so a 25-step task
/// doesn't resend 25 images. `reasoning_content` from thinking models is
/// kept on the assistant messages, as DeepSeek requires for tool calls.
class DeepSeekAgentModel implements AgentModel {
  DeepSeekAgentModel({required this.client, required this.model, this.userData = '', this.language = 'en'});

  final DeepSeekClient client;

  /// Must read images (see `pickVisionModel`).
  final String model;

  /// The presenter's own material (prep documents) for filling forms.
  final String userData;

  /// Interface language, for the summary the presenter reads.
  final String language;

  final _messages = <Map<String, Object?>>[];
  var _pending = <String>[];

  static const _maxUserData = 8000;

  String _system() {
    final data = userData.length > _maxUserData ? '${userData.substring(0, _maxUserData)}…' : userData;
    return '''
You operate the presenter's computer to finish one task, one step at a time, by calling tools.

Each turn you get a screenshot. Coordinates are in that screenshot's pixels, origin top-left.
Call exactly one tool per turn. After each action you get a new screenshot — check it before the next step.
Give every click and typing step a "target": the visible label of what you act on.
Click a field before typing into it. Prefer the Tab key to move between form fields.
Never type passwords, security codes or payment details (card numbers, CVV, IBAN): those steps are blocked.
Do not submit, send, pay, delete or buy anything unless the task says to; the presenter confirms those steps.
If you are stuck, or the task is done, call done with a short summary in ${language == 'es' ? 'Spanish' : 'English'}.
${data.isEmpty ? '' : '''

The presenter's own notes, to fill forms with (use only what the task needs):
"""
$data
"""'''}''';
  }

  Map<String, Object?> _screenMessage(String text, AgentScreen screen) => {
    'role': 'user',
    'content': DeepSeekClient.userContent(
      '$text\nScreenshot: ${screen.mapper.imageWidth}×${screen.mapper.imageHeight} px.',
      [screen.image],
    ),
  };

  /// Older screenshots become text; the newest one stays an image.
  void _dropOldImages() {
    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      if (m['role'] == 'user' && m['content'] is List) {
        final text = (m['content']! as List).whereType<Map<Object?, Object?>>().where((p) => p['type'] == 'text');
        _messages[i] = {
          'role': 'user',
          'content': '${text.map((p) => p['text']).join('\n')}\n[earlier screenshot omitted]',
        };
      }
    }
  }

  @override
  Future<AgentTurn> start(String task, AgentScreen screen) {
    _messages
      ..clear()
      ..add({'role': 'system', 'content': _system()})
      ..add(_screenMessage('Task: $task', screen));
    _pending = [];
    return _turn();
  }

  @override
  Future<AgentTurn> next({required String result, AgentScreen? screen}) {
    if (_pending.isEmpty) {
      _messages.add({'role': 'user', 'content': result});
    } else {
      // Every tool call needs an answer; only the first one ran.
      for (var i = 0; i < _pending.length; i++) {
        _messages.add({
          'role': 'tool',
          'tool_call_id': _pending[i],
          'content': i == 0 ? result : 'skipped: one action per turn',
        });
      }
    }
    _pending = [];
    if (screen != null) {
      _dropOldImages();
      _messages.add(_screenMessage('The screen now.', screen));
    }
    return _turn();
  }

  Future<AgentTurn> _turn() async {
    final msg = await client.chat(messages: _messages, tools: agentToolSchemas(), model: model);
    final calls = [...?(msg['tool_calls'] as List?)?.cast<Map<Object?, Object?>>()];
    _messages.add({
      'role': 'assistant',
      'content': msg['content'] ?? '',
      if (msg['reasoning_content'] != null) 'reasoning_content': msg['reasoning_content'],
      if (calls.isNotEmpty) 'tool_calls': calls,
    });
    _pending = [for (final c in calls) c['id']! as String];
    if (calls.isEmpty) return AgentTurn(text: msg['content'] as String? ?? '');
    final fn = (calls.first['function']! as Map).cast<String, Object?>();
    return AgentTurn(
      text: msg['content'] as String? ?? '',
      call: AgentToolCall(
        id: calls.first['id']! as String,
        name: fn['name']! as String,
        arguments: fn['arguments'] as String? ?? '{}',
      ),
    );
  }
}

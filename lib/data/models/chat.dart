import '../../core/utils/ids.dart';

enum ChatRole { user, assistant }

/// One message. Screenshots are sent with the message but never stored:
/// [hadScreen] only remembers that one was attached.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.at,
    this.reasoning = '',
    this.hadScreen = false,
    this.error,
  });

  final String id;
  final ChatRole role;
  final String text;
  final DateTime at;

  /// The model's hidden reasoning ("Think deeper"). Never shown; sent back
  /// on the next turn, as DeepSeek asks for multi-turn thinking.
  final String reasoning;
  final bool hadScreen;

  /// Why the reply failed, shown instead of text.
  final String? error;

  ChatMessage copyWith({String? text, String? reasoning, String? error, bool clearError = false}) => ChatMessage(
    id: id,
    role: role,
    text: text ?? this.text,
    at: at,
    reasoning: reasoning ?? this.reasoning,
    hadScreen: hadScreen,
    error: clearError ? null : (error ?? this.error),
  );

  factory ChatMessage.user(String text, {bool hadScreen = false}) =>
      ChatMessage(id: newId(), role: ChatRole.user, text: text, at: DateTime.now(), hadScreen: hadScreen);

  factory ChatMessage.assistant() => ChatMessage(id: newId(), role: ChatRole.assistant, text: '', at: DateTime.now());

  Map<String, Object?> toJson() => {
    'id': id,
    'role': role.name,
    'text': text,
    'at': at.toIso8601String(),
    if (reasoning.isNotEmpty) 'reasoning': reasoning,
    if (hadScreen) 'screen': true,
    'error': ?error,
  };

  /// Tolerant of missing and unknown keys, like every other model.
  factory ChatMessage.fromJson(Map<dynamic, dynamic> j) => ChatMessage(
    id: j['id'] as String? ?? newId(),
    role: ChatRole.values.asNameMap()[j['role']] ?? ChatRole.user,
    text: j['text'] as String? ?? '',
    at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
    reasoning: j['reasoning'] as String? ?? '',
    hadScreen: j['screen'] as bool? ?? false,
    error: j['error'] as String?,
  );
}

/// A chat with the assistant.
class Conversation {
  const Conversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.messages = const [],
    this.thinkDeeper = false,
    this.useScript = false,
    this.titled = false,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ChatMessage> messages;

  /// Thinking on for this conversation (off by default: slower, billed).
  final bool thinkDeeper;

  /// Send the presenter's script as context (off by default).
  final bool useScript;

  /// The presenter renamed it; don't retitle from the first message.
  final bool titled;

  Conversation copyWith({
    String? title,
    DateTime? updatedAt,
    List<ChatMessage>? messages,
    bool? thinkDeeper,
    bool? useScript,
    bool? titled,
  }) => Conversation(
    id: id,
    title: title ?? this.title,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now(),
    messages: messages ?? this.messages,
    thinkDeeper: thinkDeeper ?? this.thinkDeeper,
    useScript: useScript ?? this.useScript,
    titled: titled ?? this.titled,
  );

  factory Conversation.create(String title) {
    final now = DateTime.now();
    return Conversation(id: newId(), title: title, createdAt: now, updatedAt: now);
  }

  /// A title from the first words of the first message.
  static String titleFrom(String text, {int words = 6}) {
    final w = text.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
    final t = w.take(words).join(' ');
    return w.length > words ? '$t…' : t;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'messages': [for (final m in messages) m.toJson()],
    'thinkDeeper': thinkDeeper,
    'useScript': useScript,
    'titled': titled,
  };

  factory Conversation.fromJson(Map<dynamic, dynamic> j) {
    final created = DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
    return Conversation(
      id: j['id'] as String? ?? newId(),
      title: j['title'] as String? ?? '',
      createdAt: created,
      updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? created,
      messages: [
        for (final m in (j['messages'] as List? ?? const []))
          if (m is Map) ChatMessage.fromJson(m),
      ],
      thinkDeeper: j['thinkDeeper'] as bool? ?? false,
      useScript: j['useScript'] as bool? ?? false,
      titled: j['titled'] as bool? ?? false,
    );
  }
}

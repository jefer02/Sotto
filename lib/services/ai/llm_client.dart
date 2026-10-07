import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/secrets.dart';
import '../../data/models/settings.dart';
import '../../data/storage/secret_store.dart';
import '../../l10n/l10n.dart';
import 'task_profile.dart';

export 'task_profile.dart';

const _provider = 'DeepSeek';

class LlmException implements Exception {
  LlmException(this.message, {this.statusCode, this.retryable = false});

  final String message;
  final int? statusCode;
  final bool retryable;

  @override
  String toString() => message;

  static LlmException fromStatus(int status, String body) {
    String detail = '';
    try {
      final j = jsonDecode(body);
      detail = (j['error']?['message'] ?? j['message'] ?? '') as String;
    } catch (_) {}
    final l = L10n.current;
    final suffix = detail.isEmpty ? '' : ': $detail';
    final msg = switch (status) {
      400 || 422 => '${l.llmRejected}$suffix',
      401 || 403 => l.llmBadKey(_provider),
      402 => l.llmNoBalance,
      404 => l.llmNoModel,
      429 => l.llmRateLimit(_provider),
      >= 500 => l.llmServerError(_provider, status),
      _ => '${l.llmFailed(status)}$suffix',
    };
    return LlmException(msg, statusCode: status, retryable: status == 429 || status >= 500);
  }
}

/// DeepSeek sent nothing for [DeepSeekClient.timeout]: "DeepSeek did not
/// respond — check your connection". A [TimeoutException] too, so code
/// that knows nothing of DeepSeek (the form runner) can end its cycle on it.
class LlmTimeout extends LlmException implements TimeoutException {
  LlmTimeout({this.duration = DeepSeekClient.defaultTimeout})
    : super(L10n.current.llmTimeout(_provider), retryable: true);

  @override
  final Duration duration;
}

/// Raised when the model declines to answer (finish_reason "content_filter").
class LlmRefusal extends LlmException {
  LlmRefusal() : super(L10n.current.llmRefusal);
}

/// The key DeepSeek calls use: one saved in Settings → Integrations wins,
/// otherwise the built-in key from `lib/core/secrets.dart`. Null when
/// neither exists.
Future<String?> resolveDeepSeekKey(SecretStore secrets) async {
  final saved = await secrets.read(SecretKey.deepseekApiKey);
  if (saved != null && saved.isNotEmpty) return saved;
  return kDeepSeekApiKey.isEmpty ? null : kDeepSeekApiKey;
}

/// A model `GET /models` returned.
class DeepSeekModel {
  const DeepSeekModel(this.id, {this.images = false});
  final String id;

  /// Accepts `image_url` parts (screenshots).
  final bool images;
}

/// A piece of a streamed reply: visible [content], or the model's hidden
/// [reasoning] (thinking mode), which chat keeps to send back next turn.
class LlmDelta {
  const LlmDelta({this.content = '', this.reasoning = ''});
  final String content;
  final String reasoning;
}

/// Minimal streaming text interface over raw HTTP + server-sent events.
/// Every request names a [DeepSeekTaskProfile], which decides thinking.
abstract class LlmClient {
  /// [images] are JPEG data URLs, attached to the user message (DeepSeek
  /// accepts images in user messages only). [json] asks for a JSON object
  /// (`response_format`); the prompt must say "JSON" too.
  Stream<String> stream({
    required String system,
    required String user,
    int maxTokens = 4096,
    DeepSeekTaskProfile profile = DeepSeekTaskProfile.answers,
    List<String> images = const [],
    bool json = false,
  });

  Future<String> complete({
    required String system,
    required String user,
    int maxTokens = 8192,
    DeepSeekTaskProfile profile = DeepSeekTaskProfile.organize,
    List<String> images = const [],
    bool json = false,
  }) async {
    final buf = StringBuffer();
    await for (final chunk in stream(
      system: system,
      user: user,
      maxTokens: maxTokens,
      profile: profile,
      images: images,
      json: json,
    )) {
      buf.write(chunk);
    }
    return buf.toString();
  }

  /// A multi-turn conversation (chat), streamed. [messages] are in API
  /// form; [vision] routes to the model that reads images.
  Stream<LlmDelta> streamMessages({
    required List<Map<String, Object?>> messages,
    required DeepSeekTaskProfile profile,
    int maxTokens = 4096,
    bool vision = false,
  }) => throw UnimplementedError();

  void close();

  static LlmClient create(AppSettings s, String apiKey) =>
      DeepSeekClient(apiKey: apiKey, model: s.aiModel, visionModel: s.visionModel);

  /// A client for the current settings, or null when there is no key.
  static Future<LlmClient?> forSettings(AppSettings s, SecretStore secrets) async {
    final key = await resolveDeepSeekKey(secrets);
    return key == null ? null : create(s, key);
  }
}

/// Splits a byte stream into SSE events: (event name, data payload).
Stream<(String?, String)> _sse(Stream<List<int>> bytes) async* {
  String? event;
  final data = StringBuffer();
  await for (final line in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.isEmpty) {
      if (data.isNotEmpty) yield (event, data.toString());
      event = null;
      data.clear();
    } else if (line.startsWith('event:')) {
      event = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      if (data.isNotEmpty) data.write('\n');
      data.write(line.substring(5).trimLeft());
    }
  }
  if (data.isNotEmpty) yield (event, data.toString());
}

/// Every DeepSeek call gives up after [timeout] without a byte: waiting for
/// the headers, and between two pieces of the body (a reply may stream for
/// longer, as long as it keeps coming). The request is abandoned
/// ([LlmTimeout]) and the caller's cycle ends there.
Future<http.StreamedResponse> _send(http.Client client, http.BaseRequest req, Duration timeout) async {
  try {
    final res = await client.send(req).timeout(timeout);
    return http.StreamedResponse(
      _idleTimeout(res.stream, timeout),
      res.statusCode,
      contentLength: res.contentLength,
      request: res.request,
      headers: res.headers,
      isRedirect: res.isRedirect,
      persistentConnection: res.persistentConnection,
      reasonPhrase: res.reasonPhrase,
    );
  } on TimeoutException {
    throw LlmTimeout(duration: timeout);
  } on SocketException {
    throw LlmException(L10n.current.llmOffline(_provider), retryable: true);
  } on http.ClientException catch (e) {
    throw LlmException(L10n.current.llmUnreachable(_provider, e.message), retryable: true);
  }
}

/// [bytes], failing with [LlmTimeout] when nothing arrives for [timeout];
/// the subscription is cancelled, which closes the connection.
Stream<List<int>> _idleTimeout(Stream<List<int>> bytes, Duration timeout) => bytes.timeout(
  timeout,
  onTimeout: (sink) {
    sink.addError(LlmTimeout(duration: timeout));
    sink.close();
  },
);

/// DeepSeek's OpenAI-format API. Thinking models also stream
/// `reasoning_content`; it is never shown and never breaks parsing.
class DeepSeekClient extends LlmClient {
  DeepSeekClient({
    required this.apiKey,
    required this.model,
    this.visionModel,
    http.Client? httpClient,
    this.timeout = defaultTimeout,
  }) : _http = httpClient ?? http.Client();

  static const baseUrl = 'https://api.deepseek.com';

  /// How long a call may go without hearing from DeepSeek.
  static const defaultTimeout = Duration(seconds: 30);
  final Duration timeout;
  static const defaultModel = 'deepseek-flash';

  final String apiKey;
  final String model;

  /// Used instead of [model] when a request carries images and [model]
  /// can't read them.
  final String? visionModel;
  final http.Client _http;

  Map<String, String> get _headers => {'content-type': 'application/json', 'authorization': 'Bearer $apiKey'};

  /// `GET /models` — the models this key may use.
  Future<List<DeepSeekModel>> listModels() async {
    final req = http.Request('GET', Uri.parse('$baseUrl/models'))..headers.addAll(_headers);
    final res = await _send(_http, req, timeout);
    final body = await res.stream.bytesToString();
    if (res.statusCode != 200) throw LlmException.fromStatus(res.statusCode, body);
    final data = (jsonDecode(body) as Map)['data'] as List? ?? const [];
    return [
      for (final m in data.cast<Map<Object?, Object?>>())
        DeepSeekModel(m['id']! as String, images: (m['input_modalities'] as List?)?.contains('image') ?? false),
    ]..sort((a, b) => a.id.compareTo(b.id));
  }

  @override
  Stream<String> stream({
    required String system,
    required String user,
    int maxTokens = 4096,
    DeepSeekTaskProfile profile = DeepSeekTaskProfile.answers,
    List<String> images = const [],
    bool json = false,
  }) async* {
    await for (final d in _streamRequest(
      model: images.isEmpty ? model : (visionModel ?? model),
      messages: [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': userContent(user, images)},
      ],
      maxTokens: maxTokens,
      profile: profile,
      json: json,
    )) {
      if (d.content.isNotEmpty) yield d.content;
    }
  }

  @override
  Stream<LlmDelta> streamMessages({
    required List<Map<String, Object?>> messages,
    required DeepSeekTaskProfile profile,
    int maxTokens = 4096,
    bool vision = false,
  }) => _streamRequest(
    model: vision ? (visionModel ?? model) : model,
    messages: messages,
    maxTokens: maxTokens,
    profile: profile,
  );

  Stream<LlmDelta> _streamRequest({
    required String model,
    required List<Map<String, Object?>> messages,
    required int maxTokens,
    required DeepSeekTaskProfile profile,
    bool json = false,
  }) async* {
    final req = http.Request('POST', Uri.parse('$baseUrl/chat/completions'))
      ..headers.addAll(_headers)
      ..body = jsonEncode({
        'model': model,
        'stream': true,
        'max_tokens': maxTokens,
        ...profile.requestFields,
        if (json) 'response_format': {'type': 'json_object'},
        'messages': messages,
      });

    final res = await _send(_http, req, timeout);
    if (res.statusCode != 200) {
      throw LlmException.fromStatus(res.statusCode, await res.stream.bytesToString());
    }
    await for (final (_, data) in _sse(res.stream)) {
      if (data == '[DONE]') break;
      final j = jsonDecode(data) as Map<String, dynamic>;
      if (j['error'] != null) {
        throw LlmException((j['error'] as Map)['message'] as String? ?? L10n.current.llmGenericError(_provider));
      }
      final choices = j['choices'] as List?;
      if (choices == null || choices.isEmpty) continue;
      final choice = choices.first as Map;
      final delta = choice['delta'] as Map?;
      final content = delta?['content'];
      final reasoning = delta?['reasoning_content'];
      if ((content is String && content.isNotEmpty) || (reasoning is String && reasoning.isNotEmpty)) {
        yield LlmDelta(content: content is String ? content : '', reasoning: reasoning is String ? reasoning : '');
      }
      if (choice['finish_reason'] == 'content_filter') throw LlmRefusal();
    }
  }

  /// One non-streaming turn with tool calling (agent mode). Returns the
  /// assistant message as sent by the API — `content`, `tool_calls` and,
  /// on thinking models, `reasoning_content`, which callers must send back
  /// on later turns.
  Future<Map<String, Object?>> chat({
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const [],
    String? model,
    int maxTokens = 1024,
    DeepSeekTaskProfile profile = DeepSeekTaskProfile.agent,
  }) async {
    final req = http.Request('POST', Uri.parse('$baseUrl/chat/completions'))
      ..headers.addAll(_headers)
      ..body = jsonEncode({
        'model': model ?? this.model,
        'max_tokens': maxTokens,
        ...profile.requestFields,
        'messages': messages,
        if (tools.isNotEmpty) 'tools': tools,
      });
    final res = await _send(_http, req, timeout);
    final body = await res.stream.bytesToString();
    if (res.statusCode != 200) throw LlmException.fromStatus(res.statusCode, body);
    final j = jsonDecode(body) as Map<String, dynamic>;
    final choices = j['choices'] as List?;
    if (choices == null || choices.isEmpty) throw LlmException(L10n.current.llmGenericError(_provider));
    final choice = choices.first as Map;
    if (choice['finish_reason'] == 'content_filter') throw LlmRefusal();
    return (choice['message'] as Map).cast<String, Object?>();
  }

  /// Plain text, or text + `image_url` parts when there are images.
  static Object userContent(String text, List<String> images) => images.isEmpty
      ? text
      : [
          {'type': 'text', 'text': text},
          for (final url in images)
            {
              'type': 'image_url',
              'image_url': {'url': url},
            },
        ];

  @override
  void close() => _http.close();
}

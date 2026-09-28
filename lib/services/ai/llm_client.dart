import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/secrets.dart';
import '../../data/models/settings.dart';
import '../../data/storage/secret_store.dart';
import '../../l10n/l10n.dart';

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

/// Minimal streaming text interface over raw HTTP + server-sent events.
abstract class LlmClient {
  /// [images] are JPEG data URLs, attached to the user message (DeepSeek
  /// accepts images in user messages only).
  Stream<String> stream({
    required String system,
    required String user,
    int maxTokens = 4096,
    bool fast = true,
    List<String> images = const [],
  });

  Future<String> complete({required String system, required String user, int maxTokens = 8192}) async {
    final buf = StringBuffer();
    await for (final chunk in stream(system: system, user: user, maxTokens: maxTokens, fast: false)) {
      buf.write(chunk);
    }
    return buf.toString();
  }

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

Future<http.StreamedResponse> _send(http.Client client, http.BaseRequest req) async {
  try {
    return await client.send(req).timeout(const Duration(seconds: 30));
  } on TimeoutException {
    throw LlmException(L10n.current.llmTimeout(_provider), retryable: true);
  } on SocketException {
    throw LlmException(L10n.current.llmOffline(_provider), retryable: true);
  } on http.ClientException catch (e) {
    throw LlmException(L10n.current.llmUnreachable(_provider, e.message), retryable: true);
  }
}

/// DeepSeek's OpenAI-format API. Thinking models also stream
/// `reasoning_content`; it is never shown and never breaks parsing.
class DeepSeekClient extends LlmClient {
  DeepSeekClient({required this.apiKey, required this.model, this.visionModel, http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  static const baseUrl = 'https://api.deepseek.com';
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
    final res = await _send(_http, req);
    final body = await res.stream.bytesToString();
    if (res.statusCode != 200) throw LlmException.fromStatus(res.statusCode, body);
    final data = (jsonDecode(body) as Map)['data'] as List? ?? const [];
    return [
      for (final m in data.cast<Map<Object?, Object?>>())
        DeepSeekModel(
          m['id']! as String,
          images: (m['input_modalities'] as List?)?.contains('image') ?? false,
        ),
    ]..sort((a, b) => a.id.compareTo(b.id));
  }

  @override
  Stream<String> stream({
    required String system,
    required String user,
    int maxTokens = 4096,
    bool fast = true,
    List<String> images = const [],
  }) async* {
    final req = http.Request('POST', Uri.parse('$baseUrl/chat/completions'))
      ..headers.addAll(_headers)
      ..body = jsonEncode({
        'model': images.isEmpty ? model : (visionModel ?? model),
        'stream': true,
        'max_tokens': maxTokens,
        // Live answers are latency-bound, so they skip thinking; organizing a
        // script can afford it.
        if (fast) 'thinking': {'type': 'disabled'},
        'messages': [
          {'role': 'system', 'content': system},
          {'role': 'user', 'content': userContent(user, images)},
        ],
      });

    final res = await _send(_http, req);
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
      final content = (choice['delta'] as Map?)?['content'];
      if (content is String && content.isNotEmpty) yield content;
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
    bool thinking = false,
  }) async {
    final req = http.Request('POST', Uri.parse('$baseUrl/chat/completions'))
      ..headers.addAll(_headers)
      ..body = jsonEncode({
        'model': model ?? this.model,
        'max_tokens': maxTokens,
        if (!thinking) 'thinking': {'type': 'disabled'},
        'messages': messages,
        if (tools.isNotEmpty) 'tools': tools,
      });
    final res = await _send(_http, req);
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

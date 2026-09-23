import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../data/models/settings.dart';
import '../../l10n/l10n.dart';

class LlmException implements Exception {
  LlmException(this.message, {this.statusCode, this.retryable = false});

  final String message;
  final int? statusCode;
  final bool retryable;

  @override
  String toString() => message;

  static LlmException fromStatus(int status, String body, String provider) {
    String detail = '';
    try {
      final j = jsonDecode(body);
      detail = (j['error']?['message'] ?? j['message'] ?? '') as String;
    } catch (_) {}
    final l = L10n.current;
    final suffix = detail.isEmpty ? '' : ': $detail';
    final msg = switch (status) {
      400 => '${l.llmRejected}$suffix',
      401 || 403 => l.llmBadKey(provider),
      404 => l.llmNoModel,
      429 => l.llmRateLimit(provider),
      >= 500 => l.llmServerError(provider, status),
      _ => '${l.llmFailed(status)}$suffix',
    };
    return LlmException(msg, statusCode: status, retryable: status == 429 || status >= 500);
  }
}

/// Raised when the model declines to answer (stop_reason "refusal").
class LlmRefusal extends LlmException {
  LlmRefusal() : super(L10n.current.llmRefusal);
}

/// Minimal streaming text interface; both providers implement it over raw
/// HTTP + server-sent events.
abstract class LlmClient {
  Stream<String> stream({required String system, required String user, int maxTokens = 4096, bool fast = true});

  Future<String> complete({required String system, required String user, int maxTokens = 8192}) async {
    final buf = StringBuffer();
    await for (final chunk in stream(system: system, user: user, maxTokens: maxTokens, fast: false)) {
      buf.write(chunk);
    }
    return buf.toString();
  }

  void close();

  static LlmClient create(AppSettings s, String apiKey) => switch (s.aiProvider) {
    AiProvider.anthropic => AnthropicClient(
      apiKey: apiKey,
      model: s.aiModel.isEmpty ? s.aiProvider.defaultModel : s.aiModel,
      baseUrl: s.effectiveAiBaseUrl,
    ),
    AiProvider.openai || AiProvider.openaiCompatible => OpenAiClient(
      apiKey: apiKey,
      model: s.aiModel.isEmpty ? s.aiProvider.defaultModel : s.aiModel,
      baseUrl: s.effectiveAiBaseUrl,
      official: s.aiProvider == AiProvider.openai,
    ),
  };
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

Future<http.StreamedResponse> _send(http.Client client, http.Request req, String provider) async {
  try {
    return await client.send(req).timeout(const Duration(seconds: 30));
  } on TimeoutException {
    throw LlmException(L10n.current.llmTimeout(provider), retryable: true);
  } on SocketException {
    throw LlmException(L10n.current.llmOffline(provider), retryable: true);
  } on http.ClientException catch (e) {
    throw LlmException(L10n.current.llmUnreachable(provider, e.message), retryable: true);
  }
}

class AnthropicClient extends LlmClient {
  AnthropicClient({required this.apiKey, required this.model, required this.baseUrl});

  final String apiKey;
  final String model;
  final String baseUrl;
  final _http = http.Client();

  // Models that take output_config.effort; Haiku 4.5 rejects it.
  bool get _supportsEffort =>
      model.startsWith('claude-opus') ||
      model.startsWith('claude-fable') ||
      model.startsWith('claude-sonnet-5') ||
      model.startsWith('claude-sonnet-4-6') ||
      model.startsWith('claude-mythos');

  // Server-side refusal fallbacks: re-run a declined request on another
  // model inside the same call. Enabled for the models that support it.
  bool get _supportsFallbacks => model == 'claude-opus-5' || model == 'claude-fable-5-1';

  @override
  Stream<String> stream({required String system, required String user, int maxTokens = 4096, bool fast = true}) async* {
    final uri = Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/v1/messages');
    final req = http.Request('POST', uri)
      ..headers.addAll({
        'content-type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        if (_supportsFallbacks) 'anthropic-beta': 'server-side-fallback-2026-07-01',
      })
      ..body = jsonEncode({
        'model': model,
        'max_tokens': maxTokens,
        'stream': true,
        'system': system,
        'messages': [
          {'role': 'user', 'content': user},
        ],
        // Live answers are latency-bound (first token ≤ 1.2 s p50), so they
        // run at low effort; structuring a script can afford more.
        if (_supportsEffort) 'output_config': {'effort': fast ? 'low' : 'medium'},
        if (_supportsFallbacks) 'fallbacks': 'default',
      });

    final res = await _send(_http, req, 'Anthropic');
    if (res.statusCode != 200) {
      throw LlmException.fromStatus(res.statusCode, await res.stream.bytesToString(), 'Anthropic');
    }
    await for (final (event, data) in _sse(res.stream)) {
      final j = jsonDecode(data) as Map<String, dynamic>;
      switch (j['type'] ?? event) {
        case 'content_block_delta':
          final delta = j['delta'] as Map<String, dynamic>;
          if (delta['type'] == 'text_delta') yield delta['text'] as String;
        case 'message_delta':
          if ((j['delta'] as Map?)?['stop_reason'] == 'refusal') throw LlmRefusal();
        case 'error':
          final err = j['error'] as Map?;
          throw LlmException(
            err?['message'] as String? ?? L10n.current.llmGenericError('Anthropic'),
            retryable: err?['type'] == 'overloaded_error',
          );
      }
    }
  }

  @override
  void close() => _http.close();
}

class OpenAiClient extends LlmClient {
  OpenAiClient({required this.apiKey, required this.model, required this.baseUrl, required this.official});

  final String apiKey;
  final String model;
  final String baseUrl;

  /// api.openai.com wants `max_completion_tokens`; most compatible servers
  /// (Ollama, LM Studio, vLLM, OpenRouter) still read `max_tokens`.
  final bool official;
  final _http = http.Client();

  @override
  Stream<String> stream({required String system, required String user, int maxTokens = 4096, bool fast = true}) async* {
    final uri = Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions');
    final req = http.Request('POST', uri)
      ..headers.addAll({'content-type': 'application/json', if (apiKey.isNotEmpty) 'authorization': 'Bearer $apiKey'})
      ..body = jsonEncode({
        'model': model,
        'stream': true,
        official ? 'max_completion_tokens' : 'max_tokens': maxTokens,
        'messages': [
          {'role': 'system', 'content': system},
          {'role': 'user', 'content': user},
        ],
      });

    final provider = official ? 'OpenAI' : L10n.current.llmAiServer;
    final res = await _send(_http, req, provider);
    if (res.statusCode != 200) {
      throw LlmException.fromStatus(res.statusCode, await res.stream.bytesToString(), provider);
    }
    await for (final (_, data) in _sse(res.stream)) {
      if (data == '[DONE]') break;
      final j = jsonDecode(data) as Map<String, dynamic>;
      if (j['error'] != null) {
        throw LlmException((j['error'] as Map)['message'] as String? ?? L10n.current.llmGenericError(provider));
      }
      final choices = j['choices'] as List?;
      if (choices == null || choices.isEmpty) continue;
      final delta = (choices.first as Map)['delta'] as Map?;
      final content = delta?['content'];
      if (content is String && content.isNotEmpty) yield content;
      if ((choices.first as Map)['finish_reason'] == 'content_filter') throw LlmRefusal();
    }
  }

  @override
  void close() => _http.close();
}

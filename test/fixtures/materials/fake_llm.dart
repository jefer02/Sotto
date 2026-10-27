import 'dart:async';

import 'package:sotto/services/ai/llm_client.dart';

/// One request the fake saw.
class FakeRequest {
  const FakeRequest(this.system, this.user, this.profile, {required this.json, required this.streamed});
  final String system;
  final String user;
  final DeepSeekTaskProfile profile;
  final bool json;
  final bool streamed;
}

/// An [LlmClient] that answers from [reply] — given every request, in
/// order — and streams the answer in small pieces. [gate], when set, holds
/// a streamed reply after its first piece until it completes (to cancel
/// mid-stream).
class FakeLlm extends LlmClient {
  FakeLlm(this.reply) : requests = [];

  /// Another client answering the same way and logging to the same list —
  /// what a provider that makes a new client per call returns.
  FakeLlm.sharing(FakeLlm other) : reply = other.reply, requests = other.requests;

  final FutureOr<String> Function(FakeRequest request) reply;
  final List<FakeRequest> requests;
  Completer<void>? gate;
  bool closed = false;

  @override
  Stream<String> stream({
    required String system,
    required String user,
    int maxTokens = 4096,
    DeepSeekTaskProfile profile = DeepSeekTaskProfile.answers,
    List<String> images = const [],
    bool json = false,
  }) => _stream(FakeRequest(system, user, profile, json: json, streamed: true));

  // complete() goes through stream() in LlmClient; mark those as not
  // streamed by overriding it.
  @override
  Future<String> complete({
    required String system,
    required String user,
    int maxTokens = 8192,
    DeepSeekTaskProfile profile = DeepSeekTaskProfile.organize,
    List<String> images = const [],
    bool json = false,
  }) async {
    if (closed) throw LlmException('closed', retryable: true);
    final r = FakeRequest(system, user, profile, json: json, streamed: false);
    requests.add(r);
    return await reply(r);
  }

  Stream<String> _stream(FakeRequest r) async* {
    if (closed) throw LlmException('closed', retryable: true);
    requests.add(r);
    final text = await reply(r);
    for (var i = 0; i < text.length; i += 40) {
      if (closed) throw LlmException('connection closed', retryable: true);
      yield text.substring(i, i + 40 > text.length ? text.length : i + 40);
      if (i == 0 && gate != null) await gate!.future;
    }
  }

  @override
  void close() {
    closed = true;
    gate?.complete();
    gate = null;
  }
}

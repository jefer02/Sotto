import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app.dart' show focusedScriptProvider;
import '../../data/models/chat.dart';
import '../../data/models/script.dart';
import '../../data/models/settings.dart';
import '../../data/repositories.dart';
import '../../domain/chat/chat_context.dart';
import '../../domain/chat/markdown.dart';
import '../../l10n/l10n.dart';
import '../../services/ai/chat_service.dart';
import '../../services/ai/llm_client.dart';
import '../../services/screen/screen_service.dart';
import '../../services/speech/dictation.dart';
import '../../services/speech/model_manager.dart';
import '../../services/tts/tts_service.dart';
import '../live/live_controller.dart';

class ChatState {
  const ChatState({
    this.conversationId,
    this.streamingId,
    this.streamingText = '',
    this.recording = false,
    this.transcribing = false,
    this.attachScreen = false,
    this.capturing = false,
    this.overlayOpen = false,
    this.error,
    this.newThinkDeeper = false,
    this.newUseScript = false,
  });

  final String? conversationId;

  /// The assistant message being streamed, and its text so far.
  final String? streamingId;
  final String streamingText;
  final bool recording;
  final bool transcribing;

  /// The next message goes with a screenshot of the current display.
  final bool attachScreen;
  final bool capturing;

  /// Live mode: the compact chat panel is showing in the overlay.
  final bool overlayOpen;
  final String? error;

  /// The switches of a conversation not started yet.
  final bool newThinkDeeper;
  final bool newUseScript;

  bool get streaming => streamingId != null;

  ChatState copyWith({
    String? conversationId,
    bool clearConversation = false,
    String? streamingId,
    bool clearStreaming = false,
    String? streamingText,
    bool? recording,
    bool? transcribing,
    bool? attachScreen,
    bool? capturing,
    bool? overlayOpen,
    String? error,
    bool clearError = false,
    bool? newThinkDeeper,
    bool? newUseScript,
  }) => ChatState(
    conversationId: clearConversation ? null : (conversationId ?? this.conversationId),
    streamingId: clearStreaming ? null : (streamingId ?? this.streamingId),
    streamingText: streamingText ?? this.streamingText,
    recording: recording ?? this.recording,
    transcribing: transcribing ?? this.transcribing,
    attachScreen: attachScreen ?? this.attachScreen,
    capturing: capturing ?? this.capturing,
    overlayOpen: overlayOpen ?? this.overlayOpen,
    error: clearError ? null : (error ?? this.error),
    newThinkDeeper: newThinkDeeper ?? this.newThinkDeeper,
    newUseScript: newUseScript ?? this.newUseScript,
  );
}

/// The assistant chat, shared by the main window (Chat) and the overlay's
/// compact panel (chord + C). Conversations live in the "chats" box.
class ChatController extends Notifier<ChatState> {
  /// The composer's text — one composer is on screen at a time.
  final input = TextEditingController();

  StreamSubscription<LlmDelta>? _sub;
  LlmClient? _client;
  Dictation? _standalone;
  Dictation? _dictation;

  AppSettings get _settings => ref.read(settingsProvider);
  ChatRepository get _repo => ref.read(chatRepositoryProvider);

  @override
  ChatState build() {
    ref.onDispose(() {
      unawaited(_sub?.cancel());
      _client?.close();
      unawaited(_standalone?.dispose());
      input.dispose();
    });
    return const ChatState();
  }

  Conversation? get current => state.conversationId == null ? null : _repo.get(state.conversationId!);

  // ─────────────────────────── Conversations ───────────────────────────

  void select(String? id) =>
      state = state.copyWith(conversationId: id, clearConversation: id == null, clearError: true);

  /// A fresh conversation; saved with its first message.
  void newConversation() {
    stop();
    state = state.copyWith(clearConversation: true, clearError: true, newThinkDeeper: false, newUseScript: false);
    input.clear();
  }

  Future<void> rename(String id, String title) async {
    final c = _repo.get(id);
    if (c == null || title.trim().isEmpty) return;
    await _repo.save(c.copyWith(title: title.trim(), titled: true, updatedAt: c.updatedAt));
  }

  Future<void> delete(String id) async {
    if (state.conversationId == id) newConversation();
    await _repo.delete(id);
  }

  Future<void> _update(Conversation Function(Conversation c) change) async {
    final c = current;
    if (c != null) await _repo.save(change(c));
  }

  Future<void> toggleThinkDeeper() async {
    if (current == null) {
      state = state.copyWith(newThinkDeeper: !state.newThinkDeeper);
    } else {
      await _update((c) => c.copyWith(thinkDeeper: !c.thinkDeeper, updatedAt: c.updatedAt));
    }
  }

  Future<void> toggleUseScript() async {
    if (current == null) {
      state = state.copyWith(newUseScript: !state.newUseScript);
    } else {
      await _update((c) => c.copyWith(useScript: !c.useScript, updatedAt: c.updatedAt));
    }
  }

  void toggleAttachScreen() => state = state.copyWith(attachScreen: !state.attachScreen);

  // ─────────────────────────── Overlay panel ───────────────────────────

  void toggleOverlay() => state = state.copyWith(overlayOpen: !state.overlayOpen);

  void closeOverlay() => state = state.copyWith(overlayOpen: false);

  // ─────────────────────────── Sending ───────────────────────────

  /// The script the "Use my script" toggle sends: the live one, or the one
  /// open in the editor / up next.
  Script? contextScript() {
    final live = ref.read(liveControllerProvider);
    if (live.isLive) return live.script;
    final id = ref.read(focusedScriptProvider);
    return id == null ? null : ref.read(scriptRepositoryProvider).get(id);
  }

  static String scriptText(Script s) => [
    '# ${s.title}',
    for (final sec in s.sections) ...['## ${sec.title}', for (final b in sec.beats) b.plainText],
  ].join('\n');

  /// Sends the composer's text (or [text]).
  Future<void> send([String? text]) async {
    final body = (text ?? input.text).trim();
    if (body.isEmpty || state.streaming) return;
    if (text == null) input.clear();
    final l = L10n.current;

    var c =
        current ??
        Conversation.create(Conversation.titleFrom(body))
            .copyWith(thinkDeeper: state.newThinkDeeper, useScript: state.newUseScript);
    final client = _client ??= await LlmClient.forSettings(_settings, ref.read(secretStoreProvider));
    if (client == null) {
      state = state.copyWith(error: l.answerNeedsKey);
      return;
    }

    String? screenshot;
    if (state.attachScreen) {
      state = state.copyWith(capturing: true);
      try {
        screenshot =
            (await ref
                    .read(screenServiceProvider)
                    .capture(
                      target: _settings.screenTarget == ScreenTarget.cursorDisplay
                          ? CaptureTarget.cursorDisplay
                          : CaptureTarget.overlayDisplay,
                    ))
                .dataUrl;
      } on ScreenCaptureException catch (e) {
        state = state.copyWith(capturing: false, error: e.permissionDenied ? l.noticeScreenPermission : e.message);
        return;
      }
      state = state.copyWith(capturing: false, attachScreen: false);
    }

    final user = ChatMessage.user(body, hadScreen: screenshot != null);
    final reply = ChatMessage.assistant();
    c = c.copyWith(messages: [...c.messages, user]);
    await _repo.save(c.copyWith(messages: [...c.messages, reply]));
    state = state.copyWith(conversationId: c.id, streamingId: reply.id, streamingText: '', clearError: true);

    final script = c.useScript ? contextScript() : null;
    final content = StringBuffer();
    final reasoning = StringBuffer();
    var lastPaint = DateTime.fromMillisecondsSinceEpoch(0);
    final done = Completer<void>();
    _sub = ChatService(client)
        .reply(
          c,
          maxMessages: _settings.chatContextMessages,
          screenshot: screenshot,
          scriptContext: script == null ? null : scriptText(script),
        )
        .listen(
          (d) {
            content.write(d.content);
            reasoning.write(d.reasoning);
            // ~30 repaints a second is plenty for streaming text.
            final now = DateTime.now();
            if (d.content.isNotEmpty && now.difference(lastPaint) > const Duration(milliseconds: 33)) {
              lastPaint = now;
              state = state.copyWith(streamingText: content.toString());
            }
          },
          onError: (Object e) {
            _finish(c.id, reply, content.toString(), reasoning.toString(), error: e is LlmException ? e.message : '$e');
            if (!done.isCompleted) done.complete();
          },
          onDone: () {
            _finish(c.id, reply, content.toString(), reasoning.toString());
            if (!done.isCompleted) done.complete();
          },
          cancelOnError: true,
        );
    _stopCurrent = () {
      _finish(c.id, reply, content.toString(), reasoning.toString(), stopped: true);
      if (!done.isCompleted) done.complete();
    };
    await done.future;
  }

  void Function()? _stopCurrent;

  void _finish(
    String conversationId,
    ChatMessage reply,
    String text,
    String reasoning, {
    String? error,
    bool stopped = false,
  }) {
    _sub = null;
    _stopCurrent = null;
    final c = _repo.get(conversationId);
    if (c != null) {
      final messages = [
        for (final m in c.messages)
          if (m.id == reply.id)
            m.copyWith(text: text, reasoning: reasoning, error: text.isEmpty && !stopped ? error : null)
          else
            m,
      ];
      unawaited(_repo.save(c.copyWith(messages: messages)));
    }
    if (state.streamingId == reply.id) state = state.copyWith(clearStreaming: true, streamingText: '');
  }

  /// Stop generating: what arrived so far is kept.
  void stop() {
    final sub = _sub;
    if (sub == null) return;
    unawaited(sub.cancel());
    _stopCurrent?.call();
  }

  // ─────────────────────────── Per message ───────────────────────────

  Future<void> copy(ChatMessage m) => Clipboard.setData(ClipboardData(text: m.text));

  Future<void> readAloud(ChatMessage m) async {
    final tts = ref.read(ttsProvider);
    if (tts.isSpeaking) {
      await tts.stop();
      return;
    }
    await tts.speak(ChatMarkdown.plainText(m.text), language: _settings.language, voice: _settings.ttsVoice);
  }

  // ─────────────────────────── Voice ───────────────────────────

  Dictation _dictationFor() {
    final speech = ref.read(liveControllerProvider.notifier).speech;
    if (speech != null) return SessionDictation(speech);
    return _standalone ??= StandaloneDictation(settings: _settings, models: ref.read(modelManagerProvider));
  }

  /// Push-to-talk down / mic button.
  Future<void> startDictation() async {
    if (state.recording || state.transcribing) return;
    final d = _dictation = _dictationFor();
    state = state.copyWith(recording: true, clearError: true);
    try {
      await d.begin();
    } catch (e) {
      _dictation = null;
      state = state.copyWith(recording: false, error: e is StateError ? e.message : '$e');
    }
  }

  /// Push-to-talk up / mic button again: the transcript lands in the
  /// composer at the caret, or is sent at once ("Send dictation at once").
  Future<void> stopDictation() async {
    final d = _dictation;
    if (d == null || !state.recording) return;
    _dictation = null;
    state = state.copyWith(recording: false, transcribing: true);
    String text;
    try {
      text = await d.end();
    } catch (e) {
      state = state.copyWith(transcribing: false, error: e is StateError ? e.message : '$e');
      return;
    }
    state = state.copyWith(transcribing: false);
    if (text.isEmpty) return;
    if (_settings.chatAutoSend) {
      await send(text);
      return;
    }
    final sel = input.selection;
    final (next, caret) = insertDictation(input.text, text, caret: sel.isValid ? sel.baseOffset : null);
    input.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: caret),
    );
  }

  Future<void> toggleDictation() => state.recording ? stopDictation() : startDictation();
}

final chatControllerProvider = NotifierProvider<ChatController, ChatState>(ChatController.new);

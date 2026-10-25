import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/design/icons.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../core/platform/window_service.dart';
import '../../core/widgets/buttons.dart';
import '../../data/models/chat.dart';
import '../../data/models/settings.dart';
import '../../data/repositories.dart';
import '../../domain/forms/manual_answers.dart';
import '../../domain/forms/screen_text.dart';
import '../../domain/overlay/auto_height.dart';
import '../../l10n/l10n.dart';
import '../../services/ai/chat_service.dart';
import '../../services/ai/deepseek_models.dart';
import '../../services/ai/llm_client.dart';
import '../../services/screen/screen_service.dart';
import '../chat/chat_controller.dart' show captureForChat;
import '../chat/chat_widgets.dart' show ChatColors, MarkdownView;
import '../questionnaire/questionnaire_controller.dart';

// What the forms panel offers besides filling: the answers to fill in by
// hand when Sotto couldn't, and a chat about the form.

// ─────────────────────────── Manual answers ───────────────────────────

/// "Couldn't fill 3 — fill them in by hand" and "Copy all", over the
/// finished list.
class ManualAnswersBar extends ConsumerWidget {
  const ManualAnswersBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = context.overlayPalette;
    final l = context.l10n;
    final answers = ref.watch(questionnaireControllerProvider.select((q) => q.manualAnswers));
    final needed = ManualAnswers.needed(answers);
    final all = ManualAnswers.copyAll(answers);
    return Row(
      children: [
        Expanded(
          child: Text(
            needed > 0 ? l.formsManualTitle(needed) : l.formsManualAllFilled,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TypeScale.caption.copyWith(
              color: needed > 0 ? o.ink : o.inkAt(0.7),
              fontWeight: FontWeight.w600,
              shadows: const [],
            ),
          ),
        ),
        if (all.isNotEmpty)
          SottoButton(
            label: l.formsCopyAll,
            icon: SottoIcons.copy,
            variant: ButtonVariant.overlay,
            size: ButtonSize.small,
            onPressed: () => unawaited(Clipboard.setData(ClipboardData(text: all))),
          ),
      ],
    );
  }
}

/// One finished question: its number, the answer to put in (the option's
/// letter and text for a choice), a copy button — or a check when Sotto
/// filled it. Password and payment fields show neither answer nor copy.
class ManualAnswerRow extends StatelessWidget {
  const ManualAnswerRow({super.key, required this.answer});
  final ManualAnswer answer;

  @override
  Widget build(BuildContext context) {
    final o = context.overlayPalette;
    final l = context.l10n;
    final a = answer;
    final (icon, color) = a.done
        ? (SottoIcons.check, o.confirmed)
        : a.sensitive
        ? (SottoIcons.lock, o.capture)
        : a.manual
        ? (SottoIcons.cursor, o.cue)
        : (SottoIcons.close, o.inkAt(0.4));
    final detail = a.sensitive
        ? a.note
        : a.hasAnswer
        ? a.shown
        : (a.note.isEmpty ? l.formsNoSuggestion : a.note);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '${a.number}.',
              style: TypeScale.micro.copyWith(color: o.inkAt(0.55), fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Tooltip(
              message: a.done ? l.formsFilledTooltip : '',
              child: SottoIcon(icon, size: 11, color: color),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.question,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TypeScale.caption.copyWith(color: o.inkAt(0.62)),
                ),
                SelectableText(
                  detail,
                  style: TypeScale.body.copyWith(color: a.hasAnswer && !a.done ? o.ink : o.inkAt(0.55)),
                ),
              ],
            ),
          ),
          if (a.hasAnswer)
            SottoIconButton(
              icon: SottoIcons.copy,
              tooltip: l.formsCopyAnswer,
              overlay: true,
              size: 24,
              iconSize: 12,
              onPressed: () => unawaited(Clipboard.setData(ClipboardData(text: a.copyText))),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Panel chat ───────────────────────────

class FormChatState {
  const FormChatState({
    this.messages = const [],
    this.streamingId,
    this.streamingText = '',
    this.attachScreen = false,
    this.capturing = false,
    this.error,
  });

  final List<ChatMessage> messages;
  final String? streamingId;
  final String streamingText;
  final bool attachScreen;
  final bool capturing;
  final String? error;

  bool get streaming => streamingId != null;

  FormChatState copyWith({
    List<ChatMessage>? messages,
    String? streamingId,
    bool clearStreaming = false,
    String? streamingText,
    bool? attachScreen,
    bool? capturing,
    String? error,
    bool clearError = false,
  }) => FormChatState(
    messages: messages ?? this.messages,
    streamingId: clearStreaming ? null : (streamingId ?? this.streamingId),
    streamingText: streamingText ?? this.streamingText,
    attachScreen: attachScreen ?? this.attachScreen,
    capturing: capturing ?? this.capturing,
    error: clearError ? null : (error ?? this.error),
  );
}

/// The client the panel chat talks through (tests put a fake here).
final formChatClientProvider = Provider<Future<LlmClient?> Function()>(
  (ref) =>
      () => LlmClient.forSettings(ref.read(settingsProvider), ref.read(secretStoreProvider)),
);

/// The forms panel's chat: follow-up questions about the form on screen
/// ("why this answer?", "answer question 4 in English"). [ChatService] with
/// the form as context ([ManualAnswers.context]) and the forms' rules — no
/// graded tests, no passwords or payment details. Kept in memory only, and
/// started over with each new fill.
class FormChatController extends Notifier<FormChatState> {
  final input = TextEditingController();
  StreamSubscription<LlmDelta>? _sub;
  void Function()? _stopCurrent;
  LlmClient? _client;

  @override
  FormChatState build() {
    // A new fill starts with nothing read, and the panel closing ends it:
    // either way, a new conversation.
    ref.listen(questionnaireControllerProvider.select((q) => q.phase == FormPhase.reading && q.items.isEmpty), (
      was,
      fresh,
    ) {
      if (fresh && was != true) clear();
    });
    ref.listen(questionnaireControllerProvider.select((q) => q.active), (was, now) {
      if (was == true && !now) clear();
    });
    ref.onDispose(() {
      unawaited(_sub?.cancel());
      _client?.close();
      input.dispose();
    });
    return const FormChatState();
  }

  /// Sotto is typing into the form: the panel can't take the keyboard now.
  bool get busy => ref.read(questionnaireControllerProvider).inControl;

  void clear() {
    stop();
    state = const FormChatState();
    input.clear();
  }

  void toggleAttachScreen() => state = state.copyWith(attachScreen: !state.attachScreen);

  /// Whether the model screenshots go to reads images (`GET /models`).
  Future<bool> _readsImages(String model) async {
    try {
      return visionReadsImages(
        await ref.read(deepSeekModelsProvider.future).timeout(const Duration(seconds: 3)),
        model,
      );
    } catch (_) {
      return true;
    }
  }

  Future<void> send([String? text]) async {
    final body = (text ?? input.text).trim();
    if (body.isEmpty || state.streaming || busy) return;
    if (text == null) input.clear();
    final l = L10n.current;
    final settings = ref.read(settingsProvider);
    final client = _client ??= await ref.read(formChatClientProvider)();
    if (client == null) {
      state = state.copyWith(error: l.answerNeedsKey);
      return;
    }

    String? screenshot;
    String? screenText;
    if (state.attachScreen) {
      state = state.copyWith(capturing: true, clearError: true);
      try {
        if (await _readsImages(settings.visionModel)) {
          screenshot = await captureForChat(ref.read(screenServiceProvider), settings);
        } else {
          // A model that can't read images gets the screen's text, read on
          // this computer — never the image.
          final shot = await ref
              .read(screenServiceProvider)
              .capture(target: CaptureTarget.foregroundDisplay, ocr: true);
          screenText = OcrLine.parse(shot.ocr).map((l) => l.text).join('\n');
        }
      } on ScreenCaptureException catch (e) {
        state = state.copyWith(capturing: false, error: e.permissionDenied ? l.noticeScreenPermission : e.message);
        return;
      }
      state = state.copyWith(capturing: false, attachScreen: false);
    }

    final user = ChatMessage.user(body, hadScreen: screenshot != null || screenText != null);
    final reply = ChatMessage.assistant();
    final conversation = Conversation.create(Conversation.titleFrom(body))
        .copyWith(messages: [...state.messages, user]);
    state = state.copyWith(
      messages: [...conversation.messages, reply],
      streamingId: reply.id,
      streamingText: '',
      clearError: true,
    );
    // The form as it stands now: what was filled, what's left to the user.
    final form = [
      ManualAnswers.context(ref.read(questionnaireControllerProvider).manualAnswers),
      if (screenText != null && screenText.trim().isNotEmpty) "The screen's text now (OCR):\n$screenText",
    ].join('\n\n');

    final content = StringBuffer();
    var lastPaint = DateTime.fromMillisecondsSinceEpoch(0);
    final done = Completer<void>();
    void end({String? error, bool stopped = false}) {
      _finish(reply.id, content.toString(), error: error, stopped: stopped);
      if (!done.isCompleted) done.complete();
    }

    _sub = ChatService(client)
        .reply(conversation, maxMessages: settings.chatContextMessages, screenshot: screenshot, formContext: form)
        .listen(
          (d) {
            content.write(d.content);
            final now = DateTime.now();
            if (d.content.isNotEmpty && now.difference(lastPaint) > const Duration(milliseconds: 33)) {
              lastPaint = now;
              state = state.copyWith(streamingText: content.toString());
            }
          },
          onError: (Object e) => end(error: e is LlmException ? e.message : '$e'),
          onDone: end,
          cancelOnError: true,
        );
    _stopCurrent = () => end(stopped: true);
    await done.future;
  }

  void _finish(String id, String text, {String? error, bool stopped = false}) {
    _sub = null;
    _stopCurrent = null;
    if (!ref.mounted) return;
    state = state.copyWith(
      messages: [
        for (final m in state.messages)
          if (m.id == id) m.copyWith(text: text, error: text.isEmpty && !stopped ? error : null) else m,
      ],
      clearStreaming: true,
      streamingText: '',
    );
  }

  /// Stop generating: what arrived so far is kept.
  void stop() {
    final sub = _sub;
    if (sub == null) return;
    unawaited(sub.cancel());
    _stopCurrent?.call();
  }
}

final formChatControllerProvider = NotifierProvider<FormChatController, FormChatState>(FormChatController.new);

/// The chat at the bottom of the compact forms panel: the last messages
/// and an input that takes the keyboard only once clicked — and never
/// while Sotto is typing into the form.
class FormChat extends ConsumerStatefulWidget {
  const FormChat({super.key});

  /// The most the messages take before they scroll.
  static const messagesHeight = 150.0;

  @override
  ConsumerState<FormChat> createState() => _FormChatState();
}

class _FormChatState extends ConsumerState<FormChat> {
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => unawaited(setOverlayKeyboard(_focus.hasFocus)));
  }

  @override
  void dispose() {
    if (_focus.hasFocus) unawaited(setOverlayKeyboard(false));
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyDownEvent &&
        (e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.numpadEnter) &&
        !HardwareKeyboard.instance.isShiftPressed) {
      _send();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _send() {
    unawaited(ref.read(formChatControllerProvider.notifier).send());
    // The keyboard goes back to the form once the question is on its way.
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final colors = ChatColors.of(context, overlay: true);
    final s = ref.watch(formChatControllerProvider);
    final c = ref.read(formChatControllerProvider.notifier);
    final busy = ref.watch(questionnaireControllerProvider.select((q) => q.inControl));
    if (busy && _focus.hasFocus) _focus.unfocus();

    Widget icon(SottoIcons i, String tip, VoidCallback? onTap, {bool selected = false}) => SottoIconButton(
      icon: i,
      tooltip: tip,
      size: 26,
      iconSize: 13,
      overlay: true,
      selected: selected,
      onPressed: onTap,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (s.messages.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: FormChat.messagesHeight),
            child: ListView.builder(
              reverse: true,
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 6),
              itemCount: s.messages.length,
              itemBuilder: (context, i) {
                final m = s.messages[s.messages.length - 1 - i];
                return _FormChatMessage(
                  key: ValueKey(m.id),
                  message: m,
                  colors: colors,
                  streamingText: m.id == s.streamingId ? s.streamingText : null,
                );
              },
            ),
          ),
        if (s.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(s.error!, style: TypeScale.micro.copyWith(color: colors.error)),
          ),
        Container(
          padding: const EdgeInsets.fromLTRB(10, 2, 4, 2),
          decoration: BoxDecoration(
            color: colors.field,
            borderRadius: Radii.rL,
            border: Border.all(color: colors.faint.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: c.input,
                  focusNode: _focus,
                  enabled: !busy,
                  minLines: 1,
                  maxLines: 3,
                  keyboardType: TextInputType.multiline,
                  style: TypeScale.caption.copyWith(color: colors.ink),
                  cursorColor: colors.accent,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    hintText: busy ? l.formsChatBusy : l.formsChatPlaceholder,
                    hintStyle: TypeScale.caption.copyWith(color: colors.faint),
                  ),
                ),
              ),
              icon(
                SottoIcons.display,
                l.chatAttachScreen,
                busy ? null : c.toggleAttachScreen,
                selected: s.attachScreen,
              ),
              if (s.streaming)
                icon(SottoIcons.stop, l.chatStop, c.stop)
              else
                icon(SottoIcons.send, l.chatSend, busy || s.capturing ? null : _send),
            ],
          ),
        ),
      ],
    );
  }
}

class _FormChatMessage extends StatelessWidget {
  const _FormChatMessage({super.key, required this.message, required this.colors, this.streamingText});
  final ChatMessage message;
  final ChatColors colors;
  final String? streamingText;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    if (message.role == ChatRole.user) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6, left: 40),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: colors.userBubble, borderRadius: Radii.rL),
          child: Text(message.text, style: TypeScale.caption.copyWith(color: colors.ink)),
        ),
      );
    }
    final text = streamingText ?? message.text;
    final streaming = streamingText != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: message.error != null
                ? Text(message.error!, style: TypeScale.caption.copyWith(color: colors.error))
                : text.isEmpty && streaming
                ? Text(l.chatThinking, style: TypeScale.caption.copyWith(color: colors.faint))
                : MarkdownView(text: text, colors: colors, compact: true),
          ),
          if (!streaming && message.text.isNotEmpty)
            SottoIconButton(
              icon: SottoIcons.copy,
              tooltip: l.chatCopy,
              size: 24,
              iconSize: 12,
              overlay: true,
              onPressed: () => unawaited(Clipboard.setData(ClipboardData(text: message.text))),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Window size ───────────────────────────

/// The floating forms panel is as tall as what it shows — up to
/// [AutoHeight.panelMax] or 60 % of the display, past which its list
/// scrolls — and grows away from the screen edge it is nearer, so it stays
/// where the presenter put it. Its [child] must size itself to its content
/// (a min-size column with shrink-wrapped lists).
///
/// Once the presenter drags its edges, or Snap Assist tiles it, the window
/// keeps that size and [child] gets all of it; dragged out of the snap, it
/// follows its content again. A dragged width is remembered for next time.
class PanelWindowFit extends ConsumerStatefulWidget {
  const PanelWindowFit({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<PanelWindowFit> createState() => _PanelWindowFitState();
}

class _PanelWindowFitState extends ConsumerState<PanelWindowFit> with WindowListener {
  double _cap = AutoHeight.panelMax;
  double? _asked;

  /// The presenter dragged an edge: their size stands for this panel.
  bool _sized = false;

  /// Snap Assist holds the window at a half or a quarter of the screen.
  bool _snapped = false;

  bool _fitting = false;

  /// The content's last height, and the window's size last frame.
  double? _content;
  Size? _windowSize;

  bool get _held => _sized || _snapped;

  WindowService get _window => ref.read(windowServiceProvider);

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(_readCap());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowResized() => unawaited(_onUserResize());

  // A drag that ends in a snap zone, or out of one.
  @override
  void onWindowMoved() => unawaited(_checkSnap());

  // Never maximised or full screen — only tiled to part of the screen.
  @override
  void onWindowMaximize() => unawaited(_window.undoFill());

  @override
  void onWindowEnterFullScreen() => unawaited(_window.undoFill());

  Future<void> _onUserResize() async {
    if (!_window.isOverlay || await _window.isArranged()) return;
    final b = await _window.bounds();
    if (!mounted) return;
    setState(() => _sized = true);
    _window.noteFrame(b);
    final width = b.width.clamp(AppSettings.panelWidthMin, AppSettings.panelWidthMax);
    ref.read(settingsProvider.notifier).update((s) => s.copyWith(panelWidth: width));
  }

  /// Snapped (by a drag or Win + arrow, which sends no event of its own —
  /// hence also on every size change that isn't ours): hold the size. Out of
  /// the snap: follow the content again.
  Future<void> _checkSnap() async {
    if (!_window.isOverlay) return;
    final snapped = await _window.isArranged();
    if (!mounted || snapped == _snapped) return;
    setState(() => _snapped = snapped);
    if (!snapped) {
      _asked = null;
      final c = _content;
      if (c != null && !_sized) unawaited(_fit(c));
    }
  }

  Future<void> _readCap() async {
    if (!_window.isOverlay) return;
    final area = await _window.displayArea();
    if (!mounted) return;
    setState(() => _cap = AutoHeight.panelCap(area.height));
  }

  Future<void> _fit(double content) async {
    _content = content;
    if (!mounted || !_window.isOverlay || _held) return;
    final duration = context.motion(Motion.overlayFit);
    final area = await _window.displayArea();
    final target = AutoHeight.panel(content, screenHeight: area.height);
    if (_asked != null && (target - _asked!).abs() < 2) return;
    _asked = target;
    final b = await _window.bounds();
    // Down from where it sits, unless it's in the lower half or would run
    // off the bottom: then up, its bottom edge staying put.
    final fromBottom = !OverlayGeometry.nearTop(b, area) || b.top + target > area.bottom;
    _fitting = true;
    try {
      await _window.animateHeight(target, fromBottom: fromBottom, duration: duration);
    } finally {
      _fitting = false;
    }
  }

  void _onWindowSize(Size size) {
    final was = _windowSize;
    _windowSize = size;
    if (was == null || _fitting || ((was.width - size.width).abs() < 2 && (was.height - size.height).abs() < 2)) return;
    unawaited(_checkSnap());
  }

  @override
  Widget build(BuildContext context) {
    final window = MediaQuery.sizeOf(context);
    if (window != _windowSize) SchedulerBinding.instance.addPostFrameCallback((_) => _onWindowSize(window));
    final reporter = _SizeReporter(onSize: (s) => unawaited(_fit(s.height)), child: widget.child);
    // Held: the window's size is the presenter's (or Snap Assist's); the
    // content takes it, its list scrolling when there's more.
    if (_held) return Align(alignment: Alignment.topCenter, child: reporter);
    return OverflowBox(alignment: Alignment.topCenter, minHeight: 0, maxHeight: _cap, child: reporter);
  }
}

class _SizeReporter extends SingleChildRenderObjectWidget {
  const _SizeReporter({required this.onSize, super.child});
  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSizeReporter(onSize);

  @override
  void updateRenderObject(BuildContext context, _RenderSizeReporter renderObject) => renderObject.onSize = onSize;
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onSize);
  ValueChanged<Size> onSize;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _reported) return;
    final s = _reported = size;
    SchedulerBinding.instance.addPostFrameCallback((_) => onSize(s));
  }
}

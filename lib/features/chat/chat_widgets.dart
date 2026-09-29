import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/icons.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../core/platform/platform_keys.dart';
import '../../core/platform/window_service.dart';
import '../../core/widgets/buttons.dart';
import '../../data/models/chat.dart';
import '../../data/models/shortcut.dart';
import '../../data/repositories.dart';
import '../../domain/chat/markdown.dart';
import '../../l10n/l10n.dart';
import 'chat_controller.dart';

/// Colours for the chat in either home: the main window or the overlay.
class ChatColors {
  const ChatColors({
    required this.ink,
    required this.soft,
    required this.faint,
    required this.userBubble,
    required this.code,
    required this.accent,
    required this.error,
    required this.field,
    required this.overlay,
  });

  final Color ink;
  final Color soft;
  final Color faint;
  final Color userBubble;
  final Color code;
  final Color accent;
  final Color error;
  final Color field;
  final bool overlay;

  factory ChatColors.of(BuildContext context, {required bool overlay}) {
    if (overlay) {
      final o = context.overlayPalette;
      return ChatColors(
        ink: o.ink,
        soft: o.inkAt(0.7),
        faint: o.inkAt(0.45),
        userBubble: o.inkAt(0.1),
        code: o.inkAt(0.08),
        accent: o.cue,
        error: o.capture,
        field: o.inkAt(0.07),
        overlay: true,
      );
    }
    final p = context.palette;
    return ChatColors(
      ink: p.inkPrimary,
      soft: p.inkSecondary,
      faint: p.inkTertiary,
      userBubble: p.raised,
      code: p.panel,
      accent: p.cueText,
      error: p.liveCapture,
      field: p.panel,
      overlay: false,
    );
  }
}

/// Markdown for replies: bold, italic, inline code, lists, headings and
/// code blocks (monospace, with a copy button).
class MarkdownView extends StatelessWidget {
  const MarkdownView({super.key, required this.text, required this.colors, this.compact = false});

  final String text;
  final ChatColors colors;
  final bool compact;

  TextSpan _spans(String s, TextStyle base) => TextSpan(
    children: [
      for (final span in ChatMarkdown.inline(s))
        TextSpan(
          text: span.text,
          style: switch (span.style) {
            MdStyle.bold => base.copyWith(fontWeight: FontWeight.w700),
            MdStyle.italic => base.copyWith(fontStyle: FontStyle.italic),
            MdStyle.code => TypeScale.mono.copyWith(
              color: colors.ink,
              fontSize: (base.fontSize ?? 14) - 1,
              backgroundColor: colors.code,
            ),
            MdStyle.plain => base,
          },
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final base = (compact ? TypeScale.caption : TypeScale.body).copyWith(color: colors.ink, height: 1.45);
    final blocks = ChatMarkdown.parse(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final b in blocks)
          Padding(
            padding: EdgeInsets.only(bottom: compact ? 4 : 8),
            child: switch (b.type) {
              MdBlockType.paragraph => SelectableText.rich(_spans(b.text, base)),
              MdBlockType.heading => SelectableText.rich(
                _spans(
                  b.text,
                  base.copyWith(fontWeight: FontWeight.w700, fontSize: (base.fontSize ?? 14) + (b.level <= 2 ? 2 : 0)),
                ),
              ),
              MdBlockType.bullet || MdBlockType.numbered => Padding(
                padding: EdgeInsets.only(left: 14.0 * b.level),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: b.type == MdBlockType.bullet ? 14 : 22,
                      child: Text(
                        b.type == MdBlockType.bullet ? '•' : '${b.number}.',
                        style: base.copyWith(color: colors.soft),
                      ),
                    ),
                    Expanded(child: SelectableText.rich(_spans(b.text, base))),
                  ],
                ),
              ),
              MdBlockType.code => _CodeBlock(code: b.text, colors: colors),
            },
          ),
      ],
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.code, required this.colors});
  final String code;
  final ChatColors colors;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(12, 8, 6, 10),
    decoration: BoxDecoration(color: colors.code, borderRadius: Radii.rM),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(code, style: TypeScale.mono.copyWith(color: colors.ink, fontSize: 12.5, height: 1.5)),
          ),
        ),
        SottoIconButton(
          icon: SottoIcons.copy,
          tooltip: context.l10n.chatCopy,
          size: 24,
          iconSize: 12,
          overlay: colors.overlay,
          onPressed: () => unawaited(Clipboard.setData(ClipboardData(text: code))),
        ),
      ],
    ),
  );
}

/// One message: the user's in a bubble on the right, replies full width
/// with copy and read-aloud.
class MessageTile extends ConsumerWidget {
  const MessageTile({super.key, required this.message, required this.colors, this.streamingText, this.compact = false});

  final ChatMessage message;
  final ChatColors colors;

  /// The text so far while this reply streams in.
  final String? streamingText;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = ref.read(chatControllerProvider.notifier);
    if (message.role == ChatRole.user) {
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: compact ? 420 : 560),
          child: Container(
            margin: EdgeInsets.only(bottom: compact ? 8 : 14, left: 40),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: colors.userBubble, borderRadius: Radii.rL),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SelectableText(
                  message.text,
                  style: (compact ? TypeScale.caption : TypeScale.body).copyWith(color: colors.ink),
                ),
                if (message.hadScreen)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SottoIcon(SottoIcons.display, size: 11, color: colors.faint),
                        const SizedBox(width: 4),
                        Text(l.chatScreenAttached, style: TypeScale.micro.copyWith(color: colors.faint)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    final text = streamingText ?? message.text;
    final streaming = streamingText != null;
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 10 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.error != null)
            Text(message.error!, style: TypeScale.body.copyWith(color: colors.error))
          else if (text.isEmpty && streaming)
            Text(l.chatThinking, style: TypeScale.caption.copyWith(color: colors.faint))
          else
            MarkdownView(text: text, colors: colors, compact: compact),
          if (!streaming && message.text.isNotEmpty)
            Row(
              children: [
                SottoIconButton(
                  icon: SottoIcons.copy,
                  tooltip: l.chatCopy,
                  size: 24,
                  iconSize: 12,
                  overlay: colors.overlay,
                  onPressed: () => unawaited(c.copy(message)),
                ),
                SottoIconButton(
                  icon: SottoIcons.speaker,
                  tooltip: l.chatReadAloud,
                  size: 24,
                  iconSize: 12,
                  overlay: colors.overlay,
                  onPressed: () => unawaited(c.readAloud(message)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// The input: Enter sends, Shift+Enter is a new line; microphone, attach
/// screen, stop. In the overlay it takes the keyboard only while focused.
class ChatComposer extends ConsumerStatefulWidget {
  const ChatComposer({super.key, required this.colors, this.compact = false});

  final ChatColors colors;
  final bool compact;

  @override
  ConsumerState<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends ConsumerState<ChatComposer> {
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);

  @override
  void initState() {
    super.initState();
    if (widget.colors.overlay) {
      // Zoom / PowerPoint keep the keyboard until the input is clicked.
      _focus.addListener(() => unawaited(setOverlayKeyboard(_focus.hasFocus)));
    }
  }

  @override
  void dispose() {
    if (widget.colors.overlay && _focus.hasFocus) unawaited(setOverlayKeyboard(false));
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
    unawaited(ref.read(chatControllerProvider.notifier).send());
    // The overlay gives the keyboard back once the message is on its way.
    if (widget.colors.overlay) _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final colors = widget.colors;
    final s = ref.watch(chatControllerProvider);
    final c = ref.read(chatControllerProvider.notifier);
    final settings = ref.watch(settingsProvider);
    final talk = PlatformKeys.describe(settings.shortcutFor(LiveAction.pushToTalk));

    Widget icon(SottoIcons i, String tip, VoidCallback? onTap, {bool selected = false}) => SottoIconButton(
      icon: i,
      tooltip: tip,
      size: widget.compact ? 26 : 30,
      iconSize: widget.compact ? 13 : 15,
      overlay: colors.overlay,
      selected: selected,
      onPressed: onTap,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: colors.field,
        borderRadius: Radii.rL,
        border: Border.all(color: s.recording ? colors.error : colors.faint.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: c.input,
              focusNode: _focus,
              minLines: 1,
              maxLines: widget.compact ? 3 : 8,
              keyboardType: TextInputType.multiline,
              style: (widget.compact ? TypeScale.caption : TypeScale.body).copyWith(color: colors.ink),
              cursorColor: colors.accent,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                hintText: s.recording
                    ? l.chatListening
                    : (s.transcribing ? l.chatTranscribing : l.chatPlaceholder(talk)),
                hintStyle: TypeScale.caption.copyWith(color: s.recording ? colors.error : colors.faint),
              ),
            ),
          ),
          icon(
            SottoIcons.mic,
            s.recording ? l.chatStopDictation : l.chatDictate(talk),
            s.transcribing ? null : () => unawaited(c.toggleDictation()),
            selected: s.recording,
          ),
          icon(SottoIcons.display, l.chatAttachScreen, c.toggleAttachScreen, selected: s.attachScreen),
          if (s.streaming) icon(SottoIcons.stop, l.chatStop, c.stop) else icon(SottoIcons.send, l.chatSend, _send),
        ],
      ),
    );
  }
}

/// Think deeper · Use my script — the conversation's switches.
class ChatToggles extends ConsumerWidget {
  const ChatToggles({super.key, required this.conversation, required this.colors});
  final Conversation? conversation;
  final ChatColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = ref.read(chatControllerProvider.notifier);
    final s = ref.watch(chatControllerProvider);
    final conv = conversation;
    final script = c.contextScript();
    final think = conv?.thinkDeeper ?? s.newThinkDeeper;
    final useScript = conv?.useScript ?? s.newUseScript;
    Widget chip(String label, bool on, VoidCallback? onTap) => GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: on ? colors.accent.withValues(alpha: 0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: on ? colors.accent : colors.faint.withValues(alpha: 0.4)),
          ),
          child: Text(label, style: TypeScale.micro.copyWith(color: on ? colors.accent : colors.soft)),
        ),
      ),
    );
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        chip(l.chatThinkDeeper, think, () => unawaited(c.toggleThinkDeeper())),
        chip(
          script == null ? l.chatUseScript : l.chatUseScriptNamed(script.title),
          useScript && script != null,
          script == null ? null : () => unawaited(c.toggleUseScript()),
        ),
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/icons.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/controls.dart';
import '../../core/widgets/interactive.dart';
import '../../data/models/chat.dart';
import '../../data/repositories.dart';
import '../../l10n/l10n.dart';
import '../library/library_shell.dart' show LibraryHeader;
import 'chat_controller.dart';
import 'chat_widgets.dart';

/// Chat in the main window: conversations on the left, the open one on
/// the right.
class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final l = context.l10n;
    final conversations = ref.watch(conversationsProvider).value ?? const <Conversation>[];
    final s = ref.watch(chatControllerProvider);
    final c = ref.read(chatControllerProvider.notifier);
    final current = conversations.where((x) => x.id == s.conversationId).firstOrNull;

    return Column(
      children: [
        LibraryHeader(
          title: l.navChat,
          actions: [
            SottoButton(label: l.chatNew, icon: SottoIcons.plus, size: ButtonSize.small, onPressed: c.newConversation),
          ],
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 250,
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: p.hairline)),
                ),
                child: conversations.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(l.chatNoConversations, style: TypeScale.caption.copyWith(color: p.inkTertiary)),
                      )
                    : ListView(
                        padding: const EdgeInsets.all(10),
                        children: [
                          for (final conv in conversations)
                            _ConversationRow(conversation: conv, selected: conv.id == s.conversationId),
                        ],
                      ),
              ),
              Expanded(child: _ConversationView(conversation: current)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConversationRow extends ConsumerWidget {
  const _ConversationRow({required this.conversation, required this.selected});
  final Conversation conversation;
  final bool selected;

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final text = TextEditingController(text: conversation.title);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        final p = context.palette;
        return AlertDialog(
          backgroundColor: p.float,
          shape: RoundedRectangleBorder(
            borderRadius: Radii.rL,
            side: BorderSide(color: p.control),
          ),
          title: Text(l.chatRename, style: TypeScale.title3.copyWith(color: p.inkPrimary)),
          content: SizedBox(
            width: 360,
            child: SottoTextField(controller: text, autofocus: true, onSubmitted: (_) => Navigator.pop(context, true)),
          ),
          actions: [
            SottoButton(label: l.cancel, onPressed: () => Navigator.pop(context, false)),
            SottoButton(label: l.save, variant: ButtonVariant.primary, onPressed: () => Navigator.pop(context, true)),
          ],
        );
      },
    );
    if (ok ?? false) await ref.read(chatControllerProvider.notifier).rename(conversation.id, text.text);
    text.dispose();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final l = context.l10n;
    final c = ref.read(chatControllerProvider.notifier);
    return Interactive(
      onTap: () => c.select(conversation.id),
      builder: (context, st) => Container(
        height: 34,
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.only(left: 10, right: 2),
        decoration: BoxDecoration(
          color: selected ? p.float : (st.hovered ? p.hoverWash : Colors.transparent),
          borderRadius: Radii.rControl,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                conversation.title.isEmpty ? l.chatUntitled : conversation.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (selected ? TypeScale.bodyStrong : TypeScale.body).copyWith(color: p.inkPrimary),
              ),
            ),
            if (st.hovered || selected) ...[
              SottoIconButton(
                icon: SottoIcons.doc,
                tooltip: l.chatRename,
                size: 24,
                iconSize: 12,
                onPressed: () => unawaited(_rename(context, ref)),
              ),
              SottoIconButton(
                icon: SottoIcons.close,
                tooltip: l.delete,
                size: 24,
                iconSize: 12,
                onPressed: () => unawaited(c.delete(conversation.id)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConversationView extends ConsumerWidget {
  const _ConversationView({required this.conversation});
  final Conversation? conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final l = context.l10n;
    final s = ref.watch(chatControllerProvider);
    final colors = ChatColors.of(context, overlay: false);
    final messages = conversation?.messages ?? const <ChatMessage>[];

    return Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SottoIcon(SottoIcons.chat, size: 28, color: p.inkTertiary),
                        const SizedBox(height: 12),
                        Text(l.chatEmptyTitle, style: TypeScale.title3.copyWith(color: p.inkPrimary)),
                        const SizedBox(height: 6),
                        Text(
                          l.chatEmptyBody,
                          textAlign: TextAlign.center,
                          style: TypeScale.body.copyWith(color: p.inkSecondary),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(32, 24, 32, 12),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final m = messages[messages.length - 1 - i];
                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: MessageTile(
                          key: ValueKey(m.id),
                          message: m,
                          colors: colors,
                          streamingText: m.id == s.streamingId ? s.streamingText : null,
                        ),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 4, 32, 20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (s.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(s.error!, style: TypeScale.caption.copyWith(color: colors.error)),
                    ),
                  ChatToggles(conversation: conversation, colors: colors),
                  const SizedBox(height: 8),
                  ChatComposer(colors: colors),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

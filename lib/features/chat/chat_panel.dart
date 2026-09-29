import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/icons.dart';
import '../../core/design/typography.dart';
import '../../core/platform/platform_keys.dart';
import '../../core/widgets/buttons.dart';
import '../../data/models/chat.dart';
import '../../data/models/shortcut.dart';
import '../../data/repositories.dart';
import '../../l10n/l10n.dart';
import 'chat_controller.dart';
import 'chat_widgets.dart';

/// The compact chat in the live overlay (chord + C), in the overlay's own
/// style. The last messages, the switches and the composer — which takes
/// the keyboard only once clicked.
class ChatPanel extends ConsumerWidget {
  const ChatPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final s = ref.watch(chatControllerProvider);
    final c = ref.read(chatControllerProvider.notifier);
    final colors = ChatColors.of(context, overlay: true);
    // Rebuild as the conversation is saved.
    final conversations = ref.watch(conversationsProvider).value ?? const <Conversation>[];
    final conv = conversations.where((x) => x.id == s.conversationId).firstOrNull;
    final messages = conv?.messages ?? const <ChatMessage>[];
    final keys = PlatformKeys.describe(ref.watch(settingsProvider).shortcutFor(LiveAction.openChat));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SottoIcon(SottoIcons.chat, size: 13, color: colors.soft),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  conv?.title ?? l.chatNew,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TypeScale.caption.copyWith(color: colors.soft, fontWeight: FontWeight.w600),
                ),
              ),
              SottoIconButton(
                icon: SottoIcons.plus,
                tooltip: l.chatNew,
                overlay: true,
                size: 24,
                iconSize: 12,
                onPressed: c.newConversation,
              ),
              SottoIconButton(
                icon: SottoIcons.close,
                tooltip: '${l.close}  $keys',
                overlay: true,
                size: 24,
                iconSize: 12,
                onPressed: c.closeOverlay,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Text(
                      l.chatPanelEmpty,
                      textAlign: TextAlign.center,
                      style: TypeScale.caption.copyWith(color: colors.faint),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: EdgeInsets.zero,
                    itemCount: messages.length,
                    itemBuilder: (context, i) {
                      final m = messages[messages.length - 1 - i];
                      return MessageTile(
                        key: ValueKey(m.id),
                        message: m,
                        colors: colors,
                        compact: true,
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
          ChatToggles(conversation: conv, colors: colors),
          const SizedBox(height: 6),
          ChatComposer(colors: colors, compact: true),
        ],
      ),
    );
  }
}

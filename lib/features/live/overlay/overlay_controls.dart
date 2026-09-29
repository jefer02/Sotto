import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';

import '../../../core/design/icons.dart';
import '../../../core/design/theme.dart';
import '../../../core/design/tokens.dart';
import '../../../core/platform/platform_keys.dart';
import '../../../core/widgets/buttons.dart';
import '../../../data/models/shortcut.dart';
import '../../../data/repositories.dart';
import '../live_controller.dart';
import '../live_state.dart';
import '../../chat/chat_controller.dart';
import '../../questionnaire/questionnaire_controller.dart';

/// The hover toolbar. Appears after 150 ms of hover intent, hides 800 ms
/// after the pointer leaves, and never appears from keyboard use — hotkeys
/// stay invisible.
class OverlayControls extends ConsumerWidget {
  const OverlayControls({super.key, required this.state, required this.onEnd});

  final LiveState state;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = context.overlayPalette;
    final c = ref.read(liveControllerProvider.notifier);
    final settings = ref.watch(settingsProvider);
    String tip(String label, LiveAction a) => '$label  ${PlatformKeys.describe(settings.shortcutFor(a))}';
    final paused = state.phase == LivePhase.paused;

    Widget b(SottoIcons icon, String tooltip, VoidCallback onTap, {bool selected = false}) => SottoIconButton(
      icon: icon,
      tooltip: tooltip,
      overlay: true,
      selected: selected,
      size: 28,
      iconSize: 14,
      onPressed: onTap,
    );

    Widget divider() =>
        Container(width: 1, height: 16, margin: const EdgeInsets.symmetric(horizontal: 4), color: o.inkAt(0.12));

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Color.alphaBlend(o.inkAt(0.06), o.chromeGround.withValues(alpha: 0.96)),
        borderRadius: Radii.rM,
        border: Border.all(color: o.inkAt(0.1)),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          b(SottoIcons.up, tip(LiveAction.previousBeat.title, LiveAction.previousBeat), c.previousBeat),
          b(
            paused ? SottoIcons.play : SottoIcons.pause,
            tip(paused ? context.l10n.resume : context.l10n.pause, LiveAction.pauseResume),
            c.togglePause,
          ),
          b(SottoIcons.down, tip(LiveAction.nextBeat.title, LiveAction.nextBeat), c.nextBeat),
          divider(),
          b(
            SottoIcons.ask,
            tip(LiveAction.ask.title, LiveAction.ask),
            c.askDown,
            selected: state.phase == LivePhase.listening,
          ),
          b(
            SottoIcons.chat,
            tip(LiveAction.openChat.title, LiveAction.openChat),
            ref.read(chatControllerProvider.notifier).toggleOverlay,
            selected: ref.watch(chatControllerProvider.select((c) => c.overlayOpen)),
          ),
          if (settings.formsEnabled)
            b(
              SottoIcons.form,
              tip(LiveAction.fillForm.title, LiveAction.fillForm),
              () => ref.read(questionnaireControllerProvider.notifier).start(),
            ),
          b(
            SottoIcons.history,
            tip(context.l10n.questions, LiveAction.history),
            c.toggleHistory,
            selected: state.historyOpen,
          ),
          divider(),
          b(SottoIcons.onTop, tip(LiveAction.moveDisplay.title, LiveAction.moveDisplay), () => c.moveDisplay()),
          b(
            SottoIcons.cursor,
            tip(LiveAction.clickThrough.title, LiveAction.clickThrough),
            () => c.toggleClickThrough(),
            selected: state.clickThrough,
          ),
          b(SottoIcons.eyeOff, tip(context.l10n.hideInstantly, LiveAction.hide), () => c.toggleHidden()),
          divider(),
          b(SottoIcons.close, tip(context.l10n.endSession, LiveAction.goLive), onEnd),
        ],
      ),
    );
  }
}

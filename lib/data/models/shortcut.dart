import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';

enum ShortcutModifier { control, alt, shift, meta }

/// A concrete key combination. Stored by physical key (USB HID usage) so a
/// binding survives keyboard-layout changes.
class Shortcut {
  const Shortcut(this.modifiers, this.physicalKey);

  final Set<ShortcutModifier> modifiers;
  final int physicalKey;

  PhysicalKeyboardKey get key => PhysicalKeyboardKey(physicalKey);

  Map<String, Object?> toJson() => {'mods': modifiers.map((m) => m.name).toList(), 'key': physicalKey};

  factory Shortcut.fromJson(Map<dynamic, dynamic> json) => Shortcut({
    for (final m in (json['mods'] as List? ?? const [])) ShortcutModifier.values.byName(m as String),
  }, json['key'] as int);

  @override
  bool operator ==(Object other) =>
      other is Shortcut &&
      other.physicalKey == physicalKey &&
      other.modifiers.length == modifiers.length &&
      other.modifiers.containsAll(modifiers);

  @override
  int get hashCode => Object.hash(physicalKey, Object.hashAllUnordered(modifiers));
}

enum ShortcutGroup { live, answers, overlay }

/// Every live action. Defaults come from the "Settings — shortcuts" board.
enum LiveAction {
  goLive(ShortcutGroup.live, PhysicalKeyboardKey.keyL),
  pauseResume(ShortcutGroup.live, PhysicalKeyboardKey.space),
  nextBeat(ShortcutGroup.live, PhysicalKeyboardKey.arrowDown),
  previousBeat(ShortcutGroup.live, PhysicalKeyboardKey.arrowUp),
  nextSection(ShortcutGroup.live, PhysicalKeyboardKey.arrowRight),
  previousSection(ShortcutGroup.live, PhysicalKeyboardKey.arrowLeft),
  ask(ShortcutGroup.answers, PhysicalKeyboardKey.keyQ),
  sendToChat(ShortcutGroup.answers, PhysicalKeyboardKey.enter),
  readAloud(ShortcutGroup.answers, PhysicalKeyboardKey.keyR),
  dismiss(ShortcutGroup.answers, PhysicalKeyboardKey.keyX),
  history(ShortcutGroup.answers, PhysicalKeyboardKey.keyH),
  hide(ShortcutGroup.overlay, PhysicalKeyboardKey.keyO),
  clickThrough(ShortcutGroup.overlay, PhysicalKeyboardKey.keyT),
  textBigger(ShortcutGroup.overlay, PhysicalKeyboardKey.equal),
  textSmaller(ShortcutGroup.overlay, PhysicalKeyboardKey.minus),
  moveDisplay(ShortcutGroup.overlay, PhysicalKeyboardKey.keyM);

  const LiveAction(this.group, this.defaultKey);

  final ShortcutGroup group;
  final PhysicalKeyboardKey defaultKey;

  String get title {
    final l = L10n.current;
    return switch (this) {
      goLive => l.actionGoLive,
      pauseResume => l.actionPause,
      nextBeat => l.actionNextBeat,
      previousBeat => l.actionPrevBeat,
      nextSection => l.actionNextSection,
      previousSection => l.actionPrevSection,
      ask => l.actionAsk,
      sendToChat => l.actionSend,
      readAloud => l.actionReadAloud,
      dismiss => l.actionDismiss,
      history => l.actionHistory,
      hide => l.actionHide,
      clickThrough => l.actionClickThrough,
      textBigger => l.actionTextBigger,
      textSmaller => l.actionTextSmaller,
      moveDisplay => l.actionMoveDisplay,
    };
  }

  String? get subtitle {
    final l = L10n.current;
    return switch (this) {
      goLive => l.actionGoLiveSub,
      pauseResume => l.actionPauseSub,
      nextBeat => l.actionNextBeatSub,
      previousBeat => l.actionPrevBeatSub,
      ask => l.actionAskSub,
      sendToChat => l.actionSendSub,
      readAloud => l.actionReadAloudSub,
      dismiss => l.actionDismissSub,
      hide => l.actionHideSub,
      clickThrough => l.actionClickThroughSub,
      moveDisplay => l.actionMoveDisplaySub,
      _ => null,
    };
  }
}

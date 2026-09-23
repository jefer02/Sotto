import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../../data/models/shortcut.dart';
import '../../l10n/l10n.dart';

/// Human labels for shortcuts, in the host platform's vocabulary.
abstract final class PlatformKeys {
  static bool get isMac => Platform.isMacOS;

  static Set<ShortcutModifier> get defaultChord => {ShortcutModifier.control, ShortcutModifier.alt};

  static String modifierSymbol(ShortcutModifier m) => isMac
      ? switch (m) {
          ShortcutModifier.control => '⌃',
          ShortcutModifier.alt => '⌥',
          ShortcutModifier.shift => '⇧',
          ShortcutModifier.meta => '⌘',
        }
      : switch (m) {
          ShortcutModifier.control => 'Ctrl',
          ShortcutModifier.alt => 'Alt',
          ShortcutModifier.shift => L10n.current.modShiftShort,
          ShortcutModifier.meta => 'Win',
        };

  static String modifierName(ShortcutModifier m) => switch (m) {
    ShortcutModifier.control => 'Control',
    ShortcutModifier.alt => isMac ? L10n.current.modOption : 'Alt',
    ShortcutModifier.shift => L10n.current.modShift,
    ShortcutModifier.meta => isMac ? L10n.current.modCommand : 'Windows',
  };

  /// ⌘ on macOS, Ctrl elsewhere — for main-window (non-global) shortcuts.
  static String get primary => isMac ? '⌘' : 'Ctrl+';

  static const _order = [ShortcutModifier.control, ShortcutModifier.alt, ShortcutModifier.shift, ShortcutModifier.meta];

  static final Map<PhysicalKeyboardKey, String> _special = {
    PhysicalKeyboardKey.arrowUp: '↑',
    PhysicalKeyboardKey.arrowDown: '↓',
    PhysicalKeyboardKey.arrowLeft: '←',
    PhysicalKeyboardKey.arrowRight: '→',
    PhysicalKeyboardKey.enter: '↩',
    PhysicalKeyboardKey.escape: 'esc',
    PhysicalKeyboardKey.backspace: '⌫',
    PhysicalKeyboardKey.tab: '⇥',
    PhysicalKeyboardKey.equal: '=',
    PhysicalKeyboardKey.minus: '−',
    PhysicalKeyboardKey.comma: ',',
    PhysicalKeyboardKey.period: '.',
    PhysicalKeyboardKey.slash: '/',
    PhysicalKeyboardKey.pageUp: 'PgUp',
    PhysicalKeyboardKey.pageDown: 'PgDn',
  };

  static String keyLabel(PhysicalKeyboardKey key) {
    if (key == PhysicalKeyboardKey.space) return L10n.current.keySpace;
    final special = _special[key];
    if (special != null) return special;
    // From the USB HID usage — `debugName` is stripped in release builds.
    final usage = key.usbHidUsage & 0xFFFF;
    if (usage >= 0x04 && usage <= 0x1D) return String.fromCharCode(0x41 + usage - 0x04); // A–Z
    if (usage >= 0x1E && usage <= 0x26) return '${usage - 0x1D}'; // 1–9
    if (usage == 0x27) return '0';
    if (usage >= 0x3A && usage <= 0x45) return 'F${usage - 0x39}'; // F1–F12
    return '?';
  }

  static List<String> symbolsFor(Shortcut s) => [
    for (final m in _order)
      if (s.modifiers.contains(m)) modifierSymbol(m),
    keyLabel(s.key),
  ];

  static String describe(Shortcut s) => symbolsFor(s).join(isMac ? '' : '+');

  static bool isModifierKey(PhysicalKeyboardKey key) => _modifierKeys.contains(key);

  static final _modifierKeys = {
    PhysicalKeyboardKey.controlLeft,
    PhysicalKeyboardKey.controlRight,
    PhysicalKeyboardKey.altLeft,
    PhysicalKeyboardKey.altRight,
    PhysicalKeyboardKey.shiftLeft,
    PhysicalKeyboardKey.shiftRight,
    PhysicalKeyboardKey.metaLeft,
    PhysicalKeyboardKey.metaRight,
    PhysicalKeyboardKey.fn,
    PhysicalKeyboardKey.capsLock,
  };
}

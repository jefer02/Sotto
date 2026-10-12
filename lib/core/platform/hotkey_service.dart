import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../../data/models/settings.dart';
import '../../data/models/shortcut.dart';

typedef HotkeyHandlers = Map<LiveAction, ({VoidCallback onDown, VoidCallback? onUp})>;

/// System-wide shortcuts. They work while Zoom or the slides have focus —
/// the overlay never takes the keyboard.
class HotkeyService {
  final _registered = <LiveAction, HotKey>{};
  final Map<LiveAction, String> failures = {};
  Timer? _repeat;

  static const _repeating = {LiveAction.nextBeat, LiveAction.previousBeat};

  static HotKeyModifier _mod(ShortcutModifier m) => switch (m) {
    ShortcutModifier.control => HotKeyModifier.control,
    ShortcutModifier.alt => HotKeyModifier.alt,
    ShortcutModifier.shift => HotKeyModifier.shift,
    ShortcutModifier.meta => HotKeyModifier.meta,
  };

  static HotKey toHotKey(Shortcut s) =>
      HotKey(key: s.key, modifiers: [for (final m in s.modifiers) _mod(m)], scope: HotKeyScope.system);

  /// Registers [actions] (default: all). Returns the actions whose chord is
  /// already taken by the system or another app.
  Future<Map<LiveAction, String>> registerAll(
    AppSettings settings,
    HotkeyHandlers handlers, {
    Iterable<LiveAction>? actions,
  }) async {
    await unregisterAll();
    failures.clear();
    for (final action in actions ?? handlers.keys) {
      final h = handlers[action];
      if (h == null) continue;
      final hotKey = toHotKey(settings.shortcutFor(action));
      try {
        await hotKeyManager.register(
          hotKey,
          keyDownHandler: (_) {
            h.onDown();
            if (_repeating.contains(action)) {
              _repeat?.cancel();
              // "Holding the key repeats every 300 ms."
              _repeat = Timer(const Duration(milliseconds: 420), () {
                _repeat = Timer.periodic(const Duration(milliseconds: 300), (_) => h.onDown());
              });
            }
          },
          keyUpHandler: (_) {
            _repeat?.cancel();
            _repeat = null;
            h.onUp?.call();
          },
        );
        _registered[action] = hotKey;
      } catch (e) {
        failures[action] = '$e';
      }
    }
    return Map.of(failures);
  }

  /// Unregisters the live / idle set. Extras (the agent's emergency stop,
  /// its Enter / Esc confirmations) are left alone.
  Future<void> unregisterAll() async {
    _repeat?.cancel();
    _repeat = null;
    for (final hk in _registered.values) {
      try {
        await hotKeyManager.unregister(hk);
      } catch (_) {}
    }
    _registered.clear();
  }

  final _extras = <String, HotKey>{};

  /// A system-wide shortcut outside the live set, by [id]. Returns false if
  /// the chord is taken.
  Future<bool> registerExtra(String id, HotKey hotKey, VoidCallback onDown) async {
    await unregisterExtra(id);
    try {
      await hotKeyManager.register(hotKey, keyDownHandler: (_) => onDown());
      _extras[id] = hotKey;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> unregisterExtra(String id) async {
    final hk = _extras.remove(id);
    if (hk == null) return;
    try {
      await hotKeyManager.unregister(hk);
    } catch (_) {}
  }

  /// Probes whether a chord can be registered — used by the shortcut
  /// recorder to flag conflicts before saving.
  static Future<bool> isAvailable(Shortcut s) async {
    final hk = toHotKey(s);
    try {
      await hotKeyManager.register(hk);
      await hotKeyManager.unregister(hk);
      return true;
    } catch (_) {
      return false;
    }
  }
}

final hotkeyServiceProvider = Provider<HotkeyService>((ref) => HotkeyService());

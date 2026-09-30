import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/agent/safety.dart' show FocusInfo;

class InputException implements Exception {
  InputException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Synthetic mouse and keyboard for agent mode and the questionnaire's
/// click-and-type fallback, over `app.sotto/input`. Windows: SendInput + UI
/// Automation. macOS: CGEvent + the AX API (Accessibility permission; the
/// app runs without the App Sandbox — see the README).
///
/// Coordinates: physical pixels on Windows, points on macOS — the callers
/// ([NativeAgentExecutor], [NativeFormDriver]) convert.
class InputService {
  static const _channel = MethodChannel('app.sotto/input');

  static bool get supported => Platform.isWindows || Platform.isMacOS;

  Future<void> _call(String method, [Map<String, Object?>? args]) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on PlatformException catch (e) {
      throw InputException(e.message ?? e.code);
    } on MissingPluginException {
      throw InputException('Input control is not available on this platform.');
    }
  }

  Future<void> move(double x, double y) => _call('move', {'x': x, 'y': y});

  Future<void> click(double x, double y, {bool right = false, int count = 1}) =>
      _call('click', {'x': x, 'y': y, 'button': right ? 'right' : 'left', 'count': count});

  Future<void> scroll(int dx, int dy, {double? x, double? y}) =>
      _call('scroll', {'dx': dx, 'dy': dy, 'x': x ?? 0, 'y': y ?? 0, 'atPoint': x != null && y != null});

  /// Left button down (true) or up at (x, y).
  Future<void> mouseButton(double x, double y, {required bool down}) =>
      _call('mouseButton', {'x': x, 'y': y, 'down': down});

  /// Press at (x1, y1), move to (x2, y2) in [steps] small moves ~16 ms
  /// apart — web pages only start a drag once the pointer travels — and
  /// release there.
  Future<void> drag(double x1, double y1, double x2, double y2, {int steps = 14}) async {
    await mouseButton(x1, y1, down: true);
    try {
      for (var i = 1; i <= steps; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
        final t = i / steps;
        await move(x1 + (x2 - x1) * t, y1 + (y2 - y1) * t);
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));
    } finally {
      await mouseButton(x2, y2, down: false);
    }
  }

  Future<void> type(String text) => _call('type', {'text': text});

  Future<void> keys(List<String> keys) => _call('keys', {'keys': keys});

  /// Lets go of every held modifier and mouse button.
  Future<void> releaseAll() async {
    try {
      await _channel.invokeMethod<void>('releaseAll');
    } catch (_) {
      // Best effort: the stop must never throw.
    }
  }

  Future<FocusInfo?> focused() async {
    try {
      final m = await _channel.invokeMethod<Map<Object?, Object?>>('focused');
      if (m == null) return null;
      return FocusInfo(
        isPassword: m['isPassword'] as bool? ?? false,
        name: m['name'] as String? ?? '',
        role: m['role'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  /// macOS: Accessibility permission. Windows: always granted.
  Future<bool> hasPermission() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<String>('permission') == 'granted';
    } on MissingPluginException {
      return false;
    }
  }

  /// macOS: shows the system prompt the first time.
  Future<bool> requestPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } on MissingPluginException {
      return false;
    }
  }
}

final inputServiceProvider = Provider<InputService>((ref) => InputService());

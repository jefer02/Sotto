import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/forms/autofill_watcher.dart';
import '../../domain/forms/form_filler.dart' show ElementState;
import '../../domain/forms/form_model.dart';

class FormAccessException implements Exception {
  FormAccessException(this.code, [this.message = '']);

  /// no_window, own_window, uia_failed, permission_denied, unsupported.
  final String code;
  final String message;

  @override
  String toString() => message.isEmpty ? code : message;
}

/// The foreground window's form controls through the platform's
/// accessibility API — Windows UI Automation, macOS AX — and the
/// accessibility actions that fill them (`app.sotto/forms`). Sotto's own
/// window is never read.
class FormAccessService {
  static const _channel = MethodChannel('app.sotto/forms');

  static bool get supported => Platform.isWindows || Platform.isMacOS;

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw FormAccessException(e.code, e.message ?? '');
    } on MissingPluginException {
      throw FormAccessException('unsupported');
    }
  }

  /// The tree arrives as JSON from the native side, which walks it on its
  /// own thread; a big one is also parsed off the UI isolate.
  Future<List<UiElement>> read({int max = 800}) async {
    final json = await _call<String>('read', {'max': max}) ?? '[]';
    return json.length < isolateAbove ? parseElements(json) : Isolate.run(() => parseElements(json));
  }

  Future<FormSnapshot> snapshot() async {
    final json = await _call<String>('read', {'max': 800}) ?? '[]';
    return json.length < isolateAbove ? _snapshot(json) : Isolate.run(() => _snapshot(json));
  }

  /// Below this many characters an isolate costs more than the parse.
  static const isolateAbove = 64 * 1024;

  static List<UiElement> parseElements(String json) {
    final list = jsonDecode(json) as List;
    return [for (final m in list.whereType<Map<Object?, Object?>>()) UiElement.fromMap(m)];
  }

  static FormSnapshot _snapshot(String json) => FormSnapshot.fromElements(parseElements(json));

  Future<bool> setValue(String id, String text) async =>
      await _call<bool>('setValue', {'id': id, 'text': text}) ?? false;

  Future<bool> select(String id) async => await _call<bool>('select', {'id': id}) ?? false;

  Future<bool> toggle(String id, bool on) async => await _call<bool>('toggle', {'id': id, 'on': on}) ?? false;

  Future<bool> choose(String id, String label) async =>
      await _call<bool>('choose', {'id': id, 'label': label}) ?? false;

  Future<bool> invoke(String id) async => await _call<bool>('invoke', {'id': id}) ?? false;

  /// A slider or spinner to [value]; false where the platform can't.
  Future<bool> setRange(String id, double value) async {
    try {
      return await _call<bool>('setRange', {'id': id, 'value': value}) ?? false;
    } on FormAccessException {
      return false;
    }
  }

  /// One element as it is now; null when it's gone or the platform can't.
  Future<ElementState?> state(String id) async {
    try {
      final json = await _call<String>('state', {'id': id});
      final m = json == null ? null : jsonDecode(json);
      return m is Map<Object?, Object?> ? ElementState.fromMap(m) : null;
    } on FormAccessException {
      return null;
    }
  }

  /// Scrolls the container around [anchor] one screen down through the
  /// accessibility tree; its new position (0–100), or null when it couldn't.
  Future<double?> scrollDown({String? anchor}) async {
    try {
      return (await _call<num>('scrollDown', {'anchor': ?anchor}))?.toDouble();
    } on FormAccessException {
      return null;
    }
  }

  Future<bool> focus(String id) async => await _call<bool>('focus', {'id': id}) ?? false;

  Future<bool> scrollIntoView(String id) async => await _call<bool>('scrollIntoView', {'id': id}) ?? false;

  /// The window in front — what the auto-fill watcher polls every 1.5 s.
  Future<ForegroundWindow?> foreground() async {
    try {
      final json = await _call<String>('foreground');
      final m = jsonDecode(json ?? '{}');
      return m is Map<Object?, Object?> && m['id'] != null ? ForegroundWindow.fromMap(m) : null;
    } on FormAccessException {
      return null;
    }
  }

  /// Whether the front page — the container around [anchor] — can scroll
  /// further down; null when unknown.
  Future<bool?> canScrollDown({String? anchor}) async {
    try {
      return await _call<bool>('canScrollDown', {'anchor': ?anchor});
    } on FormAccessException {
      return null;
    }
  }

  /// macOS: Accessibility permission. Windows: always granted.
  Future<bool> hasPermission() async {
    if (!supported) return false;
    try {
      return await _call<String>('permission') == 'granted';
    } on FormAccessException {
      return false;
    }
  }

  /// macOS: the system prompt, the first time.
  Future<bool> requestPermission() async {
    try {
      return await _call<bool>('requestPermission') ?? false;
    } on FormAccessException {
      return false;
    }
  }
}

final formAccessProvider = Provider<FormAccessService>((ref) => FormAccessService());

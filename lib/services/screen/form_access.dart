import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  Future<List<UiElement>> read({int max = 800}) async {
    final json = await _call<String>('read', {'max': max});
    final list = jsonDecode(json ?? '[]') as List;
    return [for (final m in list.whereType<Map<Object?, Object?>>()) UiElement.fromMap(m)];
  }

  Future<FormSnapshot> snapshot() async => FormSnapshot.fromElements(await read());

  Future<bool> setValue(String id, String text) async =>
      await _call<bool>('setValue', {'id': id, 'text': text}) ?? false;

  Future<bool> select(String id) async => await _call<bool>('select', {'id': id}) ?? false;

  Future<bool> toggle(String id, bool on) async => await _call<bool>('toggle', {'id': id, 'on': on}) ?? false;

  Future<bool> choose(String id, String label) async =>
      await _call<bool>('choose', {'id': id, 'label': label}) ?? false;

  Future<bool> invoke(String id) async => await _call<bool>('invoke', {'id': id}) ?? false;

  Future<bool> focus(String id) async => await _call<bool>('focus', {'id': id}) ?? false;

  Future<bool> scrollIntoView(String id) async => await _call<bool>('scrollIntoView', {'id': id}) ?? false;

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

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Something that happened on one connection from a native messaging host —
/// one per browser profile that has the extension.
sealed class BridgeEvent {
  const BridgeEvent(this.conn);
  final int conn;
}

class BridgeOpened extends BridgeEvent {
  const BridgeOpened(super.conn);
}

class BridgeData extends BridgeEvent {
  const BridgeData(super.conn, this.bytes);
  final Uint8List bytes;
}

class BridgeClosed extends BridgeEvent {
  const BridgeClosed(super.conn);
}

/// Where native messaging hosts connect to the running app: a named pipe
/// on Windows, a Unix socket on macOS. Only the current OS user can connect.
abstract class BridgeTransport {
  Stream<BridgeEvent> get events;

  /// Starts listening; false when this platform or build has no transport.
  Future<bool> start();
  Future<void> stop();
  Future<bool> write(int conn, Uint8List bytes);
  Future<void> close(int conn);

  static BridgeTransport? forPlatform() {
    if (Platform.isWindows) return PipeTransport();
    if (Platform.isMacOS) return UnixSocketTransport(UnixSocketTransport.defaultPath());
    return null;
  }
}

/// Windows: the runner owns the pipe (`windows/runner/native/bridge.cpp`):
/// `\\.\pipe\sotto-bridge-<user SID>`, its DACL granting only the current
/// user, remote clients rejected, and every client's process token checked
/// against the current user before a byte is read. Bytes arrive here as they
/// come; framing is done on this side.
class PipeTransport implements BridgeTransport {
  PipeTransport() {
    _channel.setMethodCallHandler(_onCall);
  }

  static const _channel = MethodChannel('app.sotto/bridge');
  final _events = StreamController<BridgeEvent>.broadcast();

  @override
  Stream<BridgeEvent> get events => _events.stream;

  Future<Object?> _onCall(MethodCall call) async {
    final args = call.arguments;
    if (call.method != 'event' || args is! Map) return null;
    final conn = args['conn'];
    if (conn is! int) return null;
    switch (args['kind']) {
      case 'open':
        _events.add(BridgeOpened(conn));
      case 'data':
        final bytes = args['bytes'];
        if (bytes is Uint8List) _events.add(BridgeData(conn, bytes));
      case 'close':
        _events.add(BridgeClosed(conn));
    }
    return null;
  }

  @override
  Future<bool> start() async {
    try {
      return await _channel.invokeMethod<bool>('start') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      // Already stopped.
    } on MissingPluginException {
      // No runner (tests).
    }
  }

  @override
  Future<bool> write(int conn, Uint8List bytes) async {
    try {
      return await _channel.invokeMethod<bool>('write', {'conn': conn, 'bytes': bytes}) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> close(int conn) async {
    try {
      await _channel.invokeMethod<void>('close', {'conn': conn});
    } on PlatformException {
      // Gone already.
    } on MissingPluginException {
      // No runner (tests).
    }
  }

  /// Points a browser's registry key (under HKCU) at a host manifest.
  static Future<bool> registerHost(String key, String manifestPath) async {
    try {
      return await _channel.invokeMethod<bool>('registerHost', {'key': key, 'manifest': manifestPath}) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

/// macOS: a Unix socket in a folder only the current user can open (0700),
/// the socket itself 0600. The host (Sotto in host mode, see
/// `AppDelegate.swift`) also checks that the socket's owner is its own user.
class UnixSocketTransport implements BridgeTransport {
  UnixSocketTransport(this.path);

  /// Kept short: a socket path may not exceed 104 bytes on macOS.
  static String defaultPath() =>
      '${Platform.environment['HOME'] ?? ''}/Library/Application Support/Sotto/bridge/bridge.sock';

  final String path;
  final _events = StreamController<BridgeEvent>.broadcast();
  final _clients = <int, Socket>{};
  ServerSocket? _server;
  var _nextConn = 1;

  @override
  Stream<BridgeEvent> get events => _events.stream;

  @override
  Future<bool> start() async {
    if (_server != null) return true;
    try {
      final dir = Directory(File(path).parent.path);
      await dir.create(recursive: true);
      await Process.run('/bin/chmod', ['700', dir.path]);
      final stale = File(path);
      if (await FileSystemEntity.type(path, followLinks: false) != FileSystemEntityType.notFound) {
        await stale.delete();
      }
      final server = _server = await ServerSocket.bind(InternetAddress(path, type: InternetAddressType.unix), 0);
      await Process.run('/bin/chmod', ['600', path]);
      server.listen(_accept, onError: (Object _) {}, cancelOnError: false);
      return true;
    } catch (e) {
      debugPrint('[bridge] socket: $e');
      return false;
    }
  }

  void _accept(Socket socket) {
    final conn = _nextConn++;
    _clients[conn] = socket;
    _events.add(BridgeOpened(conn));
    socket.listen(
      (data) => _events.add(BridgeData(conn, data)),
      onDone: () => _drop(conn),
      onError: (Object _) => _drop(conn),
      cancelOnError: true,
    );
  }

  void _drop(int conn) {
    final s = _clients.remove(conn);
    if (s == null) return;
    s.destroy();
    _events.add(BridgeClosed(conn));
  }

  @override
  Future<void> stop() async {
    for (final conn in [..._clients.keys]) {
      _drop(conn);
    }
    await _server?.close();
    _server = null;
    try {
      await File(path).delete();
    } catch (_) {}
  }

  @override
  Future<bool> write(int conn, Uint8List bytes) async {
    final s = _clients[conn];
    if (s == null) return false;
    try {
      // No flush: another write may come before it would finish.
      s.add(bytes);
      return true;
    } catch (_) {
      _drop(conn);
      return false;
    }
  }

  @override
  Future<void> close(int conn) async => _drop(conn);
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bridge_protocol.dart';
import 'bridge_transport.dart';
import 'host_manifest.dart';

export 'bridge_protocol.dart' show BrowserKind, BridgePage;

/// One browser profile's extension, connected through its host.
class _Link {
  _Link(this.conn);
  final int conn;
  final decoder = FrameDecoder();
  BrowserKind? browser;
  final connectedAt = DateTime.now();
}

/// Sotto's side of the browser extension: the preferred way to read web
/// forms (before UI Automation / AX, before the screenshot). The extension
/// connects through the native messaging host; Sotto never launches or
/// relaunches a browser and opens no debugging port.
///
/// The extension acts only while Sotto has armed it — auto-fill on, or a
/// fill the presenter started — and only on the active tab. Every reply is
/// validated by [BridgeSchema]; a connection that breaks the framing is
/// dropped.
class BrowserBridge {
  BrowserBridge({BridgeTransport? transport, this.timeout = const Duration(seconds: 4), this.installManifests = true})
    : _transport = transport ?? BridgeTransport.forPlatform();

  final BridgeTransport? _transport;
  final Duration timeout;
  final bool installManifests;

  final _links = <int, _Link>{};
  final _pending = <int, (int conn, Completer<BridgeReply?>)>{};
  final _changes = StreamController<Set<BrowserKind>>.broadcast();
  final _armedBy = <String>{};
  StreamSubscription<BridgeEvent>? _sub;
  var _nextId = 1;
  var _started = false;

  /// Browsers with a live, introduced extension.
  Set<BrowserKind> get connected => {
    for (final l in _links.values)
      if (l.browser != null) l.browser!,
  };

  Stream<Set<BrowserKind>> get changes => _changes.stream;

  bool isConnected(BrowserKind browser) => connected.contains(browser);

  bool get armed => _armedBy.isNotEmpty;

  /// Registers the host for this user (idempotent) and starts listening.
  Future<void> start() async {
    if (_started || _transport == null) return;
    _started = true;
    if (installManifests) await HostManifests.install();
    _sub = _transport.events.listen(_onEvent);
    if (!await _transport.start()) debugPrint('[bridge] no transport');
  }

  /// Settings → Forms → Reconnect: drops every connection, registers the
  /// host again and listens anew. The hosts reconnect within seconds.
  Future<void> reconnect() async {
    final t = _transport;
    if (t == null) return;
    _dropAll();
    await t.stop();
    await _sub?.cancel();
    _started = false;
    await start();
  }

  Future<void> dispose() async {
    _dropAll();
    await _sub?.cancel();
    await _transport?.stop();
    await _changes.close();
  }

  void _dropAll() {
    for (final c in _pending.values) {
      if (!c.$2.isCompleted) c.$2.complete(null);
    }
    _pending.clear();
    final had = _links.isNotEmpty;
    _links.clear();
    if (had) _emit();
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(connected);
  }

  // ─────────────────────────── Arming ───────────────────────────

  /// [reason] ("autofill", "run") holds the extension armed until released.
  void arm(String reason, bool on) {
    final was = armed;
    on ? _armedBy.add(reason) : _armedBy.remove(reason);
    if (armed == was) return;
    for (final l in _links.values) {
      if (l.browser != null) unawaited(_request(l, (id) => BridgeRequest.arm(id, armed)));
    }
  }

  /// Chord + Esc: whatever the extension was about to do, it doesn't, and
  /// every request still waiting gets nothing.
  void cancelAll() {
    for (final (_, done) in _pending.values) {
      if (!done.isCompleted) done.complete(null);
    }
    _pending.clear();
    for (final l in _links.values) {
      if (l.browser != null) unawaited(_request(l, BridgeRequest.cancel));
    }
  }

  /// The "Sotto is filling" badge in the active tab of every connected
  /// browser: on while a fill runs, off the moment it ends or is stopped.
  void indicate(bool on) {
    if (on && !armed) return;
    for (final l in _links.values) {
      if (l.browser != null) unawaited(_request(l, (id) => BridgeRequest.indicator(id, on)));
    }
  }

  // ─────────────────────────── Requests ───────────────────────────

  /// The active tab's form in [browser], or null (not connected, not armed,
  /// a page the extension may not read, a malformed reply). Several profiles
  /// of one browser: the newest connection whose tab is [title] wins.
  Future<BridgePage?> read(BrowserKind browser, {String title = ''}) async {
    if (!armed) return null;
    final links = _linksFor(browser);
    BridgePage? fallback;
    for (final l in links) {
      final reply = await _request(l, BridgeRequest.read);
      if (reply == null || !reply.ok) continue;
      final page = BridgeSchema.page(reply.result);
      if (page == null) {
        debugPrint('[bridge] rejected a malformed page from ${browser.name}');
        continue;
      }
      if (title.isEmpty || _sameTitle(page.title, title)) return page;
      fallback ??= links.length == 1 ? page : null;
    }
    return fallback;
  }

  /// One action on a field the last [read] returned.
  Future<bool> act(BrowserKind browser, String target, String action, [Object? arg]) async {
    if (!armed || !BridgeSchema.isElementId(target)) return false;
    final l = _linksFor(browser).firstOrNull;
    if (l == null) return false;
    final reply = await _request(l, (id) => BridgeRequest.act(id, target, action, arg));
    return reply != null && reply.ok && BridgeSchema.done(reply.result);
  }

  List<_Link> _linksFor(BrowserKind browser) =>
      _links.values.where((l) => l.browser == browser).toList()..sort((a, b) => b.connectedAt.compareTo(a.connectedAt));

  static bool _sameTitle(String a, String b) {
    String n(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    final x = n(a), y = n(b);
    return x == y || (x.isNotEmpty && y.contains(x)) || (y.isNotEmpty && x.contains(y));
  }

  Future<BridgeReply?> _request(_Link l, Map<String, Object?> Function(int id) build) async {
    final t = _transport;
    if (t == null) return null;
    final id = _nextId++;
    final done = Completer<BridgeReply?>();
    _pending[id] = (l.conn, done);
    try {
      if (!await t.write(l.conn, BridgeFraming.encode(build(id)))) return null;
      return await done.future.timeout(timeout, onTimeout: () => null);
    } on FrameException {
      return null;
    } finally {
      _pending.remove(id);
    }
  }

  // ─────────────────────────── Events ───────────────────────────

  void _onEvent(BridgeEvent e) {
    switch (e) {
      case BridgeOpened(:final conn):
        final l = _links[conn] = _Link(conn);
        unawaited(_introduce(l));
      case BridgeData(:final conn, :final bytes):
        final l = _links[conn];
        if (l != null) _onData(l, bytes);
      case BridgeClosed(:final conn):
        _close(conn, notify: false);
    }
  }

  Future<void> _introduce(_Link l) async {
    final reply = await _request(l, BridgeRequest.hello);
    final hello = reply != null && reply.ok ? BridgeSchema.hello(reply.result) : null;
    if (hello == null || !_links.containsKey(l.conn)) {
      _close(l.conn);
      return;
    }
    l.browser = hello.browser;
    _emit();
    if (armed) await _request(l, (id) => BridgeRequest.arm(id, true));
  }

  void _onData(_Link l, Uint8List bytes) {
    try {
      for (final frame in l.decoder.add(bytes)) {
        final reply = BridgeSchema.reply(FrameDecoder.decodeJson(frame));
        if (reply == null) throw FrameException('not a reply');
        final pending = _pending[reply.id];
        // Only the connection that was asked may answer.
        if (pending != null && pending.$1 == l.conn && !pending.$2.isCompleted) pending.$2.complete(reply);
      }
    } on FrameException catch (e) {
      debugPrint('[bridge] dropping connection ${l.conn}: ${e.message}');
      _close(l.conn);
    }
  }

  void _close(int conn, {bool notify = true}) {
    final l = _links.remove(conn);
    for (final MapEntry(:key, :value) in [..._pending.entries]) {
      if (value.$1 == conn) {
        _pending.remove(key);
        if (!value.$2.isCompleted) value.$2.complete(null);
      }
    }
    if (notify) unawaited(_transport?.close(conn));
    if (l?.browser != null) _emit();
  }
}

final browserBridgeProvider = Provider<BrowserBridge>((ref) {
  final bridge = BrowserBridge();
  ref.onDispose(() => unawaited(bridge.dispose()));
  return bridge;
});

/// The browsers whose extension is connected right now.
final bridgeStatusProvider = StreamProvider<Set<BrowserKind>>((ref) async* {
  final bridge = ref.watch(browserBridgeProvider);
  yield bridge.connected;
  yield* bridge.changes;
});

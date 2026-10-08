import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import '../../domain/agent/safety.dart';
import '../../domain/forms/form_model.dart';

/// The browsers the Sotto Bridge extension is made for.
enum BrowserKind {
  chrome('Chrome'),
  edge('Edge'),
  firefox('Firefox');

  const BrowserKind(this.label);
  final String label;

  static BrowserKind? byName(Object? name) => values.where((b) => b.name == name).firstOrNull;

  /// The browser a foreground window belongs to, by its process / app name.
  static BrowserKind? ofApp(String app) => switch (app.toLowerCase().replaceAll(RegExp(r'\.(exe|app)$'), '').trim()) {
    'chrome' || 'google chrome' => chrome,
    'msedge' || 'edge' || 'microsoft edge' => edge,
    'firefox' || 'mozilla firefox' => firefox,
    _ => null,
  };
}

class FrameException implements Exception {
  FrameException(this.message);
  final String message;

  @override
  String toString() => 'FrameException: $message';
}

/// Native messaging framing — a 4-byte little-endian length, then that many
/// bytes of UTF-8 JSON. The browser speaks it to the host on stdin / stdout,
/// and the host and Sotto speak it over the named pipe / Unix socket.
abstract final class BridgeFraming {
  /// Chrome caps host → extension messages at 1 MB; both directions use it.
  static const maxFrame = 1024 * 1024;

  static Uint8List encode(Object? json) {
    final body = utf8.encode(jsonEncode(json));
    if (body.length > maxFrame) throw FrameException('frame of ${body.length} bytes is over $maxFrame');
    final out = Uint8List(4 + body.length);
    ByteData.sublistView(out).setUint32(0, body.length, Endian.little);
    out.setRange(4, out.length, body);
    return out;
  }
}

/// Reassembles frames from a byte stream that arrives in pieces of any size
/// — a length prefix split across reads included.
class FrameDecoder {
  FrameDecoder({this.maxFrame = BridgeFraming.maxFrame});

  final int maxFrame;
  var _buffer = Uint8List(0);
  var _length = 0;

  /// Bytes received but not yet a whole frame.
  int get pending => _length;

  /// The whole frames [chunk] completes, in order. A length of zero or over
  /// [maxFrame] throws [FrameException]: the connection should be dropped.
  List<Uint8List> add(List<int> chunk) {
    _append(chunk);
    final frames = <Uint8List>[];
    var offset = 0;
    while (_length - offset >= 4) {
      final size = ByteData.sublistView(_buffer, offset, offset + 4).getUint32(0, Endian.little);
      if (size == 0 || size > maxFrame) {
        _length = 0;
        throw FrameException('bad frame length $size');
      }
      if (_length - offset - 4 < size) break;
      frames.add(Uint8List.fromList(Uint8List.sublistView(_buffer, offset + 4, offset + 4 + size)));
      offset += 4 + size;
    }
    if (offset > 0) {
      _buffer.setRange(0, _length - offset, _buffer, offset);
      _length -= offset;
    }
    return frames;
  }

  void _append(List<int> chunk) {
    final need = _length + chunk.length;
    if (need > _buffer.length) {
      // A frame over maxFrame is refused once its prefix is in, so this
      // stays under maxFrame plus one read.
      var size = _buffer.isEmpty ? 64 : _buffer.length * 2;
      while (size < need) {
        size *= 2;
      }
      final grown = Uint8List(size);
      grown.setRange(0, _length, _buffer);
      _buffer = grown;
    }
    _buffer.setRange(_length, _length + chunk.length, chunk);
    _length += chunk.length;
  }

  /// [frame] as JSON; throws [FrameException] when it isn't.
  static Object? decodeJson(Uint8List frame) {
    try {
      return jsonDecode(utf8.decode(frame));
    } on FormatException catch (e) {
      throw FrameException('not JSON: ${e.message}');
    }
  }
}

/// Sotto → extension. Every request carries an id the reply echoes.
abstract final class BridgeRequest {
  static const version = 1;

  static Map<String, Object?> hello(int id) => {'v': version, 'id': id, 'op': 'hello'};
  static Map<String, Object?> read(int id) => {'v': version, 'id': id, 'op': 'read'};
  static Map<String, Object?> arm(int id, bool on) => {'v': version, 'id': id, 'op': 'arm', 'on': on};
  static Map<String, Object?> cancel(int id) => {'v': version, 'id': id, 'op': 'cancel'};

  /// The "Sotto is filling" badge on the active tab.
  static Map<String, Object?> indicator(int id, bool on) => {'v': version, 'id': id, 'op': 'indicator', 'on': on};
  static Map<String, Object?> act(int id, String target, String action, [Object? arg]) => {
    'v': version,
    'id': id,
    'op': 'act',
    'target': target,
    'action': action,
    'arg': ?arg,
  };
}

/// Extension → Sotto: the answer to request [id].
class BridgeReply {
  const BridgeReply(this.id, {required this.ok, this.result, this.error = ''});
  final int id;
  final bool ok;
  final Object? result;
  final String error;
}

class BridgeHello {
  const BridgeHello(this.browser, this.version);
  final BrowserKind browser;
  final String version;
}

/// The active tab's form, as the extension read it.
class BridgePage {
  const BridgePage({required this.title, required this.origin, required this.elements});
  final String title;

  /// The page's scheme and host only — no path, no query.
  final String origin;
  final List<UiElement> elements;
}

/// Everything the extension sends is checked here before Sotto uses it.
/// Anything malformed is rejected whole (null), and the caller falls back
/// to accessibility. A field that is — or looks like — a password or payment
/// field must arrive without its value: if one doesn't, the page is rejected.
abstract final class BridgeSchema {
  static const maxFields = 800;
  static const maxText = 20000;
  static const maxLabel = 4000;
  static const maxOptions = 500;
  static final _id = RegExp(r'^ext:\d{1,6}$');
  static const _types = {'edit', 'combo', 'radio', 'checkbox', 'button', 'group'};
  static const _patterns = {'value', 'toggle', 'select', 'expand', 'invoke'};
  static const _errors = {'not_armed', 'no_tab', 'no_access', 'no_result', 'cancelled'};

  static bool isElementId(String id) => _id.hasMatch(id);

  static BridgeReply? reply(Object? json) {
    if (json is! Map || json['v'] != BridgeRequest.version) return null;
    final id = json['id'];
    final ok = json['ok'];
    if (id is! int || id < 0 || ok is! bool) return null;
    if (ok) return json.containsKey('result') ? BridgeReply(id, ok: true, result: json['result']) : null;
    final error = json['error'];
    if (error is! String) return null;
    return BridgeReply(id, ok: false, error: _errors.contains(error) ? error : 'unknown');
  }

  static BridgeHello? hello(Object? result) {
    if (result is! Map) return null;
    final browser = BrowserKind.byName(result['browser']);
    final version = result['version'];
    if (browser == null || version is! String || version.length > 32) return null;
    return BridgeHello(browser, version);
  }

  /// An action's result: whether it was done.
  static bool done(Object? result) => result is Map && result['done'] == true;

  static BridgePage? page(Object? result) {
    if (result is! Map) return null;
    final title = result['title'] ?? '';
    final origin = result['origin'] ?? '';
    final fields = result['fields'];
    if (title is! String || title.length > maxLabel || origin is! String || origin.length > 300) return null;
    if (fields is! List || fields.length > maxFields) return null;
    final elements = <UiElement>[];
    for (final f in fields) {
      final e = element(f);
      if (e == null) return null;
      elements.add(e);
    }
    return BridgePage(title: title, origin: origin, elements: elements);
  }

  static UiElement? element(Object? m) {
    if (m is! Map) return null;
    final id = m['id'];
    final type = m['type'];
    final name = m['name'] ?? '';
    final value = m['value'];
    final bounds = m['bounds'];
    final checked = m['checked'];
    final parent = m['parent'];
    final options = m['options'] ?? const <Object?>[];
    final patterns = m['patterns'] ?? const <Object?>[];
    final multiline = m['multiline'] ?? false;
    final flagged = m['sensitive'] ?? false;

    if (id is! String || !_id.hasMatch(id) || type is! String || !_types.contains(type)) return null;
    if (name is! String || name.length > maxLabel) return null;
    if (value != null && (value is! String || value.length > maxText)) return null;
    if (bounds is! List || bounds.length != 4 || bounds.any((b) => b is! num || !b.isFinite)) return null;
    if (checked != null && checked is! bool) return null;
    if (parent != null && (parent is! String || !_id.hasMatch(parent))) return null;
    if (options is! List || options.length > maxOptions || options.any((o) => o is! String || o.length > maxLabel)) {
      return null;
    }
    if (patterns is! List || patterns.any((p) => p is! String || !_patterns.contains(p))) return null;
    if (multiline is! bool || flagged is! bool) return null;

    final looksSensitive = SafetyGate.isSecretLabel(name) || SafetyGate.isPaymentLabel(name);
    // The extension must never send these; one that does isn't trusted.
    if (flagged && (value != null || options.isNotEmpty)) return null;
    final sensitive = flagged || (looksSensitive && type != 'button' && type != 'group');
    double n(Object? v) => (v! as num).toDouble();
    return UiElement(
      id: id,
      type: type,
      name: name.trim(),
      value: sensitive ? null : value as String?,
      bounds: Rect.fromLTWH(n(bounds[0]), n(bounds[1]), n(bounds[2]), n(bounds[3])),
      checked: checked as bool?,
      parent: parent as String?,
      options: sensitive ? const [] : [for (final o in options) (o as String).trim()],
      patterns: sensitive ? const {} : {for (final p in patterns) p as String},
      multiline: multiline,
      sensitive: sensitive,
    );
  }
}

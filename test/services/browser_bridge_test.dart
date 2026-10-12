import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/domain/forms/form_model.dart';
import 'package:sotto/services/screen/bridge_protocol.dart';
import 'package:sotto/services/screen/bridge_transport.dart';
import 'package:sotto/services/screen/browser_bridge.dart';
import 'package:sotto/services/screen/form_access.dart';
import 'package:sotto/services/screen/form_sources.dart';
import 'package:sotto/services/screen/host_manifest.dart';

Map<String, Object?> _field(
  String id,
  String type,
  String name, {
  Object? value,
  bool? sensitive,
  List<String>? patterns,
}) => {
  'id': id,
  'type': type,
  'name': name,
  'bounds': [10, 20, 100, 24],
  'value': ?value,
  'sensitive': ?sensitive,
  'patterns': patterns ?? (sensitive == true ? <String>[] : ['value']),
};

/// An in-memory host: replies to what Sotto writes, as an extension would.
class _FakeTransport implements BridgeTransport {
  final _events = StreamController<BridgeEvent>.broadcast(sync: true);
  final sent = <Map<String, Object?>>[];
  final decoder = FrameDecoder();
  Map<String, Object?>? Function(Map<String, Object?> request) answer = (_) => null;

  @override
  Stream<BridgeEvent> get events => _events.stream;

  void open(int conn) => _events.add(BridgeOpened(conn));
  void push(int conn, List<int> bytes) => _events.add(BridgeData(conn, Uint8List.fromList(bytes)));

  @override
  Future<bool> start() async => true;
  @override
  Future<void> stop() async {}
  @override
  Future<void> close(int conn) async => scheduleMicrotask(() => _events.add(BridgeClosed(conn)));

  @override
  Future<bool> write(int conn, Uint8List bytes) async {
    for (final frame in decoder.add(bytes)) {
      final req = (FrameDecoder.decodeJson(frame)! as Map).cast<String, Object?>();
      sent.add(req);
      final reply = answer(req);
      if (reply != null) scheduleMicrotask(() => push(conn, BridgeFraming.encode({'v': 1, 'id': req['id'], ...reply})));
    }
    return true;
  }
}

Map<String, Object?>? _extension(Map<String, Object?> req, {String browser = 'chrome', Object? page}) =>
    switch (req['op']) {
      'hello' => {
        'ok': true,
        'result': {'browser': browser, 'version': '1.0.0'},
      },
      'read' => {'ok': true, 'result': page},
      'act' => {
        'ok': true,
        'result': {'done': true},
      },
      _ => {'ok': true, 'result': <String, Object?>{}},
    };

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('framing', () {
    test('a frame is a little-endian length and UTF-8 JSON', () {
      final bytes = BridgeFraming.encode({'op': 'héllo'});
      final body = utf8.encode(jsonEncode({'op': 'héllo'}));
      expect(bytes.sublist(0, 4), [body.length, 0, 0, 0]);
      expect(bytes.sublist(4), body);
    });

    test('frames split at every byte, and several in one read', () {
      final a = BridgeFraming.encode({'n': 1});
      final b = BridgeFraming.encode({'n': 2, 's': 'x' * 300});
      final stream = [...a, ...b];
      final d = FrameDecoder();
      final out = <Object?>[];
      for (final byte in stream) {
        out.addAll(d.add([byte]).map(FrameDecoder.decodeJson));
      }
      expect(out, [
        {'n': 1},
        {'n': 2, 's': 'x' * 300},
      ]);
      expect(d.pending, 0);

      final whole = FrameDecoder().add(stream).map(FrameDecoder.decodeJson).toList();
      expect(whole, out);
    });

    test('a length prefix split across reads waits for the rest', () {
      final f = BridgeFraming.encode({'ok': true});
      final d = FrameDecoder();
      expect(d.add(f.sublist(0, 2)), isEmpty);
      expect(d.add(f.sublist(2, 6)), isEmpty);
      expect(d.add(f.sublist(6)).single, utf8.encode('{"ok":true}'));
    });

    test('zero, oversized frames and non-JSON are refused', () {
      expect(() => FrameDecoder().add([0, 0, 0, 0]), throwsA(isA<FrameException>()));
      expect(() => FrameDecoder(maxFrame: 10).add([11, 0, 0, 0]), throwsA(isA<FrameException>()));
      expect(() => FrameDecoder().add([0xff, 0xff, 0xff, 0xff]), throwsA(isA<FrameException>()));
      expect(() => FrameDecoder.decodeJson(Uint8List.fromList(utf8.encode('{nope'))), throwsA(isA<FrameException>()));
      expect(() => BridgeFraming.encode('x' * (BridgeFraming.maxFrame + 1)), throwsA(isA<FrameException>()));
    });
  });

  group('schema', () {
    test('replies need v, an id and ok; errors are a known code', () {
      expect(BridgeSchema.reply({'v': 1, 'id': 3, 'ok': true, 'result': {}})!.id, 3);
      expect(BridgeSchema.reply({'v': 1, 'id': 3, 'ok': false, 'error': 'no_access'})!.error, 'no_access');
      expect(BridgeSchema.reply({'v': 1, 'id': 3, 'ok': false, 'error': 'weird'})!.error, 'unknown');
      expect(BridgeSchema.reply({'v': 2, 'id': 3, 'ok': true, 'result': {}}), isNull);
      expect(BridgeSchema.reply({'v': 1, 'id': '3', 'ok': true, 'result': {}}), isNull);
      expect(BridgeSchema.reply({'v': 1, 'id': 3, 'ok': true}), isNull);
      expect(BridgeSchema.reply([1, 2]), isNull);
    });

    test('hello names a known browser', () {
      expect(BridgeSchema.hello({'browser': 'edge', 'version': '1.0.0'})!.browser, BrowserKind.edge);
      expect(BridgeSchema.hello({'browser': 'netscape', 'version': '1'}), isNull);
    });

    test('a well-formed page becomes elements', () {
      final page = BridgeSchema.page({
        'title': 'Sign-up',
        'origin': 'https://example.org',
        'fields': [
          _field('ext:1', 'edit', 'Name', value: 'Ada'),
          {
            'id': 'ext:2',
            'type': 'group',
            'name': 'Size',
            'bounds': [0, 0, 10, 10],
            'parent': null,
          },
          {
            'id': 'ext:3',
            'type': 'radio',
            'name': 'A. Small',
            'bounds': [0, 0, 10, 10],
            'parent': 'ext:2',
            'checked': false,
            'patterns': ['select'],
          },
        ],
      })!;
      expect(page.origin, 'https://example.org');
      expect(page.elements.map((e) => e.id), ['ext:1', 'ext:2', 'ext:3']);
      expect(page.elements.first.value, 'Ada');
      expect(page.elements.last.parent, 'ext:2');
    });

    test('anything malformed rejects the whole page', () {
      Map<String, Object?> pageWith(Map<String, Object?> f) => {
        'title': '',
        'origin': '',
        'fields': [f],
      };
      final bad = <Map<String, Object?>>[
        {..._field('ext:1', 'edit', 'x'), 'id': 'uia:1'},
        {..._field('ext:1', 'edit', 'x'), 'type': 'script'},
        {
          ..._field('ext:1', 'edit', 'x'),
          'bounds': [1, 2, 3],
        },
        {
          ..._field('ext:1', 'edit', 'x'),
          'bounds': [1, 2, 3, double.nan],
        },
        {..._field('ext:1', 'edit', 'x'), 'value': 42},
        {
          ..._field('ext:1', 'edit', 'x'),
          'patterns': ['eval'],
        },
        {..._field('ext:1', 'edit', 'x'), 'parent': '../x'},
        {..._field('ext:1', 'edit', 'x'), 'value': 'x' * (BridgeSchema.maxText + 1)},
      ];
      for (final f in bad) {
        expect(BridgeSchema.page(pageWith(f)), isNull, reason: '$f');
      }
      expect(
        BridgeSchema.page({
          'title': '',
          'fields': List.filled(BridgeSchema.maxFields + 1, _field('ext:1', 'edit', 'x')),
        }),
        isNull,
      );
    });

    test('a sensitive field that carries its value is not trusted', () {
      expect(
        BridgeSchema.page({
          'fields': [_field('ext:1', 'edit', 'Password', value: 'hunter2', sensitive: true)],
        }),
        isNull,
      );
    });

    test('password and payment fields never keep a value, whatever the extension says', () {
      final page = BridgeSchema.page({
        'fields': [
          _field('ext:1', 'edit', 'Password', sensitive: true),
          // Not flagged, but its label says card number: the value is dropped.
          _field('ext:2', 'edit', 'Card number', value: '4111 1111 1111 1111'),
          _field('ext:3', 'edit', 'Email', value: 'ada@example.org'),
        ],
      })!;
      final byId = {for (final e in page.elements) e.id: e};
      expect(byId['ext:1']!.sensitive, isTrue);
      expect(byId['ext:2']!.sensitive, isTrue);
      expect(byId['ext:2']!.value, isNull);
      expect(byId['ext:2']!.patterns, isEmpty);
      expect(byId['ext:3']!.value, 'ada@example.org');

      final snap = FormSnapshot.fromElements(page.elements);
      expect(snap.fields.where((f) => f.sensitive).map((f) => f.label), ['Password', 'Card number']);
    });

    test('foreground apps map to browsers', () {
      expect(BrowserKind.ofApp('chrome'), BrowserKind.chrome);
      expect(BrowserKind.ofApp('msedge.exe'), BrowserKind.edge);
      expect(BrowserKind.ofApp('Microsoft Edge'), BrowserKind.edge);
      expect(BrowserKind.ofApp('firefox'), BrowserKind.firefox);
      expect(BrowserKind.ofApp('Safari'), isNull);
    });
  });

  group('reading order', () {
    const extPage = FormSnapshot(
      fields: [FormField(key: 'ext:1', role: FieldRole.text, label: 'Name', bounds: Rect.zero)],
    );
    const treePage = FormSnapshot(
      fields: [FormField(key: 'uia:1', role: FieldRole.text, label: 'Name', bounds: Rect.zero)],
    );

    test('the extension comes first', () async {
      var asked = false;
      final r = await FormSources.read(
        extension: () async => extPage,
        accessibility: () async {
          asked = true;
          return treePage;
        },
      );
      expect(r.source, FormSource.extension);
      expect(r.snapshot, same(extPage));
      expect(asked, isFalse, reason: 'accessibility is not read when the extension answered');
    });

    test('no extension, an empty page or a failure: accessibility', () async {
      for (final ext in <Future<FormSnapshot?> Function()?>[
        null,
        () async => null,
        () async => const FormSnapshot(fields: []),
        () async => throw StateError('gone'),
      ]) {
        final r = await FormSources.read(extension: ext, accessibility: () async => treePage);
        expect(r.source, FormSource.accessibility);
      }
    });

    test('nothing readable: vision', () async {
      final empty = await FormSources.read(
        extension: () async => null,
        accessibility: () async => const FormSnapshot(fields: []),
      );
      expect(empty.source, FormSource.vision);
      final failed = await FormSources.read(accessibility: () async => throw FormAccessException('uia_failed'));
      expect(failed.source, FormSource.vision);
    });

    test("Sotto's own window and a missing permission still stop the run", () async {
      for (final code in ['own_window', 'permission_denied']) {
        expect(
          FormSources.read(accessibility: () async => throw FormAccessException(code)),
          throwsA(isA<FormAccessException>()),
        );
      }
    });
  });

  group('BrowserBridge', () {
    late _FakeTransport transport;
    late BrowserBridge bridge;
    final page = {
      'title': 'Event sign-up',
      'origin': 'https://example.org',
      'fields': [_field('ext:1', 'edit', 'Name', value: '')],
    };

    setUp(() async {
      transport = _FakeTransport()..answer = (r) => _extension(r, page: page);
      bridge = BrowserBridge(transport: transport, installManifests: false, timeout: const Duration(milliseconds: 200));
      await bridge.start();
    });

    tearDown(() => bridge.dispose());

    test('a host that says hello becomes a connected browser', () async {
      final changes = <Set<BrowserKind>>[];
      bridge.changes.listen(changes.add);
      transport.open(1);
      await _settle();
      await _settle();
      expect(bridge.connected, {BrowserKind.chrome});
      expect(changes.last, {BrowserKind.chrome});
      await transport.close(1);
      await _settle();
      expect(bridge.connected, isEmpty);
    });

    test('a host that never says hello is dropped', () async {
      transport.answer = (_) => null;
      transport.open(1);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(bridge.connected, isEmpty);
    });

    test('nothing is read or filled unless armed', () async {
      transport.open(1);
      await _settle();
      await _settle();
      expect(await bridge.read(BrowserKind.chrome), isNull);
      expect(await bridge.act(BrowserKind.chrome, 'ext:1', 'value', 'x'), isFalse);
      expect(transport.sent.where((r) => r['op'] == 'read' || r['op'] == 'act'), isEmpty);

      bridge.arm('run', true);
      expect(transport.sent.last, containsPair('on', true));
      final p = await bridge.read(BrowserKind.chrome, title: 'Event sign-up');
      expect(p!.elements.single.name, 'Name');
      expect(await bridge.act(BrowserKind.chrome, 'ext:1', 'value', 'Ada'), isTrue);
      expect(transport.sent.last, containsPair('arg', 'Ada'));

      bridge.arm('run', false);
      expect(transport.sent.last, containsPair('on', false));
      expect(await bridge.read(BrowserKind.chrome), isNull);
    });

    test('arming is held until every reason lets go', () {
      bridge.arm('autofill', true);
      bridge.arm('run', true);
      bridge.arm('run', false);
      expect(bridge.armed, isTrue);
      bridge.arm('autofill', false);
      expect(bridge.armed, isFalse);
    });

    test('targets that are not extension ids are never sent', () async {
      transport.open(1);
      await _settle();
      await _settle();
      bridge.arm('run', true);
      expect(await bridge.act(BrowserKind.chrome, '#password', 'value', 'x'), isFalse);
      expect(transport.sent.where((r) => r['op'] == 'act'), isEmpty);
    });

    test('a malformed page falls back (null), a broken frame drops the connection', () async {
      transport.answer = (r) => _extension(r, page: {'fields': 'nope'});
      transport.open(1);
      await _settle();
      await _settle();
      bridge.arm('run', true);
      expect(await bridge.read(BrowserKind.chrome), isNull);

      transport.push(1, [0, 0, 0, 0]);
      expect(bridge.connected, isEmpty);
    });

    test('cancel answers every waiting request and tells the extension', () async {
      transport.open(1);
      await _settle();
      await _settle();
      bridge.arm('run', true);
      transport.answer = (r) => r['op'] == 'read' ? null : _extension(r, page: page);
      final pending = bridge.read(BrowserKind.chrome);
      await _settle();
      bridge.cancelAll();
      expect(await pending, isNull);
      expect(transport.sent.last['op'], 'cancel');
    });
  });

  group('host manifests', () {
    test('Windows: one Chromium manifest for Chrome and Edge, one for Firefox, all under HKCU', () {
      final t = HostManifests.forPlatform(
        windows: true,
        executable: r'C:\Program Files\Sotto\sotto.exe',
        dataDir: r'C:\Users\ada\AppData\Local\Sotto',
      );
      expect(t, hasLength(2));
      final chromium = t.first;
      expect(chromium.path, r'C:\Users\ada\AppData\Local\Sotto\NativeMessagingHosts\app.sotto.bridge.json');
      expect(chromium.registryKeys, [
        r'Software\Google\Chrome\NativeMessagingHosts\app.sotto.bridge',
        r'Software\Microsoft\Edge\NativeMessagingHosts\app.sotto.bridge',
      ]);
      expect(chromium.json, {
        'name': 'app.sotto.bridge',
        'description': 'Sotto Bridge',
        'path': r'C:\Program Files\Sotto\sotto.exe',
        'type': 'stdio',
        'allowed_origins': ['chrome-extension://oaompapbahpnpllcdpidhojbdoblcpil/'],
      });
      expect(chromium.json.containsKey('allowed_extensions'), isFalse);
      final firefox = t.last;
      expect(firefox.registryKeys, [r'Software\Mozilla\NativeMessagingHosts\app.sotto.bridge']);
      expect(firefox.json['allowed_extensions'], ['bridge@sotto.app']);
      expect(firefox.json.containsKey('allowed_origins'), isFalse);
      expect(jsonDecode(firefox.contents), firefox.json);
    });

    test("macOS: each browser's per-user folder, no registry", () {
      final t = HostManifests.forPlatform(
        windows: false,
        executable: '/Applications/Sotto.app/Contents/MacOS/Sotto',
        home: '/Users/ada',
      );
      expect(t.map((x) => x.path), [
        '/Users/ada/Library/Application Support/Google/Chrome/NativeMessagingHosts/app.sotto.bridge.json',
        '/Users/ada/Library/Application Support/Microsoft Edge/NativeMessagingHosts/app.sotto.bridge.json',
        '/Users/ada/Library/Application Support/Mozilla/NativeMessagingHosts/app.sotto.bridge.json',
      ]);
      expect(t.every((x) => x.registryKeys.isEmpty), isTrue);
      expect(t.every((x) => x.json['path'] == '/Applications/Sotto.app/Contents/MacOS/Sotto'), isTrue);
      expect(t[0].json['allowed_origins'], ['chrome-extension://oaompapbahpnpllcdpidhojbdoblcpil/']);
      expect(t[1].json['allowed_origins'], t[0].json['allowed_origins']);
      expect(t[2].json['allowed_extensions'], ['bridge@sotto.app']);
    });

    test('allowed origins name only the extension', () {
      for (final windows in [true, false]) {
        for (final t in HostManifests.forPlatform(windows: windows, executable: 'x', home: '/h', dataDir: r'C:\d')) {
          final origins = (t.json['allowed_origins'] as List?) ?? const [];
          expect(origins.every((o) => RegExp(r'^chrome-extension://[a-p]{32}/$').hasMatch('$o')), isTrue);
          expect(origins.any((o) => '$o'.contains('*')), isFalse);
        }
      }
    });
  });
}

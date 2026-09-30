import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/core/platform/window_service.dart';
import 'package:sotto/data/models/script.dart';
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/data/repositories.dart';
import 'package:sotto/data/storage/local_store.dart';
import 'package:sotto/features/live/live_controller.dart';
import 'package:window_manager/window_manager.dart' show ResizeEdge;

const _primary = DisplayArea(id: 'p', visible: Rect.fromLTWH(0, 0, 1920, 1040), primary: true);
const _second = DisplayArea(id: 's', visible: Rect.fromLTWH(1920, 0, 2560, 1400));

/// A window that behaves like the OS's: a maximised or full-screen window
/// ignores new bounds, and un-maximising returns to its normal frame.
class FakeWindowHost implements WindowHost {
  FakeWindowHost({this.maximized = false, this.fullScreen = false});

  bool maximized;
  bool fullScreen;
  Rect normal = const Rect.fromLTWH(320, 110, 1280, 820);
  final setBoundsCalls = <Rect>[];

  Rect get _filled => _primary.visible;

  @override
  Future<Rect> getBounds() async => maximized || fullScreen ? _filled : normal;

  @override
  Future<void> setBounds(Rect bounds, {bool animate = false}) async {
    setBoundsCalls.add(bounds);
    if (!maximized && !fullScreen) normal = bounds;
  }

  @override
  Future<void> setPosition(Offset position, {bool animate = false}) async {
    if (!maximized && !fullScreen) normal = position & normal.size;
  }

  @override
  Future<bool> isMaximized() async => maximized;
  @override
  Future<void> maximize() async => maximized = true;
  @override
  Future<void> unmaximize() async => maximized = false;
  @override
  Future<bool> isFullScreen() async => fullScreen;
  @override
  Future<void> setFullScreen(bool on) async => fullScreen = on;

  @override
  Future<List<DisplayArea>> displays() async => const [_primary, _second];
  @override
  Future<void> init() async {}
  @override
  Future<bool> isMinimized() async => false;
  @override
  Future<void> restore() async {}
  @override
  Future<void> setOverlayChrome(bool on, {required Size minimumSize, bool shadow = true}) async {}
  @override
  Future<void> show({bool inactive = false}) async {}
  @override
  Future<void> hide() async {}
  @override
  Future<void> focus() async {}
  @override
  Future<void> setIgnoreMouseEvents(bool on) async {}
  @override
  Future<void> startDragging() async {}
  @override
  Future<void> startResizing(ResizeEdge edge) async {}
}

Script _script() {
  final now = DateTime(2026);
  return Script(
    id: 's',
    title: 'Q3',
    createdAt: now,
    updatedAt: now,
    sections: [
      Section(
        id: 'a',
        title: 'Revenue',
        beats: [Beat.create('Revenue landed at 48 million.'), Beat.create('Margin held at 31 percent.')],
      ),
    ],
  );
}

void expectNear(Rect actual, Rect expected) {
  for (final (a, e) in [
    (actual.left, expected.left),
    (actual.top, expected.top),
    (actual.width, expected.width),
    (actual.height, expected.height),
  ]) {
    expect((a - e).abs(), lessThanOrEqualTo(2), reason: 'got $actual, want $expected');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('overlay geometry', () {
    test('nothing saved: 480 × 120 just below the top centre of the primary display', () {
      final r = OverlayGeometry.frame(
        const AppSettings(),
        OverlayGeometry.displayFor(const AppSettings(), [_second, _primary]),
      );
      expect(r.size, const Size(480, 120));
      expect(r.center.dx, 960);
      expect(r.top, 12);
    });

    test('saved geometry comes back, on the display it was left on', () {
      const s = AppSettings(overlaySize: (600, 140), overlayPositions: {'s': (2100, 40)});
      final d = OverlayGeometry.displayFor(s, const [_primary, _second]);
      expect(d.id, 's');
      expect(OverlayGeometry.frame(s, d), const Rect.fromLTWH(2100, 40, 600, 140));
    });

    test('never below 320 × 60, never off the display', () {
      const s = AppSettings(overlaySize: (100, 20), overlayPositions: {'p': (1900, 1030)});
      final r = OverlayGeometry.frame(s, _primary);
      expect(r.size, const Size(320, 60));
      expect(
        _primary.visible.contains(r.topLeft) && _primary.visible.contains(r.bottomRight - const Offset(1, 1)),
        isTrue,
      );
    });

    test('geometry saved before the fix is dropped; new geometry survives a round trip', () {
      final old = AppSettings.fromJson({
        'overlaySize': [1920, 1040],
        'overlayPositions': {
          'p': [0, 0],
        },
      });
      expect(old.overlaySize, (480.0, 120.0));
      expect(old.overlayPositions, isEmpty);
      final kept = AppSettings.fromJson(
        const AppSettings(overlaySize: (700, 150), overlayPositions: {'p': (10, 20)}).toJson(),
      );
      expect(kept.overlaySize, (700.0, 150.0));
      expect(kept.overlayPositions, {'p': (10.0, 20.0)});
    });
  });

  group('live session window', () {
    late Directory tmp;
    late ProviderContainer container;
    late FakeWindowHost host;
    late WindowService window;

    setUp(() async {
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      for (final name in ['dev.leanflutter.plugins/hotkey_manager', 'dev.leanflutter.plugins/hotkey_manager_event']) {
        messenger.setMockMethodCallHandler(MethodChannel(name), (_) async => null);
      }
      tmp = Directory.systemTemp.createTempSync('sotto_overlay');
      final store = await LocalStore.open(path: tmp.path);
      // Went live from a maximised main window: the case that filled the screen.
      host = FakeWindowHost(maximized: true);
      window = WindowService(host: host, supportedOverride: true);
      container = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store), windowServiceProvider.overrideWithValue(window)],
      );
      container
          .read(settingsProvider.notifier)
          .update(
            (s) => s.copyWith(
              advanceMode: AdvanceMode.manual,
              overlaySize: (560, 140),
              overlayPositions: {'p': (680, 12)},
            ),
          );
    });

    tearDown(() async {
      container.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    const saved = Rect.fromLTWH(680, 12, 560, 140);

    test('the overlay opens at the saved geometry, not the size of the screen', () async {
      await container.read(liveControllerProvider.notifier).start(_script());

      expect(window.isOverlay, isTrue);
      final b = await window.bounds();
      expectNear(b, saved);
      expect(OverlayGeometry.fills(b, _primary.visible), isFalse);
    });

    test('an OS maximise while live is undone and never saved', () async {
      final live = container.read(liveControllerProvider.notifier);
      await live.start(_script());

      await host.maximize(); // Aero Snap / a double-click on the drag area
      await live.rememberGeometry();
      expect(container.read(settingsProvider).overlaySize, (560.0, 140.0));

      await window.undoFill();
      expectNear(await window.bounds(), saved);
    });

    test('ending the session gives the main window back, maximised', () async {
      final live = container.read(liveControllerProvider.notifier);
      await live.start(_script());
      await live.end();
      expect(window.isOverlay, isFalse);
      expect(host.maximized, isTrue);
    });
  });
}

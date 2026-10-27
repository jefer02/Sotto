// The overlay's hover controls never cover the script: in every layout, at
// the main window's minimum size and at small overlay sizes, the line being
// read and the one after it stay clear of the controls and of the name a
// hovered button shows. Runs the real overlay (the app's live session in
// manual mode, the native window faked).
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sotto/app/app.dart';
import 'package:sotto/core/design/tokens.dart';
import 'package:sotto/core/platform/window_service.dart';
import 'package:sotto/data/models/script.dart';
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/data/repositories.dart';
import 'package:sotto/data/seed.dart';
import 'package:sotto/data/storage/local_store.dart';
import 'package:sotto/features/live/live_controller.dart';
import 'package:sotto/features/live/overlay/reading_view.dart';
import 'package:sotto/features/live/overlay_screen.dart';
import 'package:sotto/l10n/l10n.dart';

import '../core/overlay_window_test.dart' show FakeWindowHost;

void main() {
  late Directory tmp;
  late ProviderContainer container;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('sotto_controls');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);
    for (final name in [
      'com.llfbandit.record/messages',
      'dev.leanflutter.plugins/hotkey_manager',
      'dev.leanflutter.plugins/hotkey_manager_event',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'readAll' ? <String, String>{} : null,
    );
  });

  testWidgets('the active and next lines never meet the controls or a hovered name', (tester) async {
    // The main window's screens stay mounted behind the overlay and are laid
    // out at its size: their overflow is theirs, not the overlay's.
    final report = FlutterError.onError;
    FlutterError.onError = (details) {
      final behind = RegExp(r'lib/features/(editor|library)/').hasMatch(details.toString());
      if (!behind) report?.call(details);
    };
    addTearDown(() => FlutterError.onError = report);
    await tester.runAsync(() async {
      await initializeDateFormatting();
      final store = await LocalStore.open(path: tmp.path);
      container = ProviderContainer(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          // A fake native window that does move: a bottom placement puts the
          // overlay low on the display, so the controls go above the script.
          windowServiceProvider.overrideWithValue(WindowService(host: FakeWindowHost(), supportedOverride: true)),
        ],
      );
      container
          .read(settingsProvider.notifier)
          .update(
            (s) => s.copyWith(
              uiLanguage: AppLanguage.en,
              onboarded: true,
              welcomeDone: true,
              advanceMode: AdvanceMode.manual,
              reduceMotion: true,
            ),
          );
      L10n.current = lookupAppLocalizations(const Locale('en'));
      await seedIfEmpty(container.read(scriptRepositoryProvider));
    });
    addTearDown(() => container.dispose());
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    // The library behind the session, at a roomy size (the session's own
    // sizes are set below).
    tester.view.physicalSize = const Size(1280, 820);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const SottoApp()));

    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    final scripts = await tester.runAsync(() => container.read(scriptRepositoryProvider).watchAll().first);
    final Script script = scripts!.firstWhere((s) => s.beatCount > 3);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1, 1));
    addTearDown(mouse.removePointer);

    Rect? visible(Key key, Rect area) {
      final f = find.byKey(key);
      if (f.evaluate().isEmpty) return null;
      final r = tester.getRect(f.first).intersect(area);
      return r.width > 0 && r.height > 0 ? r : null;
    }

    bool overlap(Rect a, Rect b) {
      final i = a.intersect(b);
      return i.width > 0.5 && i.height > 0.5;
    }

    final cases = <(OverlayLayout, Size)>[
      for (final layout in [
        OverlayLayout.ticker,
        OverlayLayout.compact,
        OverlayLayout.standard,
        OverlayLayout.column,
        OverlayLayout.rail,
      ])
        (layout, Layout.windowMin),
      (OverlayLayout.ticker, const Size(477, 359)),
      (OverlayLayout.ticker, const Size(477, 140)),
      (OverlayLayout.compact, const Size(480, 160)),
      (OverlayLayout.standard, const Size(720, 200)),
      (OverlayLayout.column, const Size(480, 520)),
      (OverlayLayout.rail, const Size(1200, 130)),
      (OverlayLayout.standard, const Size(320, 120)),
    ];
    for (final (layout, size) in cases) {
      for (final placement in [OverlayPlacement.topCenter, OverlayPlacement.bottomCenter]) {
        final what = '${layout.name} ${size.width.round()}×${size.height.round()} ${placement.name}';
        container
            .read(settingsProvider.notifier)
            .update((s) => s.copyWith(layout: layout, placement: placement, overlaySize: (size.width, size.height)));
        tester.view.physicalSize = size;
        await tester.runAsync(() => container.read(liveControllerProvider.notifier).start(script));
        await settle();
        // Advance a beat so there are lines both before and after.
        container.read(liveControllerProvider.notifier).nextBeat();
        await settle();

        // Hover the overlay (the panel shows), then a button (it names itself).
        await mouse.moveTo(Offset(size.width / 2, size.height / 2));
        await settle();
        final controls = find.byKey(overlayControlsKey);
        expect(controls, findsOneWidget, reason: what);
        final pause = find.descendant(
          of: controls,
          matching: find.byWidgetPredicate((w) => w is Tooltip && w.message == L10n.current.pause),
        );
        await mouse.moveTo(tester.getCenter(pause));
        await tester.pump(const Duration(seconds: 2));

        // What of a line shows: it, clipped by the reading area it scrolls in.
        final area = tester.getRect(find.byType(ReadingView)).intersect(Offset.zero & size);
        final controlsRect = tester.getRect(controls);
        final current = visible(currentLineKey, area);
        expect(current, isNotNull, reason: '$what: the line being read is on screen');
        expect(overlap(current!, controlsRect), isFalse, reason: '$what: controls cover the current line');
        final next = visible(nextLineKey, area);
        if (next != null) expect(overlap(next, controlsRect), isFalse, reason: '$what: controls cover the next line');

        // The hovered button's name: never over the script, never floating.
        for (final label in find.text(L10n.current.pause).evaluate()) {
          final r = tester.getRect(find.byWidget(label.widget));
          expect(overlap(current, r), isFalse, reason: '$what: the name covers the current line');
          if (next != null) expect(overlap(next, r), isFalse, reason: '$what: the name covers the next line');
        }
        // A floating tooltip would be a second "Pause" on screen.
        expect(
          find.text(L10n.current.pause).evaluate().length,
          lessThanOrEqualTo(1),
          reason: '$what: a tooltip floats',
        );

        await mouse.moveTo(const Offset(1, 1));
        // The main window comes back at its own size, not the overlay's.
        tester.view.physicalSize = const Size(1280, 820);
        await tester.runAsync(() => container.read(liveControllerProvider.notifier).end());
        await settle();
      }
    }
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  });
}

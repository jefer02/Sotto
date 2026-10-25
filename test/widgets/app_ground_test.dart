// Switching between top-level screens (library, Settings, editor) never
// shows two screens at once, nor the bare window: the new one fades in over
// the app's ground (once the overlay has run the window is transparent, and
// the desktop showed through mid-transition). Under reduced motion the
// switch is instant: the old screen was left painted under the new one, then
// a blank frame came between them.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sotto/app/app.dart';
import 'package:sotto/app/router.dart';
import 'package:sotto/core/design/tokens.dart';
import 'package:sotto/core/platform/window_service.dart';
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/data/repositories.dart';
import 'package:sotto/data/seed.dart';
import 'package:sotto/data/storage/local_store.dart';
import 'package:sotto/l10n/l10n.dart';

import '../core/overlay_window_test.dart' show FakeWindowHost;

Future<void> _loadFonts() async {
  for (final (family, file) in const [
    ('Geist', 'assets/fonts/Geist-Variable.ttf'),
    ('GeistMono', 'assets/fonts/GeistMono-Variable.ttf'),
    ('AtkinsonHyperlegibleNext', 'assets/fonts/AtkinsonHyperlegibleNext-Variable.ttf'),
  ]) {
    final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(File(file).readAsBytesSync())));
    await loader.load();
  }
}

void main() {
  late Directory tmp;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('sotto_ground');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);
    for (final name in [
      'com.llfbandit.record/messages',
      'dev.leanflutter.plugins/hotkey_manager',
      'dev.leanflutter.plugins/hotkey_manager_event',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(name),
        (call) async => call.method == 'listInputDevices' ? [] : null,
      );
    }
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'readAll' ? <String, String>{} : null,
    );
  });

  tearDownAll(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  for (final still in [false, true]) {
    testWidgets('screen switches${still ? ' (reduced motion)' : ''}: one screen at a time, over the ground', (
      tester,
    ) async {
      late ProviderContainer container;
      await tester.runAsync(() async {
        await _loadFonts();
        await initializeDateFormatting();
        final store = await LocalStore.open(path: (Directory('${tmp.path}/$still')..createSync()).path);
        container = ProviderContainer(
          overrides: [
            localStoreProvider.overrideWithValue(store),
            windowServiceProvider.overrideWithValue(WindowService(host: FakeWindowHost(), supportedOverride: false)),
          ],
        );
        container
            .read(settingsProvider.notifier)
            .update((s) => s.copyWith(uiLanguage: AppLanguage.en, onboarded: true, reduceMotion: still));
        L10n.current = lookupAppLocalizations(const Locale('en'));
        await seedIfEmpty(container.read(scriptRepositoryProvider));
      });
      addTearDown(container.dispose);

      tester.view.physicalSize = Layout.windowMin;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(key: key, child: const SottoApp()),
        ),
      );

      Future<void> settle() async {
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      /// The least opaque pixel in the window, 0–255.
      Future<int> minAlpha() async {
        final alpha = await tester.runAsync(() async {
          final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = (await image.toByteData())!;
          image.dispose();
          var min = 255;
          for (var i = 3; i < bytes.lengthInBytes; i += 4) {
            final a = bytes.getUint8(i);
            if (a < min) min = a;
          }
          return min;
        });
        return alpha!;
      }

      await settle();
      // The welcome dialog opens on first run.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle();

      /// How visible [text] is at its most visible match: the product of the
      /// opacities above it, 0 when offstage, -1 when it isn't there.
      double visibility(String text) {
        var best = -1.0;
        for (final e in find.text(text, skipOffstage: false).evaluate()) {
          var o = 1.0;
          e.visitAncestorElements((a) {
            final w = a.widget;
            if (w is Opacity) o *= w.opacity;
            if (w is FadeTransition) o *= w.opacity.value;
            if (w is Offstage && w.offstage) o = 0;
            return true;
          });
          if (o > best) best = o;
        }
        return best;
      }

      final router = container.read(routerProvider);
      final scripts = await tester.runAsync(() => container.read(scriptRepositoryProvider).watchAll().first);
      final l = L10n.current;
      // Each screen, and a text only it shows.
      final screens = [
        ('/settings/shortcuts', l.backToLibrary),
        ('/', l.navHome),
        ('/script/${scripts!.first.id}', l.tabWrite),
        ('/settings/appearance', l.backToLibrary),
      ];
      var from = ('/', l.navHome);
      for (final to in screens) {
        router.go(to.$1);
        for (var i = 0; i < 6; i++) {
          await tester.pump(i == 0 ? Duration.zero : const Duration(milliseconds: 40));
          final what = '${from.$1} → ${to.$1}, frame $i';
          expect(await minAlpha(), 255, reason: '$what: the window shows through');
          if (from.$2 != to.$2) {
            expect(visibility(from.$2), lessThanOrEqualTo(0), reason: '$what: the old screen shows');
          }
          if (still) expect(visibility(to.$2), 1, reason: '$what: the new screen is not all there');
        }
        await settle();
        from = to;
      }

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    });
  }
}

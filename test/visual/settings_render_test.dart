// Renders every Settings page at the top and scrolled to the end, in both
// languages and at four window sizes, for reviewing how the columns fill
// the page. Opt-in, because it is slow and writes files:
//   $env:SOTTO_RENDER=1; flutter test --no-pub test/visual/settings_render_test.dart
// SOTTO_RENDER_OUT=folder (default build/settings). Files are named
// <lang>-<size>-<page>-<top|end>.png.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sotto/app/app.dart';
import 'package:sotto/app/router.dart';
import 'package:sotto/core/platform/window_service.dart';
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/data/repositories.dart';
import 'package:sotto/data/seed.dart';
import 'package:sotto/data/storage/local_store.dart';
import 'package:sotto/features/settings/settings_screen.dart';
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

final _render = Platform.environment['SOTTO_RENDER'] != null;
final _out = Platform.environment['SOTTO_RENDER_OUT'] ?? 'build/settings';
const _sizes = [Size(960, 600), Size(1280, 800), Size(1600, 1000), Size(1920, 1080)];

void main() {
  late Directory tmp;

  setUpAll(() async {
    if (!_render) return;
    TestWidgetsFlutterBinding.ensureInitialized();
    tmp = Directory.systemTemp.createTempSync('sotto_settings_render');
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

  for (final lang in ['es', 'en']) {
    testWidgets('settings pages: $lang', skip: !_render, (tester) async {
      late ProviderContainer container;
      await tester.runAsync(() async {
        await _loadFonts();
        await initializeDateFormatting();
        final store = await LocalStore.open(path: Directory(tmp.path).createTempSync(lang).path);
        container = ProviderContainer(
          overrides: [
            localStoreProvider.overrideWithValue(store),
            windowServiceProvider.overrideWithValue(WindowService(host: FakeWindowHost(), supportedOverride: false)),
          ],
        );
        container
            .read(settingsProvider.notifier)
            .update(
              (s) => s.copyWith(
                uiLanguage: lang == 'es' ? AppLanguage.es : AppLanguage.en,
                onboarded: true,
                formsEnabled: true,
              ),
            );
        L10n.current = lookupAppLocalizations(Locale(lang));
        await seedIfEmpty(container.read(scriptRepositoryProvider));
      });
      addTearDown(container.dispose);
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
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      Future<void> shot(String name) async {
        await settle();
        await tester.runAsync(() async {
          final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$_out/$name.png')
            ..createSync(recursive: true)
            ..writeAsBytesSync(png!.buffer.asUint8List());
        });
      }

      final router = container.read(routerProvider);
      for (final size in _sizes) {
        tester.view.physicalSize = size;
        for (final page in SettingsPage.values) {
          router.go('/settings/${page.name}');
          await settle();
          final name = '$lang-${size.width.round()}x${size.height.round()}-${page.name}';
          await shot('$name-top');
          // The page's own scroll view: the first one under the scaffold.
          final scrollable = find.descendant(of: find.byType(SettingsPageScaffold), matching: find.byType(Scrollable));
          final position = tester.state<ScrollableState>(scrollable.first).position;
          if (position.maxScrollExtent > 0) {
            position.jumpTo(position.maxScrollExtent);
            await shot('$name-end');
          }
        }
      }
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    });
  }
}

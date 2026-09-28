// Renders every main-window screen to build/screens/*.png for visual review.
// Opt-in, because it is slow and writes files:
//   SOTTO_RENDER=1 flutter test test/visual
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
import 'package:sotto/data/models/script.dart';
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/data/repositories.dart';
import 'package:sotto/data/seed.dart';
import 'package:sotto/data/storage/local_store.dart';
import 'package:sotto/l10n/l10n.dart';

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
final _lang = Platform.environment['SOTTO_RENDER_LANG'] ?? 'es';

void main() {
  late Directory tmp;
  late ProviderContainer container;

  setUpAll(() async {
    if (!_render) return;
    TestWidgetsFlutterBinding.ensureInitialized();
    tmp = Directory.systemTemp.createTempSync('sotto_render');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tmp.path,
    );
    // Native plugins that screens touch: answer with "nothing here".
    for (final name in [
      'com.llfbandit.record/messages',
      'dev.leanflutter.plugins/hotkey_manager',
      'dev.leanflutter.plugins/hotkey_manager_event',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), (call) async => call.method == 'listInputDevices' ? [] : null);
    }
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'readAll' ? <String, String>{} : null,
    );
  });

  testWidgets('screens', skip: !_render, (tester) async {
    await tester.runAsync(() async {
      await _loadFonts();
      await initializeDateFormatting();
      final store = await LocalStore.open(path: tmp.path);
      container = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store), windowServiceProvider.overrideWithValue(WindowService())],
      );
      container
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(uiLanguage: _lang == 'es' ? AppLanguage.es : AppLanguage.en, onboarded: true));
      L10n.current = lookupAppLocalizations(Locale(_lang));
      await seedIfEmpty(container.read(scriptRepositoryProvider));
    });

    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    final key = GlobalKey();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(key: key, child: const SottoApp()),
      ),
    );

    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> shot(String name) async {
      await settle();
      await tester.runAsync(() async {
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File('build/screens/$_lang-$name.png')
          ..createSync(recursive: true)
          ..writeAsBytesSync(png!.buffer.asUint8List());
      });
    }

    // First run: the welcome dialog opens over the library.
    await shot('welcome-1');
    await tester.tap(find.text(L10n.current.welcomeNext));
    await shot('welcome-2');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle();

    final router = container.read(routerProvider);
    final scripts = await tester.runAsync(() => container.read(scriptRepositoryProvider).watchAll().first);
    final id = scripts!.first.id;
    final blank = Script.blank();
    await tester.runAsync(() => container.read(scriptRepositoryProvider).save(blank));
    final collections = await tester.runAsync(() => container.read(scriptRepositoryProvider).watchCollections().first);
    final used = {for (final s in scripts) s.collectionId};
    final emptyCollection = collections!.firstWhere((c) => !used.contains(c.id));
    final extra = (Platform.environment['SOTTO_RENDER_ROUTES'] ?? '').split(',').where((r) => r.isNotEmpty);
    final routes = {
      'home': '/',
      'scripts': '/scripts',
      'archive': '/archive',
      'sessions': '/sessions',
      'editor-write': '/script/$id',
      'editor-prep': '/script/$id?tab=prep',
      'editor-rehearsals': '/script/$id?tab=rehearsals',
      'editor-blank': '/script/${blank.id}',
      'editor-blank-prep': '/script/${blank.id}?tab=prep',
      'collection-empty': '/collections/${emptyCollection.id}',
      for (final p in ['shortcuts', 'appearance', 'voice', 'answers', 'general', 'integrations', 'privacy'])
        'settings-$p': '/settings/$p',
      for (final r in extra) r.replaceAll(RegExp('[^a-z0-9]+'), '-'): r,
    };
    for (final MapEntry(key: name, value: route) in routes.entries) {
      router.go(route);
      await shot(name);
    }
    // Leave no timers running.
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
  });
}

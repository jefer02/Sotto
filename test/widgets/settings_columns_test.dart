// Settings pages never leave half the window blank: every page is one
// centered column at most 720 px wide, and the pages with something live
// beside it (Appearance's preview, Voice's mic test and pace) keep that
// panel in view while the column scrolls. In English and Spanish, at the
// smallest window and at three common sizes, with nothing overflowing.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/core/design/theme.dart';
import 'package:sotto/core/design/tokens.dart';
import 'package:sotto/core/widgets/display.dart';
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/data/repositories.dart';
import 'package:sotto/data/storage/local_store.dart';
import 'package:sotto/features/settings/settings_screen.dart';
import 'package:sotto/l10n/l10n.dart';

Future<void> _loadFonts() async {
  for (final (family, file) in const [
    ('Geist', 'assets/fonts/Geist-Variable.ttf'),
    ('GeistMono', 'assets/fonts/GeistMono-Variable.ttf'),
  ]) {
    final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(File(file).readAsBytesSync())));
    await loader.load();
  }
}

/// While one column scrolls, the other must keep at least this share of
/// the view filled (or all of itself, when it is shorter than that).
const _minVisible = 0.4;

const _sizes = [Size(960, 600), Size(1280, 800), Size(1600, 1000), Size(1920, 1080)];

void main() {
  late Directory tmp;
  late LocalStore store;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmp = Directory.systemTemp.createTempSync('sotto_settings_columns');
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
    store = await LocalStore.open(path: tmp.path);
  });

  tearDownAll(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  for (final lang in ['en', 'es']) {
    for (final size in _sizes) {
      final label = '$lang at ${size.width.round()}×${size.height.round()}';
      testWidgets('no blank column on any Settings page: $label', (tester) async {
        await tester.runAsync(_loadFonts);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        L10n.current = lookupAppLocalizations(Locale(lang));
        final container = ProviderContainer(overrides: [localStoreProvider.overrideWithValue(store)]);
        addTearDown(container.dispose);
        container
            .read(settingsProvider.notifier)
            .update(
              (s) => s.copyWith(
                uiLanguage: lang == 'es' ? AppLanguage.es : AppLanguage.en,
                overlayStyle: OverlayStyle.textOnly,
                overlayTextColor: OverlayTextColor.auto,
                formsEnabled: true,
              ),
            );

        for (final page in SettingsPage.values) {
          final where = '${page.name} ($label)';
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                theme: buildSottoTheme(SottoPalette.stage),
                locale: Locale(lang),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: SettingsScreen(key: ValueKey(page), page: page),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull, reason: 'overflow on $where');

          final area = tester.getRect(find.byType(SettingsPageScaffold));
          final column = tester.getRect(find.byKey(SettingsPageScaffold.columnKey));
          final panelFinder = find.byKey(SettingsPageScaffold.panelKey);
          final panel = panelFinder.evaluate().isEmpty ? null : tester.getRect(panelFinder);
          expect(column.width, lessThanOrEqualTo(SettingsPageScaffold.maxColumn + 0.5), reason: where);

          final beside = panel != null && panel.left >= column.right;
          if (!beside) {
            // One column, centered; a panel (if any) leads it at its width.
            expect(
              (column.left - area.left) - (area.right - column.right),
              moreOrLessEquals(0, epsilon: 1),
              reason: 'centered: $where',
            );
            if (panel != null) {
              expect(panel.bottom, lessThanOrEqualTo(column.top), reason: where);
              expect(panel.width, moreOrLessEquals(column.width, epsilon: 0.5), reason: where);
            }
            // Nothing sits beside the column.
            for (final e in [
              ...find
                  .descendant(of: find.byType(SettingsPageScaffold), matching: find.byType(SettingsGroup))
                  .evaluate(),
              ...find.descendant(of: find.byType(SettingsPageScaffold), matching: find.byType(SurfaceCard)).evaluate(),
            ]) {
              final r = tester.getRect(find.byWidget(e.widget));
              expect(r.left, greaterThanOrEqualTo(column.left - 0.5), reason: where);
              expect(r.right, lessThanOrEqualTo(column.right + 0.5), reason: where);
            }
            continue;
          }

          // Column and panel side by side: scroll the column from top to
          // end; the panel must stay in view the whole way.
          final scrollable = find
              .descendant(of: find.byType(SettingsPageScaffold), matching: find.byType(Scrollable))
              .first;
          final position = tester.state<ScrollableState>(scrollable).position;
          final view = tester.getRect(scrollable);
          expect(position.maxScrollExtent, greaterThan(0), reason: 'the column scrolls: $where');
          double visible(Rect r) => (r.bottom.clamp(view.top, view.bottom) - r.top.clamp(view.top, view.bottom));
          for (final t in [0.0, 0.25, 0.5, 0.75, 1.0]) {
            position.jumpTo(position.maxScrollExtent * t);
            await tester.pump();
            final c = tester.getRect(find.byKey(SettingsPageScaffold.columnKey));
            final p = tester.getRect(panelFinder);
            for (final (name, r) in [('column', c), ('panel', p)]) {
              expect(
                visible(r),
                greaterThanOrEqualTo(math.min(r.height, view.height * _minVisible) - 1),
                reason: '$name in view at ${(t * 100).round()} % scrolled: $where',
              );
            }
            // The panel never leaves the column's band or overlaps it.
            expect(p.left, greaterThanOrEqualTo(c.right), reason: where);
            expect(p.top, greaterThanOrEqualTo(c.top - 0.5), reason: where);
            expect(p.bottom, lessThanOrEqualTo(math.max(c.bottom, c.top + p.height) + 0.5), reason: where);
          }
          // And it can still be used where it is.
          expect(tester.hitTestOnBinding(tester.getCenter(panelFinder)).path, isNotEmpty);
        }
      });
    }
  }

  testWidgets('Voice and Appearance keep a side panel; the other pages are one column', (tester) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    L10n.current = lookupAppLocalizations(const Locale('en'));
    final container = ProviderContainer(overrides: [localStoreProvider.overrideWithValue(store)]);
    addTearDown(container.dispose);
    container.read(settingsProvider.notifier).update((s) => s.copyWith(formsEnabled: true));
    for (final page in SettingsPage.values) {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildSottoTheme(SottoPalette.stage),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: SettingsScreen(key: ValueKey(page), page: page),
          ),
        ),
      );
      await tester.pump();
      final hasPanel = find.byKey(SettingsPageScaffold.panelKey).evaluate().isNotEmpty;
      expect(hasPanel, page == SettingsPage.voice || page == SettingsPage.appearance, reason: page.name);
    }
    await tester.pump(const Duration(seconds: 1));
  });
}

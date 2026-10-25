// Every Settings page, in English and Spanish, at full HD, at the default
// window (1280 wide: two narrow columns) and at the smallest: no row's
// title and description may be squeezed into a sliver beside a wide control
// (the "Overlay text color" row wrapped word by word in a ~60 px column),
// and nothing may overflow.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/core/design/theme.dart';
import 'package:sotto/core/design/tokens.dart';
import 'package:sotto/core/widgets/controls.dart';
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

/// The narrowest a row's title column may get beside its control (the row
/// keeps 240; a leading icon takes the rest).
const _minLabel = 200.0;

void main() {
  late Directory tmp;
  late LocalStore store;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmp = Directory.systemTemp.createTempSync('sotto_settings_layout');
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

  group('SettingRowLayout', () {
    Widget row(double width) => MaterialApp(
      theme: buildSottoTheme(SottoPalette.stage),
      home: Material(
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: SettingRow(
              title: 'Overlay text color',
              subtitle: 'Dark text on light slides, light text on dark ones — checked on this computer every 0.8 s',
              trailing: SegmentedControl<int>(
                width: 360,
                segments: const [Segment(0, 'Auto'), Segment(1, 'Light'), Segment(2, 'Dark'), Segment(3, 'Custom')],
                value: 0,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    RenderSettingRow layout(WidgetTester tester) => tester.renderObject(find.byType(SettingRowLayout));

    testWidgets('a wide control stays beside the label while the label keeps 240 px', (tester) async {
      await tester.pumpWidget(row(700));
      final r = layout(tester);
      expect(r.stacked, isFalse);
      expect(tester.getSize(find.byType(SegmentedControl<int>)).width, 360);
      expect(tester.getTopLeft(find.byType(SegmentedControl<int>)).dx, greaterThan(14 + 240));
    });

    testWidgets('…and moves under it, full width, when it would not', (tester) async {
      await tester.pumpWidget(row(520));
      final r = layout(tester);
      expect(r.stacked, isTrue);
      final title = tester.getRect(find.text('Overlay text color'));
      final control = tester.getRect(find.byType(SegmentedControl<int>));
      expect(control.top, greaterThan(title.bottom));
      expect(control.width, 520 - 28);
      expect(tester.takeException(), isNull);
    });
  });

  for (final lang in ['en', 'es']) {
    for (final size in [const Size(1920, 1080), const Size(1280, 820), Layout.windowMin]) {
      testWidgets('every Settings page lays out: $lang at ${size.width.round()}×${size.height.round()}', (
        tester,
      ) async {
        await tester.runAsync(_loadFonts);
        // Tall enough that every row is built, at the window's width.
        tester.view.physicalSize = Size(size.width, 4000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        L10n.current = lookupAppLocalizations(Locale(lang));

        final container = ProviderContainer(overrides: [localStoreProvider.overrideWithValue(store)]);
        addTearDown(container.dispose);
        // The rows that only show in some states, shown: text-only style
        // with the automatic text color (the longest description).
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
          expect(tester.takeException(), isNull, reason: '${page.name} ($lang)');

          for (final e in find.byType(SettingRow).evaluate()) {
            final row = e.widget as SettingRow;
            final title = find.descendant(of: find.byWidget(row), matching: find.text(row.title)).first;
            final column = find.ancestor(of: title, matching: find.byType(Column)).first;
            expect(
              tester.getSize(column).width,
              greaterThanOrEqualTo(_minLabel),
              reason: '"${row.title}" on ${page.name} ($lang, ${size.width.round()} px wide)',
            );
          }
        }
      });
    }
  }
}

// Markers to check in the editor and pre-flight: the Write tab counts them,
// walks through them across sections with each one selected (so typing
// replaces it), removes one, opens on a given one; pre-flight warns without
// blocking and opens the first.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sotto/core/design/theme.dart';
import 'package:sotto/core/design/tokens.dart';
import 'package:sotto/core/widgets/stage_transitions.dart';
import 'package:sotto/data/models/script.dart';
import 'package:sotto/data/repositories.dart';
import 'package:sotto/data/storage/local_store.dart';
import 'package:sotto/domain/structuring/check_markers.dart';
import 'package:sotto/features/editor/editor_controller.dart';
import 'package:sotto/features/editor/write_tab.dart';
import 'package:sotto/features/library/readiness.dart';
import 'package:sotto/features/preflight/preflight_dialog.dart';
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

/// Scripts in memory: the editor saves as you type, and a Hive write begun
/// on one test's fake clock would hold the box for the next.
class _MemoryScripts extends ScriptRepository {
  _MemoryScripts(super.store);
  final _scripts = <String, Script>{};
  final _changes = StreamController<List<Script>>.broadcast();

  @override
  Script? get(String id) => _scripts[id];

  @override
  Future<void> save(Script script) async {
    _scripts[script.id] = script;
    _changes.add(_scripts.values.toList());
  }

  @override
  Stream<List<Script>> watchAll() async* {
    yield _scripts.values.toList();
    yield* _changes.stream;
  }
}

Script _script(String id) {
  final now = DateTime(2026);
  return Script(
    id: id,
    title: 'Q3',
    createdAt: now,
    updatedAt: now,
    sections: [
      Section(
        id: '$id-a',
        title: 'Results',
        beats: [
          Beat(id: '$id-b1', text: 'Thanks for coming, everyone.'),
          Beat(id: '$id-b2', text: 'Revenue grew [CHECK: Q3 revenue] this quarter.'),
          Beat(id: '$id-b3', text: 'Margin held at 48.2% [CHECK: confirm with finance].'),
        ],
      ),
      Section(
        id: '$id-c',
        title: 'Next',
        beats: [Beat(id: '$id-b4', text: 'We open the warehouse in [CHECK: opening month].')],
      ),
    ],
  );
}

void main() {
  late Directory tmp;
  late LocalStore store;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmp = Directory.systemTemp.createTempSync('sotto_markers_ui');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);
    store = await LocalStore.open(path: tmp.path);
    L10n.current = lookupAppLocalizations(const Locale('en'));
  });

  tearDownAll(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// The text field holding [beatId]'s text, and what is selected in it.
  String selectedIn(WidgetTester tester) {
    final focused = find.byWidgetPredicate((w) => w is EditableText && w.focusNode.hasFocus);
    expect(focused, findsOneWidget, reason: 'a beat field has focus');
    final field = tester.widget<EditableText>(focused);
    final sel = field.controller.selection;
    return field.controller.text.substring(sel.start, sel.end);
  }

  /// Closes the editor inside the test, so its last save and timers run
  /// before teardown.
  Future<void> closeEditor(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    }
  }

  Future<ProviderContainer> pumpWriteTab(WidgetTester tester, String id, {int? openMarker}) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scripts = _MemoryScripts(store);
    await scripts.save(_script(id));
    final container = ProviderContainer(
      overrides: [localStoreProvider.overrideWithValue(store), scriptRepositoryProvider.overrideWithValue(scripts)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildSottoTheme(SottoPalette.stage),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: WriteTab(scriptId: id, openMarker: openMarker),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return container;
  }

  testWidgets('the Write tab counts the markers and walks through them, selected', (tester) async {
    final container = await pumpWriteTab(tester, 'walk');
    expect(find.byKey(const ValueKey('marker-bar')), findsOneWidget);
    expect(find.text('3 spots to check'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('marker-next')));
    await tester.pump();
    await tester.pump();
    expect(selectedIn(tester), '[CHECK: Q3 revenue]');
    expect(find.textContaining('1/3 · Q3 revenue'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('marker-next')));
    await tester.pump();
    await tester.pump();
    expect(selectedIn(tester), '[CHECK: confirm with finance]');

    // Into the next section.
    await tester.tap(find.byKey(const ValueKey('marker-next')));
    await tester.pump();
    await tester.pump();
    expect(container.read(editorProvider('walk')).section, 1);
    expect(selectedIn(tester), '[CHECK: opening month]');

    // Around again, and back.
    await tester.tap(find.byKey(const ValueKey('marker-next')));
    await tester.pump();
    await tester.pump();
    expect(selectedIn(tester), '[CHECK: Q3 revenue]');
    await tester.tap(find.byKey(const ValueKey('marker-prev')));
    await tester.pump();
    await tester.pump();
    expect(selectedIn(tester), '[CHECK: opening month]');
    await closeEditor(tester);
  });

  testWidgets('a marker is resolved by removing it or typing over it', (tester) async {
    final container = await pumpWriteTab(tester, 'resolve');
    await tester.tap(find.byKey(const ValueKey('marker-next')));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('marker-remove')));
    await tester.pump();
    await tester.pump();
    final script = container.read(editorProvider('resolve')).script!;
    expect(script.sections[0].beats[1].text, 'Revenue grew this quarter.');
    expect(find.text('2 spots to check'), findsOneWidget);
    // The next marker is shown, ready to be typed over.
    expect(selectedIn(tester), '[CHECK: confirm with finance]');

    final focused = find.byWidgetPredicate((w) => w is EditableText && w.focusNode.hasFocus);
    await tester.enterText(focused, 'Margin held at 48.2%, as finance confirmed.');
    await tester.pump();
    expect(CheckMarkers.countIn(container.read(editorProvider('resolve')).script!.sections), 1);
    expect(find.text('1 spot to check'), findsOneWidget);

    // The last one gone, the bar goes too.
    await tester.tap(find.byKey(const ValueKey('marker-next')));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('marker-remove')));
    await tester.pump();
    expect(find.byKey(const ValueKey('marker-bar')), findsNothing);
    await closeEditor(tester);
  });

  testWidgets('opens on the marker it is asked for', (tester) async {
    await pumpWriteTab(tester, 'open', openMarker: 2);
    await tester.pump();
    expect(selectedIn(tester), '[CHECK: opening month]');
    await closeEditor(tester);
  });

  group('pre-flight', () {
    Future<GoRouter> pumpPreflight(WidgetTester tester, Script script, {bool showLive = true}) async {
      await tester.runAsync(_loadFonts);
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          // Still loading: the marker warning doesn't wait for it.
          readinessProvider.overrideWith((ref) => Completer<Readiness>().future),
        ],
      );
      addTearDown(container.dispose);
      container.read(settingsProvider.notifier).update((s) => s.copyWith(showMarkersLive: showLive));
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showSottoDialog<void>(
                    context: context,
                    builder: (_) => PreflightDialog(script: script),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/script/:id',
            builder: (_, s) => Text('editor ${s.pathParameters['id']} marker ${s.uri.queryParameters['marker']}'),
          ),
          GoRoute(path: '/settings/:page', builder: (_, _) => const SizedBox()),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: buildSottoTheme(SottoPalette.stage),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      return router;
    }

    testWidgets('warns about markers left, without blocking, and opens the first', (tester) async {
      await pumpPreflight(tester, _script('pf'));
      final row = find.byKey(const ValueKey('pf-markers'));
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.textContaining('3 markers are still in the script')),
        findsOneWidget,
      );
      expect(find.descendant(of: row, matching: find.textContaining('cue color')), findsOneWidget);
      // Going live is still offered.
      expect(find.text(L10n.current.goLive), findsWidgets);

      await tester.tap(find.descendant(of: row, matching: find.text('Open the first')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('editor pf marker 0'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('says the markers are hidden live when they are', (tester) async {
      await pumpPreflight(tester, _script('pf-hidden'), showLive: false);
      expect(find.textContaining('They are hidden while live'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('no markers, no warning', (tester) async {
      final clean = CheckMarkers.stripScript(_script('pf-clean'));
      await pumpPreflight(tester, clean);
      expect(find.byKey(const ValueKey('pf-markers')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });
}

// The "New script" dialog: three ways to start, labelled by whether they
// keep the presenter's words; importing pasted text word for word; and
// generating with AI — the material list, the privacy notice before
// anything is sent, the missing-key explanation, and the draft it saves.
// Every view lays out at the smallest window, in English and Spanish.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/core/design/theme.dart';
import 'package:sotto/core/design/tokens.dart';
import 'package:sotto/core/widgets/buttons.dart';
import 'package:sotto/core/widgets/stage_transitions.dart';
import 'package:sotto/data/import/material_reader.dart';
import 'package:sotto/data/import/source_material.dart';
import 'package:sotto/data/models/script.dart';
import 'package:sotto/data/repositories.dart';
import 'package:sotto/data/storage/local_store.dart';
import 'package:sotto/domain/structuring/generation_plan.dart';
import 'package:sotto/features/library/generate_controller.dart';
import 'package:sotto/features/library/new_script_dialog.dart';
import 'package:sotto/features/library/organize_jobs.dart';
import 'package:sotto/l10n/l10n.dart';
import 'package:sotto/services/ai/llm_client.dart';

import '../fixtures/materials/fake_llm.dart';

Future<void> _loadFonts() async {
  for (final (family, file) in const [
    ('Geist', 'assets/fonts/Geist-Variable.ttf'),
    ('GeistMono', 'assets/fonts/GeistMono-Variable.ttf'),
  ]) {
    final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(File(file).readAsBytesSync())));
    await loader.load();
  }
}

const _deck = SourceMaterial(
  name: 'Q3 review.pptx',
  kind: SourceKind.pptx,
  hidden: [3],
  units: [
    SourceUnit(number: 1, title: 'Q3 at a glance', body: [SourceLine('Revenue grew 12%')], notes: 'Pause here.'),
    SourceUnit(number: 2, title: 'Margin', body: [SourceLine('Gross margin 48.2%')]),
    SourceUnit(number: 4, altText: ['Bar chart']),
    SourceUnit(number: 5, title: 'Next steps', body: [SourceLine('Second warehouse')]),
  ],
);

/// Reads every file as [_deck], or fails like a Keynote file.
class _FakeReader extends MaterialReader {
  @override
  Future<SourceMaterial> read(String path) async {
    if (path.endsWith('.key')) throw const MaterialException(MaterialProblem.unsupported, detail: '.key');
    // Named after the file, so each file name is its own cache entry.
    return SourceMaterial(name: path, kind: _deck.kind, units: _deck.units, hidden: _deck.hidden);
  }
}

String _reply(FakeRequest r) {
  if (r.system == GenerationPrompt.mapSystem) {
    final refs = RegExp(r'^Refs: (.+)\.$', multiLine: true).firstMatch(r.user)![1]!.split(', ');
    return '{"slides":[${[for (final ref in refs) '{"ref":"$ref","purpose":"p","ideas":["i"],"facts":[]}'].join(',')}]}';
  }
  final beat = List.filled(20, 'growth').join(' ');
  // 10 minutes × 148 wpm = 1,480 words: 74 beats of 20.
  return '{"title":"T","sections":[{"title":"Intro","beats":[${[for (var i = 0; i < 74; i++) '{"text":"$beat"${i == 1 ? ',"slide":1' : ''}}'].join(',')}]}]}';
}

void main() {
  late Directory tmp;
  late LocalStore store;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmp = Directory.systemTemp.createTempSync('sotto_new_script');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);
    store = await LocalStore.open(path: tmp.path);
  });

  tearDownAll(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Opens the dialog over a page; the returned getter reads its result.
  Future<({NewScriptChoice? choice, bool closed}) Function()> open(
    WidgetTester tester, {
    String lang = 'en',
    FakeLlm? llm,
    String? view,
    List<String> files = const [],
  }) async {
    L10n.current = lookupAppLocalizations(Locale(lang));
    NewScriptChoice? choice;
    var closed = false;
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        organizerLlmProvider.overrideWithValue(() async => llm == null ? null : FakeLlm.sharing(llm)),
        materialReaderProvider.overrideWithValue(_FakeReader()),
      ],
    );
    addTearDown(container.dispose);
    late BuildContext ctx;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildSottoTheme(SottoPalette.stage),
          locale: Locale(lang),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              ctx = context;
              return const Scaffold(body: SizedBox.expand());
            },
          ),
        ),
      ),
    );
    unawaited(
      showSottoDialog<NewScriptChoice>(
        context: ctx,
        builder: (_) => NewScriptDialog(initialView: view, initialFiles: files),
      ).then((c) {
        choice = c;
        closed = true;
      }),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return () => (choice: choice, closed: closed);
  }

  Future<void> sized(WidgetTester tester, Size size) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('three ways to start, marked by whether they keep your words', (tester) async {
    await sized(tester, const Size(1280, 800));
    final result = await open(tester);
    expect(find.text('Write from scratch'), findsOneWidget);
    expect(find.text('Import text'), findsOneWidget);
    expect(find.text('Generate with AI'), findsOneWidget);
    expect(find.text('Keeps your words'), findsNWidgets(2));
    expect(find.text('Writes new text'), findsOneWidget);
    // Each badge sits on its own card.
    for (final (path, badge) in [
      ('path-write', 'Keeps your words'),
      ('path-import', 'Keeps your words'),
      ('path-generate', 'Writes new text'),
    ]) {
      expect(find.descendant(of: find.byKey(ValueKey(path)), matching: find.text(badge)), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('path-write')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(result().choice, isA<WriteFromScratch>());
  });

  testWidgets('importing pasted text hands it over word for word', (tester) async {
    await sized(tester, const Size(1280, 800));
    final result = await open(tester);
    await tester.tap(find.byKey(const ValueKey('path-import')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Drop a .docx, .pdf, .md or .txt file here, or'), findsOneWidget);
    final go = find.byKey(const ValueKey('import-paste-go'));
    expect(tester.widget<SottoButton>(go).onPressed, isNull, reason: 'nothing to import yet');
    const text = '## Opening\nThanks for coming —  it\'s been a  big quarter.';
    await tester.enterText(
      find.descendant(of: find.byKey(const ValueKey('import-paste')), matching: find.byType(EditableText)),
      text,
    );
    await tester.pump();
    await tester.tap(go);
    await tester.pump(const Duration(milliseconds: 400));
    final choice = result().choice;
    expect(choice, isA<ImportPasted>());
    expect((choice! as ImportPasted).text, text);
  });

  testWidgets('without a key, generating explains why and links to Integrations', (tester) async {
    await sized(tester, const Size(1280, 800));
    final result = await open(tester, view: 'generate', files: ['deck.pptx']);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Generating needs a DeepSeek API key'), findsOneWidget);
    expect(find.byKey(const ValueKey('gen-privacy')), findsNothing);
    expect(tester.widget<SottoButton>(find.byKey(const ValueKey('gen-go'))).onPressed, isNull);
    await tester.ensureVisible(find.text('Settings › Integrations  ›'));
    await tester.tap(find.text('Settings › Integrations  ›'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(result().choice, isA<OpenIntegrations>());
  });

  testWidgets('generating: what was read, the privacy notice first, then a saved draft', (tester) async {
    await sized(tester, const Size(1280, 800));
    final llm = FakeLlm(_reply);
    final result = await open(tester, llm: llm, view: 'generate', files: ['deck.pptx', 'talk.key']);
    await tester.pump(const Duration(milliseconds: 100));

    // What was read from each file, and why one couldn't be.
    expect(find.text('4 slides · 1 hidden slide skipped · notes on 1 slide · 19 words'), findsOneWidget);
    expect(find.textContaining('Export it as PowerPoint (.pptx) or PDF'), findsOneWidget);
    // The notice is on screen before anything is sent.
    expect(find.byKey(const ValueKey('gen-privacy')), findsOneWidget);
    expect(find.textContaining('is sent to DeepSeek'), findsOneWidget);
    expect(llm.requests, isEmpty);
    expect(find.textContaining('1480 words at 148 wpm'), findsOneWidget);

    final go = find.byKey(const ValueKey('gen-go'));
    await tester.ensureVisible(go);
    await tester.tap(go);
    await tester.pump();
    for (var i = 0; i < 40 && !result().closed; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    final choice = result().choice;
    expect(choice, isA<Generated>());
    final script = (choice! as Generated).script;
    expect(script.status, ScriptStatus.draft);
    expect(script.title, 'Q3 at a glance');
    expect(llm.requests.first.user, contains('<material>'));
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  });

  testWidgets('a DeepSeek error says what happened and saves nothing', (tester) async {
    await sized(tester, const Size(1280, 800));
    final before = store.scripts.length;
    final llm = FakeLlm((r) => throw LlmException.fromStatus(402, '{}'));
    // A file not generated from before in this file: not served from the cache.
    final result = await open(tester, llm: llm, view: 'generate', files: ['never-generated.pptx']);
    await tester.pump(const Duration(milliseconds: 100));
    final go = find.byKey(const ValueKey('gen-go'));
    await tester.ensureVisible(go);
    await tester.tap(go);
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text(L10n.current.genFailed), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('gen-error'))).data, L10n.current.llmNoBalance);
    expect(find.text(L10n.current.genFailedNothingSaved), findsOneWidget);
    expect(find.text(L10n.current.genTryAgain), findsOneWidget);
    expect(result().closed, isFalse, reason: 'the dialog stays, with the material, to try again');
    expect(store.scripts.length, before, reason: 'nothing saved');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  for (final lang in ['en', 'es']) {
    testWidgets('every view lays out at the smallest window: $lang', (tester) async {
      await sized(tester, Layout.windowMin);
      for (final view in [null, 'import', 'generate']) {
        await open(
          tester,
          lang: lang,
          llm: FakeLlm(_reply),
          view: view,
          files: view == 'generate' ? ['deck.pptx'] : const [],
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull, reason: '${view ?? 'choose'} ($lang)');
        await tester.pumpWidget(const SizedBox());
      }
      await tester.pump(const Duration(seconds: 1));
    });
  }
}

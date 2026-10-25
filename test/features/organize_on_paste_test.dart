// Text pasted or imported is organized at once — the rule-based pass, then
// DeepSeek refinement in the background — whichever way it comes in:
// a file (picked or dropped), the clipboard, or a paste into the Write tab.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sotto/app/router.dart';
import 'package:sotto/data/models/script.dart';
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/data/repositories.dart';
import 'package:sotto/data/storage/local_store.dart';
import 'package:sotto/domain/structuring/organize_plan.dart';
import 'package:sotto/domain/structuring/paste_placement.dart';
import 'package:sotto/features/editor/editor_controller.dart';
import 'package:sotto/features/library/library_actions.dart';
import 'package:sotto/features/library/organize_jobs.dart';
import 'package:sotto/services/ai/llm_client.dart';

const _talk = '''## Apertura
Buenos días a todos y gracias por estar aquí. Hoy les quiero contar cómo cerramos el año en la empresa.

## Resultados
Las ventas crecieron un doce por ciento frente al año pasado. La mayor parte vino de clientes nuevos en México y Colombia.

## Próximos pasos
Vamos a abrir un segundo almacén en Monterrey. Con ese almacén esperamos reducir los retrasos a la mitad.''';

/// Records refinement jobs instead of calling DeepSeek.
class _RecordingJobs extends OrganizeJobs {
  final started = <String>[];

  @override
  Future<void> start(
    String scriptId,
    OrganizePrep prep,
    LlmClient llm, {
    String? cacheKey,
    Map<String, int?> budgets = const {},
  }) async {
    started.add(scriptId);
    llm.close();
  }
}

String _words(Script s) => [for (final b in s.allBeats) b.text].join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();

String _plain(String text) =>
    text.replaceAll(RegExp(r'^## .*$', multiLine: true), '').replaceAll(RegExp(r'\s+'), ' ').trim();

void main() {
  late Directory tmp;
  late ProviderContainer container;
  late _RecordingJobs jobs;
  var withKey = false;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('sotto_paste');
    final store = await LocalStore.open(path: tmp.path);
    jobs = _RecordingJobs();
    withKey = false;
    container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        organizeJobsProvider.overrideWith(() => jobs),
        organizerLlmProvider.overrideWithValue(
          () async => withKey ? LlmClient.create(const AppSettings(), 'sk-test') : null,
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<(Script, EditorController)> openBlank() async {
    final script = Script.blank();
    await container.read(scriptRepositoryProvider).save(script);
    container.listen(editorProvider(script.id), (_, _) {});
    return (script, container.read(editorProvider(script.id).notifier));
  }

  Future<void> settle() => Future<void>.delayed(EditorController.pasteDebounce + const Duration(milliseconds: 600));

  group('PastedText.detect', () {
    test('several sentences at once is a paste', () {
      final p = PastedText.detect(
        'Hola ',
        'Hola Primera frase del guion. Segunda frase, un poco más larga, del guion.',
      )!;
      expect(p.before, 'Hola ');
      expect(p.pasted, startsWith('Primera'));
      expect(p.after, '');
    });

    test('typing, a word or one short sentence is not', () {
      expect(PastedText.detect('Hola', 'Hola a'), isNull);
      expect(PastedText.detect('', 'Una sola frase corta.'), isNull);
      expect(
        PastedText.detect('', 'una frase muy larga sin ningún punto que siga y siga sin terminar nunca jamás'),
        isNull,
      );
    });
  });

  group('Write tab paste', () {
    test('a new script organizes the paste into sections at once, without a key', () async {
      final (script, editor) = await openBlank();
      final beat = script.sections.first.beats.first;
      editor.setBeatText(beat.id, _talk);
      await settle();

      final s = editor.script!;
      expect(s.sections.length, greaterThanOrEqualTo(3));
      expect(s.sections.map((x) => x.title), containsAll(['Apertura', 'Resultados', 'Próximos pasos']));
      expect(s.allBeats.length, greaterThan(3));
      // The wording never changes.
      expect(_words(s), _plain(_talk));
      expect(s.status, ScriptStatus.structured);
      expect(jobs.started, isEmpty);
      expect(container.read(editorProvider(script.id)).pastesOrganized, 1);
    });

    test('with a key, DeepSeek refinement starts in the background', () async {
      withKey = true;
      final (script, editor) = await openBlank();
      editor.setBeatText(script.sections.first.beats.first.id, _talk);
      await settle();
      expect(jobs.started, [script.id]);
      expect(editor.script!.status, ScriptStatus.organizing);
    });

    test('pasting into a script keeps what is around the paste', () async {
      final (script, editor) = await openBlank();
      final first = script.sections.first.beats.first;
      editor.setBeatText(first.id, 'Mi introducción propia.');
      await settle();
      final intro = editor.script!.sections.first;
      editor.update(
        (s) => s.copyWith(
          sections: [
            intro.copyWith(beats: [...intro.beats, Beat.create('Lo que digo después.')]),
          ],
        ),
      );
      editor.setBeatText(first.id, 'Mi introducción propia. $_talk');
      await settle();

      final s = editor.script!;
      expect(s.allBeats.first.text, 'Mi introducción propia.');
      expect(s.allBeats.last.text, 'Lo que digo después.');
      expect(s.sections.map((x) => x.title), containsAll(['Apertura', 'Resultados']));
      expect(_words(s), 'Mi introducción propia. ${_plain(_talk)} Lo que digo después.');
    });

    test('typing never organizes', () async {
      final (script, editor) = await openBlank();
      final id = script.sections.first.beats.first.id;
      var text = '';
      for (final w in _plain(_talk).split(' ')) {
        text = text.isEmpty ? w : '$text $w';
        editor.setBeatText(id, text);
      }
      await settle();
      expect(editor.script!.sections.length, 1);
      expect(editor.script!.allBeats.length, 1);
      expect(container.read(editorProvider(script.id)).pastesOrganized, 0);
    });

    test('undo is one step back to the paste as it was', () async {
      withKey = true;
      final (script, editor) = await openBlank();
      final id = script.sections.first.beats.first.id;
      editor.setBeatText(id, _talk);
      await settle();
      expect(editor.canUndoOrganize, isTrue);

      editor.undoOrganize();
      final s = editor.script!;
      expect(s.sections.length, 1);
      expect(s.allBeats.single.text, _talk);
      expect(editor.canUndoOrganize, isFalse);
      expect(container.read(organizeJobsProvider), isNot(contains(script.id)));
    });

    test('an edit after organizing ends the undo', () async {
      final (script, editor) = await openBlank();
      editor.setBeatText(script.sections.first.beats.first.id, _talk);
      await settle();
      final beat = editor.script!.allBeats.first;
      editor.setBeatText(beat.id, '${beat.text} Más');
      expect(editor.canUndoOrganize, isFalse);
    });
  });

  group('imports', () {
    List<Script> scripts() => container.read(localStoreProvider).scripts.values.map(Script.fromJson).toList();

    /// Scripts that weren't there before [ids] (the library may hold samples).
    List<Script> added(Set<String> ids) => [
      for (final s in scripts())
        if (!ids.contains(s.id)) s,
    ];

    Future<WidgetRef> refIn(WidgetTester tester) async {
      late WidgetRef captured;
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const SizedBox()),
          GoRoute(path: '/script/:id', builder: (_, _) => const SizedBox()),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ProviderScope(
            overrides: [routerProvider.overrideWithValue(router)],
            child: MaterialApp.router(
              routerConfig: router,
              builder: (context, child) => Consumer(
                builder: (context, ref, _) {
                  captured = ref;
                  return child ?? const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      return captured;
    }

    testWidgets('a dropped (or picked) file is organized', (tester) async {
      final ref = await refIn(tester);
      final file = File('${tmp.path}/charla.txt')..writeAsStringSync(_talk);
      final context = tester.element(find.byType(Router<Object>));
      final before = {for (final s in scripts()) s.id};
      await tester.runAsync(() => importFiles(ref, context, paths: [file.path]));
      final made = added(before);
      expect(made, hasLength(1));
      expect(made.single.sections.length, greaterThanOrEqualTo(3));
      expect(made.single.status, ScriptStatus.structured);
    });

    testWidgets('the clipboard (Ctrl+V in the library, the welcome dialog) is organized', (tester) async {
      final ref = await refIn(tester);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') return {'text': _talk};
        return null;
      });
      final before = {for (final s in scripts()) s.id};
      await tester.runAsync(() => importFromClipboard(ref));
      final made = added(before);
      expect(made, hasLength(1));
      expect(made.single.sections.map((s) => s.title), contains('Resultados'));
      expect(_words(made.single), _plain(_talk));
    });
  });
}

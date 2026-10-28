// The current-word highlight stays on its own line: on a script that wraps,
// over a busy wallpaper, in panel and text-only colors, English and
// Spanish, still and moving — every pixel it changes lies on the word's
// line, never on the line above or below.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/features/live/overlay/karaoke.dart';
import 'package:sotto/l10n/l10n.dart';

import '../visual/highlight_scene.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadSceneFonts();
  });

  for (final language in SceneLanguage.values) {
    for (final palette in ScenePalette.values) {
      for (final still in [true, false]) {
        testWidgets('${language.name} ${palette.name} ${still ? 'still' : 'moving'}: '
            'the highlight paints only on its own line', (tester) async {
          L10n.current = lookupAppLocalizations(Locale(language.code));
          tester.view.physicalSize = sceneSize;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final scene = HighlightScene(language);

          await tester.pumpWidget(scene.view(palette, 0, still: still));
          await tester.pump();
          final bare = await pixels(tester, await scene.capture(tester));

          final p = scene.paragraph(tester);
          final lines = scene.lines(p);
          expect(lines.toSet().length, greaterThanOrEqualTo(3), reason: 'the beat wraps over three lines');
          // The last word of the first line, the first of the second, and
          // one in the middle of the second: each has a line right under it.
          final cases = {
            'last on its line': lines.lastIndexOf(0),
            'first on its line': lines.indexOf(1),
            'mid-line': (lines.indexOf(1) + lines.lastIndexOf(1)) ~/ 2,
          };

          for (final MapEntry(key: where, value: word) in cases.entries) {
            final box = scene.wordBox(p, word);
            final below = [
              for (var w = 0; w < lines.length; w++)
                if (lines[w] == lines[word] + 1) scene.wordBox(p, w),
            ];
            expect(
              below.any((b) => b.left < box.right && b.right > box.left),
              isTrue,
              reason: '$where: another line sits right under the word',
            );

            await scene.highlight(tester, palette, word, still: still);
            final lit = await pixels(tester, await scene.capture(tester));
            final (changed, at) = difference(lit, bare, sceneSize.width.toInt());
            expect(changed, isNotNull, reason: '$where: the highlight shows');

            // Its own line, and no further sideways than half a letter.
            final line = scene.lineOf(p, word);
            final origin = p.localToGlobal(Offset.zero);
            final allowed = Rect.fromLTRB(
              box.left - sceneFontSize * 0.5,
              line.top,
              box.right + sceneFontSize * 0.5,
              line.bottom,
            ).shift(origin);
            final outside = at.where((px) => !allowed.contains(px + const Offset(0.5, 0.5))).toList();
            expect(
              outside,
              isEmpty,
              reason:
                  '$where ("${p.text.toPlainText().substring(scene.words(p)[word].start, scene.words(p)[word].end)}"): '
                  '${outside.length} pixels changed off its line $allowed; all changes span $changed',
            );
            // The pill itself: one, clear of its line's edges, on whole pixels.
            final pills = tester.state<KaraokeLineState>(find.byType(KaraokeLine).first).paintedPills;
            expect(pills, hasLength(1), reason: where);
            expectInsideLine(pills.single, line, origin, where);

            // Back to nothing said before the next word.
            await tester.pumpWidget(scene.view(palette, 0, still: still));
            await tester.pump(const Duration(seconds: 4));
            await tester.pump(const Duration(seconds: 4));
          }
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 4));
        });
      }
    }
  }

  for (final dpr in [1.0, 1.5]) {
    testWidgets('a word broken over two lines gets a pill on each, inside its line (dpr $dpr)', (tester) async {
      L10n.current = lookupAppLocalizations(const Locale('en'));
      tester.view.physicalSize = sceneSize * dpr;
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.reset);
      final scene = HighlightScene(
        SceneLanguage.en,
        beats: const ['Hello.', 'Say pneumonoultramicroscopicsilicovolcanoconiosis twice and rest.', 'Thanks.'],
      );
      await tester.pumpWidget(scene.view(ScenePalette.panelLight, 0, still: true));
      await tester.pump();
      await scene.highlight(tester, ScenePalette.panelLight, 1, still: true);

      final p = scene.paragraph(tester);
      final pills = tester.state<KaraokeLineState>(find.byType(KaraokeLine).first).paintedPills;
      expect(pills, hasLength(2), reason: 'the long word breaks over two lines');
      final origin = p.localToGlobal(Offset.zero);
      final pitch = sceneFontSize * 1.34;
      for (final pill in pills) {
        // The line the piece sits on.
        final top = (pill.center.dy / pitch).floor() * pitch;
        expectInsideLine(pill, Rect.fromLTWH(0, top, p.size.width, pitch), origin, 'piece at $pill');
      }
      expect(pills[0].bottom, lessThan(pills[1].top), reason: 'the two pieces never touch');
    });
  }
}

/// [pill] (paragraph coordinates) stays clear of [line]'s top and bottom
/// edges, and its edges sit on physical pixels.
void expectInsideLine(Rect pill, Rect line, Offset origin, String where) {
  expect(pill.top, greaterThan(line.top), reason: '$where: $pill clears the line above ($line)');
  expect(pill.bottom, lessThan(line.bottom), reason: '$where: $pill clears the line below ($line)');
  final dpr = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first.devicePixelRatio;
  for (final edge in [pill.left + origin.dx, pill.right + origin.dx, pill.top + origin.dy, pill.bottom + origin.dy]) {
    expect((edge * dpr - (edge * dpr).roundToDouble()).abs(), lessThan(1e-3), reason: '$where: $pill on whole pixels');
  }
}

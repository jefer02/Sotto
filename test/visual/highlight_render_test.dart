// Renders the current-word highlight on a wrapped script over a busy
// wallpaper to PNG for visual review: the word sits right above the next
// line. Opt-in, because it writes files:
//   $env:SOTTO_RENDER=1; flutter test --no-pub test/visual/highlight_render_test.dart
// SOTTO_RENDER_OUT=folder (default build/highlight). Files are named
// <language>-<palette>-<still|moving>.png.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/l10n/l10n.dart';

import 'highlight_scene.dart';

final _render = Platform.environment['SOTTO_RENDER'] != null;
final _out = Platform.environment['SOTTO_RENDER_OUT'] ?? 'build/highlight';

void main() {
  testWidgets('highlight frames', skip: !_render, (tester) async {
    await tester.runAsync(loadSceneFonts);
    tester.view.physicalSize = sceneSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final language in SceneLanguage.values) {
      L10n.current = lookupAppLocalizations(Locale(language.code));
      for (final palette in ScenePalette.values) {
        for (final still in [true, false]) {
          final scene = HighlightScene(language);
          await tester.pumpWidget(scene.view(palette, 0, still: still));
          await tester.pump();
          // The last word on the first line: "bienestar" sits on "las pautas".
          final lines = scene.lines(scene.paragraph(tester));
          await scene.highlight(tester, palette, lines.lastIndexOf(0), still: still);
          final image = await scene.capture(tester);
          await tester.runAsync(() async {
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            File('$_out/${language.name}-${palette.name}-${still ? 'still' : 'moving'}.png')
              ..createSync(recursive: true)
              ..writeAsBytesSync(png!.buffer.asUint8List());
          });
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 4));
        }
      }
    }
  });
}

// Renders the karaoke highlight mid-sweep to PNG for visual review, over a
// blue sky, a dark scene and a light slide. Opt-in, because it writes files:
//   $env:SOTTO_RENDER=1; flutter test --no-pub test/visual/karaoke_render_test.dart
// SOTTO_RENDER_OUT=folder (default build/karaoke). Files are named
// <effect>-<backdrop>[-still].png.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/core/design/theme.dart';
import 'package:sotto/core/design/tokens.dart';
import 'package:sotto/core/design/typography.dart';
import 'package:sotto/data/models/script.dart';
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/domain/following/follow_engine.dart';
import 'package:sotto/domain/following/script_aligner.dart';
import 'package:sotto/domain/overlay/backdrop_tone.dart';
import 'package:sotto/features/live/live_state.dart';
import 'package:sotto/features/live/overlay/reading_view.dart';
import 'package:sotto/features/live/overlay_palette.dart';
import 'package:sotto/l10n/l10n.dart';

final _render = Platform.environment['SOTTO_RENDER'] != null;
final _out = Platform.environment['SOTTO_RENDER_OUT'] ?? 'build/karaoke';

Future<void> _fonts() async {
  for (final (family, file) in const [
    ('Geist', 'assets/fonts/Geist-Variable.ttf'),
    ('AtkinsonHyperlegibleNext', 'assets/fonts/AtkinsonHyperlegibleNext-Variable.ttf'),
    ('Cormorant', 'assets/fonts/Cormorant-Variable.ttf'),
  ]) {
    final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(File(file).readAsBytesSync())));
    await loader.load();
  }
}

enum _Backdrop {
  sky([Color(0xFF3E5BAA), Color(0xFF6C8BD6), Color(0xFF8FA6DF)], BackdropTone.dark),
  night([Color(0xFF0B0F1C), Color(0xFF1A2236), Color(0xFF2A2F3F)], BackdropTone.dark),
  slide([Color(0xFFF4F1EA), Color(0xFFDCD6CB), Color(0xFFCFC8BC)], BackdropTone.light);

  const _Backdrop(this.colors, this.tone);
  final List<Color> colors;
  final BackdropTone tone;
}

void main() {
  testWidgets('karaoke frames', skip: !_render, (tester) async {
    await tester.runAsync(_fonts);
    tester.view.physicalSize = const Size(900, 150);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime(2026);
    final script = Script(
      id: 's',
      title: 'T',
      createdAt: now,
      updatedAt: now,
      sections: [
        Section(
          id: 'a',
          title: 'A',
          beats: [
            Beat.create('Desde aquí vuelvo a intentarlo otra vez'),
            Beat.create('Había un mañana que no podía cambiar'),
          ],
        ),
      ],
    );
    final flat = FlatScript.from(script, language: 'es');
    final key = GlobalKey();

    for (final (effect, backdrop, still) in [
      (HighlightEffect.glow, _Backdrop.sky, false),
      (HighlightEffect.glow, _Backdrop.night, false),
      (HighlightEffect.glow, _Backdrop.slide, false),
      (HighlightEffect.glow, _Backdrop.sky, true),
      (HighlightEffect.simple, _Backdrop.sky, false),
    ]) {
      final settings = AppSettings(overlayStyle: OverlayStyle.textOnly, highlightEffect: effect);
      final theme = buildSottoTheme(
        SottoPalette.stage,
        overlay: overlayPaletteFor(settings, dark: true, backdrop: backdrop.tone),
      );
      LiveState at(int words) => LiveState(
        phase: LivePhase.reading,
        script: script,
        flat: flat,
        position: FollowPosition(beat: 0, spokenWords: words, confidence: 1, holding: false, charsPerSecond: 13),
      );
      Widget view(LiveState s) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Theme(
          data: theme,
          child: RepaintBoundary(
            key: key,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: backdrop.colors,
                ),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: DefaultTextStyle.merge(
                  style: TextStyle(shadows: theme.extension<SottoTheme>()!.overlay.textShadows(1, true)),
                  child: AnchoredScript(
                    state: s,
                    style: ReadingStyle(
                      size: ReadingSize.xl,
                      linesShown: 3,
                      glide: true,
                      reduceMotion: still,
                      plate: false,
                      font: const ScriptFont(family: 'Cormorant', weight: 500),
                      highlight: effect,
                    ),
                    fontSize: 40,
                    anchor: 0.25,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(view(at(0)));
      await tester.pump(const Duration(milliseconds: 100));
      // The voice confirms "Desde aquí vuelvo"; the sweep walks to it.
      await tester.pumpWidget(view(at(3)));
      for (var f = 0; f < 10; f++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.runAsync(() async {
        final image = await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$_out/${effect.name}-${backdrop.name}${still ? '-still' : ''}.png')
          ..createSync(recursive: true)
          ..writeAsBytesSync(png!.buffer.asUint8List());
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    }
  });
}

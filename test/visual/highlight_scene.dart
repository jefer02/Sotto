// The overlay's reading column with the current-word highlight on a word
// that wraps above other lines, over a busy wallpaper — shared by the
// highlight bounds test and its opt-in renders.
import 'dart:io';
import 'dart:math' as math;
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
import 'package:sotto/features/live/overlay/karaoke.dart';
import 'package:sotto/features/live/overlay/reading_view.dart';
import 'package:sotto/features/live/overlay_palette.dart';
import 'package:sotto/l10n/l10n.dart';

const sceneSize = Size(640, 420);
const sceneFontSize = 40.0;

Future<void> loadSceneFonts() async {
  for (final (family, file) in const [
    ('AtkinsonHyperlegibleNext', 'assets/fonts/AtkinsonHyperlegibleNext-Variable.ttf'),
    ('Geist', 'assets/fonts/Geist-Variable.ttf'),
  ]) {
    final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(File(file).readAsBytesSync())));
    await loader.load();
  }
}

/// The script in each language: the beat being said wraps over three lines
/// or more, so a word on any of them has a line under it.
enum SceneLanguage {
  en('en', [
    'Good evening, everyone.',
    'Tonight we talk about wellbeing and the small habits that help us rest better every single night.',
    'Thank you for coming.',
  ]),
  es('es', [
    'Buenas noches a todos.',
    'Hoy hablamos del bienestar: las pautas que nos ayudan a descansar mejor cada noche.',
    'Gracias por venir.',
  ]);

  const SceneLanguage(this.code, this.beats);
  final String code;
  final List<String> beats;
}

/// Panel light and dark (the style in the report), and text only with the
/// light and dark auto text colors.
enum ScenePalette {
  panelLight,
  panelDark,
  textLight,
  textDark;

  bool get panel => this == panelLight || this == panelDark;

  OverlayPalette get palette => switch (this) {
    panelLight => overlayPaletteFor(const AppSettings(overlayStyle: OverlayStyle.panel), dark: false),
    panelDark => overlayPaletteFor(const AppSettings(overlayStyle: OverlayStyle.panel), dark: true),
    textLight => overlayPaletteFor(
      const AppSettings(overlayStyle: OverlayStyle.textOnly),
      dark: true,
      backdrop: BackdropTone.dark,
    ),
    textDark => overlayPaletteFor(
      const AppSettings(overlayStyle: OverlayStyle.textOnly),
      dark: true,
      backdrop: BackdropTone.light,
    ),
  };
}

class HighlightScene {
  HighlightScene(this.language, {List<String>? beats}) : beats = beats ?? language.beats {
    final now = DateTime(2026);
    script = Script(
      id: 's',
      title: 'T',
      createdAt: now,
      updatedAt: now,
      sections: [
        Section(id: 'a', title: 'A', beats: [for (final b in this.beats) Beat.create(b)]),
      ],
    );
    flat = FlatScript.from(script, language: language.code);
  }

  final SceneLanguage language;
  final List<String> beats;
  late final Script script;
  late final FlatScript flat;
  final boundary = GlobalKey();

  /// The beat being said.
  static const beat = 1;

  LiveState at(int words) => LiveState(
    phase: LivePhase.reading,
    script: script,
    flat: flat,
    position: FollowPosition(beat: beat, spokenWords: words, confidence: 1, holding: false, charsPerSecond: 14),
  );

  Widget view(ScenePalette p, int words, {required bool still}) {
    final o = p.palette;
    final theme = buildSottoTheme(SottoPalette.stage, overlay: o);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: Locale(language.code),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Theme(
        data: theme,
        child: RepaintBoundary(
          key: boundary,
          child: CustomPaint(
            painter: const BusyWallpaper(),
            child: DecoratedBox(
              // The panel's own ground, as the overlay lays it.
              decoration: BoxDecoration(color: o.ground),
              child: Material(
                type: MaterialType.transparency,
                child: AnchoredScript(
                  state: at(words),
                  style: ReadingStyle(
                    size: ReadingSize.xl,
                    linesShown: 3,
                    glide: false,
                    reduceMotion: still,
                    plate: false,
                    font: const ScriptFont(family: 'AtkinsonHyperlegibleNext', weight: 500),
                    highlight: HighlightEffect.glow,
                  ),
                  fontSize: sceneFontSize,
                  anchor: 0.3,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The paragraph of the beat being said.
  RenderParagraph paragraph(WidgetTester tester) =>
      tester.renderObject<RenderParagraph>(
        find.descendant(of: find.byType(KaraokeLine), matching: find.byType(RichText)).first,
      );

  /// Each word of the beat being said: its characters in the paragraph.
  List<TextRange> words(RenderParagraph p) {
    final text = p.text.toPlainText(includePlaceholders: true, includeSemanticsLabels: false);
    return [
      for (final m in RegExp(r'[^\s ]+').allMatches(text)) TextRange(start: m.start, end: m.end),
    ];
  }

  /// Which visual line each word sits on.
  List<int> lines(RenderParagraph p) {
    final tops = <double>[];
    return [
      for (final w in words(p))
        () {
          final y = p.getOffsetForCaret(TextPosition(offset: w.start), Rect.zero).dy;
          var i = tops.indexWhere((t) => (t - y).abs() < 1);
          if (i < 0) {
            tops.add(y);
            i = tops.length - 1;
          }
          return i;
        }(),
    ];
  }

  /// The line [word] sits on, in paragraph coordinates: as tall as one line
  /// of text, as wide as the paragraph.
  Rect lineOf(RenderParagraph p, int word) {
    final w = words(p)[word];
    final top = p.getOffsetForCaret(TextPosition(offset: w.start), Rect.zero).dy;
    final h = p.getFullHeightForCaret(TextPosition(offset: w.start));
    return Rect.fromLTWH(0, top, p.size.width, h);
  }

  /// The glyph box of [word], in paragraph coordinates.
  Rect wordBox(RenderParagraph p, int word) {
    final w = words(p)[word];
    final boxes = p.getBoxesForSelection(TextSelection(baseOffset: w.start, extentOffset: w.end));
    return boxes.map((b) => b.toRect()).reduce((a, b) => a.expandToInclude(b));
  }

  /// Brings the highlight onto [word]: still, it lights the last word said
  /// at once; moving, it sweeps from the word before and is captured as it
  /// lands, while the light is still on.
  Future<void> highlight(WidgetTester tester, ScenePalette p, int word, {required bool still}) async {
    if (!still && word > 0) {
      await tester.pumpWidget(view(p, word, still: false));
      // Let the sweep to the word before land and its light fade out.
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(seconds: 4));
    }
    await tester.pumpWidget(view(p, word + 1, still: still));
    if (still) {
      await tester.pump();
      return;
    }
    final k = tester.widget<KaraokeLine>(find.byType(KaraokeLine).first);
    for (var f = 0; f < 200 && k.cursor.value < k.said.value - 1e-6; f++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<ui.Image> capture(WidgetTester tester) async {
    late ui.Image image;
    await tester.runAsync(() async {
      image = await (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();
    });
    return image;
  }
}

/// RGBA bytes of [image].
Future<List<int>> pixels(WidgetTester tester, ui.Image image) async {
  late List<int> out;
  await tester.runAsync(() async {
    out = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
  });
  return out;
}

/// Where two same-size frames differ by more than [tolerance] in any
/// channel: the bounding box of every such pixel, and the pixels themselves.
(Rect?, List<Offset>) difference(List<int> a, List<int> b, int width, {int tolerance = 3}) {
  Rect? box;
  final at = <Offset>[];
  for (var i = 0; i < a.length; i += 4) {
    var d = 0;
    for (var c = 0; c < 3; c++) {
      d = math.max(d, (a[i + c] - b[i + c]).abs());
    }
    if (d <= tolerance) continue;
    final px = Offset(((i ~/ 4) % width).toDouble(), ((i ~/ 4) ~/ width).toDouble());
    at.add(px);
    final r = Rect.fromLTWH(px.dx, px.dy, 1, 1);
    box = box == null ? r : box.expandToInclude(r);
  }
  return (box, at);
}

/// A loud desktop: a light wash with bright streaks, hard dark lines and
/// saturated blobs — what an anime wallpaper puts behind the panel.
class BusyWallpaper extends CustomPainter {
  const BusyWallpaper();

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.Random(3);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(size.width, size.height), const [
          Color(0xFFFCE4F2),
          Color(0xFFBFE3FF),
          Color(0xFFFFF1C4),
        ], const [0, 0.5, 1]),
    );
    const blobs = [Color(0xFFFF5FA2), Color(0xFF3FA9F5), Color(0xFFFFC23F), Color(0xFF7A3FF5), Color(0xFF26C281)];
    for (var i = 0; i < 14; i++) {
      canvas.drawCircle(
        Offset(r.nextDouble() * size.width, r.nextDouble() * size.height),
        20 + r.nextDouble() * 70,
        Paint()..color = blobs[i % blobs.length].withValues(alpha: 0.75),
      );
    }
    for (var i = 0; i < 40; i++) {
      final x = r.nextDouble() * size.width * 1.4 - size.width * 0.2;
      final dark = i % 3 == 0;
      canvas.drawLine(
        Offset(x, -10),
        Offset(x - size.height * (0.4 + r.nextDouble() * 0.6), size.height + 10),
        Paint()
          ..color = dark ? const Color(0xFF1B1530) : const Color(0xFFFFFFFF)
          ..strokeWidth = dark ? 1.5 + r.nextDouble() * 2 : 2 + r.nextDouble() * 6,
      );
    }
  }

  @override
  bool shouldRepaint(BusyWallpaper old) => false;
}

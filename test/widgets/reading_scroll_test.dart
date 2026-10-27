import 'package:flutter/material.dart';
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

// The script scrolls with the voice: continuously, word by word, and never
// in a single-frame jump — with reduced motion too, where it glides calmer
// rather than snapping.

const _fontSize = 28.0;
const _line = _fontSize * 1.34;

/// Long beats, so each wraps over several lines in the 420 px column.
Script _script() {
  final now = DateTime(2026);
  return Script(
    id: 's',
    title: 'T',
    createdAt: now,
    updatedAt: now,
    sections: [
      Section(
        id: 'a',
        title: 'A',
        beats: [
          for (var i = 0; i < 6; i++)
            Beat.create(
              'Beat $i opens with a long sentence that carries on across several lines of the overlay '
              'so the reading position moves inside it while the presenter keeps talking.',
            ),
        ],
      ),
    ],
  );
}

LiveState _at(Script script, FlatScript flat, int beat, int said) => LiveState(
  phase: LivePhase.reading,
  script: script,
  flat: flat,
  position: FollowPosition(beat: beat, spokenWords: said, confidence: 1, holding: false),
);

Widget _view(LiveState s, {required bool reduceMotion, bool glide = true}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Theme(
    data: buildSottoTheme(
      SottoPalette.stage,
      overlay: overlayPaletteFor(const AppSettings(), dark: true, backdrop: BackdropTone.dark),
    ),
    child: Material(
      type: MaterialType.transparency,
      child: Center(
        child: SizedBox(
          width: 420,
          height: 300,
          child: AnchoredScript(
            state: s,
            style: ReadingStyle(
              size: ReadingSize.m,
              linesShown: 5,
              glide: glide,
              reduceMotion: reduceMotion,
              plate: false,
            ),
            fontSize: _fontSize,
          ),
        ),
      ),
    ),
  ),
);

double _offset(WidgetTester tester) => tester.widget<Transform>(find.byKey(scrollKey)).transform.getTranslation().y;

/// Reads beats 0–2 a few words per update (the way recognizer updates
/// arrive), pumping 60 Hz frames between updates. Returns every frame's
/// offset and the offset each update aimed at once settled.
Future<(List<double>, List<double>)> _read(WidgetTester tester, {required bool reduceMotion, bool glide = true}) async {
  final script = _script();
  final flat = FlatScript.from(script);
  await tester.pumpWidget(_view(_at(script, flat, 0, 0), reduceMotion: reduceMotion, glide: glide));
  await tester.pump();
  final frames = <double>[_offset(tester)];
  final settled = <double>[];
  for (var beat = 0; beat < 3; beat++) {
    final words = flat.beats[beat].displayWords.length;
    for (var said = 3; said <= words; said += 3) {
      final done = said >= words;
      await tester.pumpWidget(
        _view(_at(script, flat, done ? beat + 1 : beat, done ? 0 : said), reduceMotion: reduceMotion, glide: glide),
      );
      // ~0.8 s between updates, as Whisper delivers them.
      for (var f = 0; f < 48; f++) {
        await tester.pump(const Duration(milliseconds: 16));
        frames.add(_offset(tester));
      }
    }
    // Let it settle, then note where the beat's end left it.
    for (var f = 0; f < 120; f++) {
      await tester.pump(const Duration(milliseconds: 16));
      frames.add(_offset(tester));
    }
    settled.add(_offset(tester));
  }
  return (frames, settled);
}

void main() {
  for (final reduceMotion in [false, true]) {
    final label = reduceMotion ? 'reduced motion' : 'normal motion';

    testWidgets('scrolls word by word without a jump ($label)', (tester) async {
      final (frames, settled) = await _read(tester, reduceMotion: reduceMotion);
      final steps = [for (var i = 1; i < frames.length; i++) frames[i] - frames[i - 1]];

      // It moved, a long way: three wrapped beats read.
      expect(frames.last, lessThan(frames.first - 6 * _line));
      // Every frame moves less than this — never a jump.
      final limit = reduceMotion ? _line * 0.36 : _line * 0.76;
      for (final s in steps) {
        expect(s.abs(), lessThanOrEqualTo(limit), reason: 'a frame moved ${s.toStringAsFixed(1)} px');
      }
      // Reading only ever scrolls one way: no overshoot, no drift back.
      expect(steps.every((s) => s <= 0.01), isTrue);
      // Continuous: it moves on most frames while words arrive, not in a
      // few big steps.
      expect(steps.where((s) => s.abs() > 0.05).length, greaterThan(steps.length ~/ 4));
      expect(settled, orderedEquals([...settled]..sort((a, b) => b.compareTo(a))));
    });
  }

  testWidgets('reduced motion still glides — it is never instant', (tester) async {
    final script = _script();
    final flat = FlatScript.from(script);
    await tester.pumpWidget(_view(_at(script, flat, 0, 0), reduceMotion: true));
    await tester.pump();
    final start = _offset(tester);
    await tester.pumpWidget(_view(_at(script, flat, 2, 0), reduceMotion: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final firstFrame = _offset(tester);
    await tester.pumpAndSettle();
    final end = _offset(tester);
    expect(end, lessThan(start - 4 * _line));
    // After one frame it has covered only a sliver of the way.
    expect((firstFrame - start).abs(), lessThan((end - start).abs() * 0.1));
  });

  testWidgets('"step" moves a line at a time, still gliding', (tester) async {
    final (frames, _) = await _read(tester, reduceMotion: false, glide: false);
    final steps = [for (var i = 1; i < frames.length; i++) frames[i] - frames[i - 1]];
    final worst = steps.map((s) => s.abs()).reduce((a, b) => a > b ? a : b);
    // A whole beat at a time is a longer move, spread over ~30 frames.
    expect(worst, lessThanOrEqualTo(_line * 0.5), reason: 'worst frame $worst px');
    expect(frames.last, lessThan(frames.first - 6 * _line));
  });
}

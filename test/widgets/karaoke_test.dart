// The karaoke highlight: never ahead of the voice, nothing left ticking
// under reduced motion, and a sparkle pool that never outgrows its cap.
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
import 'package:sotto/features/live/overlay/karaoke.dart';
import 'package:sotto/features/live/overlay/reading_cursor.dart';
import 'package:sotto/features/live/overlay/reading_view.dart';
import 'package:sotto/features/live/overlay_palette.dart';
import 'package:sotto/l10n/l10n.dart';

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
          Beat.create('Desde aquí vuelvo a intentarlo una vez más.'),
          Beat.create('Había un mañana que no podía cambiar.'),
        ],
      ),
    ],
  );
}

void main() {
  final script = _script();
  final flat = FlatScript.from(script, language: 'es');
  final chars = ScriptChars(flat);
  final theme = buildSottoTheme(
    SottoPalette.stage,
    overlay: overlayPaletteFor(
      const AppSettings(overlayStyle: OverlayStyle.textOnly),
      dark: true,
      backdrop: BackdropTone.dark,
    ),
  );

  LiveState at(int beat, int words) => LiveState(
    phase: LivePhase.reading,
    script: script,
    flat: flat,
    position: FollowPosition(beat: beat, spokenWords: words, confidence: 1, holding: false, charsPerSecond: 14),
  );

  Widget view(LiveState s, {bool reduceMotion = false}) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Theme(
      data: theme,
      child: Material(
        type: MaterialType.transparency,
        child: AnchoredScript(
          state: s,
          style: ReadingStyle(
            size: ReadingSize.l,
            linesShown: 3,
            glide: true,
            reduceMotion: reduceMotion,
            plate: false,
            highlight: HighlightEffect.glow,
          ),
          fontSize: 32,
        ),
      ),
    ),
  );

  KaraokeLineState karaoke(WidgetTester tester) => tester.state<KaraokeLineState>(find.byType(KaraokeLine).first);

  testWidgets('the highlight is never ahead of what was said, frame by frame', (tester) async {
    L10n.current = lookupAppLocalizations(const Locale('es'));
    tester.view.physicalSize = const Size(900, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(view(at(0, 0)));
    await tester.pump();
    // Words confirmed in bursts, as a streaming recognizer sends them.
    for (final words in [2, 3, 5, 6, 8]) {
      await tester.pumpWidget(view(at(0, words)));
      final said = chars.saidEnd(0, words) - chars.beatStart[0];
      for (var f = 0; f < 20; f++) {
        await tester.pump(const Duration(milliseconds: 16));
        final head = karaoke(tester).paintedHead;
        if (head != null) expect(head, lessThanOrEqualTo(said + 1e-6), reason: '$words words said, frame $f');
      }
    }
  });

  testWidgets('the reading cursor never passes its target, and walks there at the measured pace', (tester) async {
    final cursor = ReadingCursor(const TestVSync());
    addTearDown(cursor.dispose);
    cursor.jumpTo(0);
    var last = 0.0;
    for (final target in [30.0, 42.0, 50.0]) {
      cursor.moveTo(target, rate: 15);
      for (var f = 0; f < 90; f++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(cursor.value, lessThanOrEqualTo(target), reason: 'frame $f towards $target');
        expect(cursor.value, greaterThanOrEqualTo(last));
        last = cursor.value;
      }
      // A backlog is caught up within ReadingCursor.catchUp.
      expect(cursor.value, target);
      expect(cursor.moving, isFalse);
    }
    // A move back (a correction) or a far jump is placed at once.
    cursor.moveTo(10, rate: 15);
    expect(cursor.value, 10);
    cursor.moveTo(10 + ReadingCursor.farChars + 1, rate: 15);
    expect(cursor.value, 10 + ReadingCursor.farChars + 1);
  });

  testWidgets('under reduced motion the glow holds still: no ticker, nothing left running', (tester) async {
    L10n.current = lookupAppLocalizations(const Locale('es'));
    tester.view.physicalSize = const Size(900, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(view(at(0, 0), reduceMotion: true));
    for (final words in [2, 4, 6]) {
      await tester.pumpWidget(view(at(0, words), reduceMotion: true));
      for (var f = 0; f < 10; f++) {
        await tester.pump(const Duration(milliseconds: 16));
        final k = karaoke(tester);
        expect(k.hasTicker, isFalse, reason: 'the glow never animates under reduced motion');
        expect(k.sparkles.alive, 0, reason: 'no sparkles under reduced motion');
      }
    }
    // The still glow sits on the last word said…
    final head = karaoke(tester).paintedHead!;
    expect(head, chars.saidEnd(0, 6) - chars.beatStart[0]);
    // …and once the calm scroll has settled, nothing keeps running.
    // …and once the calm scroll has settled (frames at 60 Hz), nothing
    // keeps running.
    for (var f = 0; f < 240; f++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.binding.transientCallbackCount, 0);
  });

  test('the sparkle pool never holds more than its cap', () {
    final pool = SparklePool();
    expect(pool.cap, Karaoke.particleCap);
    for (var i = 0; i < pool.cap * 10; i++) {
      pool.spawn(10, 10, 32);
      expect(pool.alive, lessThanOrEqualTo(pool.cap));
    }
    expect(pool.alive, pool.cap);
    expect(pool.spawn(10, 10, 32), isFalse, reason: 'a full pool drops the spawn');
    // They age out, and the freed slots take new ones — still within the cap.
    pool.step(Karaoke.particleLifeMax.inMicroseconds / 1e6 + 0.01);
    expect(pool.alive, 0);
    for (var i = 0; i < pool.cap * 2; i++) {
      pool.spawn(10, 10, 32);
      pool.step(0.016);
      expect(pool.alive, lessThanOrEqualTo(pool.cap));
    }
  });
}

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
import 'package:sotto/features/live/overlay/qa_views.dart';
import 'package:sotto/features/live/overlay/reading_view.dart';
import 'package:sotto/features/live/overlay_palette.dart';
import 'package:sotto/l10n/l10n.dart';

// The reading view keeps each beat's line and hands the same widget back
// while nothing it shows has changed. These check that the far lines — the
// ones a stale cache would leave behind — follow every change that matters.

const _far = 8;

Script _script({String word = 'beat'}) {
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
          for (var i = 0; i < 12; i++)
            Beat.create('This is $word number $i.', cue: i == _far ? const Cue(CueType.slide, '3') : null),
        ],
      ),
    ],
  );
}

/// A session's state. The live controller keeps one [FlatScript] for the
/// session and copies the state around it; [flat] stands in for that.
LiveState _state(Script script, {FlatScript? flat, int spoken = 0, double voice = 0}) => LiveState(
  phase: LivePhase.reading,
  script: script,
  flat: flat ?? FlatScript.from(script),
  position: FollowPosition(beat: 0, spokenWords: spoken, confidence: 1, holding: false),
  voiceLevel: voice,
);

final _onDark = buildSottoTheme(
  SottoPalette.stage,
  overlay: overlayPaletteFor(const AppSettings(), dark: true, backdrop: BackdropTone.dark),
);
final _onLight = buildSottoTheme(
  SottoPalette.stage,
  overlay: overlayPaletteFor(const AppSettings(), dark: true, backdrop: BackdropTone.light),
);

Widget _view(
  LiveState s, {
  double fontSize = 28,
  ThemeData? theme,
  Locale locale = const Locale('en'),
  ScriptFont font = ScriptFonts.overlayDefault,
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  // A plain Theme, so a new palette applies at once rather than tweening.
  home: Theme(
    data: theme ?? _onDark,
    child: Material(
      type: MaterialType.transparency,
      child: AnchoredScript(
        state: s,
        style: ReadingStyle(
          size: ReadingSize.m,
          linesShown: 3,
          glide: false,
          reduceMotion: true,
          plate: false,
          font: font,
        ),
        fontSize: fontSize,
      ),
    ),
  ),
);

/// The far beat's paragraph, with the style its line resolved to.
RichText _farLine(WidgetTester tester, {String word = 'beat'}) => tester.widget<RichText>(
  find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('$word number $_far.')),
);

TextStyle _farStyle(WidgetTester tester, {String word = 'beat'}) =>
    (_farLine(tester, word: word).text as TextSpan).style!;

/// The cached line (its keyed subtree) around the far beat.
Widget _farCached(WidgetTester tester) => tester
    .widgetList<KeyedSubtree>(
      find.ancestor(
        of: find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('beat number $_far.')),
        matching: find.byType(KeyedSubtree),
      ),
    )
    .firstWhere((w) => w.key is GlobalKey);

void main() {
  setUp(() => L10n.current = lookupAppLocalizations(const Locale('en')));

  testWidgets('a voice level or spoken word reuses the far lines as they are', (tester) async {
    final script = _script();
    final flat = FlatScript.from(script);
    await tester.pumpWidget(_view(_state(script, flat: flat)));
    await tester.pumpAndSettle();
    final before = _farCached(tester);

    await tester.pumpWidget(_view(_state(script, flat: flat, voice: 0.6, spoken: 2)));
    await tester.pumpAndSettle();
    expect(identical(_farCached(tester), before), isTrue);
  });

  testWidgets('text size rebuilds every line at the new size', (tester) async {
    final script = _script();
    final flat = FlatScript.from(script);
    await tester.pumpWidget(_view(_state(script, flat: flat), fontSize: 28));
    await tester.pumpAndSettle();
    expect(_farStyle(tester).fontSize, 28);

    await tester.pumpWidget(_view(_state(script, flat: flat), fontSize: 36));
    await tester.pumpAndSettle();
    expect(_farStyle(tester).fontSize, 36);
  });

  testWidgets('a new script font, weight or spacing rebuilds every line in it', (tester) async {
    final script = _script();
    final flat = FlatScript.from(script);
    await tester.pumpWidget(_view(_state(script, flat: flat)));
    await tester.pumpAndSettle();
    final before = _farCached(tester);
    expect(_farStyle(tester).fontFamily, Fonts.reading);

    const lexend = ScriptFont(family: 'Lexend', weight: 400);
    await tester.pumpWidget(_view(_state(script, flat: flat), font: lexend));
    await tester.pumpAndSettle();
    expect(identical(_farCached(tester), before), isFalse);
    expect(_farStyle(tester).fontFamily, 'Lexend');
    expect(_farStyle(tester).fontWeight, FontWeight.w400);

    // The weight and the spacing alone are part of the line too.
    await tester.pumpWidget(_view(_state(script, flat: flat), font: lexend.copyWith(weight: 700)));
    await tester.pumpAndSettle();
    expect(_farStyle(tester).fontWeight, FontWeight.w700);
    await tester.pumpWidget(_view(_state(script, flat: flat), font: lexend.copyWith(weight: 700, letterSpacing: 0.1)));
    await tester.pumpAndSettle();
    expect(_farStyle(tester).letterSpacing, closeTo(28 * 0.1, 1e-9));

    // And back: the same widget as before is not reused for a different font.
    await tester.pumpWidget(_view(_state(script, flat: flat)));
    await tester.pumpAndSettle();
    expect(_farStyle(tester).fontFamily, Fonts.reading);
  });

  testWidgets('the auto text color reaches every line when the backdrop changes', (tester) async {
    final script = _script();
    final flat = FlatScript.from(script);
    Color rgb(Color c) => c.withValues(alpha: 1);

    await tester.pumpWidget(_view(_state(script, flat: flat), theme: _onDark));
    await tester.pumpAndSettle();
    expect(rgb(_farStyle(tester).color!), lightInk);
    final darkShadows = _farStyle(tester).shadows;

    await tester.pumpWidget(_view(_state(script, flat: flat), theme: _onLight));
    await tester.pumpAndSettle();
    expect(rgb(_farStyle(tester).color!), darkInk);
    expect(_farStyle(tester).shadows, isNot(equals(darkShadows)));

    await tester.pumpWidget(_view(_state(script, flat: flat), theme: _onDark));
    await tester.pumpAndSettle();
    expect(rgb(_farStyle(tester).color!), lightInk);
  });

  testWidgets('a script reorganized mid-session replaces the far lines', (tester) async {
    await tester.pumpWidget(_view(_state(_script())));
    await tester.pumpAndSettle();
    expect(find.textContaining('beat number $_far.', findRichText: true), findsOneWidget);

    await tester.pumpWidget(_view(_state(_script(word: 'line'))));
    await tester.pumpAndSettle();
    expect(find.textContaining('beat number $_far.', findRichText: true), findsNothing);
    expect(find.textContaining('line number $_far.', findRichText: true), findsOneWidget);
  });

  testWidgets('under reduced motion the drafting dots hold still and nothing keeps running', (tester) async {
    final script = _script();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) =>
            MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
        home: Theme(
          data: _onDark,
          child: Material(
            type: MaterialType.transparency,
            child: DraftingView(state: _state(script).copyWith(phase: LivePhase.drafting)),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('a new interface language renames the cues on far lines', (tester) async {
    final script = _script();
    final flat = FlatScript.from(script);
    await tester.pumpWidget(_view(_state(script, flat: flat)));
    await tester.pumpAndSettle();
    final en = L10n.current.cueSlide;
    expect(find.textContaining(en), findsOneWidget);

    L10n.current = lookupAppLocalizations(const Locale('es'));
    await tester.pumpWidget(_view(_state(script, flat: flat), locale: const Locale('es')));
    await tester.pumpAndSettle();
    final es = L10n.current.cueSlide;
    expect(es, isNot(en));
    expect(find.textContaining(es), findsOneWidget);
  });
}

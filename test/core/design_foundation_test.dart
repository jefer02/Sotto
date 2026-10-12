import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/core/design/icons.dart';
import 'package:sotto/core/design/theme.dart';
import 'package:sotto/core/design/tokens.dart';
import 'package:sotto/core/utils/display_title.dart';
import 'package:sotto/core/widgets/buttons.dart';
import 'package:sotto/core/widgets/display.dart';
import 'package:sotto/core/widgets/empty_state.dart';
import 'package:sotto/core/widgets/keycap.dart';

final _theme = buildSottoTheme(SottoPalette.houseLights);

Widget _app(Widget child) => MaterialApp(
  theme: _theme,
  home: Material(child: Center(child: child)),
);

void main() {
  group('displayTitle', () {
    test('underscores always read as spaces', () {
      expect(displayTitle('Generalidades_Solo_Monitoreo_Rastreo'), 'Generalidades Solo Monitoreo Rastreo');
      expect(displayTitle('Plan de_negocio'), 'Plan de negocio');
    });

    test('hyphens only when the title looks like a file name', () {
      expect(displayTitle('q3-board-review'), 'q3 board review');
      expect(displayTitle('Que_es-Internet'), 'Que es Internet');
      expect(displayTitle('Q3-2026 review'), 'Q3-2026 review');
      expect(displayTitle('Revisión del tercer trimestre'), 'Revisión del tercer trimestre');
    });

    test('collapses repeated separators and never returns empty', () {
      expect(displayTitle('a__b'), 'a b');
      expect(displayTitle('  spaced   out '), 'spaced out');
      expect(displayTitle('___'), '___');
    });
  });

  group('tokens', () {
    test('palette lerp blends every color and lands exactly on the ends', () {
      const a = SottoPalette.houseLights, b = SottoPalette.stage;
      expect(identical(SottoPalette.lerp(a, b, 0), a), isTrue);
      expect(identical(SottoPalette.lerp(a, b, 1), b), isTrue);
      final mid = SottoPalette.lerp(a, b, 0.5);
      expect(mid.ground, Color.lerp(a.ground, b.ground, 0.5));
      expect(mid.inkPrimary, Color.lerp(a.inkPrimary, b.inkPrimary, 0.5));
      expect(mid.collectionTones.length, a.collectionTones.length);
    });

    test('the theme crossfades palettes instead of snapping at half way', () {
      final light = SottoTheme(palette: SottoPalette.houseLights, overlay: OverlayPalette.light);
      final dark = SottoTheme(palette: SottoPalette.stage, overlay: OverlayPalette.dark);
      final quarter = light.lerp(dark, 0.25).palette.ground;
      expect(quarter, isNot(SottoPalette.houseLights.ground));
      expect(quarter, isNot(SottoPalette.stage.ground));
    });

    test('contrast follows WCAG', () {
      expect(Contrast.ratio(const Color(0xFFFFFFFF), const Color(0xFF000000)), closeTo(21, 0.01));
      expect(Contrast.ratio(const Color(0xFF777777), const Color(0xFF777777)), closeTo(1, 0.001));
    });

    test('ink tokens reach AA on their grounds in both themes', () {
      for (final p in [SottoPalette.houseLights, SottoPalette.stage]) {
        for (final ink in [p.inkPrimary, p.inkSecondary, p.inkTertiary]) {
          expect(Contrast.ratio(ink, p.ground), greaterThanOrEqualTo(Contrast.aa));
          expect(Contrast.ratio(ink, p.raised), greaterThanOrEqualTo(Contrast.aa));
        }
      }
    });

    test('micro-interactions and pages stay in their ranges; stagger is capped', () {
      for (final d in [Motion.micro, Motion.microOut, Motion.quick]) {
        expect(d.inMilliseconds, inInclusiveRange(120, 200));
      }
      for (final d in [Motion.panel, Motion.page]) {
        expect(d.inMilliseconds, inInclusiveRange(250, 400));
      }
      expect(Motion.stagger(2), Motion.staggerStep * 2);
      expect(Motion.stagger(40), Motion.staggerStep * Motion.staggerCap);
    });
  });

  testWidgets('a primary button names its shortcut in a tooltip, not a chip', (tester) async {
    await tester.pumpWidget(_app(SottoButton.primary(label: 'New script', shortcutText: 'Ctrl+N', onPressed: () {})));
    expect(find.byType(Keycap), findsNothing);
    expect(find.byTooltip('New script · Ctrl+N'), findsOneWidget);
  });

  testWidgets('a secondary button keeps its keycap', (tester) async {
    await tester.pumpWidget(_app(SottoButton(label: 'Stop', shortcutText: 'Esc', onPressed: () {})));
    expect(find.byType(Keycap), findsOneWidget);
  });

  testWidgets('the section lamp only lights what is live', (tester) async {
    await tester.pumpWidget(
      _app(const Column(children: [SectionHeading('Recent'), SectionHeading('Up next', live: true)])),
    );
    final dots = find.byWidgetPredicate(
      (w) =>
          w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).shape == BoxShape.circle,
    );
    expect(dots, findsOneWidget);
  });

  testWidgets('an empty state names the state, explains it and offers the action', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _app(
        EmptyState(
          icon: SottoIcons.sessions,
          title: 'No sessions yet',
          body: 'Rehearse once and it shows up here.',
          action: SottoButton.primary(label: 'Rehearse', onPressed: () => taps++),
        ),
      ),
    );
    expect(find.text('No sessions yet'), findsOneWidget);
    expect(find.text('Rehearse once and it shows up here.'), findsOneWidget);
    await tester.tap(find.text('Rehearse'));
    expect(taps, 1);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/core/design/theme.dart';
import 'package:sotto/core/design/tokens.dart';
import 'package:sotto/core/widgets/motion_effects.dart';
import 'package:sotto/core/widgets/stage_light.dart';

// Built once: a fresh ThemeData per pump would start an AnimatedTheme tween.
final _theme = buildSottoTheme(SottoPalette.stage);

Widget _app(Widget child, {bool still = false}) => MaterialApp(
  theme: _theme,
  home: MediaQuery(
    data: MediaQueryData(size: const Size(800, 600), disableAnimations: still),
    child: Material(child: Center(child: child)),
  ),
);

void main() {
  testWidgets('Reveal waits out its delay, then settles with no effect layers left', (tester) async {
    await tester.pumpWidget(_app(const Reveal(delay: Duration(milliseconds: 200), child: Text('hi'))));
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0);

    await tester.pumpAndSettle();
    expect(find.byType(Opacity), findsNothing);
    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.text('hi'), findsOneWidget);
  });

  testWidgets('a disabled Reveal shows its child on the first frame', (tester) async {
    await tester.pumpWidget(_app(const Reveal(enabled: false, delay: Duration(milliseconds: 300), child: Text('now'))));
    expect(find.byType(Opacity), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('RevealWords reads as one label', (tester) async {
    await tester.pumpWidget(_app(const RevealWords('Good afternoon', style: TextStyle())));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Good afternoon'), findsOneWidget);
    expect(find.text('Good '), findsOneWidget);
    expect(find.text('afternoon'), findsOneWidget);
  });

  testWidgets('under reduced motion everything is in place at once and nothing loops', (tester) async {
    await tester.pumpWidget(
      _app(
        const StageGlow(
          child: BorderBeam(
            color: Color(0xFF2F6BFF),
            child: Reveal(child: SizedBox(width: 100, height: 40)),
          ),
        ),
        still: true,
      ),
    );
    expect(find.byType(Opacity), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('the stage and the border beam keep moving otherwise', (tester) async {
    await tester.pumpWidget(
      _app(
        const StageGlow(
          child: BorderBeam(color: Color(0xFF2F6BFF), child: SizedBox(width: 100, height: 40)),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('CursorSpotlight lets taps through to its child', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _app(
        CursorSpotlight(
          color: const Color(0x332F6BFF),
          child: TextButton(onPressed: () => taps++, child: const Text('go')),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    expect(taps, 1);
  });
}

import 'package:flutter/gestures.dart';
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

  testWidgets('the border beam runs its intro laps, then rests until hovered', (tester) async {
    await tester.pumpWidget(
      _app(const BorderBeam(color: Color(0xFF2F6BFF), laps: 2, child: SizedBox(width: 100, height: 40))),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(tester.hasRunningAnimations, isTrue);

    // Two 4 s laps and the fade-out, then nothing ticks.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(tester.hasRunningAnimations, isFalse);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.byType(SizedBox).last));
    await tester.pump();
    expect(tester.hasRunningAnimations, isTrue);
    await mouse.removePointer();
  });

  testWidgets('the stage light moves on a timer, not a per-frame ticker', (tester) async {
    await tester.pumpWidget(_app(const StageGlow(child: SizedBox(width: 100, height: 40))));
    final glow = tester.state<State<StageGlow>>(find.byType(StageGlow)) as dynamic;
    expect(glow.running, isTrue);
    // No ticker asks for every vsync: idle frames only come from the timer.
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pump(StageGlow.frame * 3);
  });

  testWidgets('the stage light freezes when the window is unfocused or hidden, and carries on', (tester) async {
    await tester.pumpWidget(_app(const StageGlow(child: SizedBox(width: 100, height: 40))));
    final glow = tester.state<State<StageGlow>>(find.byType(StageGlow)) as dynamic;
    for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden]) {
      tester.binding.handleAppLifecycleStateChanged(s);
      await tester.pump();
      expect(glow.running, isFalse, reason: '$s');
    }
    // Still painted: frozen on its last frame, never blanked.
    expect(find.byType(CustomPaint), findsWidgets);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(glow.running, isTrue);
  });

  testWidgets('the stage light freezes offstage and under reduced motion', (tester) async {
    await tester.pumpWidget(_app(const TickerMode(enabled: false, child: StageGlow(child: SizedBox()))));
    expect((tester.state<State<StageGlow>>(find.byType(StageGlow)) as dynamic).running, isFalse);
    await tester.pumpWidget(_app(const StageGlow(child: SizedBox()), still: true));
    expect((tester.state<State<StageGlow>>(find.byType(StageGlow)) as dynamic).running, isFalse);
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

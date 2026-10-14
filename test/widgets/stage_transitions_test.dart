import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/core/design/icons.dart';
import 'package:sotto/core/design/theme.dart';
import 'package:sotto/core/design/tokens.dart';
import 'package:sotto/core/widgets/stage_transitions.dart';

// Built once: a fresh ThemeData per pump would start an AnimatedTheme tween.
final _theme = buildSottoTheme(SottoPalette.stage);

Widget _app(Widget home, {bool still = false, GlobalKey<NavigatorState>? nav}) => MaterialApp(
  navigatorKey: nav,
  theme: _theme,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: still),
    child: child!,
  ),
  home: home,
);

/// Compositing layers of type [L] still doing work. Settled effects keep
/// their widgets (so nothing is rebuilt) but must leave no blending or
/// filtering behind — a fully opaque opacity layer is drawn as a plain
/// offset and costs nothing.
Iterable<L> _layers<L extends Layer>(WidgetTester tester) =>
    tester.layers.whereType<L>().where((l) => l is! OpacityLayer || (l.alpha ?? 255) < 255);

void main() {
  setUp(LaunchCurtain.reset);

  testWidgets('the first curtain shows the brand, then leaves only the stage', (tester) async {
    await tester.pumpWidget(_app(const LaunchCurtain(child: Text('stage'))));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CueMark), findsOneWidget);
    expect(find.text('Sotto'), findsOneWidget);

    await tester.pump(LaunchCurtain.full);
    expect(find.byType(CueMark), findsNothing);
    expect(
      find
          .byType(CustomPaint)
          .evaluate()
          .where((e) => e.widget is CustomPaint && (e.widget as CustomPaint).painter != null),
      isEmpty,
    );
    expect(find.text('stage'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('a later mount is the house lights coming up: no brand, quicker', (tester) async {
    await tester.pumpWidget(_app(const LaunchCurtain(child: Text('stage'))));
    await tester.pump(LaunchCurtain.full + const Duration(milliseconds: 50));
    await tester.pumpWidget(_app(const SizedBox()));
    await tester.pumpWidget(_app(const LaunchCurtain(child: Text('stage'))));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(CueMark), findsNothing);
    await tester.pump(LaunchCurtain.lightsUp);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('reduced motion: no curtain at all', (tester) async {
    await tester.pumpWidget(_app(const LaunchCurtain(child: Text('stage')), still: true));
    expect(find.byType(CueMark), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('going live darkens the window, lights the tally, then resolves', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(const Text('library'), nav: nav));
    VoidCallback? lift;
    unawaited(
      playGoLive(
        nav.currentState!.overlay!,
        rehearsal: false,
        label: 'Live',
        title: 'Q3 review',
        lamp: const Color(0xFFF96050),
        still: false,
      ).then((f) => lift = f),
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('Q3 review'), findsOneWidget);
    expect(lift, isNull);

    await tester.pumpAndSettle();
    expect(lift, isNotNull);
    // Lifting the dark (the session didn't start) leaves the library as it was.
    lift!();
    await tester.pump();
    expect(find.text('LIVE'), findsNothing);
    expect(find.text('library'), findsOneWidget);
  });

  testWidgets('under reduced motion going live adds no delay', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(const Text('library'), nav: nav));
    var resolved = false;
    unawaited(
      playGoLive(
        nav.currentState!.overlay!,
        rehearsal: true,
        label: 'Rehearsal',
        title: 'Q3',
        lamp: const Color(0xFF2F6BFF),
        still: true,
      ).then((_) => resolved = true),
    );
    await tester.pump();
    expect(resolved, isTrue);
    expect(find.text('REHEARSAL'), findsNothing);
  });

  testWidgets('the overlay comes into focus, then gets out of the way', (tester) async {
    await tester.pumpWidget(
      _app(const OverlayEntrance(enabled: true, sweep: Color(0xFF2F6BFF), child: Text('reading'))),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(_layers<ImageFilterLayer>(tester), isNotEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(_layers<ImageFilterLayer>(tester), isEmpty);
    expect(_layers<OpacityLayer>(tester), isEmpty);
    expect(tester.hasRunningAnimations, isFalse);
  });
}

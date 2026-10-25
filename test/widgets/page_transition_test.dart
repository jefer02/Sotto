// Page switches never show two page layouts at once: the page leaving is
// gone on the first frame and the new one fades in (pages are transparent
// over the shared stage, so any fade-out showed both). And no transition
// rebuilds what it animates.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sotto/app/router.dart' show fadeThroughPage;
import 'package:sotto/core/design/theme.dart';
import 'package:sotto/core/design/tokens.dart';
import 'package:sotto/core/widgets/interactive.dart';
import 'package:sotto/core/widgets/motion_effects.dart';
import 'package:sotto/core/widgets/nav.dart';
import 'package:sotto/core/widgets/stage_transitions.dart';

/// How visible [text] is: the product of the opacities above it, 0 when it
/// isn't on screen.
double _visibility(WidgetTester tester, String text) {
  final f = find.text(text, skipOffstage: false);
  if (f.evaluate().isEmpty) return 0;
  final e = f.evaluate().first;
  var o = 1.0;
  e.visitAncestorElements((a) {
    final w = a.widget;
    if (w is Opacity) o *= w.opacity;
    if (w is FadeTransition) o *= w.opacity.value;
    if (w is Offstage && w.offstage) o = 0;
    return true;
  });
  return o;
}

final _theme = buildSottoTheme(SottoPalette.stage);

GoRouter _router() => GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      pageBuilder: (c, s, child) => fadeThroughPage(c, s, Scaffold(body: child)),
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (c, s) => fadeThroughPage(c, s, const Center(child: Text('Home'))),
        ),
        GoRoute(
          path: '/scripts',
          pageBuilder: (c, s) => fadeThroughPage(c, s, const Center(child: Text('All scripts'))),
        ),
      ],
    ),
    GoRoute(
      path: '/script/:id',
      pageBuilder: (c, s) => fadeThroughPage(c, s, const Center(child: Text('Editor'))),
    ),
  ],
);

Widget _app(GoRouter router, {bool still = false}) => MaterialApp.router(
  theme: _theme,
  routerConfig: router,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: still),
    child: child!,
  ),
);

void main() {
  test('the leaving page is hidden at once; an uncovered one fades back', () {
    AnimationController c(double v, AnimationStatus st) =>
        AnimationController(vsync: const TestVSync(), value: v)..stop(canceled: false);
    final shown = AlwaysStoppedAnimation<double>(1);
    // Covered: the page above has just started arriving.
    final arriving = AnimationController(vsync: const TestVSync(), duration: PageFadeThrough.duration)..forward();
    expect(PageFadeThrough.opacity(shown, arriving), 0);
    arriving.dispose();
    // Uncovered: the page above is popping.
    final popping = AnimationController(vsync: const TestVSync(), duration: PageFadeThrough.duration, value: 1)
      ..reverse();
    expect(PageFadeThrough.opacity(shown, popping), 0);
    popping.value = 0.5;
    popping.reverse();
    expect(PageFadeThrough.opacity(shown, popping), inExclusiveRange(0, 1));
    popping.dispose();
    c(0, AnimationStatus.dismissed).dispose();
  });

  for (final still in [false, true]) {
    for (final (from, to, fromText, toText) in [
      ('/', '/scripts', 'Home', 'All scripts'),
      ('/scripts', '/script/1', 'All scripts', 'Editor'),
      ('/script/1', '/', 'Editor', 'Home'),
    ]) {
      testWidgets('$from → $to${still ? ' (reduced motion)' : ''}: the old page is gone before the new one shows', (
        tester,
      ) async {
        final router = _router();
        await tester.pumpWidget(_app(router, still: still));
        router.go(from);
        await tester.pumpAndSettle();
        expect(_visibility(tester, fromText), 1);

        router.go(to);
        await tester.pump();
        expect(_visibility(tester, fromText), 0, reason: 'the old page is hidden on the first frame');
        final step = PageFadeThrough.duration ~/ 20;
        for (var i = 0; i < 22; i++) {
          final old = _visibility(tester, fromText);
          final next = _visibility(tester, toText);
          expect(old > 0.01 && next > 0.01, isFalse, reason: 'frame $i: old $old, new $next');
          await tester.pump(step);
        }
        await tester.pumpAndSettle();
        expect(_visibility(tester, toText), 1);
        expect(_visibility(tester, fromText), 0);
      });
    }
  }

  testWidgets('reduced motion: an instant switch', (tester) async {
    final router = _router();
    await tester.pumpWidget(_app(router, still: true));
    router.go('/scripts');
    await tester.pump();
    await tester.pump();
    expect(_visibility(tester, 'All scripts'), 1);
  });

  testWidgets('content that changes in place fades in only', (tester) async {
    Widget page(String name) => MaterialApp(
      theme: _theme,
      home: ContentFadeIn(key: ValueKey(name), child: Text(name)),
    );
    await tester.pumpWidget(page('Appearance'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(page('Voice'));
    expect(find.text('Appearance'), findsNothing);
    expect(_visibility(tester, 'Voice'), lessThan(0.2));
    await tester.pump(ContentFadeIn.duration);
    await tester.pump();
    expect(_visibility(tester, 'Voice'), 1);
  });

  testWidgets('a dialog over a page leaves the page visible', (tester) async {
    final router = _router();
    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();
    unawaited(
      showSottoDialog<void>(
        context: tester.element(find.text('Home')),
        builder: (_) => const Dialog(child: Text('Dialog')),
      ),
    );
    await tester.pumpAndSettle();
    expect(_visibility(tester, 'Home'), 1);
    expect(find.text('Dialog'), findsOneWidget);
  });

  group('nothing is rebuilt from scratch', () {
    testWidgets('by an entrance', (tester) async {
      _Probe.inits = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: _theme,
          home: Reveal(child: _Probe()),
        ),
      );
      await tester.pumpAndSettle();
      expect(_Probe.inits, 1);
    });

    testWidgets('by an entrance that sharpens from a blur', (tester) async {
      _Probe.inits = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: _theme,
          home: Reveal(blur: 6, child: _Probe()),
        ),
      );
      await tester.pumpAndSettle();
      expect(_Probe.inits, 1);
    });

    testWidgets('by pressing', (tester) async {
      _Probe.inits = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: _theme,
          home: Interactive(
            onTap: () {},
            builder: (_, s) => PressScale(pressed: s.pressed, child: const _Probe()),
          ),
        ),
      );
      final g = await tester.startGesture(tester.getCenter(find.byType(_Probe)));
      await tester.pumpAndSettle();
      await g.up();
      await tester.pumpAndSettle();
      expect(_Probe.inits, 1);
    });

    testWidgets('by content fading in', (tester) async {
      _Probe.inits = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: _theme,
          home: ContentFadeIn(child: _Probe()),
        ),
      );
      await tester.pumpAndSettle();
      expect(_Probe.inits, 1);
    });

    testWidgets('by the overlay entrance', (tester) async {
      _Probe.inits = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: _theme,
          home: OverlayEntrance(enabled: true, sweep: Colors.blue, child: _Probe()),
        ),
      );
      await tester.pumpAndSettle();
      expect(_Probe.inits, 1);
    });

    testWidgets('by the curtain', (tester) async {
      LaunchCurtain.reset();
      _Probe.inits = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: _theme,
          home: LaunchCurtain(child: _Probe()),
        ),
      );
      await tester.pumpAndSettle();
      expect(_Probe.inits, 1);
    });

    testWidgets('by focusing a control', (tester) async {
      _Probe.inits = 0;
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: _theme,
          home: Interactive(focusNode: focus, onTap: () {}, builder: (_, _) => const _Probe()),
        ),
      );
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
      focus.requestFocus();
      await tester.pumpAndSettle();
      focus.unfocus();
      await tester.pumpAndSettle();
      expect(_Probe.inits, 1);
    });
  });

  group('sidebar selection', () {
    testWidgets('the light slides to the newly selected row', (tester) async {
      await tester.pumpWidget(_nav(0));
      await tester.pumpAndSettle();
      final first = tester.getRect(find.text('Item 0'));
      expect(_light(tester).top, closeTo(first.top - (32 - first.height) / 2, 0.5));

      await tester.pumpWidget(_nav(3));
      await tester.pump();
      await tester.pump(NavHighlight.slide ~/ 2);
      final row3 = tester.getRect(find.ancestor(of: find.text('Item 3'), matching: find.byType(NavItem)));
      final mid = _light(tester).top;
      expect(mid, greaterThan(_light(tester).top - 1000));
      expect(mid, lessThan(row3.top), reason: 'still on its way');
      await tester.pumpAndSettle();
      expect(_light(tester).top, closeTo(row3.top, 0.5));
    });

    testWidgets('selecting a row never rebuilds it', (tester) async {
      await tester.pumpWidget(_nav(0));
      await tester.pumpAndSettle();
      final before = tester.state(find.byType(Interactive).at(2));
      await tester.pumpWidget(_nav(2));
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(Interactive).at(2)), same(before));
    });
  });
}

class _Probe extends StatefulWidget {
  const _Probe();
  static int inits = 0;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    _Probe.inits++;
  }

  @override
  Widget build(BuildContext context) => const Text('probe');
}

/// Rows inside a [NavHighlight]; the selected one is [selected].
Widget _nav(int selected) => MaterialApp(
  theme: _theme,
  home: Scaffold(
    body: SizedBox(
      width: 240,
      child: NavHighlight(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (var i = 0; i < 4; i++) NavItem(label: 'Item $i', selected: i == selected, onTap: () {})],
        ),
      ),
    ),
  ),
);

/// Where the shared selection light is.
Rect _light(WidgetTester tester) => tester.getRect(find.byType(AnimatedPositioned));

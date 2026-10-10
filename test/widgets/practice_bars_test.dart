import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/core/design/theme.dart';
import 'package:sotto/core/design/tokens.dart';
import 'package:sotto/core/widgets/ping_dot.dart';
import 'package:sotto/data/models/session_record.dart';
import 'package:sotto/features/library/practice_bars.dart';
import 'package:sotto/l10n/app_localizations.dart';

final _now = DateTime(2026, 10, 9, 15);

// Built once: a fresh ThemeData per pump would start an AnimatedTheme tween.
final _theme = buildSottoTheme(SottoPalette.stage);

SessionRecord _run(String id, DateTime at, {bool rehearsal = true, int minutes = 10, bool agent = false}) =>
    SessionRecord(
      id: id,
      scriptId: 's',
      scriptTitle: 'Q3',
      startedAt: at,
      endedAt: at.add(Duration(minutes: minutes)),
      rehearsal: rehearsal,
      wordsSpoken: agent ? 0 : 100,
      agentRuns: agent ? const [AgentRunRecord(task: 't', status: 'completed')] : const [],
    );

Widget _app(Widget child, {bool still = false}) => MaterialApp(
  theme: _theme,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: MediaQuery(
    data: MediaQueryData(size: const Size(800, 600), disableAnimations: still),
    child: Material(
      child: Padding(padding: const EdgeInsets.fromLTRB(40, 120, 40, 40), child: child),
    ),
  ),
);

void main() {
  group('practiceDays', () {
    test('buckets runs into local days, oldest first, and skips agent-only records', () {
      final days = practiceDays(
        [
          _run('a', DateTime(2026, 10, 9, 9)),
          _run('b', DateTime(2026, 10, 9, 20), rehearsal: false, minutes: 20),
          _run('c', DateTime(2026, 10, 1, 23, 50)),
          _run('old', DateTime(2026, 9, 9, 12)), // 30 days back: outside the range
          _run('agent', DateTime(2026, 10, 5), agent: true),
        ],
        days: 30,
        now: _now,
      );
      expect(days, hasLength(30));
      expect(days.first.date, DateTime(2026, 9, 10));
      expect(days.last.date, DateTime(2026, 10, 9));
      expect((days.last.rehearsals, days.last.live, days.last.seconds), (1, 1, 30 * 60));
      expect(days[21].date, DateTime(2026, 10, 1));
      expect(days[21].rehearsals, 1);
      expect(days.where((d) => !d.empty), hasLength(2));
    });

    test('crossing a daylight-saving change keeps one bucket per calendar day', () {
      final days = practiceDays([_run('a', DateTime(2026, 3, 30, 0, 30))], days: 10, now: DateTime(2026, 4, 2));
      expect(days.map((d) => d.date.day).toSet(), hasLength(10));
      expect(days.firstWhere((d) => !d.empty).date, DateTime(2026, 3, 30));
    });
  });

  testWidgets('counts the days practiced and shows a day on hover and with the arrow keys', (tester) async {
    await tester.pumpWidget(
      _app(
        PracticeBars(
          now: _now,
          sessions: [_run('a', DateTime(2026, 10, 9, 9)), _run('b', DateTime(2026, 10, 7, 9), rehearsal: false)],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 days practiced'), findsOneWidget);
    expect(find.text('Last 30 days'), findsOneWidget);

    // Every bar is drawn full height once the entrance settles.
    final bar = tester.getSize(
      find.descendant(of: find.byType(AnimatedOpacity), matching: find.byType(DecoratedBox)).first,
    );
    expect(bar.width, greaterThan(10));
    expect(bar.height, 32);

    // Hover today's bar (the right-most slot).
    final strip = tester.getRect(find.byType(AnimatedBuilder).last);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(Offset(strip.right - 2, strip.center.dy));
    await tester.pumpAndSettle();
    expect(find.text('1 rehearsal'), findsOneWidget);
    expect(find.text('10:00'), findsOneWidget);

    // Two days back with the keyboard: the live run.
    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    final focus = tester.widget<Focus>(
      find.byWidgetPredicate((w) => w is Focus && w.focusNode?.debugLabel == 'PracticeBars'),
    );
    focus.focusNode!.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('1 live run'), findsOneWidget);
  });

  testWidgets('reads in Spanish', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        theme: buildSottoTheme(SottoPalette.stage),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Material(
          child: PracticeBars(now: _now, sessions: [_run('a', DateTime(2026, 10, 9, 9))]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 día de práctica'), findsOneWidget);
    expect(find.text('Últimos 30 días'), findsOneWidget);
  });

  group('PingDot', () {
    testWidgets('repeats while active and stops when switched off', (tester) async {
      Widget dot(bool active) => _app(
        Center(
          child: PingDot(color: const Color(0xFFFF0000), active: active),
        ),
      );
      await tester.pumpWidget(dot(true));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.hasRunningAnimations, isTrue);
      expect(find.byType(Opacity), findsOneWidget);

      await tester.pumpWidget(dot(false));
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.byType(Opacity), findsNothing);
    });

    testWidgets('stays still when the system asks for less motion', (tester) async {
      await tester.pumpWidget(_app(const Center(child: PingDot(color: Color(0xFFFF0000))), still: true));
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/core/design/theme.dart';
import 'package:sotto/core/design/tokens.dart';
import 'package:sotto/core/design/typography.dart';
import 'package:sotto/core/platform/window_service.dart';
import 'package:sotto/data/models/script.dart';
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/domain/following/follow_engine.dart';
import 'package:sotto/domain/following/script_aligner.dart';
import 'package:sotto/domain/overlay/auto_height.dart';
import 'package:sotto/features/live/live_state.dart';
import 'package:sotto/features/live/overlay/reading_view.dart';
import 'package:sotto/l10n/app_localizations.dart';

import '../core/overlay_window_test.dart' show FakeWindowHost;

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
          Beat.create('Short one.'),
          Beat.create(
            'This beat is a good deal longer than the others, so it wraps over several lines '
            'in a narrow overlay and needs more room under the eye-line than a short one does.',
          ),
          Beat.create('Another short one.'),
          Beat.create('And the last.'),
        ],
      ),
    ],
  );
}

LiveState _at(int beat) {
  final script = _script();
  return LiveState(
    phase: LivePhase.reading,
    script: script,
    flat: FlatScript.from(script),
    position: FollowPosition(beat: beat, spokenWords: 0, confidence: 1, holding: false),
  );
}

void main() {
  group('clamp', () {
    test('never under 60 px, never over the setting', () {
      expect(AutoHeight.clamp(20, screenHeight: 1000, maxFraction: 0.4), 60);
      expect(AutoHeight.clamp(300, screenHeight: 1000, maxFraction: 0.4), 300);
      expect(AutoHeight.clamp(900, screenHeight: 1000, maxFraction: 0.4), 400);
      expect(AutoHeight.clamp(900, screenHeight: 1000, maxFraction: 0.8), 800);
    });

    test('a height dragged by the presenter becomes the maximum for the session', () {
      expect(AutoHeight.clamp(300, screenHeight: 1000, maxFraction: 0.4, userCap: 180), 180);
      expect(AutoHeight.clamp(600, screenHeight: 1000, maxFraction: 0.4, userCap: 520), 520);
      expect(AutoHeight.clamp(100, screenHeight: 1000, maxFraction: 0.4, userCap: 180), 100);
    });

    test('fitted ends a pad under the last visible line', () {
      expect(AutoHeight.fitted(anchorY: 40, lineHeight: 30, belowCurrent: 100), 40 - 15 + 100 + AutoHeight.bottomPad);
    });
  });

  test('height changes ease out over 150 ms and grow away from the docked edge', () async {
    final host = FakeWindowHost();
    final window = WindowService(host: host, supportedOverride: true);
    await window.enterOverlay(const AppSettings(overlaySize: (480, 120), overlayPositions: {'p': (700, 12)}));
    host.setBoundsCalls.clear();

    await window.animateHeight(300);
    final heights = [for (final r in host.setBoundsCalls) r.height];
    expect(heights.length, greaterThan(3));
    expect(heights.last, 300);
    for (var i = 1; i < heights.length; i++) {
      expect(heights[i], greaterThan(heights[i - 1]));
    }
    // Ease-out: the first step covers more than a linear share.
    expect(heights.first - 120, greaterThan((300 - 120) / heights.length));
    expect(host.setBoundsCalls.every((r) => r.top == 12), isTrue, reason: 'top-docked: grows down');

    host.setBoundsCalls.clear();
    await window.animateHeight(150, fromBottom: true);
    expect(host.setBoundsCalls.last.bottom, 312, reason: 'bottom-docked: the bottom edge stays');
    expect(host.setBoundsCalls.last.height, 150);
  });

  testWidgets('each advance reports a height that just fits the visible lines', (tester) async {
    tester.view.physicalSize = const Size(480, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fits = <double>[];

    Widget view(LiveState s) => MaterialApp(
      theme: buildSottoTheme(SottoPalette.stage),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Material(
        child: ReadingView(
          state: s,
          layout: ResolvedLayout.standard,
          style: const ReadingStyle(size: ReadingSize.m, linesShown: 3, glide: false, reduceMotion: true, plate: false),
          anchorOffset: 40,
          onFit: fits.add,
        ),
      ),
    );

    // Current: a short beat; next (the only line below): the long one.
    await tester.pumpWidget(view(_at(0)));
    await tester.pumpAndSettle();
    expect(fits, isNotEmpty);
    final shortThenLong = fits.last;
    // The overlay area is 600 tall; the fit is far less — no empty space.
    expect(shortThenLong, lessThan(400));

    // Current: a short beat; next: another short one.
    await tester.pumpWidget(view(_at(2)));
    await tester.pumpAndSettle();
    final shortThenShort = fits.last;
    expect(shortThenShort, lessThan(shortThenLong));
  });
}

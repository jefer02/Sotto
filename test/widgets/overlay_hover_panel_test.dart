import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/core/design/theme.dart';
import 'package:sotto/core/design/tokens.dart';
import 'package:sotto/core/platform/overlay_geometry.dart';
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/data/repositories.dart';
import 'package:sotto/features/forms/autofill_controller.dart';
import 'package:sotto/features/live/live_controller.dart';
import 'package:sotto/features/live/live_state.dart';
import 'package:sotto/features/live/overlay/overlay_controls.dart';
import 'package:sotto/features/live/overlay_palette.dart';
import 'package:sotto/l10n/app_localizations.dart';

class _Settings extends SettingsNotifier {
  _Settings(this.initial);
  final AppSettings initial;

  @override
  AppSettings build() => initial;

  @override
  void update(AppSettings Function(AppSettings) change) => state = change(state);
}

class _Live extends LiveController {
  _Live([this.phase = LivePhase.reading]);
  final LivePhase phase;
  final sizes = <int>[];
  final calls = <String>[];
  var moves = 0;

  @override
  LiveState build() => LiveState(phase: phase);

  @override
  void previousBeat() => calls.add('previous');

  @override
  void nextBeat() => calls.add('next');

  @override
  void togglePause() => calls.add('pause');

  @override
  void askDown() => calls.add('askDown');

  @override
  void askUp() => calls.add('askUp');

  @override
  void textSize(int delta) => sizes.add(delta);

  @override
  Future<void> moveDisplay() async => moves++;
}

class _AutoFill extends AutoFillController {
  final calls = <bool>[];

  @override
  AutoFillState build() => const AutoFillState();

  @override
  void setEnabled(bool on) => calls.add(on);
}

void main() {
  late _Live live;
  late _AutoFill autoFill;
  late ProviderContainer container;
  var ended = 0;

  Future<void> pump(WidgetTester tester, AppSettings s, {LivePhase phase = LivePhase.reading}) async {
    live = _Live(phase);
    autoFill = _AutoFill();
    ended = 0;
    container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(() => _Settings(s)),
        liveControllerProvider.overrideWith(() => live),
        autoFillControllerProvider.overrideWith(() => autoFill),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) {
            final settings = ref.watch(settingsProvider);
            return MaterialApp(
              theme: buildSottoTheme(SottoPalette.stage, overlay: overlayPaletteFor(settings, dark: true)),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Material(
                color: const Color(0xFF15181D),
                child: Center(
                  child: OverlayControls(state: ref.watch(liveControllerProvider), onEnd: () => ended++),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Presses a button by its tooltip and keeps the pointer down.
  Future<TestGesture> press(WidgetTester tester, String tooltip) async {
    final g = await tester.startGesture(tester.getCenter(find.byTooltip(tooltip)));
    await tester.pump();
    return g;
  }

  Finder card() => find.byWidgetPredicate(
    (w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).boxShadow != null,
  );

  testWidgets('buttons fire on pointer-down, before any release', (tester) async {
    await pump(tester, const AppSettings());
    final g = await press(tester, 'Text size down');
    expect(live.sizes, [-1]);
    await g.up();
    await (await press(tester, 'Text size up')).up();
    await (await press(tester, 'Move to next display')).up();
    await (await press(tester, 'Auto-fill is off — turn on')).up();
    expect(live.sizes, [-1, 1]);
    expect(live.moves, 1);
    expect(autoFill.calls, [true]);
  });

  testWidgets('previous, pause, next and Ask fire on pointer-down; Ask also reports the release', (tester) async {
    await pump(tester, const AppSettings());
    await (await press(tester, 'Previous beat')).up();
    await (await press(tester, 'Pause')).up();
    await (await press(tester, 'Next beat')).up();
    final g = await press(tester, 'Ask a question');
    expect(live.calls, ['previous', 'pause', 'next', 'askDown']);
    await g.up();
    expect(live.calls.last, 'askUp');
  });

  testWidgets('pause shows Resume while paused', (tester) async {
    await pump(tester, const AppSettings(), phase: LivePhase.paused);
    expect(find.byTooltip('Resume'), findsOneWidget);
    expect(find.byTooltip('Pause'), findsNothing);
  });

  group('End session needs a one-second hold', () {
    const tip = 'Hold 1 s to end session';

    testWidgets('a quick press or a release at 0.5 s does nothing; the ring shows while held', (tester) async {
      await pump(tester, const AppSettings());
      await (await press(tester, tip)).up();
      await tester.pump(const Duration(seconds: 2));
      expect(ended, 0);

      final g = await press(tester, tip);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(ended, 0);
      await g.up();
      await tester.pump(const Duration(seconds: 2));
      expect(ended, 0);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('leaving the button before a second cancels', (tester) async {
      await pump(tester, const AppSettings());
      final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await g.addPointer(location: Offset.zero);
      await g.moveTo(tester.getCenter(find.byTooltip(tip)));
      await g.down(tester.getCenter(find.byTooltip(tip)));
      await tester.pump(const Duration(milliseconds: 600));
      await g.moveTo(tester.getCenter(find.byTooltip(tip)) + const Offset(0, 60));
      await tester.pump(const Duration(seconds: 1));
      expect(ended, 0);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await g.up();
      await g.removePointer();
      await tester.pump(const Duration(seconds: 1));
      expect(ended, 0);
    });

    testWidgets('a full second ends the session, once, while still held', (tester) async {
      await pump(tester, const AppSettings());
      final g = await press(tester, tip);
      await tester.pump(const Duration(milliseconds: 900));
      expect(ended, 0);
      await tester.pump(const Duration(milliseconds: 150));
      expect(ended, 1);
      await g.up();
      await tester.pump(const Duration(seconds: 1));
      expect(ended, 1);
    });
  });

  testWidgets('style and text color cycle; text only has no card, panel has one', (tester) async {
    await pump(tester, const AppSettings());
    expect(card(), findsNothing);

    await (await press(tester, 'Text color: Auto')).up();
    await tester.pump();
    expect(container.read(settingsProvider).overlayTextColor, OverlayTextColor.light);
    await (await press(tester, 'Text color: Always light')).up();
    await tester.pump();
    await (await press(tester, 'Text color: Always dark')).up();
    await tester.pump();
    expect(container.read(settingsProvider).overlayTextColor, OverlayTextColor.auto);

    await (await press(tester, 'Overlay style: Text only')).up();
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).overlayStyle, OverlayStyle.panel);
    expect(card(), findsOneWidget);
    expect(find.byTooltip('Overlay style: Panel'), findsOneWidget);
  });

  testWidgets('auto-fill on shows its state; chat button only when chat is turned on', (tester) async {
    await pump(tester, const AppSettings(formsEnabled: true, formsAutoFill: true));
    expect(find.byTooltip('Auto-fill is on — turn off'), findsOneWidget);
    expect(find.byTooltip('Open chat'), findsNothing);

    await pump(tester, const AppSettings(showChat: true));
    await (await press(tester, 'Open chat')).up();
    await tester.pump();
    expect(find.byTooltip('Close chat'), findsOneWidget);
    await (await press(tester, 'Close chat')).up(); // stops its idle timer
  });

  test('custom text color cycles back to Auto', () {
    expect(OverlayControls.nextTextColor(OverlayTextColor.custom), OverlayTextColor.auto);
  });

  test('panel side: opposite the camera edge', () {
    const area = Rect.fromLTWH(0, 0, 1920, 1080);
    expect(OverlayGeometry.nearTop(const Rect.fromLTWH(700, 12, 480, 120), area), isTrue);
    expect(OverlayGeometry.nearTop(const Rect.fromLTWH(700, 940, 480, 120), area), isFalse);
  });
}

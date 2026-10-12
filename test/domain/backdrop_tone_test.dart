import 'dart:typed_data';
import 'dart:ui';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/core/design/tokens.dart';
import 'package:sotto/data/models/script.dart';
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/data/repositories.dart';
import 'package:sotto/domain/following/follow_engine.dart';
import 'package:sotto/domain/following/script_aligner.dart';
import 'package:sotto/domain/overlay/backdrop_tone.dart';
import 'package:sotto/features/live/backdrop_tone_controller.dart';
import 'package:sotto/features/live/live_controller.dart';
import 'package:sotto/features/live/live_state.dart';
import 'package:sotto/features/live/overlay_palette.dart';

/// A [width] × [height] grid of one color, 4 bytes per pixel.
Uint8List grid(int width, int height, List<int> rgba) =>
    Uint8List.fromList([for (var i = 0; i < width * height; i++) ...rgba]);

class FakeSource implements BackdropSource {
  FakeSource(this.luma0);

  double? luma0;
  int calls = 0;

  @override
  Future<double?> luma() async {
    calls++;
    return luma0;
  }
}

class FakeLive extends LiveController {
  FakeLive(this.initial);
  final LiveState initial;

  @override
  LiveState build() => initial;

  void set(LiveState s) => state = s;
}

class FakeSettings extends SettingsNotifier {
  FakeSettings(this.initial);
  final AppSettings initial;

  @override
  AppSettings build() => initial;

  @override
  void update(AppSettings Function(AppSettings) change) => state = change(state);
}

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
          Beat.create('First we look at revenue.'),
          const Beat(id: 'b2', text: 'Then the margin chart.', cue: Cue(CueType.slide, '2')),
        ],
      ),
    ],
  );
}

LiveState _live(int beat) {
  final script = _script();
  return LiveState(
    phase: LivePhase.reading,
    script: script,
    flat: FlatScript.from(script),
    position: FollowPosition(beat: beat, spokenWords: 0, confidence: 1, holding: false),
  );
}

void main() {
  group('luminance', () {
    test('white, black and mid-grey grids', () {
      expect(averageLuma(grid(4, 3, [255, 255, 255, 255]), width: 4, height: 3), closeTo(1, 1e-9));
      expect(averageLuma(grid(4, 3, [0, 0, 0, 255]), width: 4, height: 3), 0);
      expect(averageLuma(grid(2, 2, [128, 128, 128, 255]), width: 2, height: 2), closeTo(0.502, 0.001));
    });

    test('channel weights and pixel order', () {
      // Pure green is bright, pure blue is dark.
      expect(averageLuma(grid(2, 2, [0, 255, 0, 255]), width: 2, height: 2), closeTo(0.7152, 1e-4));
      expect(averageLuma(grid(2, 2, [0, 0, 255, 255]), width: 2, height: 2), closeTo(0.0722, 1e-4));
      // The same bytes read as BGRA: now it's red.
      expect(
        averageLuma(grid(2, 2, [0, 0, 255, 255]), width: 2, height: 2, order: PixelOrder.bgra),
        closeTo(0.2126, 1e-4),
      );
    });

    test('half white, half black averages to one half; transparent pixels are skipped', () {
      final px = Uint8List.fromList([
        ...grid(2, 1, [255, 255, 255, 255]),
        ...grid(2, 1, [0, 0, 0, 255]),
      ]);
      expect(averageLuma(px, width: 2, height: 2), closeTo(0.5, 1e-9));
      final holes = Uint8List.fromList([
        ...grid(1, 1, [255, 255, 255, 255]),
        ...grid(3, 1, [0, 0, 0, 0]),
      ]);
      expect(averageLuma(holes, width: 2, height: 2), closeTo(1, 1e-9));
    });

    test('threshold: above 0.5 is a light backdrop', () {
      expect(toneForLuma(0.51), BackdropTone.light);
      expect(toneForLuma(0.5), BackdropTone.dark);
      expect(toneForLuma(0.1), BackdropTone.dark);
    });
  });

  group('debounce', () {
    final t0 = DateTime(2026);
    DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

    test('a change is adopted only when a sample 400 ms later agrees', () {
      final d = ToneDebouncer();
      expect(d.observe(BackdropTone.light, at(0)), isFalse);
      expect(d.pending, isTrue);
      expect(d.observe(BackdropTone.light, at(200)), isFalse);
      expect(d.observe(BackdropTone.light, at(400)), isTrue);
      expect(d.current, BackdropTone.light);
    });

    test('a slide transition that flashes and goes back never switches', () {
      final d = ToneDebouncer();
      expect(d.observe(BackdropTone.light, at(0)), isFalse);
      expect(d.observe(BackdropTone.dark, at(400)), isFalse);
      expect(d.pending, isFalse);
      expect(d.observe(BackdropTone.light, at(800)), isFalse);
      expect(d.current, BackdropTone.dark);
    });
  });

  group('sampler', () {
    ProviderContainer container(FakeSource source, {OverlayTextColor mode = OverlayTextColor.auto, int beat = 0}) {
      final start = DateTime(2026);
      return ProviderContainer(
        overrides: [
          backdropSourceProvider.overrideWithValue(source),
          liveControllerProvider.overrideWith(() => FakeLive(_live(beat))),
          settingsProvider.overrideWith(() => FakeSettings(AppSettings(overlayTextColor: mode))),
          // fake_async's clock drives the debouncer.
          backdropTimingProvider.overrideWithValue(BackdropTiming(now: () => start.add(_elapsed))),
        ],
      );
    }

    test('samples every 800 ms and switches after the 400 ms confirmation', () {
      fakeAsync((async) {
        _async = async;
        final source = FakeSource(0.1);
        final c = container(source);
        c.listen(backdropToneProvider, (_, _) {});
        async.flushMicrotasks();
        expect(c.read(backdropToneProvider), BackdropTone.dark);
        expect(source.calls, 1);

        async.elapse(const Duration(milliseconds: 800));
        expect(source.calls, 2);

        source.luma0 = 0.9; // a white slide comes up
        async.elapse(const Duration(milliseconds: 800));
        expect(c.read(backdropToneProvider), BackdropTone.dark, reason: 'not before the confirmation');
        async.elapse(const Duration(milliseconds: 400));
        expect(c.read(backdropToneProvider), BackdropTone.light);
        c.dispose();
      });
    });

    test('a slide cue samples at once', () {
      fakeAsync((async) {
        _async = async;
        final source = FakeSource(0.1);
        final c = container(source);
        c.listen(backdropToneProvider, (_, _) {});
        async.flushMicrotasks();
        final before = source.calls;
        (c.read(liveControllerProvider.notifier) as FakeLive).set(_live(1));
        async.flushMicrotasks();
        expect(source.calls, before + 1);
        c.dispose();
      });
    });

    test('a fixed text color turns detection off', () {
      fakeAsync((async) {
        _async = async;
        for (final mode in [OverlayTextColor.light, OverlayTextColor.dark, OverlayTextColor.custom]) {
          final source = FakeSource(0.9);
          final c = container(source, mode: mode);
          c.listen(backdropToneProvider, (_, _) {});
          async.elapse(const Duration(seconds: 5));
          expect(source.calls, 0, reason: '$mode');
          expect(c.read(backdropToneProvider), isNull);
          c.dispose();
        }
      });
    });

    test('switching Auto → Always dark mid-session stops sampling', () {
      fakeAsync((async) {
        _async = async;
        final source = FakeSource(0.9);
        final c = container(source);
        c.listen(backdropToneProvider, (_, _) {});
        async.elapse(const Duration(milliseconds: 1700));
        final calls = source.calls;
        c.read(settingsProvider.notifier).update((s) => s.copyWith(overlayTextColor: OverlayTextColor.dark));
        async.elapse(const Duration(seconds: 5));
        expect(source.calls, calls);
        c.dispose();
      });
    });

    test('no permission: gives up after three misses', () {
      fakeAsync((async) {
        _async = async;
        final source = FakeSource(null);
        final c = container(source);
        c.listen(backdropToneProvider, (_, _) {});
        async.elapse(const Duration(seconds: 10));
        expect(source.calls, 3);
        c.dispose();
      });
    });
  });

  group('palette', () {
    test('tone picks near-black or near-white glyphs, outline and shadow', () {
      const s = AppSettings();
      final onLight = overlayPaletteFor(s, dark: true, backdrop: BackdropTone.light);
      final onDark = overlayPaletteFor(s, dark: true, backdrop: BackdropTone.dark);
      expect(onLight.ink, darkInk);
      expect(onLight.outline, darkInk);
      expect(onLight.shadowColor, const Color(0xFF000000));
      expect(onDark.ink, lightInk);
      expect(onDark.outline, lightInk);
      expect(onDark.shadowColor.r, 1);
      // Fixed modes ignore the backdrop.
      final fixed = overlayPaletteFor(
        const AppSettings(overlayTextColor: OverlayTextColor.dark),
        dark: true,
        backdrop: BackdropTone.dark,
      );
      expect(fixed.ink, darkInk);
    });

    test('the crossfade passes through the middle', () {
      const s = AppSettings();
      final a = overlayPaletteFor(s, dark: true, backdrop: BackdropTone.dark);
      final b = overlayPaletteFor(s, dark: true, backdrop: BackdropTone.light);
      final mid = OverlayPalette.lerp(a, b, 0.5);
      expect(mid.ink.r, closeTo((lightInk.r + darkInk.r) / 2, 0.01));
      expect(OverlayPalette.lerp(a, b, 0).ink, a.ink);
      expect(OverlayPalette.lerp(a, b, 1).ink, b.ink);
    });

    test('colors picked before the setting existed keep working', () {
      expect(AppSettings.fromJson({'textColor': 0xFFFFD60A}).overlayTextColor, OverlayTextColor.custom);
      expect(AppSettings.fromJson({}).overlayTextColor, OverlayTextColor.auto);
    });
  });
}

FakeAsync? _async;
Duration get _elapsed => _async?.elapsed ?? Duration.zero;

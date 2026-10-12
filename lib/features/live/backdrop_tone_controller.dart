import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/window_service.dart';
import '../../data/models/script.dart';
import '../../data/models/settings.dart';
import '../../data/repositories.dart';
import '../../domain/overlay/backdrop_tone.dart';
import '../../services/screen/screen_service.dart';
import 'live_controller.dart';

/// How bright the screen behind the overlay is, 0…1 — or null when it
/// can't be read (no Screen Recording permission, capture failed).
abstract class BackdropSource {
  Future<double?> luma();
}

/// Reads the pixels behind the overlay's frame. Pixel math only: nothing is
/// encoded, stored or sent — no screenshot ever goes to DeepSeek from here.
class ScreenBackdropSource implements BackdropSource {
  ScreenBackdropSource(this.window, this.screen);

  final WindowService window;
  final ScreenService screen;

  @override
  Future<double?> luma() async {
    if (!ScreenService.supported) return null;
    try {
      final frame = await window.bounds();
      final dpr = PlatformDispatcher.instance.views.firstOrNull?.devicePixelRatio ?? 1;
      return (await screen.captureRegion(frame, devicePixelRatio: dpr)).luma;
    } on ScreenCaptureException catch (e) {
      if (!e.permissionDenied) debugPrint('backdrop sample failed: $e');
      return null;
    }
  }
}

final backdropSourceProvider = Provider<BackdropSource>(
  (ref) => ScreenBackdropSource(ref.read(windowServiceProvider), ref.read(screenServiceProvider)),
);

class BackdropTiming {
  const BackdropTiming({
    this.interval = const Duration(milliseconds: 800),
    this.settle = const Duration(milliseconds: 400),
    this.now = DateTime.now,
  });

  /// Between samples while live.
  final Duration interval;

  /// A changed tone must still hold this much later (slide transitions).
  final Duration settle;
  final DateTime Function() now;
}

final backdropTimingProvider = Provider<BackdropTiming>((ref) => const BackdropTiming());

/// Live mode with "Overlay text color: Auto": which tone is behind the
/// overlay, so its text can be dark on light slides and light on dark ones.
/// Null while not sampling — not live, a fixed text color, or no reading
/// yet — and then the configured palette applies.
class BackdropToneController extends Notifier<BackdropTone?> {
  Timer? _timer;
  Timer? _confirm;
  final _debouncer = ToneDebouncer();
  bool _busy = false;
  bool _active = false;
  int _misses = 0;

  late BackdropTiming _timing;

  @override
  BackdropTone? build() {
    _timing = ref.read(backdropTimingProvider);
    ref.onDispose(_stop);
    final live = ref.watch(liveControllerProvider.select((s) => s.isLive));
    final mode = ref.watch(settingsProvider.select((s) => s.overlayTextColor));
    // A slide change: look right away rather than at the next tick.
    ref.listen(liveControllerProvider.select((s) => s.position.beat), (prev, beat) {
      final flat = ref.read(liveControllerProvider).flat;
      if (prev == beat || flat == null || beat < 0 || beat >= flat.beats.length) return;
      if (flat.beats[beat].beat.cue?.type == CueType.slide) slideChanged();
    });
    _stop();
    if (!live || mode != OverlayTextColor.auto) return null;
    _active = true;
    _misses = 0;
    _timer = Timer.periodic(_timing.interval, (_) => unawaited(_sample()));
    unawaited(_sample());
    return null;
  }

  /// A slide cue fired: sample now (the debouncer still waits for the
  /// transition to settle before switching).
  void slideChanged() {
    if (_active) unawaited(_sample());
  }

  Future<void> _sample() async {
    if (!_active || _busy) return;
    _busy = true;
    try {
      final luma = await ref.read(backdropSourceProvider).luma();
      if (!_active) return;
      if (luma == null) {
        // No permission or no capture on this system: stop trying.
        if (++_misses >= 3) _stop();
        return;
      }
      _misses = 0;
      final tone = toneForLuma(luma);
      if (state == null) {
        // First reading: nothing on screen to flicker yet.
        _debouncer.reset(tone);
        state = tone;
        return;
      }
      if (_debouncer.observe(tone, _timing.now())) {
        state = _debouncer.current;
      } else if (_debouncer.pending && _confirm == null) {
        _confirm = Timer(_timing.settle, () {
          _confirm = null;
          unawaited(_sample());
        });
      }
    } finally {
      _busy = false;
    }
  }

  void _stop() {
    _active = false;
    _timer?.cancel();
    _timer = null;
    _confirm?.cancel();
    _confirm = null;
  }
}

final backdropToneProvider = NotifierProvider<BackdropToneController, BackdropTone?>(BackdropToneController.new);

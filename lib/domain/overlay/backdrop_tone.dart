import 'dart:typed_data';

/// What is behind the overlay: a light backdrop needs dark text, a dark one
/// light text.
enum BackdropTone { light, dark }

/// Pixel order of a sampled region.
enum PixelOrder { rgba, bgra }

/// Average perceived brightness of a region, 0 (black) … 1 (white): Rec. 709
/// luma on the gamma-encoded values, which tracks how light a slide *looks*
/// (mid-grey reads as 0.5, not 0.21 as linear luminance would). Fully
/// transparent pixels (nothing drawn there) are skipped.
double averageLuma(Uint8List pixels, {required int width, required int height, PixelOrder order = PixelOrder.rgba}) {
  final count = width * height;
  if (count <= 0 || pixels.length < count * 4) return 0;
  final (ri, bi) = order == PixelOrder.rgba ? (0, 2) : (2, 0);
  var sum = 0.0;
  var used = 0;
  for (var i = 0; i < count; i++) {
    final o = i * 4;
    if (pixels[o + 3] == 0) continue;
    sum += 0.2126 * pixels[o + ri] + 0.7152 * pixels[o + 1] + 0.0722 * pixels[o + bi];
    used++;
  }
  return used == 0 ? 0 : sum / (used * 255);
}

/// Luma above one half is a light backdrop.
BackdropTone toneForLuma(double luma) => luma > 0.5 ? BackdropTone.light : BackdropTone.dark;

/// Keeps the text from flickering while slides change: a new tone is adopted
/// only when a second sample, at least [settle] after the first one that saw
/// it, agrees. A sample that matches the current tone drops any pending one.
class ToneDebouncer {
  ToneDebouncer({this.current = BackdropTone.dark, this.settle = const Duration(milliseconds: 400)});

  BackdropTone current;
  final Duration settle;

  BackdropTone? _pending;
  DateTime? _pendingSince;

  /// Feeds one sample taken at [at]. True when the tone changed.
  bool observe(BackdropTone tone, DateTime at) {
    if (tone == current) {
      _pending = null;
      return false;
    }
    if (_pending == tone && at.difference(_pendingSince!) >= settle) {
      current = tone;
      _pending = null;
      return true;
    }
    if (_pending != tone) {
      _pending = tone;
      _pendingSince = at;
    }
    return false;
  }

  /// A change is waiting for its confirming sample.
  bool get pending => _pending != null;

  void reset(BackdropTone tone) {
    current = tone;
    _pending = null;
  }
}

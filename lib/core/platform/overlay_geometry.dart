import 'dart:math' as math;
import 'dart:ui';

import '../../data/models/settings.dart';

/// A display's usable area (logical pixels, without the taskbar or the menu
/// bar).
class DisplayArea {
  const DisplayArea({required this.id, required this.visible, this.primary = false});

  final String id;
  final Rect visible;
  final bool primary;
}

/// Where the overlay goes and how big it is — pure, so the rules are tested
/// without a window.
abstract final class OverlayGeometry {
  /// Never smaller than this: one line of text and the meta strip's grip.
  static const minimum = Size(320, 60);

  /// With nothing saved: a small strip just below the top centre.
  static const initial = Size(480, 120);

  static const _margin = 12.0;

  /// Top-left position for a placement on a display's visible area.
  static Offset placementOffset(OverlayPlacement p, Rect area, Size size) {
    const margin = _margin;
    final x = switch (p) {
      OverlayPlacement.topLeft || OverlayPlacement.middleLeft || OverlayPlacement.bottomLeft => area.left + margin,
      OverlayPlacement.topRight ||
      OverlayPlacement.middleRight ||
      OverlayPlacement.bottomRight => area.right - size.width - margin,
      _ => area.left + (area.width - size.width) / 2,
    };
    final y = switch (p) {
      // "Under the camera": hug the top edge so eyes stay near the lens.
      OverlayPlacement.topLeft || OverlayPlacement.topCenter || OverlayPlacement.topRight => area.top + margin,
      OverlayPlacement.bottomLeft ||
      OverlayPlacement.bottomCenter ||
      OverlayPlacement.bottomRight => area.bottom - size.height - margin,
      _ => area.top + (area.height - size.height) / 2,
    };
    return Offset(x, y);
  }

  /// The display the overlay opens on: the one it was last left on (when
  /// positions are remembered and that display is still connected), else the
  /// primary one.
  static DisplayArea displayFor(AppSettings s, List<DisplayArea> displays, {DisplayArea? current}) {
    if (s.rememberPositionPerDisplay) {
      if (current != null && s.overlayPositions.containsKey(current.id)) return current;
      for (final d in displays) {
        if (s.overlayPositions.containsKey(d.id)) return d;
      }
    }
    return displays.firstWhere((d) => d.primary, orElse: () => displays.first);
  }

  /// The overlay's frame on [display]: the saved size (clamped to the
  /// minimum and to the display) at the saved position, or at [s.placement]
  /// when none is saved — always fully on the display.
  static Rect frame(AppSettings s, DisplayArea display) {
    final area = display.visible;
    final size = Size(
      s.overlaySize.$1.clamp(minimum.width, math.max(minimum.width, area.width)),
      s.overlaySize.$2.clamp(minimum.height, math.max(minimum.height, area.height)),
    );
    final saved = s.rememberPositionPerDisplay ? s.overlayPositions[display.id] : null;
    final pos = saved != null ? Offset(saved.$1, saved.$2) : placementOffset(s.placement, area, size);
    return clampInto(pos & size, area);
  }

  /// [r] moved (not resized) so it lies inside [area] where it fits.
  static Rect clampInto(Rect r, Rect area) {
    final left = math.min(math.max(r.left, area.left), math.max(area.left, area.right - r.width));
    final top = math.min(math.max(r.top, area.top), math.max(area.top, area.bottom - r.height));
    return Offset(left, top) & r.size;
  }

  /// Whether [overlay] sits in the top half of [area] — nearer the camera
  /// edge at the top than at the bottom.
  static bool nearTop(Rect overlay, Rect area) => overlay.center.dy <= area.center.dy;

  /// [r] covers [area], the way a maximised or tiled window does.
  static bool fills(Rect r, Rect area, {double tolerance = 2}) =>
      r.width >= area.width - tolerance && r.height >= area.height - tolerance;
}

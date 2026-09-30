import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/core/design/tokens.dart';
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/features/live/overlay_palette.dart';

void main() {
  test('text only is the default and has no ground', () {
    final o = overlayPaletteFor(const AppSettings(), dark: true);
    expect(o.textOnly, isTrue);
    expect(o.ground.a, 0);
    expect(o.edge.a, 0);
    // White text gets a dark outline by default ("Auto").
    expect(o.outline, const Color(0xFF000000));
  });

  test('auto outline contrasts with the text color', () {
    final o = overlayPaletteFor(
      const AppSettings(textColor: 0xFF111111, overlayTextColor: OverlayTextColor.custom),
      dark: true,
    );
    expect(o.outline, const Color(0xFFFFFFFF));
  });

  test('panel style keeps the translucent ground and no glyph shadows', () {
    final o = overlayPaletteFor(const AppSettings(overlayStyle: OverlayStyle.panel), dark: true);
    expect(o.textOnly, isFalse);
    expect(o.ground.a, closeTo(0.8, 0.01));
    expect(o.textShadows(), isNull);
  });

  test('outline ring + soft shadow, faded with the glyph', () {
    final o = OverlayPalette.textOnly(
      ink: const Color(0xFFFFFFFF),
      outline: const Color(0xFF000000),
      outlineWidth: 2,
      shadowStrength: 0.5,
    );
    final full = o.textShadows()!;
    expect(full.length, 13);
    expect(full.first.color.a, closeTo(1, 0.01));
    final dim = o.textShadows(0.5)!;
    expect(dim.first.color.a, closeTo(0.5, 0.01));
    // Small text never gets more than a 1.2 px outline.
    expect(o.textShadows(1, true)!.first.offset.distance, closeTo(1.2, 0.01));
    expect(
      OverlayPalette.textOnly(
        ink: const Color(0xFFFFFFFF),
        outline: const Color(0xFF000000),
        outlineWidth: 0,
        shadowStrength: 0,
      ).textShadows(),
      isEmpty,
    );
  });

  test('old settings without a style load as text only; panel round-trips', () {
    expect(AppSettings.fromJson({'overlayOpacity': 0.9}).overlayStyle, OverlayStyle.textOnly);
    final s = AppSettings.fromJson(
      const AppSettings(overlayStyle: OverlayStyle.panel, outlineColor: 0xFFFFFFFF, outlineWidth: 3).toJson(),
    );
    expect(s.overlayStyle, OverlayStyle.panel);
    expect(s.outlineColor, 0xFFFFFFFF);
    expect(s.outlineWidth, 3);
    expect(s.copyWith(autoOutline: true).outlineColor, isNull);
  });
}

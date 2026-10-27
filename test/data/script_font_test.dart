// Script fonts: settings saved before fonts could be chosen, choices that no
// longer make sense, a system font that was uninstalled, and the installed
// font scan itself.
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/core/design/typography.dart';
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/data/repositories.dart';
import 'package:sotto/services/system_fonts.dart';

class _Settings extends SettingsNotifier {
  _Settings(this.initial);
  final AppSettings initial;

  @override
  AppSettings build() => initial;
}

void main() {
  group('settings migration', () {
    test('settings saved before fonts existed keep the fonts they had', () {
      final s = AppSettings.fromJson({'readingSize': 'xl', 'overlayStyle': 'panel'});
      expect(s.overlayFont, ScriptFonts.overlayDefault);
      expect(s.editorFont, ScriptFonts.editorDefault);
      expect(s.highlightEffect, HighlightEffect.off);
      // What the overlay drew before: Atkinson at 500 with a hair of tracking.
      expect(s.overlayFont.family, Fonts.reading);
      expect(s.overlayFont.weight, 500);
    });

    test('a choice survives a save and a load', () {
      const s = AppSettings(
        overlayFont: ScriptFont(family: 'Cormorant', weight: 600, letterSpacing: 0.02),
        editorFont: ScriptFont(family: 'Segoe UI', source: FontSource.system, weight: 400),
        highlightEffect: HighlightEffect.glow,
      );
      final back = AppSettings.fromJson(s.toJson());
      expect(back.overlayFont, s.overlayFont);
      expect(back.editorFont, s.editorFont);
      expect(back.highlightEffect, HighlightEffect.glow);
    });

    test('a bundled font Sotto no longer ships, or garbage, falls back to the default', () {
      for (final bad in [
        {'family': 'Comic Neue', 'source': 'bundled', 'weight': 400},
        {'family': '', 'source': 'system'},
        'Cormorant',
        42,
      ]) {
        final s = AppSettings.fromJson({'overlayFont': bad, 'editorFont': bad});
        expect(s.overlayFont, ScriptFonts.overlayDefault, reason: '$bad');
        expect(s.editorFont, ScriptFonts.editorDefault, reason: '$bad');
      }
    });

    test('weight and spacing are brought into range', () {
      final s = AppSettings.fromJson({
        'overlayFont': {'family': 'Cormorant', 'weight': 900, 'letterSpacing': 2.0},
        'editorFont': {'family': 'Lexend', 'weight': 437, 'letterSpacing': -1.0},
      });
      expect(s.overlayFont.weight, ScriptFonts.cormorant.maxWeight);
      expect(s.overlayFont.letterSpacing, ScriptFonts.maxSpacing);
      expect(s.editorFont.weight, 400);
      expect(s.editorFont.letterSpacing, ScriptFonts.minSpacing);
    });

    test('an unknown highlight effect reads as off', () {
      expect(AppSettings.fromJson({'highlightEffect': 'confetti'}).highlightEffect, HighlightEffect.off);
    });
  });

  group('a saved system font that is gone', () {
    const gone = ScriptFont(family: 'Gone Sans', source: FontSource.system, weight: 500);

    test('falls back to the default once the installed fonts are known', () {
      final r = ScriptFonts.resolve(gone, installed: {'Arial', 'Segoe UI'}, fallback: ScriptFonts.overlayDefault);
      expect(r, ScriptFonts.overlayDefault);
      final still = ScriptFonts.resolve(
        gone.copyWith(family: 'Arial'),
        installed: {'Arial'},
        fallback: ScriptFonts.overlayDefault,
      );
      expect(still.family, 'Arial');
    });

    test('before the scan, it draws with the default as its fallback face', () {
      final r = ScriptFonts.resolve(gone, installed: null, fallback: ScriptFonts.overlayDefault);
      expect(r, gone);
      final style = ReadingType.live(30, font: r);
      expect(style.fontFamily, 'Gone Sans');
      expect(style.fontFamilyFallback, [Fonts.reading]);
    });

    test('the overlay draws the default, and the editor its own default', () async {
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(() => _Settings(const AppSettings(overlayFont: gone, editorFont: gone))),
          systemFontsProvider.overrideWith((ref) async => ['Arial', 'Segoe UI']),
        ],
      );
      addTearDown(container.dispose);
      await container.read(systemFontsProvider.future);
      expect(container.read(overlayScriptFontProvider), ScriptFonts.overlayDefault);
      expect(container.read(editorScriptFontProvider), ScriptFonts.editorDefault);
    });

    test('a bundled choice never waits for the scan', () {
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(
            () => _Settings(const AppSettings(overlayFont: ScriptFont(family: 'Lexend', weight: 400))),
          ),
          systemFontsProvider.overrideWith((ref) => Future.error('the scan must not run')),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(overlayScriptFontProvider).family, 'Lexend');
    });
  });

  group('text styles', () {
    test('family, weight on the variable axis, spacing in ems, and the same line box', () {
      final base = ReadingType.live(30, lineHeight: 40);
      final s = ReadingType.live(
        30,
        lineHeight: 40,
        font: const ScriptFont(family: 'Cormorant', weight: 600, letterSpacing: 0.05),
      );
      expect(s.fontFamily, 'Cormorant');
      expect(s.fontWeight, FontWeight.w600);
      expect(s.fontVariations, [const FontVariation.weight(600)]);
      // Cormorant's small x-height is drawn larger…
      expect(s.fontSize, closeTo(30 * ScriptFonts.cormorant.scale, 1e-9));
      expect(s.letterSpacing, closeTo(s.fontSize! * 0.05, 1e-9));
      // …in the same line box.
      expect(s.fontSize! * s.height!, closeTo(base.fontSize! * base.height!, 1e-9));
    });
  });

  group('installed fonts', () {
    test('a font file names its own family', () {
      expect(SystemFonts.familiesInFile(File('assets/fonts/Lexend-Variable.ttf')), ['Lexend']);
      expect(SystemFonts.familiesInFile(File('assets/fonts/Cormorant-Variable.ttf')), ['Cormorant']);
      expect(SystemFonts.familiesInFile(File('assets/fonts/SourceSans3-Variable.ttf')), ['Source Sans 3']);
    });
  });
}

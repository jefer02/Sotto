import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/design/theme.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/typography.dart';
import '../../../data/models/script.dart';
import '../../../data/models/settings.dart';
import '../../../data/repositories.dart';
import '../../../domain/following/follow_engine.dart';
import '../../../domain/following/script_aligner.dart';
import '../../../l10n/l10n.dart';
import '../live_state.dart';
import '../overlay_palette.dart';
import 'meta_strip.dart';
import 'reading_view.dart';

enum PreviewBackground { darkSlide, lightSlide, videoCall }

final _flatCache = Expando<FlatScript>();

FlatScript flatFor(Script s) => _flatCache[s] ??= FlatScript.from(s);

/// The real overlay widgets, driven by a still frame instead of a session.
class OverlayPreview extends ConsumerWidget {
  const OverlayPreview({
    super.key,
    required this.script,
    this.beat = 0,
    this.spokenWords = 0,
    this.layout = ResolvedLayout.standard,
    this.background = PreviewBackground.darkSlide,
    this.dark,
    this.opacity,
    this.readingSize,
    this.showCamera = true,
  });

  final Script script;
  final int beat;
  final int spokenWords;
  final ResolvedLayout layout;
  final PreviewBackground background;
  final bool? dark;
  final double? opacity;
  final ReadingSize? readingSize;
  final bool showCamera;

  static Size cardSize(ResolvedLayout l) => switch (l) {
    ResolvedLayout.ticker => const Size(320, 96),
    ResolvedLayout.compact => const Size(420, 176),
    ResolvedLayout.column => const Size(380, 520),
    ResolvedLayout.rail => const Size(1200, 120),
    ResolvedLayout.standard => Layout.overlayDefault,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final flat = flatFor(script);
    if (flat.length == 0) return const SizedBox.shrink();
    final b = beat.clamp(0, flat.length - 1);
    final isDark =
        dark ??
        switch (settings.overlayTheme) {
          OverlayThemeMode.dark => true,
          OverlayThemeMode.light => false,
          OverlayThemeMode.matchApp => context.palette.isDark,
        };
    final overlay = overlayPaletteFor(settings, dark: isDark, opacity: opacity);
    final size = readingSize ?? settings.readingSize;

    final still = LiveState(
      phase: LivePhase.reading,
      script: script,
      flat: flat,
      position: FollowPosition(beat: b, spokenWords: spokenWords, confidence: 1, holding: false),
      startedAt: DateTime(2026),
      readingSize: size,
    );
    // The preview clock sits exactly on plan, so the meta strip reads "On pace".
    final state = still.copyWith(elapsed: Duration(seconds: still.plannedAtBeat(settings.wordsPerMinute)));
    final style = ReadingStyle(
      size: size,
      linesShown: settings.linesShown,
      glide: settings.scrollStyle == ScrollStyle.glide,
      reduceMotion: settings.reduceMotion,
      plate: !overlay.textOnly && (opacity ?? settings.overlayOpacity) < 0.7,
      wpm: settings.wordsPerMinute,
    );
    final card = cardSize(layout);

    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        extensions: [SottoTheme(palette: context.palette, overlay: overlay)],
      ),
      child: Builder(
        builder: (context) {
          final o = context.overlayPalette;
          return ClipRRect(
            borderRadius: Radii.rL,
            child: Stack(
              children: [
                Positioned.fill(child: _SlideBackdrop(background: background)),
                if (showCamera)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        width: 88,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.vertical(bottom: Radius.circular(6)),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topCenter,
                      child: SizedBox.fromSize(
                        size: card,
                        child: Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: o.ground,
                            borderRadius: Radii.rXl,
                            border: Border.all(color: o.edge),
                            boxShadow: [o.shadow],
                          ),
                          child: DefaultTextStyle.merge(
                            style: TextStyle(shadows: o.textShadows(1, true)),
                            child: Column(
                              children: [
                                // Text only: the strip shows on hover, so the still frame hides it.
                                Opacity(
                                  opacity: o.textOnly ? 0 : 1,
                                  child: MetaStrip(state: state, density: metaDensityFor(layout)),
                                ),
                                Expanded(
                                  child: MediaQuery(
                                    data: MediaQuery.of(context).copyWith(disableAnimations: true),
                                    child: ReadingView(state: state, layout: layout, style: style),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A stand-in for what sits behind the overlay: a dark slide, a bright
/// slide, or a video call grid.
class _SlideBackdrop extends StatelessWidget {
  const _SlideBackdrop({required this.background});
  final PreviewBackground background;

  @override
  Widget build(BuildContext context) {
    switch (background) {
      case PreviewBackground.videoCall:
        const tiles = [Color(0xFF3B4A5A), Color(0xFF4A3F52), Color(0xFF3F5249), Color(0xFF524636)];
        return Container(
          color: const Color(0xFF111214),
          padding: const EdgeInsets.all(6),
          child: GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 1.6,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final c in tiles)
                DecoratedBox(
                  decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(8)),
                ),
            ],
          ),
        );
      case PreviewBackground.darkSlide:
      case PreviewBackground.lightSlide:
        final light = background == PreviewBackground.lightSlide;
        final bg = light ? Colors.white : const Color(0xFF15181D);
        final bar = light ? const Color(0xFFC8D1DD) : const Color(0xFF3A4658);
        final hi = light ? const Color(0xFF2E5B8C) : const Color(0xFF7FA3C9);
        final ink = light ? const Color(0xFF15181D) : const Color(0xFFE9ECF1);
        return Container(
          color: bg,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (h, highlight) in const [(0.28, false), (0.34, false), (0.38, false), (0.5, true)])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FractionallySizedBox(
                    heightFactor: h,
                    child: Container(
                      width: 24,
                      decoration: BoxDecoration(
                        color: highlight ? hi : bar,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              Text(
                NumberFormat.decimalPercentPattern(locale: L10n.current.localeName, decimalDigits: 1).format(0.314),
                style: TypeScale.title1.copyWith(color: ink, fontSize: 24),
              ),
            ],
          ),
        );
    }
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../l10n/l10n.dart';

import '../../../app/app.dart';
import '../../../core/design/icons.dart';
import '../../../core/design/theme.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/typography.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/display.dart';
import '../../../core/widgets/interactive.dart';
import '../../../data/models/script.dart';
import '../../../data/models/settings.dart';
import '../../../data/repositories.dart';
import '../../live/overlay/overlay_preview.dart';
import '../../live/overlay/reading_view.dart';
import '../settings_screen.dart';

/// The script to preview: the focused one, else the most recent.
final previewScriptProvider = Provider<Script?>((ref) {
  final id = ref.watch(focusedScriptProvider);
  final scripts = ref.watch(scriptsProvider).value ?? const <Script>[];
  return scripts.where((s) => s.id == id).firstOrNull ??
      scripts.where((s) => s.beatCount > 3).firstOrNull ??
      scripts.firstOrNull;
});

/// WCAG contrast of ink at [alpha] over the overlay ground composited on
/// the worst-case slide (white behind a dark overlay, black behind light).
double worstContrast(OverlayPalette o, double alpha) {
  final behind = o.ink.computeLuminance() > 0.5 ? Colors.white : Colors.black;
  final ground = Color.alphaBlend(o.ground, behind);
  final fg = Color.alphaBlend(o.ink.withValues(alpha: alpha), ground);
  final l1 = fg.computeLuminance(), l2 = ground.computeLuminance();
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

class AppearancePage extends ConsumerStatefulWidget {
  const AppearancePage({super.key});

  @override
  ConsumerState<AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends ConsumerState<AppearancePage> {
  PreviewBackground _bg = PreviewBackground.darkSlide;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final script = ref.watch(previewScriptProvider);

    final dark = switch (s.overlayTheme) {
      OverlayThemeMode.dark => true,
      OverlayThemeMode.light => false,
      OverlayThemeMode.matchApp => p.isDark,
    };
    final o = (dark ? OverlayPalette.dark : OverlayPalette.light).withGroundOpacity(s.overlayOpacity);
    final fontPx = overlayFontSize(s.overlaySize.$1, s.readingSize);
    final chars = ((s.overlaySize.$1 - 62) / (fontPx * 0.52)).round();

    return SettingsPageScaffold(
      title: context.l10n.setAppearance,
      description: context.l10n.appearanceDescription,
      action: ResetLink(
        label: context.l10n.reset,
        onTap: () => n.reset(
          (cur, d) => cur.copyWith(
            appTheme: d.appTheme,
            overlayTheme: d.overlayTheme,
            readingSize: d.readingSize,
            linesShown: d.linesShown,
            overlayOpacity: d.overlayOpacity,
            placement: d.placement,
            layout: d.layout,
            scrollStyle: d.scrollStyle,
            reduceMotion: d.reduceMotion,
            blurBehind: d.blurBehind,
            overlaySize: d.overlaySize,
          ),
        ),
      ),
      left: [
        SettingsGroup(
          title: context.l10n.theme,
          children: [
            SettingRow(
              title: context.l10n.app,
              trailing: SegmentedControl<AppThemeMode>(
                width: 236,
                segments: [
                  Segment(AppThemeMode.dark, context.l10n.themeDark, icon: SottoIcons.moon),
                  Segment(AppThemeMode.light, context.l10n.themeLight, icon: SottoIcons.sun),
                  Segment(AppThemeMode.auto, context.l10n.themeAuto, icon: SottoIcons.auto),
                ],
                value: s.appTheme,
                onChanged: (v) => n.update((x) => x.copyWith(appTheme: v)),
              ),
            ),
            SettingRow(
              title: context.l10n.groupOverlay,
              subtitle: context.l10n.overlayThemeSub,
              trailing: SegmentedControl<OverlayThemeMode>(
                width: 236,
                segments: [
                  Segment(OverlayThemeMode.dark, context.l10n.themeDark),
                  Segment(OverlayThemeMode.light, context.l10n.themeLight),
                  Segment(OverlayThemeMode.matchApp, context.l10n.matchApp),
                ],
                value: s.overlayTheme,
                onChanged: (v) => n.update((x) => x.copyWith(overlayTheme: v)),
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: context.l10n.readability,
          children: [
            SettingRow(
              title: context.l10n.textSize,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${fontPx.round()}  px',
                    style: TypeScale.mono.copyWith(color: p.inkTertiary, fontWeight: FontWeight.w400),
                  ),
                  const SizedBox(width: 10),
                  SegmentedControl<ReadingSize>(
                    width: 180,
                    segments: [for (final r in ReadingSize.values) Segment(r, r.label)],
                    value: s.readingSize,
                    onChanged: (v) => n.update((x) => x.copyWith(readingSize: v)),
                  ),
                ],
              ),
            ),
            SettingRow(
              title: context.l10n.linesShown,
              subtitle: context.l10n.linesShownSub,
              trailing: SegmentedControl<int>(
                width: 180,
                segments: const [Segment(3, '3'), Segment(5, '5'), Segment(7, '7')],
                value: s.linesShown,
                onChanged: (v) => n.update((x) => x.copyWith(linesShown: v)),
              ),
            ),
            SettingRow(
              title: context.l10n.opacity,
              subtitle: context.l10n.opacitySub,
              trailing: SottoSlider(
                value: s.overlayOpacity,
                min: 0.5,
                max: 1,
                divisions: 50,
                marker: 0.7,
                label: NumberFormat.percentPattern(context.l10n.localeName).format(s.overlayOpacity),
                onChanged: (v) => n.update((x) => x.copyWith(overlayOpacity: v)),
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: context.l10n.placement,
          children: [
            SettingRow(
              title: context.l10n.position,
              subtitle: context.l10n.positionSub,
              trailing: _PlacementPicker(
                value: s.placement,
                onChanged: (v) => n.update((x) => x.copyWith(placement: v, overlayPositions: const {})),
              ),
            ),
            SettingRow(
              title: context.l10n.layout,
              subtitle: context.l10n.layoutSub,
              trailing: SegmentedControl<OverlayLayout>(
                width: 258,
                segments: [
                  Segment(OverlayLayout.auto, context.l10n.layoutAuto),
                  Segment(OverlayLayout.ticker, context.l10n.layoutTicker),
                  Segment(OverlayLayout.column, context.l10n.layoutColumn),
                  Segment(OverlayLayout.rail, context.l10n.layoutRail),
                ],
                value: s.layout == OverlayLayout.standard || s.layout == OverlayLayout.compact
                    ? OverlayLayout.auto
                    : s.layout,
                onChanged: (v) => n.update((x) => x.copyWith(layout: v)),
              ),
            ),
            SettingRow(
              title: context.l10n.rememberPosition,
              trailing: SottoToggle(
                value: s.rememberPositionPerDisplay,
                onChanged: (v) => n.update((x) => x.copyWith(rememberPositionPerDisplay: v)),
              ),
            ),
          ],
        ),
      ],
      right: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(context.l10n.preview, style: TypeScale.bodyStrong.copyWith(color: p.inkSecondary)),
                const Spacer(),
                SegmentedControl<PreviewBackground>(
                  segments: [
                    Segment(PreviewBackground.darkSlide, context.l10n.bgDarkSlide),
                    Segment(PreviewBackground.lightSlide, context.l10n.bgLightSlide),
                    Segment(PreviewBackground.videoCall, context.l10n.bgVideoCall),
                  ],
                  value: _bg,
                  onChanged: (v) => setState(() => _bg = v),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              height: 380,
              decoration: BoxDecoration(
                borderRadius: Radii.rL,
                border: Border.all(color: p.hairline),
              ),
              child: script == null
                  ? Center(
                      child: Text(
                        context.l10n.writeToPreview,
                        style: TypeScale.body.copyWith(color: p.inkTertiary),
                      ),
                    )
                  : OverlayPreview(
                      script: script,
                      beat: math.min(2, script.beatCount - 1),
                      spokenWords: 3,
                      layout: switch (s.layout) {
                        OverlayLayout.ticker => ResolvedLayout.ticker,
                        OverlayLayout.column => ResolvedLayout.column,
                        _ => ResolvedLayout.standard,
                      },
                      background: _bg,
                    ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    value: '${worstContrast(o, o.readNow).toStringAsFixed(1)}:1',
                    label: context.l10n.metricCurrentLine,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Metric(
                    value: '${worstContrast(o, o.readNext).toStringAsFixed(1)}:1',
                    label: context.l10n.metricNextLine,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Metric(value: '$chars ch', label: context.l10n.metricLineLength),
                ),
              ],
            ),
          ],
        ),
        SettingsGroup(
          title: context.l10n.motion,
          children: [
            SettingRow(
              title: context.l10n.scrolling,
              subtitle: context.l10n.scrollingSub,
              trailing: SegmentedControl<ScrollStyle>(
                width: 160,
                segments: [Segment(ScrollStyle.glide, context.l10n.scrollGlide), Segment(ScrollStyle.step, context.l10n.scrollStep)],
                value: s.scrollStyle,
                onChanged: (v) => n.update((x) => x.copyWith(scrollStyle: v)),
              ),
            ),
            SettingRow(
              title: context.l10n.reduceMotion,
              subtitle: context.l10n.reduceMotionSub,
              trailing: SottoToggle(
                value: s.reduceMotion,
                onChanged: (v) => n.update((x) => x.copyWith(reduceMotion: v)),
              ),
            ),
            SettingRow(
              title: context.l10n.blurBehind,
              subtitle: context.l10n.blurBehindSub,
              trailing: SottoToggle(
                value: s.blurBehind,
                onChanged: (v) => n.update((x) => x.copyWith(blurBehind: v)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: Radii.rM,
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: TypeScale.mono.copyWith(fontSize: 15, color: p.inkPrimary)),
          const SizedBox(height: 2),
          Text(label, style: TypeScale.caption.copyWith(color: p.inkTertiary, fontSize: 11)),
        ],
      ),
    );
  }
}

/// A screen with a camera notch and nine positions.
class _PlacementPicker extends StatelessWidget {
  const _PlacementPicker({required this.value, required this.onChanged});
  final OverlayPlacement value;
  final ValueChanged<OverlayPlacement> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: 236,
      height: 168,
      decoration: BoxDecoration(
        color: p.ground,
        borderRadius: Radii.rM,
        border: Border.all(color: p.control),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                  color: p.emphasis,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(3)),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
            child: GridView.count(
              crossAxisCount: 3,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.5,
              children: [
                for (final pl in OverlayPlacement.values)
                  Interactive(
                    onTap: () => onChanged(pl),
                    semanticLabel: pl.name,
                    builder: (context, st) => Center(
                      child: pl == value
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 56,
                                  height: 14,
                                  decoration: BoxDecoration(color: p.cueFill, borderRadius: BorderRadius.circular(4)),
                                ),
                                if (pl == OverlayPlacement.topCenter) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    context.l10n.placeUnderCamera,
                                    style: TypeScale.micro.copyWith(color: p.cueText, fontSize: 10),
                                  ),
                                ],
                              ],
                            )
                          : Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: st.hovered ? p.inkSecondary : p.emphasis),
                              ),
                            ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

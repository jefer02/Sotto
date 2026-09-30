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
import '../../live/overlay_palette.dart';
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
/// Text only: the glyph against its own outline, which is what the eye gets
/// on any slide.
double worstContrast(OverlayPalette o, double alpha) {
  if (o.textOnly) {
    final fg = Color.alphaBlend(o.ink.withValues(alpha: alpha), o.outline);
    final l1 = fg.computeLuminance(), l2 = o.outline.computeLuminance();
    return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
  }
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
    final o = overlayPaletteFor(s, dark: dark);
    final textOnly = s.overlayStyle == OverlayStyle.textOnly;
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
            overlayStyle: d.overlayStyle,
            textColor: d.textColor,
            autoOutline: true,
            outlineWidth: d.outlineWidth,
            shadowStrength: d.shadowStrength,
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
          title: context.l10n.overlayStyle,
          footer: textOnly ? context.l10n.overlayStyleTextOnlyFooter : null,
          children: [
            SettingRow(
              title: context.l10n.overlayStyle,
              subtitle: textOnly ? context.l10n.overlayStyleTextOnlySub : context.l10n.overlayStylePanelSub,
              trailing: SegmentedControl<OverlayStyle>(
                width: 220,
                segments: [
                  Segment(OverlayStyle.textOnly, context.l10n.overlayStyleTextOnly),
                  Segment(OverlayStyle.panel, context.l10n.overlayStylePanel),
                ],
                value: s.overlayStyle,
                onChanged: (v) => n.update((x) => x.copyWith(overlayStyle: v)),
              ),
            ),
            if (textOnly) ...[
              SettingRow(
                title: context.l10n.overlayTextColor,
                subtitle: switch (s.overlayTextColor) {
                  OverlayTextColor.auto => context.l10n.overlayTextColorAutoSub,
                  OverlayTextColor.custom => context.l10n.overlayTextColorCustomSub,
                  _ => context.l10n.overlayTextColorFixedSub,
                },
                trailing: SegmentedControl<OverlayTextColor>(
                  width: 360,
                  segments: [
                    Segment(OverlayTextColor.auto, context.l10n.overlayTextColorAuto),
                    Segment(OverlayTextColor.light, context.l10n.overlayTextColorLight),
                    Segment(OverlayTextColor.dark, context.l10n.overlayTextColorDark),
                    Segment(OverlayTextColor.custom, context.l10n.overlayTextColorCustom),
                  ],
                  value: s.overlayTextColor,
                  onChanged: (v) => n.update((x) => x.copyWith(overlayTextColor: v)),
                ),
              ),
            ],
            if (textOnly && s.overlayTextColor == OverlayTextColor.custom) ...[
              SettingRow(
                title: context.l10n.textColor,
                trailing: _Swatches(
                  colors: _textColors,
                  value: s.textColor,
                  onChanged: (v) => n.update((x) => x.copyWith(textColor: v)),
                ),
              ),
              SettingRow(
                title: context.l10n.outlineColor,
                subtitle: s.outlineColor == null ? context.l10n.outlineAutoSub : null,
                trailing: _Swatches(
                  colors: _outlineColors,
                  value: s.outlineColor,
                  autoLabel: context.l10n.outlineAuto,
                  onChanged: (v) =>
                      n.update((x) => v == null ? x.copyWith(autoOutline: true) : x.copyWith(outlineColor: v)),
                ),
              ),
            ],
            if (textOnly) ...[
              SettingRow(
                title: context.l10n.outlineWidth,
                trailing: SottoSlider(
                  value: s.outlineWidth,
                  min: 0,
                  max: 4,
                  divisions: 8,
                  label: '${NumberFormat('0.#', context.l10n.localeName).format(s.outlineWidth)} px',
                  onChanged: (v) => n.update((x) => x.copyWith(outlineWidth: v)),
                ),
              ),
              SettingRow(
                title: context.l10n.shadowStrength,
                trailing: SottoSlider(
                  value: s.shadowStrength,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  label: NumberFormat.percentPattern(context.l10n.localeName).format(s.shadowStrength),
                  onChanged: (v) => n.update((x) => x.copyWith(shadowStrength: v)),
                ),
              ),
            ],
          ],
        ),
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
            if (!textOnly)
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
              title: context.l10n.maxOverlayHeight,
              subtitle: context.l10n.maxOverlayHeightSub,
              trailing: SottoSlider(
                value: s.maxOverlayHeight,
                min: 0.2,
                max: 0.8,
                divisions: 12,
                label: NumberFormat.percentPattern(context.l10n.localeName).format(s.maxOverlayHeight),
                onChanged: (v) => n.update((x) => x.copyWith(maxOverlayHeight: v)),
              ),
            ),
            if (!textOnly)
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
                      child: Text(context.l10n.writeToPreview, style: TypeScale.body.copyWith(color: p.inkTertiary)),
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
                segments: [
                  Segment(ScrollStyle.glide, context.l10n.scrollGlide),
                  Segment(ScrollStyle.step, context.l10n.scrollStep),
                ],
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
            if (!textOnly)
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

const _textColors = [0xFFFFFFFF, 0xFFFFE55C, 0xFF8BE9FF, 0xFF111111];
const _outlineColors = [null, 0xFF000000, 0xFFFFFFFF];

/// A row of round color swatches. A null entry is "Auto".
class _Swatches extends StatelessWidget {
  const _Swatches({required this.colors, required this.value, required this.onChanged, this.autoLabel});
  final List<int?> colors;
  final int? value;
  final ValueChanged<int?> onChanged;
  final String? autoLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final c in colors)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Tooltip(
              message: c == null
                  ? (autoLabel ?? '')
                  : '#${(c & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
              child: Interactive(
                onTap: () => onChanged(c),
                builder: (context, s) => AnimatedContainer(
                  duration: Motion.quick,
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c == null ? p.raised : Color(c),
                    border: Border.all(
                      color: c == value ? p.cueFill : (s.hovered ? p.emphasis : p.control),
                      width: c == value ? 2 : 1,
                    ),
                  ),
                  child: c == null ? Text('A', style: TypeScale.captionStrong.copyWith(color: p.inkSecondary)) : null,
                ),
              ),
            ),
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

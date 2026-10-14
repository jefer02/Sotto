import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';

import '../design/icons.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../../data/models/qa_entry.dart';
import '../../data/models/script.dart';
import '../../l10n/l10n.dart';

// ───────────────────────────── Chips ─────────────────────────────

enum ChipTone { outline, neutral, confirmed, cue, capture }

/// Status chip: Draft · Structured · Rehearsed ×2 · Organizing… · Listening.
class StatusChip extends StatelessWidget {
  const StatusChip(
    this.label, {
    super.key,
    this.tone = ChipTone.neutral,
    this.icon,
    this.dot = false,
    this.mono = false,
  });

  final String label;
  final ChipTone tone;
  final SottoIcons? icon;
  final bool dot;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (Color bg, Color border, Color ink) = switch (tone) {
      ChipTone.outline => (Colors.transparent, p.control, p.inkTertiary),
      ChipTone.neutral => (p.raised, p.control, p.inkSecondary),
      ChipTone.confirmed => (p.confirmed.withValues(alpha: 0.12), Colors.transparent, p.confirmed),
      ChipTone.cue => (p.cueFill.withValues(alpha: 0.12), Colors.transparent, p.cueText),
      ChipTone.capture => (p.liveCapture.withValues(alpha: 0.12), Colors.transparent, p.liveCapture),
    };
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(shape: BoxShape.circle, color: ink),
            ),
            const SizedBox(width: 5),
          ],
          if (icon != null) ...[SottoIcon(icon!, size: 12, color: ink), const SizedBox(width: 5)],
          Text(
            label,
            style: (mono ? TypeScale.mono.copyWith(fontSize: 11) : TypeScale.micro).copyWith(color: ink, height: 1),
          ),
        ],
      ),
    );
  }

  static Widget forScript(BuildContext context, Script s) {
    final l = context.l10n;
    return switch (s.status) {
      ScriptStatus.organizing => StatusChip(l.statusOrganizing, tone: ChipTone.cue, icon: SottoIcons.structure),
      _ when s.rehearsalCount > 1 => StatusChip(
        l.statusRehearsedTimes(s.rehearsalCount),
        tone: ChipTone.confirmed,
        icon: SottoIcons.check,
      ),
      _ when s.rehearsalCount == 1 => StatusChip(l.statusRehearsed, tone: ChipTone.confirmed, icon: SottoIcons.check),
      ScriptStatus.structured || ScriptStatus.ready => StatusChip(l.statusStructured, tone: ChipTone.cue, dot: true),
      ScriptStatus.draft => StatusChip(l.statusDraft, tone: ChipTone.outline),
    };
  }
}

/// `§3 Revenue & margin` / `Prep Carrier contracts.pdf`.
class SourceChip extends StatelessWidget {
  const SourceChip(this.source, {super.key, this.overlay = false});

  final SourceRef source;
  final bool overlay;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final o = context.overlayPalette;
    final ink = overlay ? o.inkAt(0.7) : p.inkSecondary;
    final code = overlay ? o.cue : p.cueText;
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: overlay ? o.inkAt(0.06) : Colors.transparent,
        borderRadius: Radii.rS,
        border: Border.all(color: overlay ? o.inkAt(0.10) : p.control),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (source.code != null) ...[
            Text(source.code!, style: TypeScale.mono.copyWith(fontSize: 11, color: code, height: 1)),
            const SizedBox(width: 6),
          ] else if (source.kind == SourceKind.general) ...[
            SottoIcon(SottoIcons.globe, size: 11, color: code),
            const SizedBox(width: 6),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              source.label,
              overflow: TextOverflow.ellipsis,
              style: TypeScale.micro.copyWith(color: ink, height: 1),
            ),
          ),
        ],
      ),
    );
  }
}

/// Stage cue: mono caps in a cue outline — impossible to read aloud by
/// accident.
class CueChip extends StatelessWidget {
  const CueChip(this.cue, {super.key, this.color, this.dimmed = false});

  final Cue cue;
  final Color? color;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.palette.cueText;
    final icon = switch (cue.type) {
      CueType.slide => SottoIcons.slide,
      CueType.pause => SottoIcons.pause,
      CueType.demo => SottoIcons.display,
      CueType.note => SottoIcons.info,
    };
    return Opacity(
      opacity: dimmed ? 0.7 : 1,
      child: Container(
        height: 20,
        padding: const EdgeInsets.fromLTRB(5, 0, 6, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: c.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SottoIcon(icon, size: 12, color: c),
            const SizedBox(width: 4),
            Text(cue.display, style: TypeScale.mono.copyWith(fontSize: 11, color: c, letterSpacing: 0.44, height: 1)),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── Section chrome ─────────────────────────────

/// "Inputs ─────────" : a label followed by a hairline.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.title, {super.key, this.trailing, this.muted = false});

  final String title;
  final Widget? trailing;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        Text(
          title,
          style: (muted ? TypeScale.bodyStrong : TypeScale.title3.copyWith(fontSize: 13)).copyWith(
            color: muted ? p.inkSecondary : p.inkPrimary,
          ),
        ),
        if (trailing == null) ...[
          const SizedBox(width: 12),
          Expanded(child: Container(height: 1, color: p.hairline)),
        ] else ...[
          const Spacer(),
          trailing!,
        ],
      ],
    );
  }
}

/// A quiet section label: small, grey, a touch of tracking — hierarchy
/// from weight and color, not decoration. [live] leads it with the cue
/// lamp, kept for what is happening now or next ("Up next", live states).
class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key, this.color, this.live = false, this.rule = false});

  final String title;
  final Color? color;
  final bool live;

  /// A hairline after the label, to the end of the row.
  final bool rule;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: withWeight(TypeScale.caption, 600).copyWith(color: color ?? p.inkSecondary, letterSpacing: 0.24),
    );
    return Row(
      mainAxisSize: rule ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (live) ...[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.primary,
              boxShadow: [BoxShadow(color: p.primary.withValues(alpha: 0.5), blurRadius: 6)],
            ),
          ),
          const SizedBox(width: 9),
        ],
        if (rule) ...[
          Flexible(child: text),
          const SizedBox(width: 12),
          Expanded(child: Container(height: 1, color: p.hairline)),
        ] else
          Flexible(child: text),
      ],
    );
  }
}

/// A grouped card of rows separated by hairlines (Settings).
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children, this.title, this.footer});

  final String? title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) Padding(padding: const EdgeInsets.only(left: 2, bottom: 8), child: SectionHeading(title!)),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [p.cardTop, p.cardBottom],
            ),
            borderRadius: Radii.rL,
            border: Border.all(color: p.cardEdge),
          ),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) Divider(height: 1, thickness: 1, color: p.hairline),
                children[i],
              ],
            ],
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.only(left: 2, top: 10),
            child: Text(footer!, style: TypeScale.caption.copyWith(color: p.inkTertiary)),
          ),
      ],
    );
  }
}

/// A setting: its title and description, and the control beside them —
/// or under them at full width when the control is too wide to leave the
/// text [SettingRowLayout.minLabel] (a four-way segmented control in a
/// narrow column).
class SettingRow extends StatelessWidget {
  const SettingRow({super.key, required this.title, this.subtitle, this.trailing, this.below, this.leading});

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? below;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final label = Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 10)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TypeScale.bodyStrong.copyWith(color: p.inkPrimary)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: TypeScale.caption.copyWith(color: p.inkTertiary, height: 1.4)),
              ],
            ],
          ),
        ),
      ],
    );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: subtitle == null ? 13 : 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (trailing == null) label else SettingRowLayout(label: label, trailing: trailing!),
          if (below != null) ...[const SizedBox(height: 10), below!],
        ],
      ),
    );
  }
}

/// [label] and [trailing] side by side while the label keeps at least
/// [minLabel]; otherwise [trailing] goes under it, as wide as the row.
class SettingRowLayout extends MultiChildRenderObjectWidget {
  SettingRowLayout({super.key, required Widget label, required Widget trailing}) : super(children: [label, trailing]);

  /// The narrowest the title and description get beside a control.
  static const minLabel = 240.0;
  static const gap = 16.0;
  static const stackGap = 10.0;

  @override
  RenderSettingRow createRenderObject(BuildContext context) => RenderSettingRow();
}

class _SettingRowData extends ContainerBoxParentData<RenderBox> {}

class RenderSettingRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SettingRowData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SettingRowData> {
  /// The control went under the label.
  bool get stacked => _stacked;
  bool _stacked = false;

  RenderBox get _label => firstChild!;
  RenderBox get _trailing => lastChild!;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SettingRowData) child.parentData = _SettingRowData();
  }

  static bool _fits(double width, double trailing) =>
      !width.isFinite || width - trailing - SettingRowLayout.gap >= SettingRowLayout.minLabel;

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    _trailing.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
    final tw = _trailing.size.width;
    _stacked = !_fits(width, tw);
    final labelData = _label.parentData! as _SettingRowData;
    final trailingData = _trailing.parentData! as _SettingRowData;
    if (!_stacked) {
      final lw = width.isFinite ? width - tw - SettingRowLayout.gap : _label.getMaxIntrinsicWidth(double.infinity);
      _label.layout(BoxConstraints.tightFor(width: lw), parentUsesSize: true);
      final h = math.max(_label.size.height, _trailing.size.height);
      labelData.offset = Offset(0, (h - _label.size.height) / 2);
      trailingData.offset = Offset(lw + SettingRowLayout.gap, (h - _trailing.size.height) / 2);
      size = constraints.constrain(Size(lw + SettingRowLayout.gap + tw, h));
      return;
    }
    _label.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
    _trailing.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
    labelData.offset = Offset.zero;
    trailingData.offset = Offset(0, _label.size.height + SettingRowLayout.stackGap);
    size = constraints.constrain(Size(width, _label.size.height + SettingRowLayout.stackGap + _trailing.size.height));
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      math.max(_label.getMinIntrinsicWidth(height), _trailing.getMinIntrinsicWidth(height));

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _label.getMaxIntrinsicWidth(height) + SettingRowLayout.gap + _trailing.getMaxIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) => computeMaxIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) {
    final tw = _trailing.getMaxIntrinsicWidth(double.infinity);
    if (_fits(width, tw)) {
      final lw = width.isFinite ? width - tw - SettingRowLayout.gap : double.infinity;
      return math.max(_label.getMaxIntrinsicHeight(lw), _trailing.getMaxIntrinsicHeight(tw));
    }
    return _label.getMaxIntrinsicHeight(width) + SettingRowLayout.stackGap + _trailing.getMaxIntrinsicHeight(width);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final width = constraints.maxWidth;
    final t = _trailing.getDryLayout(BoxConstraints(maxWidth: width));
    if (_fits(width, t.width)) {
      final lw = width.isFinite ? width - t.width - SettingRowLayout.gap : _label.getMaxIntrinsicWidth(double.infinity);
      final l = _label.getDryLayout(BoxConstraints.tightFor(width: lw));
      return constraints.constrain(Size(lw + SettingRowLayout.gap + t.width, math.max(l.height, t.height)));
    }
    final l = _label.getDryLayout(BoxConstraints.tightFor(width: width));
    final s = _trailing.getDryLayout(BoxConstraints.tightFor(width: width));
    return constraints.constrain(Size(width, l.height + SettingRowLayout.stackGap + s.height));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);
}

// ───────────────────────────── Meters ─────────────────────────────

/// A row of section segments sized by duration; the current one can glow.
class SectionBar extends StatelessWidget {
  const SectionBar({
    super.key,
    required this.weights,
    this.labels,
    this.highlight,
    this.progressColor,
    this.trackColor,
    this.filled = 0,
    this.height = 3,
    this.gap = 3,
  });

  final List<double> weights;
  final List<String>? labels;
  final int? highlight;
  final Color? progressColor;

  /// Unplayed segments; defaults to the cue track.
  final Color? trackColor;

  /// Segments before this index draw as done.
  final int filled;
  final double height;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final total = weights.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < weights.length; i++)
          Expanded(
            flex: (weights[i] / total * 1000).round().clamp(1, 1000),
            child: Padding(
              padding: EdgeInsets.only(right: i == weights.length - 1 ? 0 : gap),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: height,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(height),
                      color: i == highlight
                          ? (progressColor ?? p.cueFill)
                          : i < filled
                          ? p.inkTertiary
                          : (trackColor ?? p.primaryTrack),
                    ),
                  ),
                  if (labels != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      labels![i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TypeScale.caption.copyWith(color: p.inkTertiary, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Input level bars — green zone in the middle, like the voice settings.
class LevelMeter extends StatelessWidget {
  const LevelMeter({super.key, required this.level, this.bars = 14, this.color});

  final double level;
  final int bars;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final lit = (level * bars).round();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < bars; i++)
          Container(
            width: 3,
            height: 5.0 + (i % 5 == 2 ? 7 : (i % 3) * 2 + 4),
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(1),
              color: i < lit ? (color ?? p.confirmed) : p.control,
            ),
          ),
      ],
    );
  }
}

// ───────────────────────────── Script text ─────────────────────────────

/// Phrase-aware wrapping: glue a number to its unit and a verb to its
/// object with non-breaking spaces, so "$48.2 million" never splits.
String phraseGlue(String text) {
  const nbsp = ' ';
  return text
      .replaceAllMapped(
        RegExp(
          r'([$€£]?\d[\d.,]*%?)\s+(million|billion|thousand|percent|pts|points|millones|millón|mil|puntos|x|k|M|B|bn|per)\b',
          caseSensitive: false,
        ),
        (m) => '${m[1]}$nbsp${m[2]}',
      )
      .replaceAllMapped(RegExp(r'\s+([—–])\s+'), (m) => '$nbsp${m[1]} ')
      .replaceAllMapped(RegExp(r'\b(on|in|at|of|to|by)\s+([A-Z]?\d[\w.%]*)'), (m) => '${m[1]}$nbsp${m[2]}');
}

/// Parses `**bold**` spans. Returns (text, isBold) runs.
List<(String, bool)> emphasisRuns(String text) {
  final runs = <(String, bool)>[];
  final parts = text.split('**');
  for (var i = 0; i < parts.length; i++) {
    if (parts[i].isNotEmpty) runs.add((parts[i], i.isOdd));
  }
  return runs;
}

/// Script text with emphasis rendered bold.
class ScriptText extends StatelessWidget {
  const ScriptText(this.text, {super.key, required this.style, this.boldColor, this.glue = true, this.maxLines});

  final String text;
  final TextStyle style;
  final Color? boldColor;
  final bool glue;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final source = glue ? phraseGlue(text) : text;
    return Text.rich(
      TextSpan(
        children: [
          for (final (t, bold) in emphasisRuns(source))
            TextSpan(
              text: t,
              style: bold ? withWeight(style, 700).copyWith(color: boldColor) : style,
            ),
        ],
      ),
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}

// ───────────────────────────── Surfaces ─────────────────────────────

/// Sidebar surface: the panel, warmed at the top where the brand sits.
BoxDecoration sidebarDecoration(SottoPalette p) => BoxDecoration(
  color: p.panel,
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color.alphaBlend(p.primary.withValues(alpha: p.isDark ? 0.11 : 0.10), p.panel),
      p.panel,
    ],
    stops: const [0, 0.45],
  ),
  border: Border(right: BorderSide(color: p.hairline)),
);

/// e1 · card — hairline-bordered, radius 12, lit from above; on hover the
/// edge catches the cue light.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.hovered = false,
    this.accent,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final bool hovered;

  /// A collection's color: a fading line along the top edge, a faint tint,
  /// and the hover glow. Defaults to cue for the glow only.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final glow = accent ?? p.primary;
    final lift = hovered && p.isDark ? 0.35 : 0.0;
    final base = color ?? Color.lerp(p.cardBottom, p.float, lift)!;
    // Top edge a step lighter than the bottom: the light comes from above.
    final top = color ?? Color.lerp(p.cardTop, p.control, lift)!;
    // A collection owns the top of its card: its color pools there and fades
    // out before the text, so the card reads as that collection at a glance.
    final tinted = accent != null && color == null;
    final wash = tinted
        ? Color.alphaBlend(accent!.withValues(alpha: (p.isDark ? 0.16 : 0.11) + (hovered ? 0.05 : 0)), top)
        : top;
    final card = AnimatedContainer(
      duration: Motion.quick,
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [wash, top, base],
          stops: [0, tinted ? 0.55 : 0.0, 1],
        ),
        borderRadius: Radii.rL,
        border: Border.all(color: hovered ? glow.withValues(alpha: 0.6) : p.cardEdge),
        boxShadow: [
          if (hovered) BoxShadow(color: glow.withValues(alpha: p.isDark ? 0.22 : 0.22), blurRadius: 28),
          BoxShadow(
            color: Color(p.isDark ? 0x66000000 : 0x141C1916),
            offset: const Offset(0, 6),
            blurRadius: 16,
            spreadRadius: -8,
          ),
        ],
      ),
      child: child,
    );
    if (accent == null) return card;
    return Stack(
      children: [
        card,
        Positioned(
          top: 0,
          left: 12,
          right: 12,
          child: IgnorePointer(
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(1),
                gradient: LinearGradient(
                  colors: [
                    accent!,
                    accent!.withValues(alpha: hovered ? 0.7 : 0.45),
                    accent!.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.55, 1],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String formatClock(int seconds) {
  final neg = seconds < 0;
  final s = seconds.abs();
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  final body = h > 0
      ? '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}'
      : '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  return neg ? '−$body' : body;
}

String formatDuration(int seconds) {
  final m = seconds ~/ 60, s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

String formatMinutes(int seconds) => '${(seconds / 60).round()} min';

/// "Edited 2 h ago" / "Yesterday" / "Monday" / "Sep 12", in the active
/// language. With [edited] false, the recent forms read "2 h ago".
String relativeTime(DateTime t, {DateTime? now, bool edited = false}) {
  final l = L10n.current;
  final n = now ?? DateTime.now();
  final d = n.difference(t);
  if (d.inMinutes < 1) return l.timeJustNow;
  if (d.inMinutes < 60) return edited ? l.timeEditedMinutesAgo(d.inMinutes) : l.timeMinutesAgo(d.inMinutes);
  if (d.inHours < 24 && n.day == t.day) return edited ? l.timeEditedHoursAgo(d.inHours) : l.timeHoursAgo(d.inHours);
  final yesterday = n.subtract(const Duration(days: 1));
  if (t.year == yesterday.year && t.month == yesterday.month && t.day == yesterday.day) return l.timeYesterday;
  final day = d.inDays < 7 ? DateFormat.EEEE(l.localeName).format(t) : DateFormat.MMMd(l.localeName).format(t);
  return toBeginningOfSentenceCase(day);
}

/// "Sep 23 · 14:04" in the active language.
String shortDateTime(DateTime t) =>
    '${DateFormat.MMMd(L10n.current.localeName).format(t)} · ${DateFormat.Hm().format(t)}';

/// "3:00 PM" / "15:00" as the active language writes it.
String clockTime(DateTime t) => DateFormat.jm(L10n.current.localeName).format(t);

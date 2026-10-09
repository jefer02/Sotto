import 'package:flutter/material.dart';
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

/// Stage cue: mono caps in a tungsten outline — impossible to read aloud by
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

/// Section heading led by a small tungsten dot — a lamp on the marker.
class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key, this.color});

  final String title;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
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
        Text(title, style: TypeScale.bodyStrong.copyWith(color: color ?? p.inkPrimary)),
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
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 10),
            child: SectionHeading(title!, color: p.inkSecondary),
          ),
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
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: subtitle == null ? 13 : 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
              if (trailing != null) ...[const SizedBox(width: 16), trailing!],
            ],
          ),
          if (below != null) ...[const SizedBox(height: 10), below!],
        ],
      ),
    );
  }
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

  /// Unplayed segments; defaults to the tungsten track.
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

/// The ghost light on a dark stage: a warm pool of light falling on the
/// content from above, so the ground isn't one flat sheet.
class StageGlow extends StatelessWidget {
  const StageGlow({super.key, required this.child, this.alignment = const Alignment(-0.35, -1.25)});

  final Widget child;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.ground,
        gradient: RadialGradient(
          center: alignment,
          radius: 1.15,
          colors: [p.stageGlow, p.stageGlow.withValues(alpha: 0)],
          stops: const [0, 1],
        ),
      ),
      child: child,
    );
  }
}

/// e1 · card — hairline-bordered, radius 12, lit from above; on hover the
/// edge catches the tungsten light.
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
  /// and the hover glow. Defaults to tungsten for the glow only.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final glow = accent ?? p.primary;
    final lift = hovered && p.isDark ? 0.35 : 0.0;
    final base = color ?? Color.lerp(p.cardBottom, p.float, lift)!;
    // Top edge a step lighter than the bottom: the light comes from above.
    var top = color ?? Color.lerp(p.cardTop, p.control, lift)!;
    if (accent != null && color == null) top = Color.alphaBlend(accent!.withValues(alpha: p.isDark ? 0.07 : 0.06), top);
    final card = AnimatedContainer(
      duration: Motion.quick,
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, base]),
        borderRadius: Radii.rL,
        border: Border.all(color: hovered ? glow.withValues(alpha: 0.42) : p.cardEdge),
        boxShadow: [
          if (hovered) BoxShadow(color: glow.withValues(alpha: p.isDark ? 0.12 : 0.18), blurRadius: 24),
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
                    accent!.withValues(alpha: hovered ? 0.5 : 0.15),
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

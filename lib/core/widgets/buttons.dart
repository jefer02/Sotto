import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../../data/models/shortcut.dart';
import '../platform/platform_keys.dart';
import 'interactive.dart';
import 'keycap.dart';
import 'motion_effects.dart';

enum ButtonVariant { primary, secondary, ghost, overlay }

enum ButtonSize {
  small(26, 12),
  medium(30, 13),
  large(36, 14);

  const ButtonSize(this.height, this.fontSize);
  final double height;
  final double fontSize;
}

/// Controls sit at 26–36 px, the density of a desktop tool. Secondary and
/// overlay buttons carry their keycap so the mouse stays optional; a
/// primary button keeps its face clean and names the shortcut in its
/// tooltip instead.
class SottoButton extends StatelessWidget {
  const SottoButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = ButtonVariant.secondary,
    this.size = ButtonSize.medium,
    this.shortcut,
    this.shortcutText,
    this.expand = false,
    this.tone,
  });

  const SottoButton.primary({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.size = ButtonSize.medium,
    this.shortcut,
    this.shortcutText,
    this.expand = false,
  }) : variant = ButtonVariant.primary,
       tone = null;

  const SottoButton.ghost({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.size = ButtonSize.medium,
    this.shortcut,
    this.shortcutText,
    this.expand = false,
    this.tone,
  }) : variant = ButtonVariant.ghost;

  final String label;
  final VoidCallback? onPressed;
  final SottoIcons? icon;
  final ButtonVariant variant;
  final ButtonSize size;
  final Shortcut? shortcut;

  /// Free-form keycap text, e.g. "⌘N" for main-window shortcuts.
  final String? shortcutText;
  final bool expand;

  /// Overrides the ink colour (used for destructive ghost actions).
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final o = context.overlayPalette;

    final keys = shortcut != null ? PlatformKeys.describe(shortcut!) : shortcutText;
    // The chip on a cue-filled face can't reach AA contrast; the tooltip can.
    final chipInTooltip = variant == ButtonVariant.primary && keys != null;
    final button = Interactive(
      onTap: onPressed,
      enabled: onPressed != null,
      semanticLabel: keys == null ? label : '$label, $keys',
      builder: (context, s) {
        final (Color bg, Color border, Color ink, List<BoxShadow> shadow) = switch (variant) {
          ButtonVariant.primary => (
            s.pressed
                ? p.cuePressed
                : s.hovered
                ? p.cueHover
                : p.cueFill,
            Colors.transparent,
            p.onPrimary,
            [
              const BoxShadow(color: Color(0x40000000), offset: Offset(0, 1), blurRadius: 2),
              // The lamp throws a little light around itself.
              BoxShadow(
                color: p.primary.withValues(alpha: s.hovered ? 0.50 : 0.32),
                offset: const Offset(0, 4),
                blurRadius: s.hovered ? 22 : 16,
                spreadRadius: -4,
              ),
            ],
          ),
          ButtonVariant.secondary => (
            s.pressed
                ? p.panel
                : s.hovered
                ? p.float
                : p.raised,
            s.hovered || s.pressed ? p.emphasis : p.control,
            p.inkPrimary,
            const <BoxShadow>[],
          ),
          ButtonVariant.ghost => (
            s.pressed
                ? p.pressWash
                : s.hovered
                ? p.hoverWash
                : Colors.transparent,
            Colors.transparent,
            tone ?? (s.hovered || s.pressed ? p.inkPrimary : p.inkSecondary),
            const <BoxShadow>[],
          ),
          ButtonVariant.overlay => (
            o.inkAt(s.pressed || s.hovered ? 0.11 : 0.06),
            o.inkAt(0.10),
            o.inkAt(0.86),
            const <BoxShadow>[],
          ),
        };

        final hasKey = keys != null && !chipInTooltip;
        final content = Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              SottoIcon(icon!, size: size == ButtonSize.large ? 16 : 14, color: ink),
              const SizedBox(width: 7),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: withWeight(TypeScale.body, 500).copyWith(fontSize: size.fontSize, height: 1, color: ink),
              ),
            ),
            if (hasKey) ...[
              const SizedBox(width: 8),
              _ShortcutHint(
                shortcut: shortcut,
                text: shortcutText,
                tone: variant == ButtonVariant.overlay ? KeycapTone.overlay : KeycapTone.main,
              ),
            ],
          ],
        );

        return PressScale(
          pressed: s.pressed,
          child: AnimatedContainer(
            duration: Motion.quick,
            height: size.height,
            padding: EdgeInsets.only(left: icon != null ? 10 : 12, right: hasKey ? 6 : 12),
            decoration: BoxDecoration(
              color: bg,
              // Primary: brighter at the top, deepening toward indigo at the base.
              gradient: variant == ButtonVariant.primary
                  ? LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color.lerp(bg, const Color(0xFFFFFFFF), 0.08)!, Color.lerp(bg, p.cueDeep, 0.35)!],
                    )
                  : null,
              borderRadius: Radii.rControl,
              border: Border.all(color: border),
              boxShadow: shadow,
            ),
            // inset 0 1px 0 rgba(255,255,255,.28) — the lit top edge.
            foregroundDecoration: variant == ButtonVariant.primary
                ? const BoxDecoration(
                    borderRadius: Radii.rControl,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment(0, -0.88),
                      colors: [Color(0x47FFFFFF), Color(0x00FFFFFF)],
                    ),
                  )
                : null,
            child: content,
          ),
        );
      },
    );
    if (!chipInTooltip) return button;
    return Tooltip(message: '$label · $keys', child: button);
  }
}

class _ShortcutHint extends StatelessWidget {
  const _ShortcutHint({this.shortcut, this.text, required this.tone});

  final Shortcut? shortcut;
  final String? text;
  final KeycapTone tone;

  @override
  Widget build(BuildContext context) {
    if (shortcut != null) {
      return KeyCombo(shortcut!, tone: tone, merged: true);
    }
    return Keycap(text!, tone: tone);
  }
}

/// 30 × 30 icon-only control. Icons never carry meaning alone — every
/// icon button has a tooltip with its shortcut.
class SottoIconButton extends StatelessWidget {
  const SottoIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.selected = false,
    this.size = 30,
    this.iconSize = 14,
    this.overlay = false,
    this.color,
  });

  final SottoIcons icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;
  final double size;
  final double iconSize;
  final bool overlay;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final o = context.overlayPalette;
    return Tooltip(
      message: tooltip,
      child: Interactive(
        onTap: onPressed,
        enabled: onPressed != null,
        semanticLabel: tooltip,
        builder: (context, s) {
          final Color bg;
          final Color ink;
          if (overlay) {
            bg = selected || s.pressed
                ? o.inkAt(0.14)
                : s.hovered
                ? o.inkAt(0.08)
                : Colors.transparent;
            ink = o.inkAt(selected || s.hovered ? 0.95 : 0.7);
          } else {
            bg = selected || s.pressed
                ? p.pressWash
                : s.hovered
                ? p.hoverWash
                : Colors.transparent;
            ink = color ?? (selected || s.hovered ? p.inkPrimary : p.inkSecondary);
          }
          return PressScale(
            pressed: s.pressed,
            scale: 0.94,
            child: AnimatedContainer(
              duration: Motion.quick,
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: bg, borderRadius: Radii.rControl),
              child: SottoIcon(icon, size: iconSize, color: ink),
            ),
          );
        },
      ),
    );
  }
}

/// Inline text link in cue ("Add", "Reset to defaults").
class TextLink extends StatelessWidget {
  const TextLink(this.label, {super.key, this.onTap, this.muted = false});

  final String label;
  final VoidCallback? onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Interactive(
      onTap: onTap,
      builder: (context, s) => Text(
        label,
        style: withWeight(
          TypeScale.body,
          500,
        ).copyWith(color: muted ? (s.hovered ? p.inkPrimary : p.inkSecondary) : (s.hovered ? p.cueHover : p.cueText)),
      ),
    );
  }
}

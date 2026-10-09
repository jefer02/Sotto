import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import 'interactive.dart';

/// Sidebar navigation row: 32 px, icon 16, label, optional count/hint.
class NavItem extends StatelessWidget {
  const NavItem({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
    this.trailing,
    this.collapsed = false,
    this.muted = false,
    this.iconColor,
  });

  final String label;
  final SottoIcons? icon;
  final bool selected;
  final VoidCallback? onTap;
  final String? trailing;
  final bool collapsed;
  final bool muted;

  /// Fixed icon color (a collection's own), kept even when selected.
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final item = Interactive(
      onTap: onTap,
      builder: (context, s) {
        final ink = selected ? p.inkPrimary : (s.hovered ? p.inkPrimary : (muted ? p.inkTertiary : p.inkSecondary));
        final iconInk = iconColor ?? (selected ? p.primaryText : ink);
        final row = AnimatedContainer(
          duration: Motion.quick,
          height: 32,
          padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 10),
          alignment: collapsed ? Alignment.center : null,
          decoration: BoxDecoration(
            color: selected ? p.primaryWash : (s.hovered ? p.hoverWash : Colors.transparent),
            borderRadius: Radii.rControl,
          ),
          child: collapsed
              ? SottoIcon(icon ?? SottoIcons.doc, size: 16, color: iconInk)
              : Row(
                  children: [
                    if (icon != null) ...[SottoIcon(icon!, size: 16, color: iconInk), const SizedBox(width: 10)],
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: (selected ? TypeScale.bodyStrong : TypeScale.body).copyWith(color: ink),
                      ),
                    ),
                    if (trailing != null) Text(trailing!, style: TypeScale.caption.copyWith(color: p.inkTertiary)),
                  ],
                ),
        );
        if (!selected || collapsed) return row;
        // A tungsten tick marks where you are, like the cue column on stage.
        return Stack(
          children: [
            row,
            Positioned(
              left: 0,
              top: 8,
              bottom: 8,
              child: Container(
                width: 3,
                decoration: BoxDecoration(color: p.primary, borderRadius: BorderRadius.circular(2)),
              ),
            ),
          ],
        );
      },
    );
    return collapsed ? Tooltip(message: label, child: item) : item;
  }
}

class NavHeading extends StatelessWidget {
  const NavHeading(this.label, {super.key, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 18, 6, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TypeScale.bodyStrong.copyWith(color: p.inkSecondary)),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// "‹ Library" / "‹ Back to library".
class BackLink extends StatelessWidget {
  const BackLink({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Interactive(
      onTap: onTap,
      builder: (context, s) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '‹  ',
              style: TypeScale.body.copyWith(color: s.hovered ? p.inkPrimary : p.inkTertiary, fontSize: 15, height: 1),
            ),
            Text(label, style: TypeScale.body.copyWith(color: s.hovered ? p.inkPrimary : p.inkSecondary)),
          ],
        ),
      ),
    );
  }
}

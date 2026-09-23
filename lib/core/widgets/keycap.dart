import 'package:flutter/material.dart';

import '../design/theme.dart';
import '../design/typography.dart';
import '../platform/platform_keys.dart';
import '../../data/models/shortcut.dart';

enum KeycapTone { main, onCue, overlay }

/// A single key, drawn like the component sheet: mono 11, 18 px square-ish,
/// hairline border with a 1 px inner bottom edge.
class Keycap extends StatelessWidget {
  const Keycap(this.label, {super.key, this.tone = KeycapTone.main, this.compact = false});

  final String label;
  final KeycapTone tone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final o = context.overlayPalette;
    final (Color bg, Color border, Color ink) = switch (tone) {
      KeycapTone.main => (p.float, p.control, p.inkSecondary),
      KeycapTone.onCue => (
        p.onCue.withValues(alpha: 0.12),
        p.onCue.withValues(alpha: 0.18),
        p.onCue.withValues(alpha: 0.7),
      ),
      KeycapTone.overlay => (o.inkAt(0.08), o.inkAt(0.12), o.inkAt(0.62)),
    };
    final size = compact ? 16.0 : 18.0;
    return Container(
      constraints: BoxConstraints(minWidth: size, minHeight: size, maxHeight: size),
      padding: EdgeInsets.symmetric(horizontal: label.length > 1 ? 5 : 0),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: border),
        boxShadow: [BoxShadow(color: border, offset: const Offset(0, 1), blurRadius: 0)],
      ),
      child: Text(
        label,
        style: TypeScale.keycap.copyWith(color: ink, fontSize: compact ? 10 : 11),
      ),
    );
  }
}

/// A full shortcut rendered as separate keycaps (⌃ ⌥ Q).
class KeyCombo extends StatelessWidget {
  const KeyCombo(this.shortcut, {super.key, this.tone = KeycapTone.main, this.merged = false});

  final Shortcut shortcut;
  final KeycapTone tone;

  /// Merged draws the whole chord inside one cap (⌃⌥Q), as the overlay does.
  final bool merged;

  @override
  Widget build(BuildContext context) {
    final parts = PlatformKeys.symbolsFor(shortcut);
    if (merged) {
      return Keycap(PlatformKeys.describe(shortcut), tone: tone, compact: tone == KeycapTone.overlay);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < parts.length; i++) ...[if (i > 0) const SizedBox(width: 3), Keycap(parts[i], tone: tone)],
      ],
    );
  }
}

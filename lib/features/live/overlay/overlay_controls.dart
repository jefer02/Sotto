import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../l10n/l10n.dart';

import '../../../core/design/icons.dart';
import '../../../core/design/theme.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/typography.dart';
import '../../../data/models/settings.dart';
import '../../../data/repositories.dart';
import '../live_controller.dart';
import '../live_state.dart';
import '../../chat/chat_controller.dart';
import '../../forms/autofill_controller.dart';

/// The hover panel: shown while the pointer is over the overlay (never in
/// click-through), faded out 2 s after it leaves. No shortcut opens it.
///
/// Every button fires on pointer-down, not on click, so pressing one never
/// needs the overlay to take focus from the slides — except End session,
/// which needs a one-second hold.
class OverlayControls extends ConsumerWidget {
  const OverlayControls({super.key, required this.state, required this.onEnd});

  final LiveState state;
  final VoidCallback onEnd;

  /// Text color cycle: Auto → Always light → Always dark (Custom → Auto).
  static OverlayTextColor nextTextColor(OverlayTextColor c) => switch (c) {
    OverlayTextColor.auto => OverlayTextColor.light,
    OverlayTextColor.light => OverlayTextColor.dark,
    OverlayTextColor.dark || OverlayTextColor.custom => OverlayTextColor.auto,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final o = context.overlayPalette;
    final c = ref.read(liveControllerProvider.notifier);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final settings = ref.watch(settingsProvider);
    final chatOpen = ref.watch(chatControllerProvider.select((c) => c.overlayOpen));
    final autoFillOn = settings.formsEnabled && settings.formsAutoFill;
    final size = state.readingSize.index;
    final paused = state.phase == LivePhase.paused;

    final styleName = switch (settings.overlayStyle) {
      OverlayStyle.textOnly => l.overlayStyleTextOnly,
      OverlayStyle.panel => l.overlayStylePanel,
    };
    final colorName = switch (settings.overlayTextColor) {
      OverlayTextColor.auto => l.overlayTextColorAuto,
      OverlayTextColor.light => l.overlayTextColorLight,
      OverlayTextColor.dark => l.overlayTextColorDark,
      OverlayTextColor.custom => l.overlayTextColorCustom,
    };

    Widget divider() => Container(
      width: 1,
      height: 16,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: o.textOnly ? null : o.inkAt(0.12),
    );

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PanelButton(
          icon: SottoIcons.textSizeMinus,
          label: l.actionTextSmaller,
          onDown: size > 0 ? () => c.textSize(-1) : null,
        ),
        _PanelButton(
          icon: SottoIcons.textSizePlus,
          label: l.actionTextBigger,
          onDown: size < ReadingSize.values.length - 1 ? () => c.textSize(1) : null,
        ),
        divider(),
        _PanelButton(icon: SottoIcons.up, label: l.actionPrevBeat, onDown: c.previousBeat),
        _PanelButton(
          icon: paused ? SottoIcons.play : SottoIcons.pause,
          label: paused ? l.resume : l.pause,
          onDown: c.togglePause,
        ),
        _PanelButton(icon: SottoIcons.down, label: l.actionNextBeat, onDown: c.nextBeat),
        // Same as prefix + Q: down starts (or, in toggle mode, finishes) the
        // capture; up finishes it in hold mode.
        _PanelButton(
          icon: SottoIcons.ask,
          label: l.actionAsk,
          selected: state.phase == LivePhase.listening,
          onDown: c.askDown,
          onUp: c.askUp,
        ),
        divider(),
        _PanelButton(
          icon: SottoIcons.layers,
          label: l.hoverOverlayStyle(styleName),
          onDown: () => settingsNotifier.update(
            (s) => s.copyWith(
              overlayStyle: s.overlayStyle == OverlayStyle.textOnly ? OverlayStyle.panel : OverlayStyle.textOnly,
            ),
          ),
        ),
        _PanelButton(
          icon: switch (settings.overlayTextColor) {
            OverlayTextColor.light => SottoIcons.sun,
            OverlayTextColor.dark => SottoIcons.moon,
            _ => SottoIcons.auto,
          },
          label: l.hoverTextColor(colorName),
          onDown: () => settingsNotifier.update((s) => s.copyWith(overlayTextColor: nextTextColor(s.overlayTextColor))),
        ),
        divider(),
        _PanelButton(
          icon: SottoIcons.form,
          label: autoFillOn ? l.hoverAutoFillOn : l.hoverAutoFillOff,
          dot: autoFillOn ? o.confirmed : o.inkAt(0.4),
          onDown: () => ref.read(autoFillControllerProvider.notifier).setEnabled(!autoFillOn),
        ),
        if (settings.showChat || chatOpen)
          _PanelButton(
            icon: SottoIcons.chat,
            label: chatOpen ? l.hoverCloseChat : l.hoverOpenChat,
            selected: chatOpen,
            onDown: ref.read(chatControllerProvider.notifier).toggleOverlay,
          ),
        _PanelButton(icon: SottoIcons.display, label: l.actionMoveDisplay, onDown: () => c.moveDisplay()),
        divider(),
        _PanelButton(icon: SottoIcons.close, label: l.hoverEndSessionHold, onDown: onEnd, hold: true),
      ],
    );

    // Text only: the icons carry their own outline and shadow, no card.
    if (o.textOnly) return Padding(padding: const EdgeInsets.all(3), child: row);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Color.alphaBlend(o.inkAt(0.06), o.ground.withValues(alpha: 0.82)),
        borderRadius: Radii.rM,
        border: Border.all(color: o.inkAt(0.1)),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: row,
    );
  }
}

class _PanelButton extends StatefulWidget {
  const _PanelButton({
    required this.icon,
    required this.label,
    this.onDown,
    this.onUp,
    this.selected = false,
    this.dot,
    this.hold = false,
  });

  final SottoIcons icon;
  final String label;

  /// Fires on pointer-down — or, with [hold], once the pointer has stayed
  /// down on the button for [_PanelButtonState.holdTime].
  final VoidCallback? onDown;

  /// Fires when the pointer comes back up (not for [hold] buttons).
  final VoidCallback? onUp;
  final bool selected;

  /// Hold-to-confirm: a ring fills while held; releasing or leaving the
  /// button early cancels.
  final bool hold;

  /// A status dot in the icon's corner (auto-fill).
  final Color? dot;

  @override
  State<_PanelButton> createState() => _PanelButtonState();
}

class _PanelButtonState extends State<_PanelButton> with SingleTickerProviderStateMixin {
  static const _size = 30.0;
  static const _iconSize = 16.0;
  static const holdTime = Duration(seconds: 1);

  bool _hovered = false;
  bool _pressed = false;

  late final AnimationController _holdProgress = AnimationController(vsync: this, duration: holdTime)
    ..addListener(() => setState(() {}))
    ..addStatusListener((s) {
      if (s != AnimationStatus.completed) return;
      _holdProgress.value = 0;
      _pressed = false;
      widget.onDown?.call();
    });

  @override
  void dispose() {
    _holdProgress.dispose();
    super.dispose();
  }

  void _down(PointerDownEvent e) {
    if (widget.onDown == null || e.buttons & kPrimaryButton == 0) return;
    setState(() => _pressed = true);
    if (widget.hold) {
      unawaited(_holdProgress.forward(from: 0));
    } else {
      widget.onDown!();
    }
  }

  void _release() {
    if (!_pressed) return;
    setState(() => _pressed = false);
    if (widget.hold) {
      _holdProgress.stop();
      _holdProgress.value = 0;
    } else {
      widget.onUp?.call();
    }
  }

  /// A held pointer that slides off the button cancels a hold.
  void _move(PointerMoveEvent e) {
    if (widget.hold && _pressed && !(Offset.zero & const Size.square(_size)).contains(e.localPosition)) _release();
  }

  @override
  Widget build(BuildContext context) {
    final o = context.overlayPalette;
    final enabled = widget.onDown != null;
    final active = enabled && (widget.selected || _hovered);
    final ink = o.inkAt(!enabled ? 0.3 : (active ? 0.98 : 0.75));
    final wash = o.textOnly
        ? Colors.transparent
        : (widget.selected || _pressed)
        ? o.inkAt(0.14)
        : (_hovered && enabled)
        ? o.inkAt(0.08)
        : Colors.transparent;

    Widget icon = _OutlinedIcon(icon: widget.icon, color: ink, size: _iconSize, pressed: _pressed);
    if (_holdProgress.value > 0) {
      icon = Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          icon,
          SizedBox.square(
            dimension: _size - 4,
            child: CircularProgressIndicator(
              value: _holdProgress.value,
              strokeWidth: 2,
              color: o.capture,
              backgroundColor: o.inkAt(0.15),
            ),
          ),
        ],
      );
    }
    if (widget.dot != null) {
      icon = Stack(
        clipBehavior: Clip.none,
        children: [
          icon,
          Positioned(
            right: -3,
            top: -2,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.dot,
                border: Border.all(color: o.textOnly ? o.outline : o.ground, width: 1),
              ),
            ),
          ),
        ],
      );
    }

    return Tooltip(
      message: widget.label,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: widget.label,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) {
            setState(() => _hovered = false);
            _release();
          },
          child: Listener(
            behavior: HitTestBehavior.opaque,
            // Down, not click: the overlay never has to become the focused
            // window for a button to work.
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: (_) => _release(),
            onPointerCancel: (_) => _release(),
            child: AnimatedContainer(
              duration: Motion.quick,
              width: _size,
              height: _size,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: wash, borderRadius: Radii.rControl),
              child: icon,
            ),
          ),
        ),
      ),
    );
  }
}

/// A design-system icon; in text-only style it gets the same outline and
/// soft shadow as the words, so it reads over any slide.
class _OutlinedIcon extends StatelessWidget {
  const _OutlinedIcon({required this.icon, required this.color, required this.size, this.pressed = false});

  final SottoIcons icon;
  final Color color;
  final double size;
  final bool pressed;

  @override
  Widget build(BuildContext context) {
    final o = context.overlayPalette;
    final glyph = SvgPicture.string(icon.svg(color), width: size, height: size);
    final scaled = AnimatedScale(scale: pressed ? 0.9 : 1, duration: Motion.quick, child: glyph);
    if (!o.textOnly) return SizedBox.square(dimension: size, child: scaled);

    // viewBox 16 at 16 px: one stroke unit is one pixel.
    final halo = 1.5 + 2 * o.outlineWidth.clamp(1.0, 2.5);
    final outline = SvgPicture.string(
      icon.svg(o.outline.withValues(alpha: o.outline.a * color.a), strokeWidth: halo),
      width: size,
      height: size,
    );
    final shadow = o.shadowStrength <= 0
        ? null
        : ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 1 + 3 * o.shadowStrength, sigmaY: 1 + 3 * o.shadowStrength),
            child: SvgPicture.string(
              icon.svg(o.shadowColor.withValues(alpha: 0.9 * o.shadowStrength * color.a), strokeWidth: halo + 1),
              width: size,
              height: size,
            ),
          );
    return AnimatedScale(
      scale: pressed ? 0.9 : 1,
      duration: Motion.quick,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (shadow != null) Positioned(left: 0, top: 1.5, width: size, height: size, child: shadow),
            outline,
            glyph,
          ],
        ),
      ),
    );
  }
}

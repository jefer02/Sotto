import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/theme.dart';
import '../design/tokens.dart';

/// Hover / pressed / focused state for custom controls, plus keyboard
/// activation (Enter / Space). Focus paints the cue ring, which is the
/// one place cue appears on every control.
class Interactive extends StatefulWidget {
  const Interactive({
    super.key,
    required this.builder,
    this.onTap,
    this.onLongPressStart,
    this.onLongPressEnd,
    this.enabled = true,
    this.focusRadius = Radii.rControl,
    this.cursor = SystemMouseCursors.click,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
  });

  final Widget Function(BuildContext context, InteractiveState state) builder;
  final VoidCallback? onTap;
  final VoidCallback? onLongPressStart;
  final VoidCallback? onLongPressEnd;
  final bool enabled;
  final BorderRadius focusRadius;
  final MouseCursor cursor;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? semanticLabel;

  @override
  State<Interactive> createState() => _InteractiveState();
}

class InteractiveState {
  const InteractiveState({required this.hovered, required this.pressed, required this.focused, required this.enabled});

  final bool hovered;
  final bool pressed;
  final bool focused;
  final bool enabled;
}

class _InteractiveState extends State<Interactive> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  bool get _active => widget.enabled && widget.onTap != null;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final state = InteractiveState(
      hovered: _hovered && _active,
      pressed: _pressed && _active,
      focused: _focused && _active,
      enabled: widget.enabled,
    );

    // outline: 2px solid rgba(244,181,92,.9); outline-offset: 2px. Always
    // in the tree (empty when unfocused) so focusing never rebuilds the
    // control.
    final child = DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: state.focused
          ? BoxDecoration(
              borderRadius: widget.focusRadius.add(const BorderRadius.all(Radius.circular(2))),
              border: Border.all(color: palette.focusRing, width: 2),
            )
          : const BoxDecoration(),
      child: widget.builder(context, state),
    );

    return Semantics(
      button: true,
      enabled: _active,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        enabled: _active,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        mouseCursor: _active ? widget.cursor : SystemMouseCursors.basic,
        onShowHoverHighlight: (v) => setState(() => _hovered = v),
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _active ? (_) => setState(() => _pressed = true) : null,
          onTapUp: _active ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: _active ? () => setState(() => _pressed = false) : null,
          onTap: _active ? widget.onTap : null,
          onLongPressStart: widget.onLongPressStart == null ? null : (_) => widget.onLongPressStart!(),
          onLongPressEnd: widget.onLongPressEnd == null ? null : (_) => widget.onLongPressEnd!(),
          child: AnimatedOpacity(
            duration: context.motion(Motion.quick),
            opacity: widget.enabled ? 1 : 0.42,
            child: child,
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import 'interactive.dart';

bool _still(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// The selected row's light: a cue wash pooling at the tick and falling off.
class _SelectedWash extends StatelessWidget {
  const _SelectedWash({required this.tick});

  /// Shows the cue tick at the left edge (hidden in a collapsed sidebar).
  final bool tick;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                p.primary.withValues(alpha: p.isDark ? 0.26 : 0.28),
                p.primaryWash,
              ],
            ),
            borderRadius: Radii.rControl,
          ),
        ),
        // A cue tick marks where you are, like the cue column on stage.
        Positioned(
          left: 0,
          top: 8,
          bottom: 8,
          width: 3,
          child: AnimatedOpacity(
            duration: _still(context) ? Duration.zero : Motion.quick,
            opacity: tick ? 1 : 0,
            child: DecoratedBox(
              decoration: BoxDecoration(color: p.primary, borderRadius: BorderRadius.circular(2)),
            ),
          ),
        ),
      ],
    );
  }
}

/// One selection light shared by the [NavItem]s in [child]: it slides to
/// the selected row instead of jumping, and fades out when none is
/// selected. Wrap the column of rows (inside its scroll view, so the light
/// scrolls with them). Rows outside a [NavHighlight] light themselves.
class NavHighlight extends StatefulWidget {
  const NavHighlight({super.key, required this.child, this.collapsed = false});

  /// How long the light takes to reach a newly selected row.
  static const slide = Duration(milliseconds: 180);

  final Widget child;

  /// The sidebar shows icons only: no tick.
  final bool collapsed;

  static _NavHighlightState? _of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_NavHighlightScope>()?.state;

  @override
  State<NavHighlight> createState() => _NavHighlightState();
}

class _NavHighlightScope extends InheritedWidget {
  const _NavHighlightScope({required this.state, required super.child});

  final _NavHighlightState state;

  @override
  bool updateShouldNotify(_NavHighlightScope old) => false;
}

class _NavHighlightState extends State<NavHighlight> {
  Object? _owner;
  Rect? _rect;
  bool _shown = false;
  bool _slide = false;

  /// [owner]'s row, laid out as [box], is the selected one.
  void claim(Object owner, RenderBox box) {
    _owner = owner;
    final stack = context.findRenderObject();
    if (stack is! RenderBox || !stack.attached || !box.attached || !box.hasSize) return;
    final rect = box.localToGlobal(Offset.zero, ancestor: stack) & box.size;
    if (_shown && rect == _rect) return;
    setState(() {
      // Slide only between rows; a first selection appears in place.
      _slide = _shown;
      _rect = rect;
      _shown = true;
    });
  }

  /// [owner]'s row is no longer selected. Checked once this frame's claims
  /// are in, so a selection moving between rows slides rather than blinks.
  void release(Object owner) {
    if (_owner != owner) return;
    _owner = null;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => scheduleMicrotask(() {
        if (mounted && _owner == null && _shown) setState(() => _shown = false);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final still = _still(context);
    final r = _rect;
    return _NavHighlightScope(
      state: this,
      child: Stack(
        children: [
          if (r != null)
            AnimatedPositioned(
              duration: _slide && !still ? NavHighlight.slide : Duration.zero,
              curve: Motion.move,
              left: r.left,
              top: r.top,
              width: r.width,
              height: r.height,
              child: AnimatedOpacity(
                duration: still ? Duration.zero : Motion.quick,
                opacity: _shown ? 1 : 0,
                child: _SelectedWash(tick: !widget.collapsed),
              ),
            ),
          widget.child,
        ],
      ),
    );
  }
}

/// Tells the [NavHighlight] above where its row is while [selected].
class _NavAnchor extends StatefulWidget {
  const _NavAnchor({required this.selected, required this.child});

  final bool selected;
  final Widget child;

  @override
  State<_NavAnchor> createState() => _NavAnchorState();
}

class _NavAnchorState extends State<_NavAnchor> {
  _NavHighlightState? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scope = NavHighlight._of(context);
  }

  @override
  void didUpdateWidget(_NavAnchor old) {
    super.didUpdateWidget(old);
    if (old.selected && !widget.selected) _scope?.release(this);
  }

  @override
  void dispose() {
    _scope?.release(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.selected) {
      // Every build: rows above may have moved this one.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !widget.selected) return;
        final box = context.findRenderObject();
        if (box is RenderBox) _scope?.claim(this, box);
      });
    }
    return widget.child;
  }
}

/// A count that ticks to its new value instead of swapping.
class _Count extends StatelessWidget {
  const _Count(this.value, {required this.style});

  final int value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: value.toDouble()),
    duration: _still(context) ? Duration.zero : Motion.smooth,
    curve: Motion.standard,
    builder: (context, v, _) => Text('${v.round()}', style: style),
  );
}

/// Sidebar navigation row: 32 px, icon 16, label, optional count/hint.
/// Inside a [NavHighlight] the selection light is shared and slides between
/// rows; otherwise the row lights itself.
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
    final shared = NavHighlight._of(context) != null;
    final item = Interactive(
      onTap: onTap,
      builder: (context, s) {
        final ink = selected ? p.inkPrimary : (s.hovered ? p.inkPrimary : (muted ? p.inkTertiary : p.inkSecondary));
        final iconInk = iconColor ?? (selected ? p.primaryText : ink);
        final trailingStyle = TypeScale.caption.copyWith(color: p.inkTertiary);
        final count = trailing == null ? null : int.tryParse(trailing!);
        final row = AnimatedContainer(
          duration: Motion.quick,
          height: 32,
          padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 10),
          alignment: collapsed ? Alignment.center : null,
          decoration: BoxDecoration(
            color: !selected && s.hovered ? p.hoverWash : Colors.transparent,
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
                    if (count != null)
                      _Count(count, style: trailingStyle)
                    else if (trailing != null)
                      Text(trailing!, style: trailingStyle),
                  ],
                ),
        );
        // One shape whether selected or not, so selecting a row never
        // rebuilds it — the light fades in behind instead.
        return _NavAnchor(
          selected: selected && shared,
          child: Stack(
            children: [
              if (!shared)
                Positioned.fill(
                  child: AnimatedOpacity(
                    duration: _still(context) ? Duration.zero : Motion.quick,
                    opacity: selected ? 1 : 0,
                    child: _SelectedWash(tick: !collapsed),
                  ),
                ),
              row,
            ],
          ),
        );
      },
    );
    return collapsed ? Tooltip(message: label, waitDuration: Motion.hoverIntent, child: item) : item;
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

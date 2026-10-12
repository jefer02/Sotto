import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/l10n.dart';

import '../design/icons.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import 'interactive.dart';
import 'keycap.dart';

// ───────────────────────────── Toggle ─────────────────────────────

class SottoToggle extends StatelessWidget {
  const SottoToggle({super.key, required this.value, this.onChanged, this.label});

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      toggled: value,
      label: label,
      child: Interactive(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        enabled: onChanged != null,
        focusRadius: const BorderRadius.all(Radius.circular(9)),
        builder: (context, s) => AnimatedContainer(
          duration: Motion.snappy,
          curve: Motion.glideEnter,
          width: 30,
          height: 18,
          decoration: BoxDecoration(
            color: value ? p.cueFill : p.float,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: value ? Colors.transparent : p.emphasis),
          ),
          child: AnimatedAlign(
            duration: Motion.snappy,
            curve: Motion.glideEnter,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 14,
              height: 14,
              margin: const EdgeInsets.all(1),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value ? const Color(0xFFFFFDF9) : p.inkSecondary,
                boxShadow: const [BoxShadow(color: Color(0x59000000), offset: Offset(0, 1), blurRadius: 2)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── Check & radio ─────────────────────────────

class SottoCheckbox extends StatelessWidget {
  const SottoCheckbox({super.key, required this.value, this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Interactive(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      focusRadius: Radii.rXs,
      builder: (context, s) => AnimatedContainer(
        duration: Motion.quick,
        width: 16,
        height: 16,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: value ? p.cueFill : Colors.transparent,
          borderRadius: Radii.rXs,
          border: Border.all(color: value ? p.cueFill : (s.hovered ? p.emphasis : p.control)),
        ),
        child: value ? SottoIcon(SottoIcons.check, size: 12, color: p.onCue) : null,
      ),
    );
  }
}

class SottoRadio extends StatelessWidget {
  const SottoRadio({super.key, required this.selected, this.onTap});

  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Interactive(
      onTap: onTap,
      focusRadius: const BorderRadius.all(Radius.circular(9)),
      builder: (context, s) => AnimatedContainer(
        duration: Motion.quick,
        width: 16,
        height: 16,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? p.cueFill : Colors.transparent,
          border: Border.all(color: selected ? p.cueFill : (s.hovered ? p.emphasis : p.control)),
        ),
        child: selected
            ? Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(shape: BoxShape.circle, color: p.onCue),
              )
            : null,
      ),
    );
  }
}

// ───────────────────────────── Segmented ─────────────────────────────

class Segment<T> {
  const Segment(this.value, this.label, {this.icon});
  final T value;
  final String label;
  final SottoIcons? icon;
}

class SegmentedControl<T> extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.height = 28,
    this.width,
  });

  final List<Segment<T>> segments;
  final T value;
  final ValueChanged<T>? onChanged;
  final double height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      height: height,
      width: width,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: Radii.rM,
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        mainAxisSize: width == null ? MainAxisSize.min : MainAxisSize.max,
        children: [
          for (final seg in segments)
            _wrap(
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Interactive(
                  onTap: onChanged == null ? null : () => onChanged!(seg.value),
                  focusRadius: Radii.rS,
                  builder: (context, s) {
                    final selected = seg.value == value;
                    final ink = selected ? p.primaryText : (s.hovered ? p.inkSecondary : p.inkTertiary);
                    return AnimatedContainer(
                      duration: Motion.snappy,
                      height: height - 6,
                      padding: EdgeInsets.symmetric(horizontal: width == null ? 10 : 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? p.float : Colors.transparent,
                        borderRadius: BorderRadius.circular(5),
                        boxShadow: selected
                            ? [
                                BoxShadow(color: p.control, spreadRadius: 1),
                                const BoxShadow(color: Color(0x4D000000), offset: Offset(0, 1), blurRadius: 2),
                              ]
                            : null,
                      ),
                      // Fixed-width controls shrink long labels rather than overflow.
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (seg.icon != null) ...[
                              SottoIcon(seg.icon!, size: 13, color: ink),
                              const SizedBox(width: 6),
                            ],
                            Text(seg.label, maxLines: 1, style: TypeScale.captionStrong.copyWith(color: ink)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _wrap(Widget child) => width == null ? child : Expanded(child: child);
}

// ───────────────────────────── Slider ─────────────────────────────

class SottoSlider extends StatelessWidget {
  const SottoSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.marker,
    this.label,
    this.width = 150,
    this.divisions,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final double min;
  final double max;

  /// A recommended value, drawn as a small tick under the track.
  final double? marker;
  final String? label;
  final double width;
  final int? divisions;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: width,
          height: 20,
          child: LayoutBuilder(
            builder: (context, c) {
              final t = ((value - min) / (max - min)).clamp(0.0, 1.0);
              void set(Offset local) {
                if (onChanged == null) return;
                var v = min + (local.dx / c.maxWidth).clamp(0.0, 1.0) * (max - min);
                if (divisions != null) {
                  final step = (max - min) / divisions!;
                  v = min + ((v - min) / step).round() * step;
                }
                onChanged!(v);
              }

              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => set(d.localPosition),
                  onHorizontalDragUpdate: (d) => set(d.localPosition),
                  child: Focus(
                    onKeyEvent: (node, e) {
                      if (e is KeyUpEvent || onChanged == null) return KeyEventResult.ignored;
                      final step = (max - min) / (divisions ?? 20);
                      if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
                        onChanged!((value + step).clamp(min, max));
                        return KeyEventResult.handled;
                      }
                      if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
                        onChanged!((value - step).clamp(min, max));
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          height: 4,
                          decoration: BoxDecoration(color: p.float, borderRadius: BorderRadius.circular(2)),
                        ),
                        FractionallySizedBox(
                          widthFactor: t,
                          child: Container(
                            height: 4,
                            decoration: BoxDecoration(color: p.cueFill, borderRadius: BorderRadius.circular(2)),
                          ),
                        ),
                        if (marker != null)
                          Positioned(
                            left: ((marker! - min) / (max - min)) * c.maxWidth - 0.5,
                            top: 13,
                            child: Container(width: 1, height: 4, color: p.emphasis),
                          ),
                        Positioned(
                          left: t * (c.maxWidth - 16),
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFFFFFDF9),
                              boxShadow: [BoxShadow(color: Color(0x66000000), offset: Offset(0, 1), blurRadius: 3)],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (label != null) ...[
          const SizedBox(width: 12),
          SizedBox(
            width: 36,
            child: Text(label!, style: TypeScale.mono.copyWith(color: p.inkPrimary)),
          ),
        ],
      ],
    );
  }
}

// ───────────────────────────── Text input ─────────────────────────────

class SottoTextField extends StatefulWidget {
  const SottoTextField({
    super.key,
    this.controller,
    this.placeholder,
    this.leading,
    this.shortcutHint,
    this.error,
    this.onChanged,
    this.onSubmitted,
    this.obscure = false,
    this.mono = false,
    this.width,
    this.focusNode,
    this.autofocus = false,
    this.maxLines = 1,
    this.minLines,
    this.initialValue,
  });

  final TextEditingController? controller;
  final String? placeholder;
  final SottoIcons? leading;
  final String? shortcutHint;
  final String? error;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool obscure;
  final bool mono;
  final double? width;
  final FocusNode? focusNode;
  final bool autofocus;
  final int? maxLines;
  final int? minLines;
  final String? initialValue;

  @override
  State<SottoTextField> createState() => _SottoTextFieldState();
}

class _SottoTextFieldState extends State<SottoTextField> {
  late final FocusNode _focus = widget.focusNode ?? FocusNode();
  late final TextEditingController _controller = widget.controller ?? TextEditingController(text: widget.initialValue);

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  void _onFocus() => setState(() {});

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    if (widget.focusNode == null) _focus.dispose();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final focused = _focus.hasFocus;
    final hasError = widget.error != null;
    final multi = widget.maxLines != 1;
    final style = (widget.mono ? TypeScale.mono.copyWith(fontSize: 13) : TypeScale.body).copyWith(color: p.inkPrimary);

    final field = AnimatedContainer(
      duration: Motion.quick,
      width: widget.width,
      height: multi ? null : 30,
      padding: EdgeInsets.fromLTRB(10, multi ? 8 : 0, 8, multi ? 8 : 0),
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: Radii.rControl,
        border: Border.all(
          color: hasError
              ? p.liveCapture
              : focused
              ? p.cueFill.withValues(alpha: 0.7)
              : p.control,
        ),
        boxShadow: focused && !hasError ? [BoxShadow(color: p.cueFill.withValues(alpha: 0.16), spreadRadius: 3)] : null,
      ),
      child: Row(
        crossAxisAlignment: multi ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          if (widget.leading != null) ...[
            SottoIcon(widget.leading!, size: 14, color: p.inkTertiary),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              autofocus: widget.autofocus,
              obscureText: widget.obscure,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              maxLines: widget.obscure ? 1 : widget.maxLines,
              minLines: widget.minLines,
              style: style,
              cursorWidth: 1.5,
              cursorHeight: 16,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: widget.placeholder,
                hintStyle: style.copyWith(color: p.inkTertiary),
              ),
            ),
          ),
          if (widget.shortcutHint != null) Keycap(widget.shortcutHint!, compact: true),
        ],
      ),
    );

    if (!hasError) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        field,
        const SizedBox(height: 6),
        Text(widget.error!, style: TypeScale.caption.copyWith(color: p.liveCapture)),
      ],
    );
  }
}

// ───────────────────────────── Select ─────────────────────────────

class SelectOption<T> {
  const SelectOption(this.value, this.label, {this.detail});
  final T value;
  final String label;
  final String? detail;
}

/// A dropdown that opens a float-surface menu, like the component sheet.
class SottoSelect<T> extends StatelessWidget {
  const SottoSelect({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.width = 190,
    this.placeholder,
  });

  final T? value;
  final List<SelectOption<T>> options;
  final ValueChanged<T>? onChanged;
  final double width;
  final String? placeholder;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final current = options.where((o) => o.value == value).firstOrNull;
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(p.float),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: Radii.rM,
            side: BorderSide(color: p.control),
          ),
        ),
        elevation: const WidgetStatePropertyAll(8),
        minimumSize: WidgetStatePropertyAll(Size(width, 0)),
      ),
      menuChildren: [
        for (final o in options)
          MenuItemButton(
            onPressed: onChanged == null ? null : () => onChanged!(o.value),
            style: ButtonStyle(
              minimumSize: WidgetStatePropertyAll(Size(width - 8, 30)),
              padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
              shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: Radii.rS)),
              backgroundColor: WidgetStateProperty.resolveWith(
                (s) => s.contains(WidgetState.hovered) || s.contains(WidgetState.focused)
                    ? p.pressWash
                    : Colors.transparent,
              ),
            ),
            trailingIcon: o.value == value ? SottoIcon(SottoIcons.check, size: 13, color: p.cueText) : null,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: o.label,
                    style: TypeScale.body.copyWith(color: p.inkPrimary),
                  ),
                  if (o.detail != null)
                    TextSpan(
                      text: '  ${o.detail}',
                      style: TypeScale.caption.copyWith(color: p.inkTertiary),
                    ),
                ],
              ),
            ),
          ),
      ],
      builder: (context, controller, _) => Interactive(
        onTap: onChanged == null ? null : () => controller.isOpen ? controller.close() : controller.open(),
        builder: (context, s) => AnimatedContainer(
          duration: Motion.quick,
          width: width,
          height: 30,
          padding: const EdgeInsets.only(left: 10, right: 8),
          decoration: BoxDecoration(
            color: s.hovered ? p.float : p.raised,
            borderRadius: Radii.rControl,
            border: Border.all(color: s.hovered ? p.emphasis : p.control),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  current?.label ?? placeholder ?? context.l10n.choosePlaceholder,
                  overflow: TextOverflow.ellipsis,
                  style: TypeScale.body.copyWith(color: current == null ? p.inkTertiary : p.inkPrimary),
                ),
              ),
              const SizedBox(width: 6),
              _Chevron(color: p.inkSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(size: const Size(10, 6), painter: _ChevronPainter(color));
}

class _ChevronPainter extends CustomPainter {
  _ChevronPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(1, 1)
        ..lineTo(size.width / 2, size.height - 1)
        ..lineTo(size.width - 1, 1),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ChevronPainter old) => old.color != color;
}

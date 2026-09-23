import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import 'interactive.dart';

/// Space reserved for the macOS traffic lights in the hidden title bar.
double get trafficLightInset => Platform.isMacOS ? 78 : 12;

bool get drawsCaptionButtons => Platform.isWindows || Platform.isLinux;

/// A 52 px header row that drags the window, as the title bar would.
class TitleBarArea extends StatelessWidget {
  const TitleBarArea({super.key, required this.child, this.showCaptionButtons = false});

  final Widget child;
  final bool showCaptionButtons;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      height: Layout.titleBar,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.hairline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(child: SizedBox.expand(child: child)),
          ),
          if (showCaptionButtons && drawsCaptionButtons) const CaptionButtons(),
        ],
      ),
    );
  }
}

/// Minimise / maximise / close for Windows and Linux, where the native
/// title bar is hidden.
class CaptionButtons extends StatelessWidget {
  const CaptionButtons({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Caption(icon: _CaptionIcon.minimize, onTap: () => windowManager.minimize()),
        _Caption(
          icon: _CaptionIcon.maximize,
          onTap: () async => await windowManager.isMaximized() ? windowManager.unmaximize() : windowManager.maximize(),
        ),
        _Caption(icon: _CaptionIcon.close, onTap: () => windowManager.close(), danger: true),
      ],
    );
  }
}

enum _CaptionIcon { minimize, maximize, close }

class _Caption extends StatelessWidget {
  const _Caption({required this.icon, required this.onTap, this.danger = false});

  final _CaptionIcon icon;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Interactive(
      onTap: onTap,
      cursor: SystemMouseCursors.basic,
      builder: (context, s) => Container(
        width: 46,
        height: Layout.titleBar,
        color: s.hovered ? (danger ? const Color(0xFFC42B1C) : p.hoverWash) : Colors.transparent,
        alignment: Alignment.center,
        child: CustomPaint(
          size: const Size(10, 10),
          painter: _CaptionPainter(icon, s.hovered && danger ? Colors.white : p.inkSecondary),
        ),
      ),
    );
  }
}

class _CaptionPainter extends CustomPainter {
  _CaptionPainter(this.icon, this.color);
  final _CaptionIcon icon;
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    switch (icon) {
      case _CaptionIcon.minimize:
        canvas.drawLine(Offset(0, s.height / 2), Offset(s.width, s.height / 2), paint);
      case _CaptionIcon.maximize:
        canvas.drawRect(Offset.zero & s, paint);
      case _CaptionIcon.close:
        canvas
          ..drawLine(Offset.zero, Offset(s.width, s.height), paint)
          ..drawLine(Offset(s.width, 0), Offset(0, s.height), paint);
    }
  }

  @override
  bool shouldRepaint(_CaptionPainter old) => old.color != color || old.icon != icon;
}

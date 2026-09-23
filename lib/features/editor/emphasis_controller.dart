import 'package:flutter/material.dart';

import '../../core/design/typography.dart';

/// Shows `**emphasis**` as bold while keeping the markers editable (drawn
/// faint), so what you type is exactly what the overlay will render.
class EmphasisController extends TextEditingController {
  EmphasisController({super.text, required this.markerColor});

  Color markerColor;

  static final _pattern = RegExp(r'\*\*(.+?)\*\*');

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final base = style ?? const TextStyle();
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _pattern.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      final marker = TextStyle(color: markerColor, fontWeight: FontWeight.w400);
      spans
        ..add(TextSpan(text: '**', style: marker))
        ..add(TextSpan(text: m.group(1), style: withWeight(base, 700)))
        ..add(TextSpan(text: '**', style: marker));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return TextSpan(style: base, children: spans);
  }
}

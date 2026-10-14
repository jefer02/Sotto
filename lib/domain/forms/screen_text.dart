import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'package:image/image.dart' as img;

import 'form_filler.dart' show OptionMatcher;

// The screen as text, read on this computer (Windows.Media.Ocr, macOS
// Vision), and the numbered marks the model answers with: on the
// screenshot it draws them; with no image, it reads them as a list.

/// A word OCR found, its box in screenshot pixels.
class OcrWord {
  const OcrWord(this.text, this.box);
  final String text;
  final Rect box;
}

/// A line of text OCR found, its box in screenshot pixels.
class OcrLine {
  const OcrLine(this.text, this.box, [this.words = const []]);
  final String text;
  final Rect box;
  final List<OcrWord> words;

  static Rect _rect(Object? v) {
    if (v is! List || v.length < 4) return Rect.zero;
    double n(int i) => (v[i] as num?)?.toDouble() ?? 0;
    return Rect.fromLTWH(n(0), n(1), n(2), n(3));
  }

  /// The native side's `{"lines":[{"text","box","words":[[x,y,w,h,"w"]…]}]}`.
  static List<OcrLine> parse(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      final j = jsonDecode(json);
      final lines = j is Map ? j['lines'] : null;
      if (lines is! List) return const [];
      return [
        for (final l in lines.whereType<Map<Object?, Object?>>())
          if ('${l['text'] ?? ''}'.trim().isNotEmpty)
            OcrLine('${l['text']}'.trim(), _rect(l['box']), [
              for (final w in (l['words'] as List? ?? const []).whereType<List<Object?>>())
                if (w.length >= 5) OcrWord('${w[4]}', _rect(w)),
            ]),
      ];
    } on FormatException {
      return const [];
    }
  }
}

/// One numbered mark: a field from the accessibility tree ([fieldId]), or a
/// line of text on screen.
class ScreenMark {
  const ScreenMark(this.number, this.box, this.text, {this.fieldId});
  final int number;

  /// Screenshot pixels.
  final Rect box;
  final String text;
  final String? fieldId;

  bool get isField => fieldId != null;
}

abstract final class ScreenMarks {
  /// At most this many text marks: past it, the page is too busy to mark.
  static const maxText = 150;

  /// Text shorter than this (screenshot pixels) is too small to read at the
  /// screenshot's scale: it gets no mark.
  static const minTextHeight = 8.0;

  /// Fields first — field fN is mark N — then each line of text on [page]
  /// (the browser's page, not its toolbar; null: the whole screenshot) that
  /// isn't inside a field, top to bottom.
  static List<ScreenMark> build({required Map<String, Rect?> fields, required List<OcrLine> lines, Rect? page}) {
    final marks = <ScreenMark>[];
    var next = 1;
    for (final MapEntry(key: id, value: box) in fields.entries) {
      final n = int.tryParse(id.replaceFirst(RegExp(r'^f'), ''));
      if (n == null || box == null || box.isEmpty) continue;
      marks.add(ScreenMark(n, box, '', fieldId: id));
      next = math.max(next, n + 1);
    }
    final fieldBoxes = [for (final m in marks) m.box.inflate(2)];
    final text =
        [
          for (final l in lines)
            if (!l.box.isEmpty &&
                l.box.height >= minTextHeight &&
                (page == null || page.contains(l.box.center)) &&
                !fieldBoxes.any((b) => b.contains(l.box.center)))
              l,
        ]..sort(
          (a, b) =>
              (a.box.top - b.box.top).abs() > 4 ? a.box.top.compareTo(b.box.top) : a.box.left.compareTo(b.box.left),
        );
    for (final l in text.take(maxText)) {
      marks.add(ScreenMark(next++, l.box, l.text));
    }
    return marks;
  }

  /// The text marks as the model reads them.
  static String json(Iterable<ScreenMark> marks) => jsonEncode([
    for (final m in marks)
      if (!m.isField)
        {
          'mark': m.number,
          'text': m.text,
          'box': [m.box.left.round(), m.box.top.round(), m.box.width.round(), m.box.height.round()],
        },
  ]);

  /// [jpeg] with every mark drawn on it — a box and its number — as a JPEG
  /// again. Fields in blue, text in orange.
  static Uint8List draw(Uint8List jpeg, List<ScreenMark> marks) {
    final image = img.decodeJpg(jpeg);
    if (image == null || marks.isEmpty) return jpeg;
    final field = img.ColorRgb8(30, 90, 255);
    final text = img.ColorRgb8(235, 110, 0);
    final white = img.ColorRgb8(255, 255, 255);
    final font = img.arial14;
    for (final m in marks) {
      final c = m.isField ? field : text;
      final b = m.box;
      img.drawRect(
        image,
        x1: b.left.round(),
        y1: b.top.round(),
        x2: b.right.round(),
        y2: b.bottom.round(),
        color: c,
        thickness: m.isField ? 2 : 1,
      );
      // The number in a tag at the box's top-left corner, above it when
      // there's room.
      final label = '${m.number}';
      final w = label.length * 8 + 4;
      const h = 15;
      final x = b.left.round().clamp(0, math.max(0, image.width - w)).toInt();
      final y = (b.top.round() - h >= 0 ? b.top.round() - h : b.top.round())
          .clamp(0, math.max(0, image.height - h))
          .toInt();
      img.fillRect(image, x1: x, y1: y, x2: x + w, y2: y + h, color: c);
      img.drawString(image, label, font: font, x: x + 2, y: y, color: white);
    }
    return img.encodeJpg(image, quality: 80);
  }

  /// Where [label] is written on screen, in screenshot pixels: the line
  /// that says it, else the run of words that does. Null when OCR didn't
  /// see it — no model needed to find a drop-down's option.
  static Offset? locate(List<OcrLine> lines, String label, {Rect? within}) {
    final want = OptionMatcher.fold(label);
    if (want.isEmpty) return null;
    bool inside(Rect r) => within == null || within.contains(r.center);
    for (final l in lines) {
      if (inside(l.box) && OptionMatcher.fold(l.text) == want) return l.box.center;
    }
    final wantWords = want.split(' ');
    for (final l in lines) {
      if (!inside(l.box)) continue;
      final words = l.words;
      for (var i = 0; i + wantWords.length <= words.length; i++) {
        var ok = true;
        for (var k = 0; k < wantWords.length && ok; k++) {
          ok = OptionMatcher.fold(words[i + k].text) == wantWords[k];
        }
        if (ok) {
          return words[i].box.expandToInclude(words[i + wantWords.length - 1].box).center;
        }
      }
    }
    return null;
  }

  /// The text a control at [point] shows: the line whose box holds it, else
  /// the nearest line on the same row to its right (the text inside a box).
  static String? textAt(List<OcrLine> lines, Offset point) {
    for (final l in lines) {
      if (l.box.inflate(3).contains(point)) return l.text;
    }
    OcrLine? best;
    var bestDx = double.infinity;
    for (final l in lines) {
      final dx = l.box.left - point.dx;
      if (dx < -20 || dx > 400) continue;
      if (point.dy < l.box.top - 6 || point.dy > l.box.bottom + 6) continue;
      if (dx.abs() < bestDx) {
        bestDx = dx.abs();
        best = l;
      }
    }
    return best?.text;
  }
}

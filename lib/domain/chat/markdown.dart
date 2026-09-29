// The Markdown chat replies use — paragraphs, headings, bullet and
// numbered lists, fenced code, **bold**, *italic*, `code` — parsed into
// blocks the UI renders. Safe on a half-streamed reply: an unclosed code
// fence is a code block that is still growing, an unclosed `**` is text.

enum MdBlockType { paragraph, heading, bullet, numbered, code }

class MdBlock {
  const MdBlock(this.type, this.text, {this.level = 0, this.number, this.language = '', this.open = false});

  final MdBlockType type;

  /// Inline text (paragraphs, headings, list items) or raw code.
  final String text;

  /// Heading level, or list nesting (0 = top).
  final int level;

  /// A numbered item's number.
  final int? number;
  final String language;

  /// A code block whose closing fence hasn't arrived yet.
  final bool open;

  @override
  String toString() => '$type($text)';
}

enum MdStyle { plain, bold, italic, code }

class MdSpan {
  const MdSpan(this.text, this.style);
  final String text;
  final MdStyle style;

  @override
  bool operator ==(Object other) => other is MdSpan && other.text == text && other.style == style;

  @override
  int get hashCode => Object.hash(text, style);

  @override
  String toString() => '${style.name}:$text';
}

abstract final class ChatMarkdown {
  static final _fence = RegExp(r'^\s*```\s*([\w+-]*)\s*$');
  static final _heading = RegExp(r'^(#{1,6})\s+(.*)$');
  static final _bullet = RegExp(r'^(\s*)[-*•]\s+(.*)$');
  static final _numbered = RegExp(r'^(\s*)(\d{1,3})[.)]\s+(.*)$');

  static List<MdBlock> parse(String source) {
    final lines = source.replaceAll('\r\n', '\n').split('\n');
    final out = <MdBlock>[];
    final para = <String>[];

    void flush() {
      if (para.isNotEmpty) out.add(MdBlock(MdBlockType.paragraph, para.join(' ').trim()));
      para.clear();
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final fence = _fence.firstMatch(line);
      if (fence != null) {
        flush();
        final code = <String>[];
        var j = i + 1;
        while (j < lines.length && !_fence.hasMatch(lines[j])) {
          code.add(lines[j]);
          j++;
        }
        out.add(MdBlock(MdBlockType.code, code.join('\n'), language: fence.group(1) ?? '', open: j >= lines.length));
        i = j;
        continue;
      }
      if (line.trim().isEmpty) {
        flush();
        continue;
      }
      final h = _heading.firstMatch(line);
      if (h != null) {
        flush();
        out.add(MdBlock(MdBlockType.heading, h.group(2)!.trim(), level: h.group(1)!.length));
        continue;
      }
      final b = _bullet.firstMatch(line);
      if (b != null) {
        flush();
        out.add(MdBlock(MdBlockType.bullet, b.group(2)!.trim(), level: b.group(1)!.length ~/ 2));
        continue;
      }
      final n = _numbered.firstMatch(line);
      if (n != null) {
        flush();
        out.add(
          MdBlock(
            MdBlockType.numbered,
            n.group(3)!.trim(),
            level: n.group(1)!.length ~/ 2,
            number: int.parse(n.group(2)!),
          ),
        );
        continue;
      }
      para.add(line.trim());
    }
    flush();
    return out;
  }

  /// **bold**, *italic* / _italic_, `code`. Unclosed markers stay text.
  static List<MdSpan> inline(String text) {
    final out = <MdSpan>[];
    final buf = StringBuffer();
    void plain() {
      if (buf.isNotEmpty) out.add(MdSpan(buf.toString(), MdStyle.plain));
      buf.clear();
    }

    var i = 0;
    while (i < text.length) {
      if (text.startsWith('`', i)) {
        final end = text.indexOf('`', i + 1);
        if (end > i + 1) {
          plain();
          out.add(MdSpan(text.substring(i + 1, end), MdStyle.code));
          i = end + 1;
          continue;
        }
      }
      if (text.startsWith('**', i)) {
        final end = text.indexOf('**', i + 2);
        if (end > i + 2) {
          plain();
          out.add(MdSpan(text.substring(i + 2, end), MdStyle.bold));
          i = end + 2;
          continue;
        }
      }
      final ch = text[i];
      if ((ch == '*' || ch == '_') && i + 1 < text.length && text[i + 1] != ' ') {
        final end = text.indexOf(ch, i + 1);
        // "_" inside words (snake_case) is not emphasis.
        final wordish = ch == '_' && i > 0 && RegExp(r'\w').hasMatch(text[i - 1]);
        if (end > i + 1 && !wordish && text[end - 1] != ' ') {
          plain();
          out.add(MdSpan(text.substring(i + 1, end), MdStyle.italic));
          i = end + 1;
          continue;
        }
      }
      buf.write(ch);
      i++;
    }
    plain();
    return out;
  }

  /// The reply as plain text, for copying and reading aloud.
  static String plainText(String source) => [
    for (final b in parse(source))
      switch (b.type) {
        MdBlockType.code => b.text,
        MdBlockType.bullet => '• ${_strip(b.text)}',
        MdBlockType.numbered => '${b.number}. ${_strip(b.text)}',
        _ => _strip(b.text),
      },
  ].join('\n');

  static String _strip(String s) => inline(s).map((x) => x.text).join();
}

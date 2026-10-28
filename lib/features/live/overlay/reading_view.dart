import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../../../l10n/l10n.dart';

import '../../../core/design/theme.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/typography.dart';
import '../../../core/widgets/display.dart';
import '../../../data/models/settings.dart';
import '../../../domain/structuring/check_markers.dart';
import '../../../domain/following/script_aligner.dart';
import '../../../domain/following/text_normalizer.dart';
import '../../../domain/overlay/auto_height.dart';
import '../live_state.dart';
import 'karaoke.dart';
import 'meta_strip.dart';
import 'reading_cursor.dart';
import 'script_scroll.dart';

enum ResolvedLayout { ticker, compact, standard, column, rail }

/// Container-query breakpoints from the responsive-overlay board.
ResolvedLayout resolveLayout(OverlayLayout pref, Size size) {
  switch (pref) {
    case OverlayLayout.ticker:
      return ResolvedLayout.ticker;
    case OverlayLayout.compact:
      return ResolvedLayout.compact;
    case OverlayLayout.standard:
      return ResolvedLayout.standard;
    case OverlayLayout.column:
      return ResolvedLayout.column;
    case OverlayLayout.rail:
      return ResolvedLayout.rail;
    case OverlayLayout.auto:
      if (size.width >= 1100 && size.height <= 140) return ResolvedLayout.rail;
      if (size.width < 380) return ResolvedLayout.ticker;
      if (size.height >= 460 && size.width < 1100) return ResolvedLayout.column;
      if (size.width < 520) return ResolvedLayout.compact;
      return ResolvedLayout.standard;
  }
}

/// The height of one line of script in [layout] at [width] — what each
/// layout below draws its lines at.
double readingLineHeight(ResolvedLayout layout, double width, ReadingSize size) {
  final font = overlayFontSize(width, size);
  return 1.34 *
      switch (layout) {
        ResolvedLayout.ticker => (font * 0.78).clamp(17.0, 24.0),
        ResolvedLayout.column => font * 0.86,
        ResolvedLayout.rail => font * 1.1,
        _ => font,
      };
}

/// The meta strip's density for [l] — and for [width]: a layout chosen by
/// hand can be narrower than the strip it would carry.
MetaDensity metaDensityFor(ResolvedLayout l, [double width = double.infinity]) {
  final byLayout = switch (l) {
    ResolvedLayout.ticker => MetaDensity.ticker,
    ResolvedLayout.compact => MetaDensity.compact,
    _ => MetaDensity.full,
  };
  final byWidth = width < 380
      ? MetaDensity.ticker
      : width < 520
      ? MetaDensity.compact
      : MetaDensity.full;
  return byLayout.index < byWidth.index ? byLayout : byWidth;
}

/// Display settings for the reading surface.
class ReadingStyle {
  const ReadingStyle({
    required this.size,
    required this.linesShown,
    required this.glide,
    required this.reduceMotion,
    required this.plate,
    this.wpm = 148,
    this.font = ScriptFonts.overlayDefault,
    this.highlight = HighlightEffect.off,
    this.highlightStill = false,
  });

  final ReadingSize size;
  final int wpm;
  final int linesShown;
  final bool glide;
  final bool reduceMotion;

  /// The script font (resolved: a missing system font is already the
  /// default here) and the karaoke highlight.
  final ScriptFont font;
  final HighlightEffect highlight;

  /// Previews: the highlight rests on the last word said, as under reduced
  /// motion.
  final bool highlightStill;

  /// Below 70 % opacity a plate appears behind the current line.
  final bool plate;

  (int before, int after) get window => switch (linesShown) {
    <= 3 => (1, 1),
    <= 5 => (1, 3),
    _ => (2, 4),
  };
}

// ─────────────────────────── Words & glue ───────────────────────────

class ScriptWord {
  const ScriptWord(this.text, this.bold, this.glueNext, {this.marker = false});
  final String text;
  final bool bold;

  /// Part of a marker to check ("[CHECK: …]"): a note, never said — drawn
  /// in the cue color and never dimmed as spoken.
  final bool marker;

  /// Join to the next word with a non-breaking space.
  final bool glueNext;
}

final _numberish = RegExp(r'^[$€£]?\d[\d.,]*%?[.,;:]?$');
final _unit = RegExp(
  r'^(million|billion|thousand|percent|pts|points|millones|millón|mil|puntos|k|m|bn|x)[.,;:!?]?$',
  caseSensitive: false,
);
final _preposition = RegExp(r'^(on|in|at|of|to|by|up|en|de|a|del|al)$', caseSensitive: false);

/// Splits beat text into display words — the same indexing the aligner
/// uses — tracking `**bold**` and phrase glue (a number never splits from
/// its unit; a short preposition stays with its number; dashes stay with
/// the word before).
List<ScriptWord> splitWords(String text) {
  final raw = text.split(RegExp(r'\s+')).where((w) => w.replaceAll('**', '').isNotEmpty).toList();
  final out = <ScriptWord>[];
  final mask = CheckMarkers.wordMask(text);
  var bold = false;
  final clean = <(String, bool)>[];
  for (final w in raw) {
    var t = w;
    var wordBold = bold;
    if (t.startsWith('**')) {
      bold = !bold;
      wordBold = bold;
      t = t.substring(2);
    }
    if (t.endsWith('**')) {
      t = t.substring(0, t.length - 2);
      bold = !bold;
    }
    if (t.contains('**')) t = t.replaceAll('**', '');
    clean.add((t, wordBold));
  }
  for (var i = 0; i < clean.length; i++) {
    final (t, b) = clean[i];
    final next = i + 1 < clean.length ? clean[i + 1].$1 : null;
    final glue =
        next != null &&
        ((_numberish.hasMatch(t) && _unit.hasMatch(next)) ||
            (_preposition.hasMatch(t) && RegExp(r'^[A-Z]?\d').hasMatch(next)) ||
            next == '—' ||
            next == '–');
    out.add(ScriptWord(t, b, glue, marker: i < mask.length && mask[i]));
  }
  // Must match TextNormalizer.displayWords exactly.
  assert(out.length == TextNormalizer.displayWords(text).length);
  return out;
}

// ─────────────────────────── Reading view ───────────────────────────

class ReadingView extends StatelessWidget {
  const ReadingView({
    super.key,
    required this.state,
    required this.layout,
    required this.style,
    this.anchorOffset,
    this.onFit,
  });

  final LiveState state;
  final ResolvedLayout layout;
  final ReadingStyle style;

  /// See [AnchoredScript.anchorOffset] / [AnchoredScript.onFit].
  final double? anchorOffset;
  final ValueChanged<double>? onFit;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        return switch (layout) {
          // Small windows: small type, the line being read at the top. It
          // scrolls with the voice like the other layouts — a block
          // replaced by the next made the text jump at every beat.
          ResolvedLayout.ticker => AnchoredScript(
            state: state,
            style: style,
            fontSize: (overlayFontSize(width, style.size) * 0.78).clamp(17.0, 24.0),
            anchorOffset: 0,
            fadeTop: 14,
            fadeBottom: 18,
          ),
          ResolvedLayout.rail => _RailView(state: state, style: style, width: width),
          ResolvedLayout.column => _ColumnView(state: state, style: style, width: width),
          _ => AnchoredScript(
            state: state,
            style: style,
            fontSize: overlayFontSize(width, style.size),
            anchorOffset: anchorOffset,
            onFit: onFit,
            // Auto-height ends just under the last line: fade only the pad.
            fadeBottom: onFit == null ? 46 : AutoHeight.bottomPad + 4,
          ),
        };
      },
    );
  }
}

/// The standard surface: the line being read sits on the eye-line (30 %),
/// words already said dim, and the column follows the voice word by word
/// ([ScriptScroll]) — a line at a time with [ScrollStyle.step].
class AnchoredScript extends StatefulWidget {
  const AnchoredScript({
    super.key,
    required this.state,
    required this.style,
    required this.fontSize,
    this.leftInset = Layout.overlayTextInset,
    this.rightInset = 28,
    this.anchor = Layout.overlayAnchor,
    this.fadeTop = 40,
    this.fadeBottom = 46,
    this.anchorOffset,
    this.onFit,
  });

  final LiveState state;
  final ReadingStyle style;
  final double fontSize;
  final double leftInset;
  final double rightInset;

  /// Fraction of the overlay height where the current line sits.
  final double anchor;

  /// The eye-line in pixels from the top instead of a fraction — so it stays
  /// put while the window's height follows the text.
  final double? anchorOffset;

  /// After each advance: the reading-area height that shows the visible
  /// lines with nothing empty under the last one ([AutoHeight.fitted]).
  final ValueChanged<double>? onFit;
  final double fadeTop;
  final double fadeBottom;

  @override
  State<AnchoredScript> createState() => _AnchoredScriptState();
}

/// The transform that scrolls the script (tests read its offset).
@visibleForTesting
const scrollKey = ValueKey('script-scroll');

/// The current line and the one after it (tests measure them against the
/// overlay's controls).
@visibleForTesting
const currentLineKey = ValueKey('current-line');
@visibleForTesting
const nextLineKey = ValueKey('next-line');

class _AnchoredScriptState extends State<AnchoredScript> with TickerProviderStateMixin {
  final _columnKey = GlobalKey();
  final _keys = <int, GlobalKey>{};
  final _dy = <int, double>{};

  /// The column's offset: the reading position held on the eye-line.
  late final _scroll = ScriptScroll(this);

  /// Where the reading is, letter by letter, and where the last word said
  /// ends: the scroll follows the first, the highlight sweeps up to it.
  late final _cursor = ReadingCursor(this)..addListener(_followCursor);
  final _said = ValueNotifier<double>(0);
  late ScriptChars? _chars = _charsFor(widget.state.flat);

  /// Each beat's laid-out paragraph and its top within the beat's box.
  final _paragraphs = <int, RenderParagraph>{};
  final _paragraphTop = <int, double>{};
  late final _pulse = AnimationController(vsync: this, duration: Motion.cuePulse);
  late final _sweep = AnimationController(vsync: this, duration: Motion.cueSweep);
  bool _measured = false;
  bool _needsMeasure = true;
  double _areaHeight = 0;

  final _h = <int, double>{};

  /// The line last built for each beat, with what it was built from. The
  /// overlay rebuilds on every voice level and clock tick; a line whose
  /// reading level and spoken words haven't moved comes back as the same
  /// widget, so Flutter skips it instead of rebuilding every beat. Anything
  /// a line shows is in its key: the beat itself (a reorganized script
  /// brings new beats), its level, its spoken words, the text style (text
  /// size, layout), the palette (the auto text color), plate, reduce
  /// motion and the locale.
  final _lines = <int, (Object, Widget)>{};

  Widget _line(int i, Object inputs, Widget Function() build) {
    final cached = _lines[i];
    if (cached != null && cached.$1 == inputs) return cached.$2;
    final line = build();
    _lines[i] = (inputs, line);
    return line;
  }

  /// A fixed eye-line stays clear of the top fade.
  double get _anchorY => widget.anchorOffset == null
      ? _areaHeight * widget.anchor
      : math.max(widget.anchorOffset!, widget.fadeTop * 0.75 + _lineHeight / 2);

  GlobalKey _key(int i) => _keys.putIfAbsent(i, GlobalKey.new);

  static ScriptChars? _charsFor(FlatScript? flat) => flat == null ? null : ScriptChars(flat);

  /// The end of the last word said, in global characters.
  double get _saidEnd => _chars?.saidEnd(widget.state.position.saidBeat, widget.state.position.saidWords) ?? 0;

  @override
  void initState() {
    super.initState();
    _said.value = _saidEnd;
    _cursor.jumpTo(_said.value);
  }

  @override
  void didUpdateWidget(AnchoredScript old) {
    super.didUpdateWidget(old);
    final was = old.state.position, now = widget.state.position;
    final moved = was.beat != now.beat || was.saidBeat != now.saidBeat || was.saidWords != now.saidWords;
    if (old.state.flat != widget.state.flat) {
      _chars = _charsFor(widget.state.flat);
      _said.value = _saidEnd;
      _cursor.jumpTo(_said.value);
    } else if (old.state.jumps != widget.state.jumps) {
      // A key, the clicker or a relock skipped text: no sweep through it.
      _said.value = _saidEnd;
      _cursor.jumpTo(_said.value);
    } else if (moved) {
      _said.value = _saidEnd;
      _cursor.moveTo(_said.value, rate: now.charsPerSecond);
    }
    if (moved ||
        old.fontSize != widget.fontSize ||
        old.state.script != widget.state.script ||
        old.style.size != widget.style.size ||
        old.style.font != widget.style.font ||
        old.style.highlight != widget.style.highlight) {
      _needsMeasure = true;
    }
    if (old.state.lastAdvanceAt != widget.state.lastAdvanceAt && !widget.style.reduceMotion) {
      _pulse.forward(from: 0);
    }
    if (old.state.resumedAt != widget.state.resumedAt && widget.state.resumedAt != null && !widget.style.reduceMotion) {
      _sweep.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _cursor.dispose();
    _said.dispose();
    _scroll.dispose();
    _pulse.dispose();
    _sweep.dispose();
    super.dispose();
  }

  void _measure() {
    if (!mounted) return;
    final column = _columnKey.currentContext?.findRenderObject() as RenderBox?;
    if (column == null || !column.hasSize) return;
    _dy.clear();
    _h.clear();
    _paragraphs.clear();
    _paragraphTop.clear();
    for (final e in _keys.entries) {
      final box = e.value.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.attached) {
        _dy[e.key] = box.localToGlobal(Offset.zero, ancestor: column).dy;
        _h[e.key] = box.size.height;
        final paragraph = _paragraphIn(box);
        if (paragraph != null && paragraph.hasSize && paragraph.attached) {
          _paragraphs[e.key] = paragraph;
          _paragraphTop[e.key] = paragraph.localToGlobal(Offset.zero, ancestor: box).dy;
        }
      }
    }
    final pos = widget.state.position;
    final cur = pos.beat;
    final said = _dy[pos.saidBeat];
    if (said == null || _dy[cur] == null) return;
    _needsMeasure = false;
    _reportFit(cur, _dy[cur]!);
    // Gliding, the column follows the reading cursor letter by letter;
    // stepping, it moves a line at a time to the top of the beat being said.
    final step = _anchorY - _lineHeight * 0.5 - said;
    final target = widget.style.glide ? (_targetFor(_cursor.value) ?? step) : step;
    if (!_measured) {
      _scroll.jumpTo(target);
      setState(() => _measured = true);
      return;
    }
    _scroll.glideTo(target, calm: widget.style.reduceMotion || !widget.style.glide, line: _lineHeight);
  }

  /// Every frame the cursor moves: keep the letters being said level with
  /// the eye-line.
  void _followCursor() {
    if (!_measured || !widget.style.glide || _needsMeasure) return;
    final target = _targetFor(_cursor.value);
    if (target != null) _scroll.glideTo(target, calm: widget.style.reduceMotion, line: _lineHeight);
  }

  /// The column offset that puts global character [c] on the eye-line: the
  /// line holding it, crept up by the share of that line already read, so
  /// the column glides on as a line is read instead of jumping when it ends.
  /// Read from the laid-out text; O(1) paragraph queries.
  double? _targetFor(double c) {
    final chars = _chars;
    if (chars == null) return null;
    final beat = chars.beatOf(c);
    final top = _dy[beat];
    if (top == null) return null;
    final local = c - chars.beatStart[beat];
    final paragraph = _paragraphs[beat];
    var offset = 0.0;
    if (paragraph != null && paragraph.attached && local > 0) {
      final starts = chars.wordStart[beat];
      final length = starts.isEmpty ? 0 : starts.last + chars.wordLength[beat].last;
      final at = local.clamp(0.0, length.toDouble());
      final i = at.floor();
      final line = lineRange(paragraph, i, _lineHeight);
      final y = paragraph.getOffsetForCaret(TextPosition(offset: i), Rect.zero).dy;
      final span = math.max(1, line.end - line.start);
      final read = ((at - line.start) / span).clamp(0.0, 1.0);
      offset = (_paragraphTop[beat] ?? 0) + y + read * _lineHeight;
    }
    return _anchorY - _lineHeight * 0.5 - (top + offset);
  }

  static RenderParagraph? _paragraphIn(RenderObject root) {
    if (root is RenderParagraph) return root;
    RenderParagraph? found;
    root.visitChildren((child) => found ??= _paragraphIn(child));
    return found;
  }

  double get _lineHeight => widget.fontSize * 1.34;

  double? _lastFit;

  void _reportFit(int cur, double curTop) {
    final onFit = widget.onFit;
    final flat = widget.state.flat;
    if (onFit == null || flat == null) return;
    final last = math.min(cur + widget.style.window.$2, flat.length - 1);
    final top = _dy[last], height = _h[last];
    if (top == null || height == null) return;
    // The beat boxes carry the inter-beat gap below them; it isn't content.
    final gap = widget.fontSize * 0.46;
    final fit = AutoHeight.fitted(
      anchorY: _anchorY,
      lineHeight: _lineHeight,
      belowCurrent: top + height - gap - curTop,
    );
    if (_lastFit != null && (fit - _lastFit!).abs() < 1) return;
    _lastFit = fit;
    onFit(fit);
  }

  @override
  Widget build(BuildContext context) {
    final o = context.overlayPalette;
    final s = widget.state;
    final flat = s.flat;
    if (flat == null) return const SizedBox.shrink();
    if (_needsMeasure) SchedulerBinding.instance.addPostFrameCallback((_) => _measure());

    final text = ReadingType.live(widget.fontSize, lineHeight: _lineHeight, font: widget.style.font);
    final gap = widget.fontSize * 0.46;
    final (before, after) = widget.style.window;
    final cur = s.position.beat;
    // The lines the highlight sweeps: the one being said and, past "Move on
    // when said", the one shown as current.
    final hostFrom = s.position.saidBeat, hostTo = math.max(s.position.saidBeat, cur);
    // Cue chips name their cue in the interface language.
    final locale = Localizations.maybeLocaleOf(context);
    _lines.removeWhere((i, _) => i >= flat.length);

    return LayoutBuilder(
      builder: (context, c) {
        if (_areaHeight != c.maxHeight) {
          _areaHeight = c.maxHeight;
          _needsMeasure = true;
          SchedulerBinding.instance.addPostFrameCallback((_) => _measure());
        }
        final anchorY = _anchorY;
        final dpr = MediaQuery.devicePixelRatioOf(context);
        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [Color(0x00000000), Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
            stops: [
              0,
              (widget.fadeTop / rect.height).clamp(0.0, 0.5),
              (1 - widget.fadeBottom / rect.height).clamp(0.5, 1.0),
              1,
            ],
          ).createShader(rect),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                top: 0,
                left: widget.leftInset,
                right: widget.rightInset,
                child: AnimatedBuilder(
                  animation: _scroll,
                  // On whole physical pixels: the glyphs and the highlight's
                  // pill stay sharp while the column glides.
                  builder: (context, child) => Opacity(
                    opacity: _measured ? 1 : 0,
                    child: Transform.translate(
                      key: scrollKey,
                      offset: Offset(0, (_scroll.value * dpr).roundToDouble() / dpr),
                      child: child,
                    ),
                  ),
                  child: RepaintBoundary(
                    child: Column(
                      key: _columnKey,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < flat.length; i++)
                          _line(
                            i,
                            (
                              flat.beats[i],
                              // Its reading level: done, now, next or later.
                              (i - cur).clamp(-1, 2),
                              i >= cur - before && i <= cur + after,
                              i == cur ? s.position.spokenWords : 0,
                              text,
                              gap,
                              widget.style.plate,
                              widget.style.reduceMotion,
                              o,
                              locale,
                              widget.style.font,
                              widget.style.highlight,
                              widget.style.highlightStill,
                              i >= hostFrom && i <= hostTo,
                            ),
                            () => KeyedSubtree(
                              key: _key(i),
                              child: Padding(
                                padding: EdgeInsets.only(bottom: gap),
                                child: KeyedSubtree(
                                  key: i == cur ? currentLineKey : (i == cur + 1 ? nextLineKey : null),
                                  child: _BeatLine(
                                    beat: flat.beats[i],
                                    index: i,
                                    current: cur,
                                    spoken: i == cur ? s.position.spokenWords : 0,
                                    visible: i >= cur - before && i <= cur + after,
                                    style: text,
                                    plate: widget.style.plate && i == cur,
                                    reduceMotion: widget.style.reduceMotion,
                                    stillHighlight: widget.style.highlightStill,
                                    palette: o,
                                    highlight: i >= hostFrom && i <= hostTo
                                        ? widget.style.highlight
                                        : HighlightEffect.off,
                                    cursor: _cursor,
                                    said: _said,
                                    beatStart: _chars?.beatStart[i] ?? 0,
                                    fontSize: widget.fontSize,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              // The cue dot never moves — it is the eye-line. Its pulse
              // repaints its own layer, not the script column.
              Positioned(
                left: Layout.overlayCueColumn,
                top: anchorY - 3,
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, _) {
                      final t = _pulse.value;
                      final scale = t < 0.5 ? 1 + 0.8 * t : 1.4 - 0.8 * (t - 0.5);
                      return Transform.scale(
                        scale: _pulse.isAnimating ? scale : 1,
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: s.phase == LivePhase.paused ? o.inkAt(0.4) : o.cue,
                            boxShadow: [BoxShadow(color: o.cue.withValues(alpha: 0.12), spreadRadius: 3)],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              // After Dismiss: a cue sweep re-anchors the eye (none under
              // reduced motion).
              Positioned(
                left: widget.leftInset,
                right: widget.rightInset,
                top: anchorY + _lineHeight * 0.5 + 2,
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _sweep,
                    builder: (context, _) => !_sweep.isAnimating
                        ? const SizedBox.shrink()
                        : Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: Motion.glideEnter.transform(_sweep.value),
                              child: Opacity(
                                opacity: 1 - _sweep.value * 0.6,
                                child: Container(height: 1.5, color: o.cue),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One beat. Its reading level — done, now, next, later — is its color.
class _BeatLine extends StatefulWidget {
  const _BeatLine({
    required this.beat,
    required this.index,
    required this.current,
    required this.spoken,
    required this.visible,
    required this.style,
    required this.plate,
    required this.reduceMotion,
    required this.palette,
    this.highlight = HighlightEffect.off,
    this.stillHighlight = false,
    this.cursor,
    this.said,
    this.beatStart = 0,
    this.fontSize = 26,
  });

  final FlatBeat beat;
  final int index;
  final int current;
  final int spoken;
  final bool visible;
  final TextStyle style;
  final bool plate;
  final bool reduceMotion;
  final OverlayPalette palette;

  /// The karaoke highlight this line carries (off unless it's being said).
  final HighlightEffect highlight;
  final bool stillHighlight;
  final ValueListenable<double>? cursor;
  final ValueListenable<double>? said;
  final int beatStart;
  final double fontSize;

  @override
  State<_BeatLine> createState() => _BeatLineState();
}

class _BeatLineState extends State<_BeatLine> with SingleTickerProviderStateMixin {
  late final _dim = AnimationController(vsync: this, duration: Motion.wordDim);
  late List<ScriptWord> _words = splitWords(widget.beat.beat.text);
  int _dimFrom = 0;
  final _paragraphKey = GlobalKey();

  /// A word's text as laid out: words are joined by one space, a glued pair
  /// by a non-breaking one.
  String _wordText(int i) => _words[i].text + (i == _words.length - 1 ? '' : (_words[i].glueNext ? '\u00a0' : ' '));

  /// The line as one span drawn with [foreground], for the highlight: the
  /// same words, weights and cue placeholder as the line itself.
  InlineSpan _replica(Paint foreground) => TextSpan(
    style: widget.style.copyWith(foreground: foreground, shadows: const []),
    children: [
      if (widget.beat.beat.cue != null)
        const WidgetSpan(alignment: PlaceholderAlignment.middle, child: SizedBox.shrink()),
      for (var i = 0; i < _words.length; i++)
        TextSpan(
          text: _wordText(i),
          style: _words[i].bold
              ? const TextStyle(fontWeight: FontWeight.w700, fontVariations: [FontVariation.weight(700)])
              : null,
        ),
    ],
  );

  @override
  void didUpdateWidget(_BeatLine old) {
    super.didUpdateWidget(old);
    if (old.beat.beat.text != widget.beat.beat.text) _words = splitWords(widget.beat.beat.text);
    if (widget.spoken > old.spoken && widget.index == widget.current) {
      _dimFrom = old.spoken;
      if (widget.reduceMotion) {
        _dim.value = 1;
      } else {
        _dim.forward(from: 0);
      }
    } else if (widget.spoken < old.spoken) {
      _dimFrom = widget.spoken;
      _dim.value = 1;
    }
  }

  @override
  void dispose() {
    _dim.dispose();
    super.dispose();
  }

  double get _level {
    final o = widget.palette;
    if (!widget.visible) return 0;
    final d = widget.index - widget.current;
    if (d < 0) return o.readDone;
    if (d == 0) return o.readNow;
    if (d == 1) return o.readNext;
    return o.readLater;
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.palette;
    final isCurrent = widget.index == widget.current;
    final base = widget.style.copyWith(color: o.inkAt(_level), shadows: o.textShadows(_level));
    final cue = widget.beat.beat.cue;
    // Under the glow the line keeps its color: what was said stays lit.
    final dims = widget.highlight != HighlightEffect.glow;

    Widget text = AnimatedBuilder(
      animation: _dim,
      builder: (context, _) {
        final done = o.inkAt(o.readDone);
        return Text.rich(
          key: _paragraphKey,
          TextSpan(
            children: [
              if (cue != null)
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: AnimatedOpacity(
                      duration: context.motion(Motion.glide),
                      opacity: widget.visible ? 1 : 0,
                      child: CueChip(cue, color: o.cue, dimmed: true),
                    ),
                  ),
                ),
              for (var i = 0; i < _words.length; i++)
                TextSpan(
                  text: _wordText(i),
                  style: () {
                    final color = _words[i].marker
                        ? o.cue.withValues(alpha: o.cue.a * _level)
                        : !isCurrent || !dims
                        ? null
                        : i < _dimFrom
                        ? done
                        : i < widget.spoken
                        ? Color.lerp(o.inkAt(o.readNow), done, _dim.value)
                        : null;
                    return TextStyle(
                      fontWeight: _words[i].bold ? FontWeight.w700 : null,
                      fontVariations: _words[i].bold ? const [FontVariation.weight(700)] : null,
                      color: color,
                      shadows: o.shadowsFor(color),
                    );
                  }(),
                ),
            ],
          ),
        );
      },
    );

    if (widget.highlight != HighlightEffect.off && widget.cursor != null && widget.said != null) {
      final starts = <int>[], lengths = <int>[];
      var c = cue == null ? 0 : 1;
      for (var i = 0; i < _words.length; i++) {
        starts.add(c);
        lengths.add(_words[i].text.length);
        c += _wordText(i).length;
      }
      text = KaraokeLine(
        effect: widget.highlight,
        reduceMotion: widget.reduceMotion || widget.stillHighlight,
        palette: o,
        fontSize: widget.fontSize,
        cursor: widget.cursor!,
        said: widget.said!,
        beatStart: widget.beatStart,
        wordStarts: starts,
        wordLengths: lengths,
        paragraphKey: _paragraphKey,
        replica: _replica,
        child: text,
      );
    }

    text = AnimatedDefaultTextStyle(
      duration: widget.reduceMotion ? Duration.zero : Motion.glide,
      curve: Motion.glideEnter,
      style: base,
      child: text,
    );

    if (widget.plate) {
      // The plate extends past the text; shift it so the words stay put.
      text = Transform.translate(
        offset: const Offset(-6, 0),
        child: Container(
          decoration: BoxDecoration(color: o.ground.withValues(alpha: 0.72), borderRadius: Radii.rS),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: text,
        ),
      );
    }
    // Every shown line on its own layer: a line that changes (a word
    // dimming, a level easing at a beat change) re-rasterizes alone, and the
    // still ones stay cached. Text-only glyphs carry a 13-shadow outline, so
    // re-drawing the whole column for one line cost 100–200 ms a frame.
    return widget.visible || isCurrent ? RepaintBoundary(child: text) : text;
  }
}

// ─────────────────────────── Column ───────────────────────────

/// Height ≥ 460: adds a section rail and the section's key points.
class _ColumnView extends StatelessWidget {
  const _ColumnView({required this.state, required this.style, required this.width});
  final LiveState state;
  final ReadingStyle style;
  final double width;

  @override
  Widget build(BuildContext context) {
    final o = context.overlayPalette;
    final section = state.section;
    final script = state.script!;
    final next = state.sectionIndex + 1 < script.sections.length ? script.sections[state.sectionIndex + 1] : null;
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned(left: 11, top: 24, child: SectionProgress(state: state, vertical: true)),
              Positioned.fill(
                child: AnchoredScript(
                  state: state,
                  style: style,
                  fontSize: overlayFontSize(width, style.size) * 0.86,
                  anchor: 0.34,
                ),
              ),
            ],
          ),
        ),
        if (section != null && (section.keyPoints.isNotEmpty || next != null))
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 14, 16, 14),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: o.inkAt(0.08))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (section.keyPoints.isNotEmpty) ...[
                  Text(context.l10n.keyPoints, style: TypeScale.captionStrong.copyWith(color: o.inkAt(0.7))),
                  const SizedBox(height: 8),
                  for (final k in section.keyPoints)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 7, right: 9),
                            child: Container(
                              width: 3,
                              height: 3,
                              decoration: BoxDecoration(shape: BoxShape.circle, color: o.inkAt(0.6)),
                            ),
                          ),
                          Expanded(
                            child: Text(k, style: TypeScale.body.copyWith(color: o.inkAt(0.82))),
                          ),
                        ],
                      ),
                    ),
                ],
                if (next != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(context.l10n.upNextOverlay, style: TypeScale.caption.copyWith(color: o.inkAt(0.55))),
                      Expanded(
                        child: Text(
                          next.title,
                          overflow: TextOverflow.ellipsis,
                          style: TypeScale.captionStrong.copyWith(color: o.inkAt(0.85)),
                        ),
                      ),
                      Text(
                        formatDuration(next.budgetSeconds ?? 0),
                        style: TypeScale.mono.copyWith(fontSize: 11, color: o.inkAt(0.55)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────── Rail ───────────────────────────

/// Ultrawide / stage monitors: now, next and time side by side. The line
/// never exceeds 64 characters.
class _RailView extends StatelessWidget {
  const _RailView({required this.state, required this.style, required this.width});
  final LiveState state;
  final ReadingStyle style;
  final double width;

  @override
  Widget build(BuildContext context) {
    final o = context.overlayPalette;
    final flat = state.flat!;
    final cur = state.position.beat;
    final beat = flat.beats[cur];
    final words = splitWords(beat.beat.text);
    final spoken = state.position.spokenWords.clamp(0, words.length);
    final nextBeat = cur + 1 < flat.length ? flat.beats[cur + 1] : null;

    return LayoutBuilder(
      builder: (context, c) {
        // Two lines always fit the rail's height, whatever the text size.
        final size = math.min(overlayFontSize(640, style.size) * 1.1, (c.maxHeight - 6) / (2 * 1.34));
        return _rail(context, o, words, spoken, nextBeat, size);
      },
    );
  }

  Widget _rail(
    BuildContext context,
    OverlayPalette o,
    List<ScriptWord> words,
    int spoken,
    FlatBeat? nextBeat,
    double size,
  ) {
    return Row(
      children: [
        Container(
          width: 300,
          padding: const EdgeInsets.fromLTRB(22, 0, 16, 0),
          decoration: BoxDecoration(
            border: Border(right: BorderSide(color: o.inkAt(0.08))),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SectionProgress(state: state),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      state.section?.title ?? '',
                      overflow: TextOverflow.ellipsis,
                      style: TypeScale.captionStrong.copyWith(color: o.inkAt(0.78)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: formatClock(state.elapsed.inSeconds),
                      style: TypeScale.mono.copyWith(fontSize: 20, color: o.ink),
                    ),
                    TextSpan(
                      text: ' / ${formatClock(state.plannedSeconds(style.wpm))}',
                      style: TypeScale.mono.copyWith(color: o.inkAt(0.5)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: o.cue),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text.rich(
                    key: currentLineKey,
                    TextSpan(
                      children: [
                        for (var i = 0; i < words.length; i++)
                          TextSpan(
                            text: words[i].text + (i == words.length - 1 ? '' : (words[i].glueNext ? ' ' : ' ')),
                            style: TextStyle(
                              color: words[i].marker
                                  ? o.cue
                                  : i < spoken
                                  ? o.inkAt(o.readDone)
                                  : o.ink,
                              fontWeight: words[i].bold ? FontWeight.w700 : null,
                            ),
                          ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: ReadingType.live(size, font: style.font),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (nextBeat != null)
          Container(
            width: 400,
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: o.inkAt(0.08))),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.next, style: TypeScale.captionStrong.copyWith(color: o.inkAt(0.6))),
                const SizedBox(height: 6),
                ScriptText(
                  key: nextLineKey,
                  nextBeat.beat.text,
                  maxLines: 3,
                  style: ReadingType.live(17, lineHeight: 23, font: style.font).copyWith(color: o.inkAt(0.82)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

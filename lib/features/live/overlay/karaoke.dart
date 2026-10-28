import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../../core/design/tokens.dart';
import '../../../data/models/settings.dart';

/// Sparkles rising off the letters being said: a fixed pool of [cap]
/// particles in flat arrays, so a frame never allocates. A spawn with the
/// pool full is dropped: the pool never holds more than [cap].
class SparklePool {
  SparklePool([this.cap = Karaoke.particleCap])
    : x = Float32List(cap),
      y = Float32List(cap),
      vx = Float32List(cap),
      vy = Float32List(cap),
      age = Float32List(cap),
      life = Float32List(cap),
      size = Float32List(cap),
      twinkle = Float32List(cap),
      phase = Float32List(cap);

  final int cap;
  final Float32List x, y, vx, vy, age, life, size, twinkle, phase;
  final _random = math.Random(7);
  int _alive = 0;

  /// Particles alive now; never more than [cap].
  int get alive => _alive;

  /// A new sparkle at ([px], [py]) for text [em] pixels tall. False when the
  /// pool is full.
  bool spawn(double px, double py, double em) {
    if (_alive >= cap) return false;
    // Live particles are packed at the front: the next slot is free.
    final i = _alive++;
    double between(double a, double b) => a + (b - a) * _random.nextDouble();
    x[i] = px + between(-0.35, 0.2) * em;
    y[i] = py + between(-0.45, 0.25) * em;
    vx[i] = between(-0.15, 0.15) * em;
    vy[i] = -between(Karaoke.particleRiseMin, Karaoke.particleRiseMax) * em;
    age[i] = 0;
    life[i] = between(Karaoke.particleLifeMin.inMilliseconds / 1000, Karaoke.particleLifeMax.inMilliseconds / 1000);
    size[i] = between(Karaoke.particleSizeMin, Karaoke.particleSizeMax) * em;
    twinkle[i] = between(Karaoke.twinkleMin, Karaoke.twinkleMax);
    phase[i] = between(0, 2 * math.pi);
    return true;
  }

  /// Moves every particle on by [dt] seconds; the dead are swapped out of
  /// the live run. O(alive).
  void step(double dt) {
    var i = 0;
    while (i < _alive) {
      age[i] += dt;
      if (age[i] >= life[i]) {
        _alive--;
        _move(_alive, i);
        continue;
      }
      x[i] += vx[i] * dt;
      y[i] += vy[i] * dt;
      // Light dust slows as it rises.
      vy[i] *= 1 - 0.8 * dt;
      i++;
    }
  }

  void _move(int from, int to) {
    if (from == to) return;
    x[to] = x[from];
    y[to] = y[from];
    vx[to] = vx[from];
    vy[to] = vy[from];
    age[to] = age[from];
    life[to] = life[from];
    size[to] = size[from];
    twinkle[to] = twinkle[from];
    phase[to] = phase[from];
  }

  void clear() => _alive = 0;
}

/// The karaoke highlight under one line of the overlay.
///
/// [child] is the line's text; [paragraphKey] finds its paragraph, whose
/// layout says where each letter is. The highlight reads the reading
/// cursor ([cursor], global characters, see ReadingCursor) and never runs
/// ahead of it: the cursor itself never passes the last word confirmed as
/// said.
///
/// * [HighlightEffect.glow]: a crisp rounded pill in the cue color behind
///   the word at the cursor, the line keeping its color over it. It is as
///   tall as the font's own box and inset from its line, so it never
///   touches the line above or below; a word broken over two lines gets a
///   pill on each. A soft shine follows the cursor across it and sparkles
///   twinkle in it, both clipped to the pill. Nothing is blurred, and
///   nothing is drawn over the glyphs.
/// * [HighlightEffect.simple]: the letters at the cursor take the cue color.
/// * Reduced motion: the pill holds still on the word last said; no shine,
///   no sparkles, no ticker.
///
/// Per frame: O(s + p) — s ≤ 2 line pieces, p ≤ [Karaoke.particleCap]
/// sparkles. Space: the fixed sparkle pool plus one laid-out copy of the
/// line, rebuilt only when the line, its style or its width change.
class KaraokeLine extends StatefulWidget {
  const KaraokeLine({
    super.key,
    required this.effect,
    required this.reduceMotion,
    required this.palette,
    required this.fontSize,
    required this.cursor,
    required this.said,
    required this.beatStart,
    required this.wordStarts,
    required this.wordLengths,
    required this.paragraphKey,
    required this.replica,
    required this.child,
  });

  final HighlightEffect effect;
  final bool reduceMotion;
  final OverlayPalette palette;
  final double fontSize;

  /// Where the reading is (global characters, continuous) and where the
  /// last word said ends.
  final ValueListenable<double> cursor;
  final ValueListenable<double> said;

  /// The global character this line starts at.
  final int beatStart;

  /// Each word's first character within the line, and its length.
  final List<int> wordStarts;
  final List<int> wordLengths;

  final GlobalKey paragraphKey;

  /// The line's text as one span drawn with [foreground] — the same words,
  /// weights and placeholder as [child], so it lays out identically.
  final InlineSpan Function(Paint foreground) replica;
  final Widget child;

  @override
  State<KaraokeLine> createState() => KaraokeLineState();
}

class KaraokeLineState extends State<KaraokeLine> with SingleTickerProviderStateMixin {
  final sparkles = SparklePool();
  final _frame = _Frame();
  Ticker? _ticker;
  Duration _lastTick = Duration.zero;
  double _lastCursor = 0;

  /// How lit the glow is: 1 while the voice moves the cursor, fading out
  /// after it stops.
  double _energy = 0;
  double _idle = 0;
  late Listenable _repaint;

  /// Where the head of the glow was last painted, for spawning sparkles.
  Offset? _head;
  final _random = math.Random(11);

  /// The laid-out copies of the line and what they were laid out for, and
  /// the lines they broke into.
  (Object, List<TextPainter>)? _copies;
  List<ui.LineMetrics> _lineMetrics = const [];

  bool get _animated => widget.effect == HighlightEffect.glow && !widget.reduceMotion;

  /// Whether a ticker is running (tests: reduced motion never starts one).
  @visibleForTesting
  bool get ticking => _ticker?.isActive ?? false;

  /// Whether a ticker was ever made (reduced motion makes none).
  @visibleForTesting
  bool get hasTicker => _ticker != null;

  /// The end of the lit letters as last painted, in characters of this line
  /// (tests: never past what was said).
  @visibleForTesting
  double? paintedHead;

  /// Glow's pills as last painted, in the paragraph's coordinates: one per
  /// line the word spans (tests: each stays inside its line).
  @visibleForTesting
  List<Rect> paintedPills = const [];

  @override
  void initState() {
    super.initState();
    _lastCursor = widget.cursor.value;
    _listen();
  }

  void _listen() {
    _repaint = Listenable.merge([if (widget.reduceMotion) widget.said else widget.cursor, _frame]);
    if (_animated) widget.cursor.addListener(_onCursor);
  }

  void _unlisten(KaraokeLine w) => w.cursor.removeListener(_onCursor);

  @override
  void didUpdateWidget(KaraokeLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cursor != widget.cursor ||
        oldWidget.said != widget.said ||
        oldWidget.reduceMotion != widget.reduceMotion ||
        oldWidget.effect != widget.effect) {
      _unlisten(oldWidget);
      _listen();
      if (!_animated) {
        _ticker?.stop();
        sparkles.clear();
        _energy = 0;
      }
    }
  }

  @override
  void dispose() {
    _unlisten(widget);
    _ticker?.dispose();
    _frame.dispose();
    for (final c in {...?_copies?.$2}) {
      c.dispose();
    }
    super.dispose();
  }

  void _onCursor() {
    final c = widget.cursor.value;
    final moved = c - _lastCursor;
    _lastCursor = c;
    final local = c - widget.beatStart;
    if (moved <= 0 || local < 0 || local > _length + Karaoke.trailChars) return;
    _idle = 0;
    // Sparkles in proportion to the letters swept.
    final head = _head;
    if (head != null) {
      var n = moved * Karaoke.particlesPerChar;
      while (n > 0 && (n >= 1 || _random.nextDouble() < n)) {
        sparkles.spawn(head.dx, head.dy, widget.fontSize);
        n -= 1;
      }
    }
    final ticker = _ticker ??= createTicker(_tick);
    if (!ticker.isActive) {
      _lastTick = Duration.zero;
      ticker.start();
    }
  }

  int get _length => widget.wordStarts.isEmpty ? 0 : widget.wordStarts.last + widget.wordLengths.last;

  void _tick(Duration elapsed) {
    final dt = math.min((elapsed - _lastTick).inMicroseconds / 1e6, 1 / 20);
    _lastTick = elapsed;
    if (dt <= 0) return;
    _idle += dt;
    final hold = Karaoke.idleHold.inMicroseconds / 1e6;
    if (_idle < hold) {
      _energy = math.min(1, _energy + dt / 0.12);
    } else {
      _energy = math.max(0, _energy - dt / (Karaoke.idleFade.inMicroseconds / 1e6));
    }
    sparkles.step(dt);
    _frame.tick();
    if (_energy <= 0 && sparkles.alive == 0) _ticker?.stop();
  }

  @override
  Widget build(BuildContext context) {
    final painter = _KaraokePainter(
      this,
      textScaler: MediaQuery.textScalerOf(context),
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    // Glow's pill sits behind the glyphs, so nothing is ever drawn over
    // them and they stay crisp. Simple's tint recolors the letters, so it
    // sits over them.
    final glowBehind = widget.effect == HighlightEffect.glow;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (glowBehind)
          Positioned.fill(
            child: RepaintBoundary(child: CustomPaint(painter: painter)),
          ),
        widget.child,
        if (!glowBehind)
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(child: CustomPaint(painter: painter)),
            ),
          ),
      ],
    );
  }
}

class _Frame extends ChangeNotifier {
  void tick() => notifyListeners();
}

/// The glow (or tint) and the sparkles. Lays out copies of the line once
/// and repaints them masked each frame.
class _KaraokePainter extends CustomPainter {
  _KaraokePainter(this.s, {required this.textScaler, required this.devicePixelRatio}) : super(repaint: s._repaint);

  final KaraokeLineState s;
  final TextScaler textScaler;
  final double devicePixelRatio;

  KaraokeLine get w => s.widget;

  static final _maskPaint = Paint();
  static final _layerPaint = Paint();
  static final _sparkPaint = Paint();
  static final _fillPaint = Paint();
  static final _edgePaint = Paint()..style = PaintingStyle.stroke;
  static final _shinePaint = Paint();
  static final _star = () {
    // A four-point star, one unit across.
    final p = Path()..moveTo(0, -0.5);
    for (var k = 1; k <= 8; k++) {
      final r = k.isEven ? 0.5 : 0.06;
      final a = -math.pi / 2 + k * math.pi / 4;
      p.lineTo(r * math.cos(a), r * math.sin(a));
    }
    return p..close();
  }();

  RenderParagraph? get _paragraph {
    final ro = w.paragraphKey.currentContext?.findRenderObject();
    return ro is RenderParagraph && ro.hasSize ? ro : null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p = _paragraph;
    if (p == null) return;
    if (w.effect == HighlightEffect.glow) {
      _paintPill(canvas, p);
    } else {
      _paintTint(canvas, p);
    }
  }

  /// Glow: a crisp pill behind the word being said — or, still, the word
  /// last said — inside its own line. Moving, a soft shine follows the
  /// cursor across it and sparkles twinkle in it; both are clipped to the
  /// pill, and nothing is blurred.
  void _paintPill(Canvas canvas, RenderParagraph p) {
    final o = w.palette;
    final lightInk = o.ink.computeLuminance() > 0.5;
    final em = w.fontSize;
    final length = s._length.toDouble();

    final int word;
    double? head;
    if (w.reduceMotion) {
      word = _wordEndingBy(w.said.value - w.beatStart);
      if (word >= 0) s.paintedHead = (w.wordStarts[word] + w.wordLengths[word]).toDouble();
    } else {
      final h = w.cursor.value - w.beatStart;
      word = h <= 0 || h > length + Karaoke.trailChars ? -1 : _wordAt(math.min(h, length));
      if (word >= 0) s.paintedHead = head = math.min(h, length);
    }
    final pills = word < 0 ? const <RRect>[] : _pills(p, word, lightInk);
    s.paintedPills = [for (final pill in pills) pill.outerRect];
    if (pills.isEmpty) return;

    final fill = o.textOnly
        ? (lightInk ? Karaoke.pillTextOnlyOnLightInk : Karaoke.pillTextOnlyOnDarkInk)
        : (lightInk ? Karaoke.pillOnLightInk : Karaoke.pillOnDarkInk);
    _fillPaint.color = o.cue.withValues(alpha: o.cue.a * fill);
    _edgePaint
      ..color = o.cue.withValues(alpha: o.cue.a * (lightInk ? Karaoke.pillEdgeOnLightInk : Karaoke.pillEdgeOnDarkInk))
      ..strokeWidth = 1 / devicePixelRatio;
    final headAt = head == null ? null : _caret(p, head);
    if (headAt != null) s._head = Offset(headAt.dx, headAt.dy + em * 0.55);
    for (final pill in pills) {
      canvas.drawRRect(pill, _fillPaint);
      canvas.drawRRect(pill.deflate(0.5 / devicePixelRatio), _edgePaint);
      // The shine and sparkles live in the piece of the pill the cursor is on.
      if (headAt == null || headAt.dy + em * 0.5 < pill.top || headAt.dy + em * 0.5 > pill.bottom) continue;
      canvas.save();
      canvas.clipRRect(pill);
      final energy = s._energy;
      if (energy > 0) {
        final shine = (lightInk ? Karaoke.coreOnLightInk : Karaoke.coreOnDarkInk).withValues(
          alpha: (lightInk ? Karaoke.shineOnLightInk : Karaoke.shineOnDarkInk) * energy,
        );
        final trail = em * Karaoke.shineTrail, lead = em * Karaoke.shineLead;
        _shinePaint.shader = ui.Gradient.linear(
          Offset(headAt.dx - trail, 0),
          Offset(headAt.dx + lead, 0),
          [shine.withValues(alpha: 0), shine, shine.withValues(alpha: 0)],
          [0, trail / (trail + lead), 1],
        );
        canvas.drawRect(pill.outerRect, _shinePaint);
      }
      _paintSparkles(canvas, lightInk);
      canvas.restore();
    }
  }

  /// The pill around [word]: one per line the word spans, as wide as its
  /// letters plus a little, as tall as the font's own box (its ascent and
  /// descent, without the extra line height) and always inset from its
  /// line's edges, so it never reaches the line above or below. Its edges
  /// sit on physical pixels.
  List<RRect> _pills(RenderParagraph p, int word, bool lightInk) {
    final em = w.fontSize;
    _copies(p, lightInk);
    final metrics = s._lineMetrics;
    final start = w.wordStarts[word];
    final boxes = p.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: start + w.wordLengths[word]),
    );
    final onLine = <int, Rect>{};
    for (final b in boxes) {
      final r = b.toRect(), y = r.center.dy;
      final i = metrics.indexWhere((m) => y >= m.baseline - m.ascent && y <= m.baseline + m.descent);
      if (i >= 0) onLine[i] = onLine[i]?.expandToInclude(r) ?? r;
    }
    final dpr = devicePixelRatio;
    final origin = p.localToGlobal(Offset.zero);
    double snap(double v, double o, double Function(double) round) => round((o + v) * dpr) / dpr - o;
    final inset = math.max(1 / dpr, em * Karaoke.pillInset);
    return [
      for (final MapEntry(key: i, value: r) in onLine.entries)
        () {
          final m = metrics[i];
          // The line's height spreads ascent and descent alike.
          final unscaled = m.ascent <= 0 ? 1.0 : m.unscaledAscent / m.ascent;
          final top = math.max(m.baseline - m.unscaledAscent - em * Karaoke.pillPadY, m.baseline - m.ascent + inset);
          final bottom = math.min(
            m.baseline + m.descent * unscaled + em * Karaoke.pillPadY,
            m.baseline + m.descent - inset,
          );
          // Vertical edges snap inwards: never a pixel nearer the next line.
          final rect = Rect.fromLTRB(
            snap(r.left - em * Karaoke.pillPadX, origin.dx, (v) => v.roundToDouble()),
            snap(top, origin.dy, (v) => v.ceilToDouble()),
            snap(r.right + em * Karaoke.pillPadX, origin.dx, (v) => v.roundToDouble()),
            snap(bottom, origin.dy, (v) => v.floorToDouble()),
          );
          return RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2));
        }(),
    ];
  }

  /// Simple: the letters at the cursor take the cue color — a crisp tinted
  /// copy of the line over it, masked to them and clipped to their line.
  void _paintTint(Canvas canvas, RenderParagraph p) {
    final lightInk = w.palette.ink.computeLuminance() > 0.5;
    final em = w.fontSize;

    // Which letters: the still word, or the sweep at the cursor.
    final double head, tail;
    if (w.reduceMotion) {
      final said = w.said.value - w.beatStart;
      final word = _wordEndingBy(said);
      if (word < 0) return;
      tail = w.wordStarts[word].toDouble();
      head = (w.wordStarts[word] + w.wordLengths[word]).toDouble();
    } else {
      head = w.cursor.value - w.beatStart;
      tail = head - Karaoke.simpleTrailChars;
    }
    final length = s._length.toDouble();
    if (head <= 0 || tail >= length) return;

    final h = head.clamp(0.0, length), t = tail.clamp(0.0, length);
    s.paintedHead = h;
    final segments = _segments(p, t, h);
    if (segments.isEmpty) return;

    // The tint rolls off over about a letter past the head; behind it, it
    // trails off eased (fast at first, then slowly), never a hard edge.
    final feather = w.reduceMotion ? 0.0 : Karaoke.headFeather * em;
    var bounds = segments.first.rect;
    for (final seg in segments.skip(1)) {
      bounds = bounds.expandToInclude(seg.rect);
    }
    _layerPaint.blendMode = BlendMode.srcOver;
    canvas.saveLayer(bounds.inflate(feather), _layerPaint);
    _maskPaint.blendMode = BlendMode.dstIn;
    for (final seg in segments) {
      final x0 = seg.x0, x1 = seg.x1;
      final end = seg.endsAtHead ? x1 + feather : x1;
      final a0 = w.reduceMotion ? 1.0 : seg.a0, a1 = w.reduceMotion ? 1.0 : seg.a1;
      final span = math.max(end - x0, 0.001);
      // Only this line: the copy carries the lines above and below too.
      final clip = Rect.fromLTRB(x0, seg.rect.top, end, seg.rect.bottom);
      canvas.save();
      canvas.clipRect(clip);
      for (final copy in _copies(p, lightInk)) {
        copy.paint(canvas, Offset.zero);
      }
      final at = ((x1 - x0) / span).clamp(0.0, 1.0);
      Color white(double a) => const Color(0xFFFFFFFF).withValues(alpha: a.clamp(0.0, 1.0));
      _maskPaint.shader = ui.Gradient.linear(
        Offset(x0, 0),
        Offset(end, 0),
        [
          white(a0),
          white(a0 + (a1 - a0) * 0.25),
          white(a1),
          white(seg.endsAtHead && feather > 0 ? a1 * 0.35 : a1),
          white(seg.endsAtHead && feather > 0 ? 0 : a1),
        ],
        [0, at * 0.55, at, at + (1 - at) * 0.4, 1],
        TileMode.decal,
      );
      canvas.drawRect(clip, _maskPaint);
      canvas.restore();
    }
    canvas.restore();
  }

  /// The word local character [c] falls in — or, between words, the one
  /// before — or −1 before the first.
  int _wordAt(double c) {
    var word = -1;
    for (var k = 0; k < w.wordStarts.length && w.wordStarts[k] < c; k++) {
      word = k;
    }
    return word;
  }

  /// The last word that has ended by local character [said], or −1.
  int _wordEndingBy(double said) {
    var word = -1;
    for (var k = 0; k < w.wordStarts.length; k++) {
      if (w.wordStarts[k] + w.wordLengths[k] <= said + 0.5) word = k;
    }
    return word;
  }

  /// Where character [c] (fractional) is: between the carets either side
  /// of it on its line.
  Offset _caret(RenderParagraph p, double c) {
    final i = c.floor();
    final a = p.getOffsetForCaret(TextPosition(offset: i), Rect.zero);
    if (c == i) return a;
    final b = p.getOffsetForCaret(TextPosition(offset: i + 1), Rect.zero);
    if ((b.dy - a.dy).abs() > 0.5) return a;
    return Offset(a.dx + (b.dx - a.dx) * (c - i), a.dy);
  }

  /// The masked span [t, h] cut at line breaks, each piece with its x range
  /// and how lit its ends are.
  List<_Segment> _segments(RenderParagraph p, double t, double h) {
    final lineHeight = p.getFullHeightForCaret(TextPosition(offset: t.floor()));
    final out = <_Segment>[];
    var start = t;
    final trail = math.max(h - t, 0.001);
    for (var guard = 0; guard < 3 && start < h; guard++) {
      final line = lineRange(p, start.floor(), lineHeight);
      final end = math.min(h, line.end.toDouble());
      final a = _caret(p, start), b = _caret(p, end);
      final endsAtHead = end >= h;
      out.add(
        _Segment(
          rect: Rect.fromLTRB(a.dx, a.dy, math.max(b.dx, a.dx + 1), a.dy + lineHeight),
          x0: a.dx,
          x1: math.max(b.dx, a.dx + 1),
          a0: ((start - t) / trail).clamp(0.0, 1.0),
          a1: ((end - t) / trail).clamp(0.0, 1.0),
          endsAtHead: endsAtHead,
        ),
      );
      if (endsAtHead || line.end <= start.floor()) break;
      start = line.end.toDouble();
    }
    return out;
  }

  /// The sparkles, crisp four-point stars; the caller clips them to the pill.
  void _paintSparkles(Canvas canvas, bool lightInk) {
    final pool = s.sparkles;
    if (pool.alive == 0) return;
    final color = lightInk ? Karaoke.coreOnLightInk : Karaoke.coreOnDarkInk;
    _sparkPaint.blendMode = lightInk ? BlendMode.plus : BlendMode.srcOver;
    for (var i = 0; i < pool.alive; i++) {
      final life = pool.age[i] / pool.life[i];
      // In fast, out slow; it twinkles all the while.
      final fade = life < 0.15 ? life / 0.15 : 1 - (life - 0.15) / 0.85;
      final glint = 0.55 + 0.45 * math.sin(pool.phase[i] + pool.twinkle[i] * pool.age[i] * 2 * math.pi);
      final a = (fade * glint * Karaoke.sparkleAlpha).clamp(0.0, 1.0);
      if (a <= 0.02) continue;
      final r = pool.size[i] * (0.7 + 0.3 * glint);
      _sparkPaint.color = color.withValues(alpha: a);
      canvas.save();
      canvas.translate(pool.x[i], pool.y[i]);
      canvas.scale(r);
      canvas.drawPath(_star, _sparkPaint);
      canvas.restore();
    }
  }

  /// The line laid out again to the paragraph's width: for Glow, to read
  /// its line metrics; for Simple, the crisp tinted copy it draws.
  List<TextPainter> _copies(RenderParagraph p, bool lightInk) {
    final em = w.fontSize;
    final key = (p.constraints.maxWidth, w.effect, lightInk, w.palette.cue, em, w.replica, textScaler);
    final cache = s._copies;
    if (cache != null && cache.$1 == key) return cache.$2;
    for (final old in {...?cache?.$2}) {
      old.dispose();
    }
    TextPainter copy(Color color) {
      final paint = Paint()..color = color;
      final tp = TextPainter(text: w.replica(paint), textDirection: TextDirection.ltr, textScaler: textScaler);
      // The cue chip's placeholder, as big as the real one.
      final boxes = p.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 1));
      final placeholders = <PlaceholderDimensions>[];
      tp.text!.visitChildren((span) {
        if (span is PlaceholderSpan) {
          final b = boxes.isEmpty ? Rect.zero : boxes.first.toRect();
          placeholders.add(PlaceholderDimensions(size: b.size, alignment: span.alignment));
        }
        return true;
      });
      if (placeholders.isNotEmpty) tp.setPlaceholderDimensions(placeholders);
      tp.layout(maxWidth: p.constraints.maxWidth);
      return tp;
    }

    final copies = [copy(w.palette.cue)];
    s._copies = (key, copies);
    s._lineMetrics = copies.first.computeLineMetrics();
    return copies;
  }

  @override
  bool shouldRepaint(_KaraokePainter old) =>
      old.s != s || old.textScaler != textScaler || old.devicePixelRatio != devicePixelRatio;
}

/// The characters on the line holding character [c] of [p]: what sits at
/// its left and right edges.
TextRange lineRange(RenderParagraph p, int c, double lineHeight) {
  final y = p.getOffsetForCaret(TextPosition(offset: c), Rect.zero).dy + lineHeight / 2;
  return TextRange(
    start: p.getPositionForOffset(Offset(0, y)).offset,
    end: p.getPositionForOffset(Offset(p.size.width, y)).offset,
  );
}

class _Segment {
  const _Segment({
    required this.rect,
    required this.x0,
    required this.x1,
    required this.a0,
    required this.a1,
    required this.endsAtHead,
  });
  final Rect rect;
  final double x0, x1, a0, a1;
  final bool endsAtHead;
}

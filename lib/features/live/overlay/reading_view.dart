import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../../l10n/l10n.dart';

import '../../../core/design/theme.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/typography.dart';
import '../../../core/widgets/display.dart';
import '../../../data/models/settings.dart';
import '../../../domain/following/script_aligner.dart';
import '../../../domain/following/text_normalizer.dart';
import '../live_state.dart';
import 'meta_strip.dart';

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

MetaDensity metaDensityFor(ResolvedLayout l) => switch (l) {
  ResolvedLayout.ticker => MetaDensity.ticker,
  ResolvedLayout.compact => MetaDensity.compact,
  _ => MetaDensity.full,
};

/// Display settings for the reading surface.
class ReadingStyle {
  const ReadingStyle({
    required this.size,
    required this.linesShown,
    required this.glide,
    required this.reduceMotion,
    required this.plate,
    this.wpm = 148,
  });

  final ReadingSize size;
  final int wpm;
  final int linesShown;
  final bool glide;
  final bool reduceMotion;

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
  const ScriptWord(this.text, this.bold, this.glueNext);
  final String text;
  final bool bold;

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
    out.add(ScriptWord(t, b, glue));
  }
  // Must match TextNormalizer.displayWords exactly.
  assert(out.length == TextNormalizer.displayWords(text).length);
  return out;
}

// ─────────────────────────── Reading view ───────────────────────────

class ReadingView extends StatelessWidget {
  const ReadingView({super.key, required this.state, required this.layout, required this.style});

  final LiveState state;
  final ResolvedLayout layout;
  final ReadingStyle style;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        return switch (layout) {
          ResolvedLayout.ticker => _TickerView(state: state, style: style, width: width),
          ResolvedLayout.rail => _RailView(state: state, style: style, width: width),
          ResolvedLayout.column => _ColumnView(state: state, style: style, width: width),
          _ => AnchoredScript(state: state, style: style, fontSize: overlayFontSize(width, style.size)),
        };
      },
    );
  }
}

/// The standard surface: the current beat sits on the eye-line (30 %),
/// words already said dim, and the column glides one beat at a time.
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
  });

  final LiveState state;
  final ReadingStyle style;
  final double fontSize;
  final double leftInset;
  final double rightInset;

  /// Fraction of the overlay height where the current line sits.
  final double anchor;
  final double fadeTop;
  final double fadeBottom;

  @override
  State<AnchoredScript> createState() => _AnchoredScriptState();
}

class _AnchoredScriptState extends State<AnchoredScript> with TickerProviderStateMixin {
  final _columnKey = GlobalKey();
  final _keys = <int, GlobalKey>{};
  final _dy = <int, double>{};
  late final _glide = AnimationController(vsync: this, duration: Motion.glide);
  late final _pulse = AnimationController(vsync: this, duration: Motion.cuePulse);
  late final _sweep = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
  double _from = 0, _to = 0;
  bool _measured = false;
  bool _needsMeasure = true;
  double _areaHeight = 0;

  double get _translate =>
      lerpDouble(_from, _to, (widget.style.glide ? Motion.glideEnter : Motion.shiftMove).transform(_glide.value))!;

  GlobalKey _key(int i) => _keys.putIfAbsent(i, GlobalKey.new);

  @override
  void didUpdateWidget(AnchoredScript old) {
    super.didUpdateWidget(old);
    final beatChanged = old.state.position.beat != widget.state.position.beat;
    if (beatChanged ||
        old.fontSize != widget.fontSize ||
        old.state.script != widget.state.script ||
        old.style.size != widget.style.size) {
      _needsMeasure = true;
    }
    if (old.state.lastAdvanceAt != widget.state.lastAdvanceAt && !widget.style.reduceMotion) {
      _pulse.forward(from: 0);
    }
    if (old.state.resumedAt != widget.state.resumedAt && widget.state.resumedAt != null) {
      _sweep.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _glide.dispose();
    _pulse.dispose();
    _sweep.dispose();
    super.dispose();
  }

  void _measure() {
    if (!mounted) return;
    final column = _columnKey.currentContext?.findRenderObject() as RenderBox?;
    if (column == null || !column.hasSize) return;
    _dy.clear();
    for (final e in _keys.entries) {
      final box = e.value.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.attached) _dy[e.key] = box.localToGlobal(Offset.zero, ancestor: column).dy;
    }
    final cur = widget.state.position.beat;
    final dy = _dy[cur];
    if (dy == null) return;
    final target = _areaHeight * widget.anchor - _lineHeight * 0.5 - dy;
    _needsMeasure = false;
    if (!_measured || widget.style.reduceMotion || !widget.style.glide) {
      setState(() {
        _from = _to = target;
        _measured = true;
      });
      return;
    }
    if ((target - _to).abs() < 0.5) return;
    _from = _translate;
    _to = target;
    // Manual advances use the shorter "shift" motion; auto-advance glides.
    _glide.duration = Motion.glide;
    _glide.forward(from: 0);
  }

  double get _lineHeight => widget.fontSize * 1.34;

  @override
  Widget build(BuildContext context) {
    final o = context.overlayPalette;
    final s = widget.state;
    final flat = s.flat;
    if (flat == null) return const SizedBox.shrink();
    if (_needsMeasure) SchedulerBinding.instance.addPostFrameCallback((_) => _measure());

    final text = ReadingType.live(widget.fontSize, lineHeight: _lineHeight);
    final gap = widget.fontSize * 0.46;
    final (before, after) = widget.style.window;
    final cur = s.position.beat;

    return LayoutBuilder(
      builder: (context, c) {
        if (_areaHeight != c.maxHeight) {
          _areaHeight = c.maxHeight;
          _needsMeasure = true;
          SchedulerBinding.instance.addPostFrameCallback((_) => _measure());
        }
        final anchorY = c.maxHeight * widget.anchor;
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
                  animation: _glide,
                  builder: (context, child) => Opacity(
                    opacity: _measured ? 1 : 0,
                    child: Transform.translate(offset: Offset(0, _translate), child: child),
                  ),
                  child: RepaintBoundary(
                    child: Column(
                      key: _columnKey,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < flat.length; i++)
                          KeyedSubtree(
                            key: _key(i),
                            child: Padding(
                              padding: EdgeInsets.only(bottom: gap),
                              child: _BeatLine(
                                beat: flat.beats[i],
                                index: i,
                                current: cur,
                                spoken: i == cur ? s.position.spokenWords : 0,
                                visible: i >= cur - before && i <= cur + after,
                                style: text,
                                plate: widget.style.plate && i == cur,
                                reduceMotion: widget.style.reduceMotion,
                                palette: o,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              // The cue dot never moves — it is the eye-line.
              Positioned(
                left: Layout.overlayCueColumn,
                top: anchorY - 3,
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
              // After Dismiss: a 300 ms tungsten sweep re-anchors the eye.
              Positioned(
                left: widget.leftInset,
                right: widget.rightInset,
                top: anchorY + _lineHeight * 0.5 + 2,
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

  @override
  State<_BeatLine> createState() => _BeatLineState();
}

class _BeatLineState extends State<_BeatLine> with SingleTickerProviderStateMixin {
  late final _dim = AnimationController(vsync: this, duration: Motion.wordDim);
  late List<ScriptWord> _words = splitWords(widget.beat.beat.text);
  int _dimFrom = 0;

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
    final base = widget.style.copyWith(color: o.inkAt(_level));
    final cue = widget.beat.beat.cue;

    Widget text = AnimatedBuilder(
      animation: _dim,
      builder: (context, _) {
        final done = o.inkAt(o.readDone);
        return Text.rich(
          TextSpan(
            children: [
              if (cue != null)
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: AnimatedOpacity(
                      duration: Motion.glide,
                      opacity: widget.visible ? 1 : 0,
                      child: CueChip(cue, color: o.cue, dimmed: true),
                    ),
                  ),
                ),
              for (var i = 0; i < _words.length; i++)
                TextSpan(
                  text: _words[i].text + (i == _words.length - 1 ? '' : (_words[i].glueNext ? ' ' : ' ')),
                  style: TextStyle(
                    fontWeight: _words[i].bold ? FontWeight.w700 : null,
                    fontVariations: _words[i].bold ? const [FontVariation.weight(700)] : null,
                    color: !isCurrent
                        ? null
                        : i < _dimFrom
                        ? done
                        : i < widget.spoken
                        ? Color.lerp(o.inkAt(o.readNow), done, _dim.value)
                        : null,
                  ),
                ),
            ],
          ),
        );
      },
    );

    text = AnimatedDefaultTextStyle(
      duration: widget.reduceMotion ? Motion.reducedMotionFade : Motion.glide,
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
    return isCurrent ? RepaintBoundary(child: text) : text;
  }
}

// ─────────────────────────── Ticker ───────────────────────────

/// < 380 px: spoken words slide out to the left, so the line always starts
/// with the next word to say.
class _TickerView extends StatelessWidget {
  const _TickerView({required this.state, required this.style, required this.width});
  final LiveState state;
  final ReadingStyle style;
  final double width;

  @override
  Widget build(BuildContext context) {
    final o = context.overlayPalette;
    final flat = state.flat!;
    final beat = flat.beats[state.position.beat];
    final words = splitWords(beat.beat.text);
    final spoken = state.position.spokenWords.clamp(0, words.length);
    final size = (overlayFontSize(width, style.size) * 0.78).clamp(17.0, 24.0);
    final text = ReadingType.live(size);
    final rest = words.sublist(spoken);
    String join(List<ScriptWord> ws) =>
        [for (var i = 0; i < ws.length; i++) ws[i].text + (i == ws.length - 1 ? '' : (ws[i].glueNext ? ' ' : ' '))]
            .join();

    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 4, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: size * 0.67 - 3, right: 8),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(shape: BoxShape.circle, color: o.cue),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: style.reduceMotion ? Motion.reducedMotionFade : Motion.smooth,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0.06, 0), end: Offset.zero).animate(anim),
                  child: child,
                ),
              ),
              child: Text.rich(
                key: ValueKey('${state.position.beat}:$spoken'),
                TextSpan(
                  children: [
                    if (spoken > 0)
                      TextSpan(
                        text: '…${words[spoken - 1].text} ',
                        style: TextStyle(color: o.inkAt(o.readDone)),
                      ),
                    TextSpan(text: join(rest)),
                  ],
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: text.copyWith(color: o.ink),
              ),
            ),
          ),
        ],
      ),
    );
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
    final size = overlayFontSize(640, style.size) * 1.1;

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
                    TextSpan(
                      children: [
                        for (var i = 0; i < words.length; i++)
                          TextSpan(
                            text: words[i].text + (i == words.length - 1 ? '' : (words[i].glueNext ? ' ' : ' ')),
                            style: TextStyle(
                              color: i < spoken ? o.inkAt(o.readDone) : o.ink,
                              fontWeight: words[i].bold ? FontWeight.w700 : null,
                            ),
                          ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: ReadingType.live(size),
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
                  nextBeat.beat.text,
                  maxLines: 3,
                  style: ReadingType.live(17, lineHeight: 23).copyWith(color: o.inkAt(0.82)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

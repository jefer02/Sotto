import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import '../../l10n/l10n.dart';

import '../../core/design/icons.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../core/platform/window_service.dart';
import '../../data/models/settings.dart';
import '../../data/models/shortcut.dart';
import '../../data/repositories.dart';
import 'live_controller.dart';
import 'live_state.dart';
import 'overlay/history_panel.dart';
import 'overlay/meta_strip.dart';
import 'overlay/overlay_controls.dart';
import 'overlay/qa_views.dart';
import 'overlay/reading_view.dart';

/// The overlay: frameless, always on top, semi-transparent, draggable and
/// resizable. The only object in Sotto that floats — so the only one with a
/// real shadow (drawn by the OS around the window).
class OverlayScreen extends ConsumerStatefulWidget {
  const OverlayScreen({super.key});

  @override
  ConsumerState<OverlayScreen> createState() => _OverlayScreenState();
}

class _OverlayScreenState extends ConsumerState<OverlayScreen> with WindowListener {
  static const _historyWidth = 340.0;
  static const _metaHeight = Layout.overlayMeta;
  static const _actionsHeight = 50.0;

  bool _controlsVisible = false;
  Timer? _hoverIntent;
  Timer? _hoverHide;
  Timer? _geometryDebounce;
  DateTime _programmaticUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastWheel = DateTime.fromMillisecondsSinceEpoch(0);

  late double _readingHeight = ref.read(settingsProvider).overlaySize.$2;
  bool _widened = false;
  ResolvedLayout? _layout;
  int _layoutBeat = -1;
  bool _showClickThroughEdge = false;
  Timer? _edgeTimer;

  WindowService get _window => ref.read(windowServiceProvider);

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _hoverIntent?.cancel();
    _hoverHide?.cancel();
    _geometryDebounce?.cancel();
    _edgeTimer?.cancel();
    super.dispose();
  }

  // ─────────────────────────── Window events ───────────────────────────

  bool get _programmatic => DateTime.now().isBefore(_programmaticUntil);

  void _markProgrammatic() => _programmaticUntil = DateTime.now().add(const Duration(milliseconds: 700));

  @override
  void onWindowMoved() {
    if (_programmatic) return;
    _geometryDebounce?.cancel();
    _geometryDebounce = Timer(const Duration(milliseconds: 160), () async {
      _markProgrammatic();
      await _window.snapAfterDrag();
      await ref.read(liveControllerProvider.notifier).rememberGeometry();
    });
  }

  @override
  void onWindowResized() {
    if (_programmatic) return;
    final phase = ref.read(liveControllerProvider).phase;
    if (phase == LivePhase.answer || phase == LivePhase.drafting) return;
    _geometryDebounce?.cancel();
    _geometryDebounce = Timer(const Duration(milliseconds: 200), () async {
      final b = await _window.bounds();
      _readingHeight = b.height;
      await ref.read(liveControllerProvider.notifier).rememberGeometry();
    });
  }

  bool get _bottomDocked {
    final p = ref.read(settingsProvider).placement;
    return p == OverlayPlacement.bottomLeft || p == OverlayPlacement.bottomCenter || p == OverlayPlacement.bottomRight;
  }

  Future<void> _resizeTo(double height) async {
    _markProgrammatic();
    await _window.resizeOverlay(height, fromBottom: _bottomDocked);
  }

  /// Answers grow the window away from the camera edge, once, then shrink
  /// back on dismiss.
  void _onAnswerMeasured(double contentHeight) {
    final target = math.max(_readingHeight, _metaHeight + contentHeight + _actionsHeight + 2);
    unawaited(_resizeTo(target));
  }

  void _onPhaseChanged(LivePhase? prev, LivePhase next) {
    final wasAnswer = prev == LivePhase.answer || prev == LivePhase.drafting;
    final isAnswer = next == LivePhase.answer || next == LivePhase.drafting;
    if (wasAnswer && !isAnswer) unawaited(_resizeTo(_readingHeight));
  }

  Future<void> _onHistoryChanged(bool open) async {
    if (open == _widened) return;
    final b = await _window.bounds();
    _widened = open;
    _markProgrammatic();
    await _window.setOverlayWidth(open ? b.width + _historyWidth : math.max(300.0, b.width - _historyWidth));
  }

  void _onClickThroughChanged(bool on) {
    _edgeTimer?.cancel();
    setState(() => _showClickThroughEdge = on);
    if (on) {
      // Dotted edge for 1.2 s, then just the corner badge.
      _edgeTimer = Timer(const Duration(milliseconds: 1200), () {
        if (mounted) setState(() => _showClickThroughEdge = false);
      });
    }
  }

  // ─────────────────────────── Hover & input ───────────────────────────

  void _onEnter() {
    _hoverHide?.cancel();
    _hoverIntent?.cancel();
    _hoverIntent = Timer(Motion.hoverIntent, () {
      if (mounted) setState(() => _controlsVisible = true);
    });
  }

  void _onExit() {
    _hoverIntent?.cancel();
    _hoverHide?.cancel();
    _hoverHide = Timer(Motion.hoverHide, () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _onWheel(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final now = DateTime.now();
    if (now.difference(_lastWheel) < const Duration(milliseconds: 220)) return;
    if (e.scrollDelta.dy.abs() < 8) return;
    _lastWheel = now;
    final c = ref.read(liveControllerProvider.notifier);
    e.scrollDelta.dy > 0 ? c.nextBeat() : c.previousBeat();
  }

  Future<void> _end() => ref.read(liveControllerProvider.notifier).end();

  // ─────────────────────────── Build ───────────────────────────

  @override
  Widget build(BuildContext context) {
    ref.listen(liveControllerProvider.select((s) => s.phase), _onPhaseChanged);
    ref.listen(liveControllerProvider.select((s) => s.historyOpen), (_, open) => unawaited(_onHistoryChanged(open)));
    ref.listen(liveControllerProvider.select((s) => s.clickThrough), (_, on) => _onClickThroughChanged(on));

    final s = ref.watch(liveControllerProvider);
    final settings = ref.watch(settingsProvider);
    final o = context.overlayPalette;
    final size = MediaQuery.sizeOf(context);
    final reduceMotion = settings.reduceMotion || MediaQuery.disableAnimationsOf(context);

    // Layout switches only between beats, never mid-sentence.
    final readingWidth = s.historyOpen && _widened ? size.width - _historyWidth : size.width;
    final candidate = resolveLayout(settings.layout, Size(readingWidth, _readingHeight));
    if (_layout == null || s.position.beat != _layoutBeat || !s.following) {
      _layout = candidate;
      _layoutBeat = s.position.beat;
    }
    final layout = _layout!;

    final style = ReadingStyle(
      size: s.readingSize,
      linesShown: settings.linesShown,
      glide: settings.scrollStyle == ScrollStyle.glide,
      reduceMotion: reduceMotion,
      plate: settings.overlayOpacity < 0.7,
      wpm: settings.wordsPerMinute,
    );

    final reading = s.flat == null ? const SizedBox.shrink() : ReadingView(state: s, layout: layout, style: style);

    final Widget content = switch (s.phase) {
      LivePhase.idle || LivePhase.starting => Center(
        child: Text(context.l10n.gettingReady, style: TypeScale.caption.copyWith(color: o.inkAt(0.6))),
      ),
      LivePhase.standby || LivePhase.reading || LivePhase.paused => reading,
      LivePhase.listening => _Behind(
        script: reading,
        child: ListeningView(state: s),
      ),
      LivePhase.drafting => _Behind(
        script: reading,
        child: DraftingView(state: s),
      ),
      LivePhase.answer => AnswerView(state: s, onMeasured: _onAnswerMeasured),
    };

    final surface = ClipRRect(
      borderRadius: Radii.rXl,
      child: DecoratedBox(
        decoration: BoxDecoration(color: o.ground),
        child: Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  MetaStrip(
                    density: s.phase == LivePhase.answer ? MetaDensity.full : metaDensityFor(layout),
                    onDragStart: () => unawaited(_window.startDragging()),
                  ),
                  if (layout == ResolvedLayout.ticker && s.flat != null) _TickerProgress(state: s),
                  Expanded(
                    child: Listener(
                      onPointerSignal: _onWheel,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onPanStart: s.phase == LivePhase.answer ? null : (_) => unawaited(_window.startDragging()),
                        child: AnimatedSwitcher(
                          duration: reduceMotion ? Motion.reducedMotionFade : Motion.smooth,
                          switchInCurve: Motion.glideEnter,
                          switchOutCurve: Motion.leaveExit,
                          layoutBuilder: (current, previous) =>
                              Stack(fit: StackFit.expand, children: [...previous, ?current]),
                          child: KeyedSubtree(key: ValueKey(_phaseGroup(s.phase)), child: content),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (s.historyOpen && s.sessionId != null)
              SizedBox(
                width: _historyWidth,
                child: HistoryPanel(sessionId: s.sessionId!),
              ),
          ],
        ),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: MouseRegion(
        onEnter: (_) => _onEnter(),
        onExit: (_) => _onExit(),
        child: Stack(
          children: [
            Positioned.fill(child: surface),
            // Hairline edge + lit top edge (inset 0 1px 0 rgba(255,255,255,.05)).
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: Radii.rXl,
                    border: Border.all(color: o.edge),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              top: 0.5,
              child: IgnorePointer(child: Container(height: 1, color: o.innerHighlight)),
            ),
            if (s.phase != LivePhase.answer)
              Positioned(
                left: 0,
                right: s.historyOpen ? _historyWidth : 0,
                bottom: 10,
                child: Center(
                  child: IgnorePointer(
                    ignoring: !_controlsVisible,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 120),
                      opacity: _controlsVisible ? 1 : 0,
                      child: OverlayControls(state: s, onEnd: () => unawaited(_end())),
                    ),
                  ),
                ),
              ),
            if (s.clickThrough) ...[
              if (_showClickThroughEdge)
                Positioned.fill(
                  child: IgnorePointer(child: CustomPaint(painter: _DottedEdge(o.inkAt(0.5)))),
                ),
              Positioned(right: 10, bottom: 8, child: _ClickThroughBadge(palette: o)),
            ],
            if (!Platform.isMacOS) ..._resizeEdges(),
          ],
        ),
      ),
    );
  }

  static int _phaseGroup(LivePhase p) => switch (p) {
    LivePhase.listening => 1,
    LivePhase.drafting => 2,
    LivePhase.answer => 3,
    _ => 0,
  };

  /// Frameless windows on Windows/Linux need their own resize edges.
  List<Widget> _resizeEdges() {
    Widget edge(
      ResizeEdge e,
      MouseCursor cursor, {
      double? left,
      double? top,
      double? right,
      double? bottom,
      double? width,
      double? height,
    }) => Positioned(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      width: width,
      height: height,
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanStart: (_) => unawaited(_window.startResizing(e)),
        ),
      ),
    );
    const t = 5.0;
    return [
      edge(ResizeEdge.right, SystemMouseCursors.resizeLeftRight, right: 0, top: 16, bottom: 16, width: t),
      edge(ResizeEdge.left, SystemMouseCursors.resizeLeftRight, left: 0, top: 16, bottom: 16, width: t),
      edge(ResizeEdge.bottom, SystemMouseCursors.resizeUpDown, left: 16, right: 16, bottom: 0, height: t),
      edge(ResizeEdge.bottomRight, SystemMouseCursors.resizeDownRight, right: 0, bottom: 0, width: 14, height: 14),
      edge(ResizeEdge.bottomLeft, SystemMouseCursors.resizeDownLeft, left: 0, bottom: 0, width: 14, height: 14),
    ];
  }
}

/// While the room is being captured the script steps back: 7 % and a 3 px
/// blur, so it's there but unreadable.
class _Behind extends StatelessWidget {
  const _Behind({required this.script, required this.child});
  final Widget script;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      IgnorePointer(
        child: Opacity(
          opacity: 0.07,
          child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 3, sigmaY: 3), child: script),
        ),
      ),
      child,
    ],
  );
}

/// Ticker mode's meta shrinks to a progress hairline.
class _TickerProgress extends StatelessWidget {
  const _TickerProgress({required this.state});
  final LiveState state;

  @override
  Widget build(BuildContext context) {
    final o = context.overlayPalette;
    final total = state.flat!.length;
    final t = total <= 1 ? 1.0 : state.position.beat / (total - 1);
    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: t.clamp(0.02, 1.0),
        child: Container(height: 2, color: o.cue),
      ),
    );
  }
}

class _ClickThroughBadge extends StatelessWidget {
  const _ClickThroughBadge({required this.palette});
  final OverlayPalette palette;

  @override
  Widget build(BuildContext context) {
    final o = palette;
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: o.inkAt(0.1),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: o.inkAt(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SottoIcon(SottoIcons.cursor, size: 11, color: o.inkAt(0.75)),
          const SizedBox(width: 4),
          Text(
            LiveAction.clickThrough.title,
            style: TypeScale.micro.copyWith(color: o.inkAt(0.75), fontWeight: FontWeight.w400),
          ),
        ],
      ),
    );
  }
}

class _DottedEdge extends CustomPainter {
  _DottedEdge(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius((Offset.zero & size).deflate(1), const Radius.circular(Radii.xl)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 6) {
        canvas.drawPath(m.extractPath(d, d + 2.5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DottedEdge old) => old.color != color;
}

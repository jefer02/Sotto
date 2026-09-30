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
import '../../domain/overlay/auto_height.dart';
import '../agent/agent_controller.dart';
import '../agent/agent_view.dart';
import '../chat/chat_controller.dart';
import '../chat/chat_panel.dart';
import '../forms/autofill_controller.dart';
import '../forms/autofill_view.dart';
import '../questionnaire/questionnaire_controller.dart';
import '../questionnaire/questionnaire_view.dart';
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
  static const _chatHeight = 440.0;
  static const _panelHeight = QuestionnaireController.panelHeight;

  bool _controlsVisible = false;

  /// Text-only style: meta strip and controls appear on hover or while a
  /// shortcut is held, then fade out [_chromeLinger] later.
  bool _chromeVisible = false;
  bool _hovering = false;
  Timer? _chromeHide;
  StreamSubscription<bool>? _pings;
  static const _chromeLinger = Duration(seconds: 2);
  Timer? _hoverIntent;
  Timer? _hoverHide;
  Timer? _geometryDebounce;
  Timer? _saveDebounce;
  DateTime _programmaticUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastWheel = DateTime.fromMillisecondsSinceEpoch(0);

  late double _readingHeight = ref.read(settingsProvider).overlaySize.$2;

  /// The height the presenter chose (saved, or dragged this session): it
  /// picks the layout and places the eye-line, so neither moves while the
  /// window's height follows the text.
  late double _layoutHeight = _readingHeight;

  /// Set once the presenter drags the height: the most auto-height may use
  /// for the rest of the session.
  double? _userCap;
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
    _pings = ref.read(liveControllerProvider.notifier).chromePings.listen((down) {
      if (down) {
        _showChrome();
      } else if (!_hovering) {
        _hideChromeLater();
      }
    });
  }

  void _showChrome() {
    _chromeHide?.cancel();
    if (!_chromeVisible && mounted) setState(() => _chromeVisible = true);
  }

  void _hideChromeLater() {
    _chromeHide?.cancel();
    _chromeHide = Timer(_chromeLinger, () {
      if (mounted) setState(() => _chromeVisible = false);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _hoverIntent?.cancel();
    _hoverHide?.cancel();
    _chromeHide?.cancel();
    unawaited(_pings?.cancel());
    _geometryDebounce?.cancel();
    _saveDebounce?.cancel();
    _edgeTimer?.cancel();
    super.dispose();
  }

  // ─────────────────────────── Window events ───────────────────────────

  bool get _programmatic => DateTime.now().isBefore(_programmaticUntil);

  void _markProgrammatic() => _programmaticUntil = DateTime.now().add(const Duration(milliseconds: 700));

  /// Geometry is saved 500 ms after the last move or resize.
  static const _saveDelay = Duration(milliseconds: 500);

  void _saveGeometryLater() {
    _saveDebounce?.cancel();
    // The chosen height, not auto-height's (a resize drag has set it by now).
    _saveDebounce = Timer(
      _saveDelay,
      () => unawaited(ref.read(liveControllerProvider.notifier).rememberGeometry(height: _layoutHeight)),
    );
  }

  @override
  void onWindowMoved() {
    if (_programmatic) return;
    _geometryDebounce?.cancel();
    _geometryDebounce = Timer(const Duration(milliseconds: 160), () async {
      _markProgrammatic();
      await _window.snapAfterDrag();
    });
    _saveGeometryLater();
  }

  @override
  void onWindowResized() {
    if (_programmatic) return;
    final phase = ref.read(liveControllerProvider).phase;
    if (phase == LivePhase.answer || phase == LivePhase.drafting) return;
    _geometryDebounce?.cancel();
    _geometryDebounce = Timer(const Duration(milliseconds: 200), () async {
      final b = await _window.bounds();
      _readingHeight = _layoutHeight = b.height;
      _userCap = b.height;
    });
    _saveGeometryLater();
  }

  // The overlay is never maximised, zoomed or tiled by the OS — only the
  // presenter's own edge drag makes it big.
  @override
  void onWindowMaximize() => unawaited(_undoFill());

  @override
  void onWindowEnterFullScreen() => unawaited(_undoFill());

  Future<void> _undoFill() async {
    _saveDebounce?.cancel();
    _markProgrammatic();
    await _window.undoFill();
  }

  bool get _bottomDocked {
    final p = ref.read(settingsProvider).placement;
    return p == OverlayPlacement.bottomLeft || p == OverlayPlacement.bottomCenter || p == OverlayPlacement.bottomRight;
  }

  Future<void> _resizeTo(double height) async {
    _markProgrammatic();
    await _window.resizeOverlay(height, fromBottom: _bottomDocked);
  }

  /// Auto-height: after each advance the window is just tall enough for
  /// the lines showing (150 ms ease-out), up to the setting's share of the
  /// display or the height the presenter dragged. Only while reading —
  /// answers, chat, agent and forms size the window themselves.
  Future<void> _onFit(double area) async {
    final live = ref.read(liveControllerProvider);
    final reading =
        live.phase == LivePhase.standby || live.phase == LivePhase.reading || live.phase == LivePhase.paused;
    if (!reading ||
        ref.read(chatControllerProvider).overlayOpen ||
        ref.read(agentControllerProvider).active ||
        ref.read(questionnaireControllerProvider).active) {
      return;
    }
    final screen = await _window.displayArea();
    final target = AutoHeight.clamp(
      area + _metaHeight,
      screenHeight: screen.height,
      maxFraction: ref.read(settingsProvider).maxOverlayHeight,
      userCap: _userCap,
    );
    _readingHeight = target;
    _markProgrammatic();
    await _window.animateHeight(target, fromBottom: _bottomDocked);
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
    await _window.setOverlayWidth(
      open ? b.width + _historyWidth : math.max(OverlayGeometry.minimum.width, b.width - _historyWidth),
    );
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
    _hovering = true;
    _showChrome();
    _hoverHide?.cancel();
    _hoverIntent?.cancel();
    _hoverIntent = Timer(Motion.hoverIntent, () {
      if (mounted) setState(() => _controlsVisible = true);
    });
  }

  void _onExit() {
    _hovering = false;
    _hideChromeLater();
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
    // The chat panel needs room; the reading size comes back on close.
    ref.listen(chatControllerProvider.select((c) => c.overlayOpen), (_, open) {
      unawaited(_resizeTo(open ? math.max(_readingHeight, _chatHeight) : _readingHeight));
    });
    // So do a questionnaire's list and an agent task's steps.
    void panel(bool? was, bool open) {
      if (was == open) return;
      unawaited(_resizeTo(open ? math.max(_readingHeight, _panelHeight) : _readingHeight));
    }

    ref.listen(questionnaireControllerProvider.select((q) => q.active), panel);
    ref.listen(agentControllerProvider.select((a) => a.active), panel);

    final s = ref.watch(liveControllerProvider);
    final settings = ref.watch(settingsProvider);
    final o = context.overlayPalette;
    final size = MediaQuery.sizeOf(context);
    final reduceMotion = settings.reduceMotion || MediaQuery.disableAnimationsOf(context);

    // Layout switches only between beats, never mid-sentence.
    final readingWidth = s.historyOpen && _widened ? size.width - _historyWidth : size.width;
    final candidate = resolveLayout(settings.layout, Size(readingWidth, _layoutHeight));
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
      plate: !o.textOnly && settings.overlayOpacity < 0.7,
      wpm: settings.wordsPerMinute,
    );

    final reading = s.flat == null
        ? const SizedBox.shrink()
        : ReadingView(
            state: s,
            layout: layout,
            style: style,
            anchorOffset: (_layoutHeight - _metaHeight) * Layout.overlayAnchor,
            onFit: (h) => unawaited(_onFit(h)),
          );

    final agentActive = ref.watch(agentControllerProvider.select((a) => a.active));
    final formActive = ref.watch(questionnaireControllerProvider.select((q) => q.active));
    final autoFillOn = ref.watch(autoFillControllerProvider.select((a) => a.on || a.countdown > 0));
    final chatOpen = ref.watch(chatControllerProvider.select((c) => c.overlayOpen));
    final Widget content = formActive
        ? const QuestionnaireView()
        : agentActive
        ? const AgentView()
        : chatOpen
        ? const ChatPanel()
        : switch (s.phase) {
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

    // Text only: no ground, and the chrome fades with hover / shortcuts.
    final textOnly = o.textOnly;
    final chrome = !textOnly || _chromeVisible;
    Widget fading(Widget child) => textOnly
        ? IgnorePointer(
            ignoring: !chrome,
            child: AnimatedOpacity(
              duration: chrome ? Motion.quick : Motion.smooth,
              opacity: chrome ? 1 : 0,
              child: child,
            ),
          )
        : child;

    final surface = ClipRRect(
      borderRadius: Radii.rXl,
      child: DecoratedBox(
        decoration: BoxDecoration(color: o.ground),
        child: Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  fading(
                    MetaStrip(
                      density: s.phase == LivePhase.answer ? MetaDensity.full : metaDensityFor(layout),
                      onDragStart: () => unawaited(_window.startDragging()),
                    ),
                  ),
                  if (layout == ResolvedLayout.ticker && s.flat != null) fading(_TickerProgress(state: s)),
                  // Auto-fill's status bar stays while it's on.
                  if (autoFillOn) const Padding(padding: EdgeInsets.fromLTRB(10, 2, 10, 6), child: AutoFillBar()),
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
                          child: KeyedSubtree(
                            key: ValueKey(formActive ? 10 : (agentActive ? 9 : (chatOpen ? 8 : _phaseGroup(s.phase)))),
                            child: content,
                          ),
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
        // Text only: every glyph below carries the outline + soft shadow.
        child: DefaultTextStyle.merge(
          style: TextStyle(shadows: o.textShadows(1, true)),
          child: Stack(
            children: [
              Positioned.fill(child: surface),
              // Hairline edge + lit top edge (inset 0 1px 0 rgba(255,255,255,.05)).
              if (!textOnly)
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
              if (!textOnly)
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
                      ignoring: !(textOnly ? _chromeVisible : _controlsVisible),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 120),
                        opacity: (textOnly ? _chromeVisible : _controlsVisible) ? 1 : 0,
                        child: OverlayControls(state: s, onEnd: () => unawaited(_end())),
                      ),
                    ),
                  ),
                ),
              // Always visible while a screenshot is taken: nothing is captured silently.
              if (s.capturingScreen)
                Positioned(
                  right: 10,
                  top: 8,
                  child: _Badge(palette: o, icon: SottoIcons.display, label: context.l10n.capturingScreen, alert: true),
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
      ),
    );
  }

  static int _phaseGroup(LivePhase p) => switch (p) {
    LivePhase.listening => 1,
    LivePhase.drafting => 2,
    LivePhase.answer => 3,
    _ => 0,
  };

  /// Frameless windows on Windows/Linux need their own resize edges (every
  /// side; the top one is thin so the meta strip still drags the window).
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
      edge(ResizeEdge.top, SystemMouseCursors.resizeUpDown, left: 16, right: 16, top: 0, height: 3),
      edge(ResizeEdge.topRight, SystemMouseCursors.resizeUpRight, right: 0, top: 0, width: 10, height: 10),
      edge(ResizeEdge.topLeft, SystemMouseCursors.resizeUpLeft, left: 0, top: 0, width: 10, height: 10),
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

/// A small labelled chip on the overlay's edge (the screen-capture light).
class _Badge extends StatelessWidget {
  const _Badge({required this.palette, required this.icon, required this.label, this.alert = false});
  final OverlayPalette palette;
  final SottoIcons icon;
  final String label;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final o = palette;
    final color = alert ? o.capture : o.inkAt(0.75);
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: o.textOnly ? o.chromeGround : o.inkAt(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: alert ? o.capture.withValues(alpha: 0.6) : o.inkAt(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SottoIcon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TypeScale.micro.copyWith(color: color, fontWeight: FontWeight.w600, shadows: const []),
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

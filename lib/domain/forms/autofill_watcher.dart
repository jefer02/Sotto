import 'dart:convert';

import 'form_filler.dart';
import 'form_model.dart';

// Always-on auto-fill, the pure parts: when a page is worth a fill cycle,
// the one-at-a-time cycle queue, the scroll loop's limits and the Stop
// button's hold. The screen and the model come in from the controller.

/// The window in front, as the native side reports it.
class ForegroundWindow {
  const ForegroundWindow({required this.id, this.title = '', this.app = '', this.own = false});

  /// HWND / window number: changes when another window comes to the front.
  final String id;

  /// The window title — a browser's is the page title.
  final String title;

  /// The process / application name ("chrome", "Safari", "AcroRd32").
  final String app;

  /// One of Sotto's windows: never read, never filled.
  final bool own;

  factory ForegroundWindow.fromMap(Map<Object?, Object?> m) => ForegroundWindow(
    id: '${m['id'] ?? ''}',
    title: '${m['title'] ?? ''}'.trim(),
    app: '${m['app'] ?? ''}'.trim(),
    own: m['own'] as bool? ?? false,
  );

  static const _browsers = {
    'chrome', 'msedge', 'edge', 'microsoft edge', 'firefox', 'brave', 'opera', 'vivaldi', 'arc', 'safari', //
    'chromium', 'google chrome', 'iexplore', 'duckduckgo', 'zen', 'orion',
  };
  static const _viewers = {
    'acrord32',
    'acrobat',
    'adobe acrobat',
    'sumatrapdf',
    'preview',
    'foxitpdfreader',
    'pdfxedit',
  };

  static String _norm(String app) => app.toLowerCase().replaceAll(RegExp(r'\.(exe|app)$'), '').trim();

  /// A browser: forms may be web pages the accessibility tree barely shows.
  bool get isBrowser => _browsers.contains(_norm(app));

  /// A browser or document viewer: a questionnaire may be only pixels here
  /// (a PDF form, a canvas-drawn page), so a screenshot is worth a look.
  bool get mayShowQuestions => isBrowser || _viewers.contains(_norm(app));

  /// "Event sign-up" from "Event sign-up - Google Chrome".
  String get pageName {
    final t = title.replaceFirst(
      RegExp(
        r'\s+[-–—]\s+(Google Chrome|Microsoft​? Edge|Mozilla Firefox|Brave|Opera|Vivaldi|Safari|Chromium|Arc)$',
        caseSensitive: false,
      ),
      '',
    );
    return t.isEmpty ? app : t;
  }
}

/// What makes a page "the same page": its questions, not their answers.
abstract final class PageSignature {
  /// Fields hashed by role, label and option labels — never values, so
  /// Sotto's own typing doesn't look like a new page. With fewer than two
  /// fields (a vision-only page) the window and its title stand in.
  static String of(ForegroundWindow w, List<FormField> fields) {
    if (fields.length < 2) return 'w:${w.id}|${w.title}|${fields.map(_field).join()}';
    return 'f:${w.id}|${_hash(fields.map(_field).join('\n'))}';
  }

  static String _field(FormField f) =>
      '${f.role.name}:${OptionMatcher.fold(f.label)}[${f.options.map((o) => OptionMatcher.fold(o.label)).join('|')}]';

  /// FNV-1a, 64-bit folded to hex: cheap and stable across runs.
  static String _hash(String s) {
    var h = 0xcbf29ce484222325;
    for (final b in utf8.encode(s)) {
      h ^= b;
      h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return h.toRadixString(16);
  }
}

enum AutoFillStatus { off, watching, filling, paused }

enum WatchDecision {
  /// Nothing new.
  none,

  /// Start a fill cycle for this page now.
  start,

  /// A cycle is running; this page is next (at most one waits).
  queued,
}

/// The watcher's state machine. The controller polls the foreground window
/// every 1.5 s and feeds [observe]; a new page starts a cycle, one page at
/// most waits while a cycle runs, and a page that was already handled is
/// never filled twice.
class AutoFillWatcher {
  AutoFillStatus _status = AutoFillStatus.off;
  AutoFillStatus get status => _status;

  String? _handled;
  String? _current;
  String? _queued;
  bool _pauseAfterCycle = false;

  String? get queued => _queued;

  void enable() {
    _status = AutoFillStatus.watching;
    _handled = _current = _queued = null;
    _pauseAfterCycle = false;
  }

  void disable() {
    _status = AutoFillStatus.off;
    _afterManual = null;
    _current = _queued = null;
    _pauseAfterCycle = false;
  }

  /// A running cycle finishes first; then the watcher rests.
  void pause() {
    if (_status == AutoFillStatus.filling) {
      _pauseAfterCycle = true;
      _queued = null;
    } else if (_status == AutoFillStatus.watching) {
      _status = AutoFillStatus.paused;
    }
  }

  void resume() {
    _pauseAfterCycle = false;
    if (_status == AutoFillStatus.paused) _status = AutoFillStatus.watching;
  }

  /// The emergency stop: the cycle was cancelled; rest at once.
  void emergencyStop() {
    if (_status == AutoFillStatus.off) return;
    // A manual fill with auto-fill off stays off.
    _status = _afterManual == AutoFillStatus.off ? AutoFillStatus.off : AutoFillStatus.paused;
    _afterManual = null;
    _queued = null;
    _pauseAfterCycle = false;
  }

  /// One poll. [eligible]: the page has fields, or may show questions only
  /// as pixels (a browser, a PDF viewer).
  WatchDecision observe(ForegroundWindow w, String page, {required bool eligible}) {
    if (_status == AutoFillStatus.off || _status == AutoFillStatus.paused) return WatchDecision.none;
    if (w.own || !eligible) return WatchDecision.none;
    if (_status == AutoFillStatus.filling) {
      if (page == _current || page == _queued || page == _handled || _pauseAfterCycle) return WatchDecision.none;
      _queued = page;
      return WatchDecision.queued;
    }
    if (page == _handled) return WatchDecision.none;
    _status = AutoFillStatus.filling;
    _current = page;
    return WatchDecision.start;
  }

  /// What a manual fill goes back to (auto-fill may be off or paused).
  AutoFillStatus? _afterManual;

  /// A manual "fill now" runs through the same queue — whether auto-fill is
  /// on, paused or off — and leaves it as it was.
  bool startManual(String page) {
    if (_status == AutoFillStatus.filling) return false;
    _afterManual = _status == AutoFillStatus.watching ? null : _status;
    _current = page;
    _status = AutoFillStatus.filling;
    return true;
  }

  /// The cycle ended on [endPage] (it may have moved to later pages): that
  /// page counts as handled. True when a page was queued meanwhile — the
  /// caller looks again at once (the queued page may have changed since).
  bool cycleFinished(String? endPage) {
    _handled = endPage ?? _current;
    _current = null;
    final queued = _queued != null && _queued != _handled;
    _queued = null;
    final back = _afterManual;
    _afterManual = null;
    if (back != null && _status == AutoFillStatus.filling) _status = back;
    if (_status == AutoFillStatus.off) return false;
    if (_status == AutoFillStatus.paused || _pauseAfterCycle) {
      _pauseAfterCycle = false;
      _status = AutoFillStatus.paused;
      return false;
    }
    _status = AutoFillStatus.watching;
    return queued;
  }
}

/// Scrolling to find more questions on one page: at most [limit] scrolls,
/// and never once a scroll turned up nothing new, the page can't scroll
/// further, or Submit is in view.
class ScrollLoop {
  ScrollLoop({this.enabled = true, this.limit = 10});

  final bool enabled;
  final int limit;
  int _scrolls = 0;
  int get scrolls => _scrolls;

  bool shouldScroll({required bool newFieldsSinceLastScroll, required bool atSubmit, bool? canScrollMore}) {
    if (!enabled || atSubmit || canScrollMore == false || _scrolls >= limit) return false;
    if (_scrolls > 0 && !newFieldsSinceLastScroll) return false;
    _scrolls++;
    return true;
  }

  /// A new page starts with a fresh count.
  void reset() => _scrolls = 0;
}

/// "Stop" turns auto-fill off only after a one-second hold — a brush of the
/// button does nothing. [progress] drives the countdown on the button.
class HoldToConfirm {
  HoldToConfirm({this.hold = const Duration(seconds: 1)});

  final Duration hold;
  DateTime? _down;

  bool get holding => _down != null;

  void press(DateTime at) => _down = at;

  /// 0…1 of the hold done.
  double progress(DateTime at) {
    final d = _down;
    if (d == null) return 0;
    return (at.difference(d).inMilliseconds / hold.inMilliseconds).clamp(0.0, 1.0);
  }

  /// True when the hold lasted long enough.
  bool release(DateTime at) {
    final done = progress(at) >= 1;
    _down = null;
    return done;
  }

  void cancel() => _down = null;
}

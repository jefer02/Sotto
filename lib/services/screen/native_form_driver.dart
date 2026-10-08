import 'dart:io';
import 'dart:ui' show Offset;

import '../../data/models/session_record.dart';
import '../../domain/agent/coordinates.dart';
import '../../domain/agent/safety.dart';
import '../../domain/forms/form_model.dart';
import '../../domain/forms/form_runner.dart';
import '../agent/input_service.dart';
import 'bridge_protocol.dart';
import 'browser_bridge.dart';
import 'form_access.dart';
import 'form_sources.dart';
import 'screen_service.dart';

/// The real [FormDriver]. Pages are read in [FormSources] order: the
/// browser extension ([BrowserBridge]) when the window in front is a browser
/// whose extension is connected, else the accessibility tree through
/// [FormAccessService] (UI Automation / AX), else nothing — and the
/// screenshot of the foreground window's display does the work, with
/// synthetic input for visual-only fields (SendInput on Windows, CGEvent on
/// macOS). Points arrive in physical pixels; macOS input takes points, so
/// they are divided by the captured display's scale.
///
/// Fields read through the extension (`ext:…` ids) are filled through it
/// too. Every read and action is kept in [actions] for the session record.
class NativeFormDriver implements FormDriver {
  NativeFormDriver({required this.screen, required this.forms, required this.input, this.bridge});

  final ScreenService screen;
  final FormAccessService forms;
  final InputService input;
  final BrowserBridge? bridge;
  CoordinateMapper? _mapper;

  /// The browser the last extension read came from.
  BrowserKind? _browser;

  /// Labels of the last read's elements, for the log.
  Map<String, UiElement> _elements = const {};

  /// Where the last read came from.
  FormSource source = FormSource.vision;

  /// Every read and action of this fill, oldest first.
  final actions = <FormActionRecord>[];

  /// The one screenshot this driver may hold: released before the next
  /// capture and when the fill ends.
  ScreenFrame? _frame;

  static bool _isExt(String id) => BridgeSchema.isElementId(id);

  Offset _native(Offset physical) => Platform.isMacOS && _mapper != null ? _mapper!.toLogical(physical) : physical;

  void _log(String op, String via, {String target = '', bool ok = true}) =>
      actions.add(FormActionRecord(op: op, via: via, target: target, ok: ok, at: DateTime.now()));

  @override
  Future<ScreenFrame> capture() async {
    _frame?.release();
    _frame = null;
    // The JPEG bytes live only in this call: the frame keeps the data URL.
    final shot = await screen.capture(target: CaptureTarget.foregroundDisplay);
    final mapper = _mapper = CoordinateMapper(
      imageWidth: shot.width,
      imageHeight: shot.height,
      screen: shot.screen,
      scale: shot.scale,
    );
    return _frame = ScreenFrame(shot.dataUrl, mapper);
  }

  /// A tree that can't be read (some browsers, canvas-drawn forms) is an
  /// empty one: the screenshot takes over. Only "it's Sotto's own window"
  /// and a missing permission stop the run.
  @override
  Future<FormSnapshot> read() async {
    final b = bridge;
    BrowserKind? browser;
    var title = '';
    var origin = '';
    if (b != null && b.connected.isNotEmpty) {
      final w = await forms.foreground();
      if (w != null && !w.own) {
        browser = BrowserKind.ofApp(w.app);
        title = w.pageName;
      }
    }
    final read = await FormSources.read(
      extension: browser == null || !b!.isConnected(browser)
          ? null
          : () async {
              final page = await b.read(browser!, title: title);
              if (page == null) return null;
              origin = page.origin;
              return FormSnapshot.fromElements(page.elements);
            },
      accessibility: forms.snapshot,
    );
    source = read.source;
    _browser = read.source == FormSource.extension ? browser : null;
    _elements = read.snapshot.elements;
    _log('read', read.source.name, target: origin);
    return read.snapshot;
  }

  /// Lets go of the last screenshot.
  Future<void> close() async {
    _frame?.release();
    _frame = null;
  }

  Future<bool> _act(String op, String id, Future<bool> Function() viaTree, [Object? arg]) async {
    final ext = _isExt(id);
    final browser = _browser;
    final ok = ext ? browser != null && bridge != null && await bridge!.act(browser, id, op, arg) : await viaTree();
    _log(
      op,
      ext ? FormSource.extension.name : FormSource.accessibility.name,
      target: _elements[id]?.name ?? '',
      ok: ok,
    );
    return ok;
  }

  @override
  Future<bool> setValue(String elementId, String text) =>
      _act('value', elementId, () => forms.setValue(elementId, text), text);

  @override
  Future<bool> select(String elementId) => _act('select', elementId, () => forms.select(elementId));

  @override
  Future<bool> toggle(String elementId, bool on) => _act('toggle', elementId, () => forms.toggle(elementId, on), on);

  @override
  Future<bool> choose(String elementId, String label) =>
      _act('choose', elementId, () => forms.choose(elementId, label), label);

  @override
  Future<bool> invoke(String elementId) => _act('invoke', elementId, () => forms.invoke(elementId));

  @override
  bool get canInput => InputService.supported;

  @override
  Future<void> click(Offset physical) {
    _log('click', 'input');
    final p = _native(physical);
    return input.click(p.dx, p.dy);
  }

  /// Cmd+A on macOS; the Windows side maps "cmd" to Ctrl.
  @override
  Future<void> selectAll() => input.keys(['cmd', 'a']);

  @override
  Future<void> typeKeys(String text, Duration interval) async {
    _log('type', 'input');
    // One Unicode key event per character (surrogate pairs stay together).
    for (final rune in text.runes) {
      await input.type(String.fromCharCode(rune));
      if (interval > Duration.zero) await Future<void>.delayed(interval);
    }
  }

  @override
  Future<void> pressKey(String key) => input.keys([key]);

  @override
  Future<void> scroll(Offset physical, int notches) {
    final p = _native(physical);
    return input.scroll(0, notches, x: p.dx, y: p.dy);
  }

  @override
  Future<void> drag(Offset from, Offset to) {
    final a = _native(from), b = _native(to);
    return input.drag(a.dx, a.dy, b.dx, b.dy);
  }

  @override
  Future<bool?> canScrollDown() => forms.canScrollDown();

  @override
  Future<FocusInfo?> focused() => input.focused();

  @override
  Future<void> pause(Duration d) => Future<void>.delayed(d);
}

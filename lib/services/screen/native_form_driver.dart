import 'dart:io';
import 'dart:ui' show Offset;

import '../../domain/agent/coordinates.dart';
import '../../domain/agent/safety.dart';
import '../../domain/forms/form_model.dart';
import '../../domain/forms/form_runner.dart';
import '../agent/input_service.dart';
import 'form_access.dart';
import 'screen_service.dart';

/// The real [FormDriver]: the accessibility tree through [FormAccessService]
/// (UI Automation / AX), screenshots of the foreground window's display,
/// and synthetic input for visual-only fields — SendInput on Windows,
/// CGEvent on macOS. Points arrive in physical pixels; macOS input takes
/// points, so they are divided by the captured display's scale.
class NativeFormDriver implements FormDriver {
  NativeFormDriver({required this.screen, required this.forms, required this.input});

  final ScreenService screen;
  final FormAccessService forms;
  final InputService input;
  CoordinateMapper? _mapper;

  Offset _native(Offset physical) => Platform.isMacOS && _mapper != null ? _mapper!.toLogical(physical) : physical;

  @override
  Future<ScreenFrame> capture() async {
    final shot = await screen.capture(target: CaptureTarget.foregroundDisplay);
    final mapper = _mapper = CoordinateMapper(
      imageWidth: shot.width,
      imageHeight: shot.height,
      screen: shot.screen,
      scale: shot.scale,
    );
    return ScreenFrame(shot.dataUrl, mapper);
  }

  /// A tree that can't be read (some browsers, canvas-drawn forms) is an
  /// empty one: the screenshot takes over. Only "it's Sotto's own window"
  /// and a missing permission stop the run.
  @override
  Future<FormSnapshot> read() async {
    try {
      return await forms.snapshot();
    } on FormAccessException catch (e) {
      if (e.code == 'own_window' || e.code == 'permission_denied') rethrow;
      return const FormSnapshot(fields: []);
    }
  }

  @override
  Future<bool> setValue(String elementId, String text) => forms.setValue(elementId, text);

  @override
  Future<bool> select(String elementId) => forms.select(elementId);

  @override
  Future<bool> toggle(String elementId, bool on) => forms.toggle(elementId, on);

  @override
  Future<bool> choose(String elementId, String label) => forms.choose(elementId, label);

  @override
  Future<bool> invoke(String elementId) => forms.invoke(elementId);

  @override
  bool get canInput => InputService.supported;

  @override
  Future<void> click(Offset physical) {
    final p = _native(physical);
    return input.click(p.dx, p.dy);
  }

  /// Cmd+A on macOS; the Windows side maps "cmd" to Ctrl.
  @override
  Future<void> selectAll() => input.keys(['cmd', 'a']);

  @override
  Future<void> typeKeys(String text, Duration interval) async {
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
  Future<FocusInfo?> focused() => input.focused();

  @override
  Future<void> pause(Duration d) => Future<void>.delayed(d);
}

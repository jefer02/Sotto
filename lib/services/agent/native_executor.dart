import 'dart:io';
import 'dart:ui' show Offset;

import '../../domain/agent/agent_action.dart';
import '../../domain/agent/agent_loop.dart';
import '../../domain/agent/coordinates.dart';
import '../../domain/agent/safety.dart';
import '../screen/screen_service.dart';
import 'input_service.dart';

/// The real [AgentExecutor]: screenshots from [ScreenService], input from
/// [InputService]. Points arrive in physical pixels; macOS wants points.
class NativeAgentExecutor implements AgentExecutor {
  NativeAgentExecutor({required this.screen, required this.input, required this.target});

  final ScreenService screen;
  final InputService input;
  final CaptureTarget target;
  CoordinateMapper? _mapper;

  @override
  Future<AgentScreen> capture() async {
    final shot = await screen.capture(target: target);
    final mapper = CoordinateMapper(
      imageWidth: shot.width,
      imageHeight: shot.height,
      screen: shot.screen,
      scale: shot.scale,
    );
    _mapper = mapper;
    return AgentScreen(image: shot.dataUrl, mapper: mapper);
  }

  @override
  Future<FocusInfo?> focusedElement() => input.focused();

  Offset _native(Offset physical) => Platform.isMacOS && _mapper != null ? _mapper!.toLogical(physical) : physical;

  @override
  Future<void> perform(AgentAction action, {Offset? point}) async {
    final p = point == null ? null : _native(point);
    switch (action) {
      case ClickAction(:final button, :final clicks):
        await input.click(p!.dx, p.dy, right: button == MouseButton.right, count: clicks);
      case MoveAction():
        await input.move(p!.dx, p.dy);
      case TypeTextAction(:final text):
        await input.type(text);
      case PressKeysAction(:final keys):
        await input.keys(keys);
      case ScrollAction(:final dx, :final dy):
        await input.scroll(dx.round(), dy.round(), x: p?.dx, y: p?.dy);
      case WaitAction(:final ms):
        await Future<void>.delayed(Duration(milliseconds: ms));
      case ScreenshotAction() || DoneAction():
        break;
    }
    // Let the UI react before the next screenshot.
    if (action is! WaitAction && action is! ScreenshotAction) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
  }

  @override
  Future<void> releaseAll() => input.releaseAll();
}

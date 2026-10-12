import 'dart:convert';

/// One thing the agent asks to do, parsed from a model tool call.
/// Coordinates are in screenshot pixels until [CoordinateMapper] maps them.
sealed class AgentAction {
  const AgentAction();

  /// What the model said it is acting on ("Submit button", "Email field").
  /// Used for the confirmation line and by the safety gate.
  String get target => '';

  /// Short line for the overlay and the session log.
  String describe();

  /// Parses a tool call. Throws [FormatException] on anything malformed —
  /// the loop reports it back to the model instead of guessing.
  static AgentAction parse(String name, String arguments) {
    final Object? decoded = arguments.trim().isEmpty ? <String, Object?>{} : jsonDecode(arguments);
    if (decoded is! Map) throw const FormatException('arguments must be a JSON object');
    final a = decoded.cast<String, Object?>();
    double number(String k) {
      final v = a[k];
      if (v is num) return v.toDouble();
      throw FormatException('"$k" must be a number');
    }

    String str(String k, {bool required = true}) {
      final v = a[k];
      if (v is String) return v;
      if (!required && v == null) return '';
      throw FormatException('"$k" must be a string');
    }

    final target = str('target', required: false);
    return switch (name) {
      'click' => ClickAction(number('x'), number('y'), target: target),
      'double_click' => ClickAction(number('x'), number('y'), clicks: 2, target: target),
      'right_click' => ClickAction(number('x'), number('y'), button: MouseButton.right, target: target),
      'move_mouse' => MoveAction(number('x'), number('y'), target: target),
      'type_text' => TypeTextAction(str('text'), target: target),
      'press_keys' => PressKeysAction(switch (a['keys']) {
        final List<Object?> l => [for (final k in l) '$k'.trim().toLowerCase()],
        final String s => s.split('+').map((k) => k.trim().toLowerCase()).toList(),
        _ => throw const FormatException('"keys" must be a list of key names'),
      }, target: target),
      'scroll' => ScrollAction(
        number('dx'),
        number('dy'),
        x: (a['x'] as num?)?.toDouble(),
        y: (a['y'] as num?)?.toDouble(),
      ),
      'wait' => WaitAction(number('ms').round().clamp(0, 10000)),
      'screenshot' => const ScreenshotAction(),
      'done' => DoneAction(str('summary', required: false)),
      _ => throw FormatException('unknown tool "$name"'),
    };
  }
}

enum MouseButton { left, right }

String _at(double x, double y) => '${x.round()},${y.round()}';
String _quoted(String t) => t.isEmpty ? '' : ' “$t”';

class ClickAction extends AgentAction {
  const ClickAction(this.x, this.y, {this.button = MouseButton.left, this.clicks = 1, this.target = ''});
  final double x;
  final double y;
  final MouseButton button;
  final int clicks;
  @override
  final String target;

  @override
  String describe() {
    final verb = button == MouseButton.right ? 'Right-click' : (clicks == 2 ? 'Double-click' : 'Click');
    return '$verb${_quoted(target)} at ${_at(x, y)}';
  }
}

class MoveAction extends AgentAction {
  const MoveAction(this.x, this.y, {this.target = ''});
  final double x;
  final double y;
  @override
  final String target;

  @override
  String describe() => 'Move the pointer${_quoted(target)} to ${_at(x, y)}';
}

class TypeTextAction extends AgentAction {
  const TypeTextAction(this.text, {this.target = ''});
  final String text;
  @override
  final String target;

  @override
  String describe() {
    final shown = text.length > 60 ? '${text.substring(0, 57)}…' : text;
    return 'Type “$shown”${target.isEmpty ? '' : ' into $target'}';
  }
}

class PressKeysAction extends AgentAction {
  const PressKeysAction(this.keys, {this.target = ''});
  final List<String> keys;
  @override
  final String target;

  @override
  String describe() => 'Press ${keys.join('+')}${target.isEmpty ? '' : ' ($target)'}';
}

class ScrollAction extends AgentAction {
  const ScrollAction(this.dx, this.dy, {this.x, this.y});
  final double dx;
  final double dy;
  final double? x;
  final double? y;

  @override
  String describe() =>
      'Scroll ${dy > 0 ? 'down' : (dy < 0 ? 'up' : (dx > 0 ? 'right' : 'left'))}'
      '${x != null && y != null ? ' at ${_at(x!, y!)}' : ''}';
}

class WaitAction extends AgentAction {
  const WaitAction(this.ms);
  final int ms;

  @override
  String describe() => 'Wait ${ms}ms';
}

class ScreenshotAction extends AgentAction {
  const ScreenshotAction();

  @override
  String describe() => 'Take a new screenshot';
}

class DoneAction extends AgentAction {
  const DoneAction(this.summary);
  final String summary;

  @override
  String describe() => 'Done${summary.isEmpty ? '' : ': $summary'}';
}

/// JSON-schema function definitions for the model (OpenAI tools format).
List<Map<String, Object?>> agentToolSchemas() {
  Map<String, Object?> tool(String name, String description, Map<String, Object?> props, List<String> required) => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': {'type': 'object', 'properties': props, 'required': required},
    },
  };
  const x = {'type': 'number', 'description': 'X in screenshot pixels, from the left edge'};
  const y = {'type': 'number', 'description': 'Y in screenshot pixels, from the top edge'};
  const target = {
    'type': 'string',
    'description': 'The visible label of what you act on, e.g. "Submit button" or "Email field"',
  };
  return [
    tool(
      'click',
      'Left-click once at a point on the screenshot.',
      {'x': x, 'y': y, 'target': target},
      ['x', 'y', 'target'],
    ),
    tool('double_click', 'Double-click at a point.', {'x': x, 'y': y, 'target': target}, ['x', 'y', 'target']),
    tool('right_click', 'Right-click at a point.', {'x': x, 'y': y, 'target': target}, ['x', 'y', 'target']),
    tool('move_mouse', 'Move the pointer without clicking.', {'x': x, 'y': y, 'target': target}, ['x', 'y']),
    tool(
      'type_text',
      'Type text into the focused field. Click the field first. Never use for passwords or payment details.',
      {
        'text': {'type': 'string'},
        'target': target,
      },
      ['text', 'target'],
    ),
    tool(
      'press_keys',
      'Press a key or a combination, e.g. ["tab"], ["ctrl","a"], ["enter"].',
      {
        'keys': {
          'type': 'array',
          'items': {'type': 'string'},
        },
        'target': target,
      },
      ['keys'],
    ),
    tool(
      'scroll',
      'Scroll by dx, dy wheel notches (positive dy scrolls down), optionally at a point.',
      {
        'dx': {'type': 'number'},
        'dy': {'type': 'number'},
        'x': x,
        'y': y,
      },
      ['dx', 'dy'],
    ),
    tool(
      'wait',
      'Wait for the screen to update.',
      {
        'ms': {'type': 'number', 'description': 'Milliseconds, at most 10000'},
      },
      ['ms'],
    ),
    tool('screenshot', 'Take a fresh screenshot without acting.', {}, []),
    tool(
      'done',
      'Finish: the task is complete or cannot be done.',
      {
        'summary': {'type': 'string', 'description': 'One or two sentences on what was done'},
      },
      ['summary'],
    ),
  ];
}

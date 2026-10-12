import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/domain/agent/agent_action.dart';
import 'package:sotto/domain/agent/agent_loop.dart';
import 'package:sotto/domain/agent/coordinates.dart';
import 'package:sotto/domain/agent/safety.dart';

/// A 2560×1440 display at 150 %, left of the primary one, captured at
/// 1300×731.
const _mapper = CoordinateMapper(
  imageWidth: 1300,
  imageHeight: 731,
  screen: Rect.fromLTWH(-2560, 0, 2560, 1440),
  scale: 1.5,
);

class _FakeExecutor implements AgentExecutor {
  final performed = <(AgentAction, Offset?)>[];
  FocusInfo? focus;
  int captures = 0;
  bool released = false;

  @override
  Future<AgentScreen> capture() async {
    captures++;
    return const AgentScreen(image: 'data:image/jpeg;base64,AA==', mapper: _mapper);
  }

  @override
  Future<FocusInfo?> focusedElement() async => focus;

  @override
  Future<void> perform(AgentAction action, {Offset? point}) async => performed.add((action, point));

  @override
  Future<void> releaseAll() async => released = true;
}

/// Plays back a script of tool calls; records what it was told.
class _FakeModel implements AgentModel {
  _FakeModel(this.calls);
  final List<(String, Map<String, Object?>)> calls;
  final results = <String>[];
  var _i = 0;

  AgentTurn _turn() {
    if (_i >= calls.length) return const AgentTurn(text: 'nothing left');
    final (name, args) = calls[_i];
    return AgentTurn(
      call: AgentToolCall(id: 'c${_i++}', name: name, arguments: jsonEncode(args)),
    );
  }

  @override
  Future<AgentTurn> start(String task, AgentScreen screen) async => _turn();

  @override
  Future<AgentTurn> next({required String result, AgentScreen? screen}) async {
    results.add(result);
    return _turn();
  }
}

void main() {
  group('coordinates', () {
    test('maps screenshot pixels to physical pixels on a negative-origin display', () {
      expect(_mapper.toScreen(0, 0), const Offset(-2560, 0));
      expect(_mapper.toScreen(650, 365.5), const Offset(-1280, 720));
      // The far edge stays on this display.
      expect(_mapper.toScreen(1300, 731), const Offset(-1, 1439));
      expect(_mapper.toLogical(const Offset(-1280, 720)), const Offset(-1280 / 1.5, 480));
    });

    test('points outside the screenshot are rejected', () {
      expect(_mapper.toScreen(-1, 10), isNull);
      expect(_mapper.toScreen(10, 732), isNull);
      expect(_mapper.toScreen(double.nan, 10), isNull);
    });
  });

  group('actions', () {
    test('parse tool calls', () {
      expect(AgentAction.parse('click', '{"x":10,"y":20,"target":"OK"}'), isA<ClickAction>());
      final keys = AgentAction.parse('press_keys', '{"keys":"Ctrl + A"}') as PressKeysAction;
      expect(keys.keys, ['ctrl', 'a']);
      final dbl = AgentAction.parse('double_click', '{"x":1,"y":2}') as ClickAction;
      expect(dbl.clicks, 2);
      expect((AgentAction.parse('wait', '{"ms":99999}') as WaitAction).ms, 10000);
      expect(() => AgentAction.parse('click', '{"x":"a","y":2}'), throwsFormatException);
      expect(() => AgentAction.parse('format_disk', '{}'), throwsFormatException);
      expect(() => AgentAction.parse('click', '[1,2]'), throwsFormatException);
    });

    test('tool schemas cover every tool', () {
      final names = [for (final t in agentToolSchemas()) (t['function']! as Map)['name']];
      expect(names, [
        'click',
        'double_click',
        'right_click',
        'move_mouse',
        'type_text',
        'press_keys',
        'scroll',
        'wait',
        'screenshot',
        'done',
      ]);
    });
  });

  group('safety gate', () {
    test('never types into password fields', () {
      const type = TypeTextAction('hunter2', target: 'Name');
      expect(SafetyGate.check(type, mode: AgentMode.auto, focus: const FocusInfo(isPassword: true)), isA<Block>());
      expect(SafetyGate.check(const TypeTextAction('x', target: 'Contraseña'), mode: AgentMode.auto), isA<Block>());
    });

    test('never handles payment data', () {
      expect(SafetyGate.check(const TypeTextAction('4111 1111 1111 1111'), mode: AgentMode.auto), isA<Block>());
      expect(SafetyGate.check(const TypeTextAction('123', target: 'CVV'), mode: AgentMode.auto), isA<Block>());
      expect(
        SafetyGate.check(const TypeTextAction('12/29', target: 'Fecha de caducidad'), mode: AgentMode.auto),
        isA<Block>(),
      );
      // Ordinary numbers are fine (not Luhn-valid card numbers).
      expect(SafetyGate.looksLikeCardNumber('+34 600 123 456'), isFalse);
      expect(
        SafetyGate.check(const TypeTextAction('Ana García', target: 'Full name'), mode: AgentMode.auto),
        isA<Allow>(),
      );
    });

    test('irreversible actions need confirmation even in auto mode', () {
      for (final a in [
        const ClickAction(1, 1, target: 'Submit'),
        const ClickAction(1, 1, target: 'Enviar formulario'),
        const ClickAction(1, 1, target: 'Pay now'),
        const ClickAction(1, 1, target: 'Delete file'),
        const PressKeysAction(['enter']),
      ]) {
        final v = SafetyGate.check(a, mode: AgentMode.auto);
        expect(v, isA<Confirm>().having((c) => c.sensitive, 'sensitive', isTrue), reason: a.describe());
      }
      expect(SafetyGate.check(const ClickAction(1, 1, target: 'Email field'), mode: AgentMode.auto), isA<Allow>());
    });

    test('confirm-each mode confirms everything but done / wait / screenshot', () {
      expect(SafetyGate.check(const ClickAction(1, 1, target: 'Email'), mode: AgentMode.confirmEach), isA<Confirm>());
      expect(SafetyGate.check(const DoneAction('ok'), mode: AgentMode.confirmEach), isA<Allow>());
      expect(SafetyGate.check(const WaitAction(100), mode: AgentMode.confirmEach), isA<Allow>());
    });
  });

  group('loop', () {
    test('runs until done, mapping every point to the real screen', () async {
      final exec = _FakeExecutor();
      final model = _FakeModel([
        ('click', {'x': 650, 'y': 365.5, 'target': 'Email field'}),
        ('type_text', {'text': 'ana@example.com', 'target': 'Email field'}),
        ('done', {'summary': 'Filled the email.'}),
      ]);
      final result = await AgentLoop(
        executor: exec,
        model: model,
        mode: AgentMode.auto,
        confirm: (_) async => fail('nothing here needs confirmation'),
      ).run('fill the form', AgentCancel());
      expect(result.status, AgentStatus.completed);
      expect(result.summary, 'Filled the email.');
      expect(exec.performed.first.$2, const Offset(-1280, 720));
      expect(exec.performed[1].$1, isA<TypeTextAction>());
      expect(model.results, ['ok', 'ok']);
      expect(result.log.map((e) => e.outcome), [AgentOutcome.done, AgentOutcome.done, AgentOutcome.done]);
      // A fresh screenshot after every action, plus the first one.
      expect(exec.captures, 3);
    });

    test('confirm-each asks before every action; declining stops the task', () async {
      final exec = _FakeExecutor();
      final asked = <PendingAction>[];
      final result = await AgentLoop(
        executor: exec,
        model: _FakeModel([
          ('click', {'x': 10, 'y': 10, 'target': 'Name'}),
          ('click', {'x': 20, 'y': 20, 'target': 'Submit'}),
        ]),
        confirm: (p) async {
          asked.add(p);
          return asked.length == 1;
        },
      ).run('task', AgentCancel());
      expect(asked.length, 2);
      expect(asked[1].sensitive, isTrue);
      expect(exec.performed.length, 1);
      expect(result.status, AgentStatus.declined);
      expect(result.log.last.outcome, AgentOutcome.declined);
    });

    test('auto mode still stops at a submit button', () async {
      final asked = <PendingAction>[];
      await AgentLoop(
        executor: _FakeExecutor(),
        mode: AgentMode.auto,
        model: _FakeModel([
          ('click', {'x': 10, 'y': 10, 'target': 'Name'}),
          ('click', {'x': 20, 'y': 20, 'target': 'Submit order'}),
          ('done', {'summary': ''}),
        ]),
        confirm: (p) async {
          asked.add(p);
          return true;
        },
      ).run('task', AgentCancel());
      expect(asked.map((p) => p.action.target), ['Submit order']);
    });

    test('a password field blocks typing and the model is told', () async {
      final exec = _FakeExecutor()..focus = const FocusInfo(isPassword: true);
      final model = _FakeModel([
        ('type_text', {'text': 'secret', 'target': 'Field'}),
        ('done', {'summary': 'gave up'}),
      ]);
      final result = await AgentLoop(
        executor: exec,
        model: model,
        mode: AgentMode.auto,
        confirm: (_) async => true,
      ).run('log in', AgentCancel());
      expect(exec.performed, isEmpty);
      expect(model.results.single, startsWith('BLOCKED'));
      expect(result.log.first.outcome, AgentOutcome.blocked);
    });

    test('points outside the screenshot are reported, not clicked', () async {
      final exec = _FakeExecutor();
      final model = _FakeModel([
        ('click', {'x': 5000, 'y': 10, 'target': 'Far away'}),
        ('done', {'summary': ''}),
      ]);
      await AgentLoop(
        executor: exec,
        model: model,
        mode: AgentMode.auto,
        confirm: (_) async => true,
      ).run('task', AgentCancel());
      expect(exec.performed, isEmpty);
      expect(model.results.single, contains('outside'));
    });

    test('stops after 25 model turns', () async {
      final exec = _FakeExecutor();
      final result = await AgentLoop(
        executor: exec,
        model: _FakeModel([
          for (var i = 0; i < 100; i++) ('wait', {'ms': 0}),
        ]),
        confirm: (_) async => true,
      ).run('never ends', AgentCancel());
      expect(result.status, AgentStatus.limit);
      expect(result.steps, 25);
      expect(exec.performed.length, 25);
    });

    test('the emergency stop cancels a pending confirmation immediately', () async {
      final exec = _FakeExecutor();
      final cancel = AgentCancel();
      final waiting = Completer<bool>(); // never completed by the "presenter"
      final run = AgentLoop(
        executor: exec,
        model: _FakeModel([
          ('click', {'x': 1, 'y': 1, 'target': 'Next'}),
        ]),
        confirm: (_) {
          scheduleMicrotask(cancel.cancel);
          return waiting.future;
        },
      ).run('task', cancel);
      final result = await run.timeout(const Duration(seconds: 1));
      expect(result.status, AgentStatus.stopped);
      expect(exec.performed, isEmpty);
      expect(exec.released, isTrue);
    });

    test('malformed tool calls are sent back as errors', () async {
      final model = _FakeModel([
        ('click', {'x': 'left'}),
        ('done', {'summary': ''}),
      ]);
      await AgentLoop(executor: _FakeExecutor(), model: model, confirm: (_) async => true).run('t', AgentCancel());
      expect(model.results.single, startsWith('ERROR'));
    });
  });
}

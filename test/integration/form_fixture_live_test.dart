// The real FormRunner against a real browser showing a page from
// test/fixtures/forms, through a small native probe that calls the same
// UI Automation code Sotto uses (windows/runner/native/forms.cpp). The model
// is replaced by fixed answers per question, so this measures the tree: what
// gets filled through it, what falls back to the screen, how many model
// calls a fill makes. Windows only, opt-in:
//
//   SOTTO_PROBE=<path to probe.exe> SOTTO_PROBE_WINDOW="long page&Edge" \
//   SOTTO_PROBE_OUT=build/forms-live.txt flutter test test/integration/form_fixture_live_test.dart
//
// SOTTO_PROBE_WINDOW: parts of the window title, '&'-separated.
// SOTTO_PROBE_SCREEN: the display in physical pixels, default 1920x1080.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/domain/agent/coordinates.dart';
import 'package:sotto/domain/agent/safety.dart';
import 'package:sotto/domain/forms/form_filler.dart';
import 'package:sotto/domain/forms/form_model.dart';
import 'package:sotto/domain/forms/form_runner.dart';

final _env = Platform.environment;
final _probe = _env['SOTTO_PROBE'];
final _window = _env['SOTTO_PROBE_WINDOW'] ?? 'Sotto form fixture';
final _screen = () {
  final m = RegExp(r'^(\d+)x(\d+)$').firstMatch(_env['SOTTO_PROBE_SCREEN'] ?? '');
  return m == null
      ? const Rect.fromLTWH(0, 0, 1920, 1080)
      : Rect.fromLTWH(0, 0, double.parse(m[1]!), double.parse(m[2]!));
}();

/// What the presenter's instructions answer, by a word of each question.
const _answers = <String, String>{
  'full name': 'Ana Ruiz',
  'city': 'Santo Domingo',
  'email': 'ana@example.com',
  'improve': 'Faster exports',
  'how often': 'Weekly',
  'features': 'Teleprompter, Answers',
  'role': 'Designer',
  'newsletter': 'no',
  'country': 'Dominican Republic',
  'recommend': '9',
  'satisfaction': '4',
  'presenting': '6',
  'language': 'Spanish',
  // scroll-container.html
  'name': 'Ana Ruiz',
  'session': 'Afternoon',
  'dietary': 'Vegetarian',
  'anything we should know': 'Arriving a bit late',
};

class ProbeDriver implements FormDriver {
  final calls = <String, int>{};
  final dir = Directory.systemTemp.createTempSync('sotto_probe');
  var _n = 0;

  Future<String> _exec(String command) async {
    calls.update(command.split(' ').first, (n) => n + 1, ifAbsent: () => 1);
    final cmd = File('${dir.path}/c${_n++}.txt')..writeAsStringSync('$command\n');
    final out = File('${cmd.path}.out');
    await Process.run(_probe!, ['exec', _window, cmd.path, out.path]);
    final line = out.readAsLinesSync().skip(1).firstOrNull ?? '';
    final i = line.indexOf(' => ');
    return i < 0 ? '' : line.substring(i + 4).replaceFirst(RegExp(r' \(\d+ms\)$'), '');
  }

  Future<bool> _ok(String command) async => await _exec(command) == 'true';

  late final mapper = CoordinateMapper(
    imageWidth: (_screen.width / 1.5).round(),
    imageHeight: (_screen.height / 1.5).round(),
    screen: _screen,
    scale: 1,
  );

  @override
  Future<ScreenFrame> capture() async => ScreenFrame('data:image/jpeg;base64,', mapper);

  @override
  Future<FormSnapshot> read() async {
    calls.update('read', (n) => n + 1, ifAbsent: () => 1);
    final f = File('${dir.path}/r${_n++}.json');
    await Process.run(_probe!, ['read', _window, f.path]);
    final j = jsonDecode(f.readAsStringSync()) as Map<String, Object?>;
    return FormSnapshot.fromElements([
      for (final m in (j['elements']! as List).whereType<Map<Object?, Object?>>()) UiElement.fromMap(m),
    ]);
  }

  @override
  Future<bool> setValue(String id, String text) => _ok('setValue $id $text');
  @override
  Future<bool> select(String id) => _ok('select $id');
  @override
  Future<bool> toggle(String id, bool on) => _ok('toggle $id ${on ? 1 : 0}');
  @override
  Future<bool> choose(String id, String label) => _ok('choose $id $label');
  @override
  Future<bool> invoke(String id) => _ok('invoke $id');
  @override
  Future<bool> setRange(String id, double value) => _ok('setRange $id $value');
  @override
  Future<bool> focusElement(String id) => _ok('focus $id');
  @override
  Future<ElementState?> state(String id) async {
    final r = await _exec('state $id');
    if (!r.startsWith('{')) return null;
    return ElementState.fromMap(jsonDecode(r) as Map<Object?, Object?>);
  }

  @override
  bool get canInput => true;
  @override
  Future<void> click(Offset p) => _exec('click ${p.dx.round()},${p.dy.round()}');
  @override
  Future<void> selectAll() => _exec('key ctrl+a');
  @override
  Future<void> typeKeys(String text, Duration interval) => _exec('type - $text');
  @override
  Future<void> pressKey(String key) => _exec('key $key');
  @override
  Future<void> scroll(Offset p, int notches) => _exec('wheel ${p.dx.round()},${p.dy.round()}');
  @override
  Future<void> scrollDown({String? anchor, required Offset fallback}) async {
    final r = double.tryParse(await _exec('scrollDown ${anchor ?? '-'}')) ?? -1;
    if (r < 0) await scroll(fallback, 5);
  }

  @override
  Future<void> drag(Offset from, Offset to) async {}
  @override
  Future<bool?> canScrollDown({String? anchor}) async => switch (await _exec('canScroll ${anchor ?? '-'}')) {
    '1' => true,
    '0' => false,
    _ => null,
  };
  @override
  Future<FocusInfo?> focused() async => null;
  @override
  Future<void> pause(Duration d) => Future<void>.delayed(d);
}

/// Answers the fields it's given from [_answers], by their labels; sees
/// nothing on the (empty) screenshot.
class ScriptedVision implements FormVision {
  final asked = <List<String>>[];

  @override
  Future<FormReply> answer(ScreenFrame frame, Map<String, FormField> ids) async {
    asked.add([for (final f in ids.values) f.label]);
    final answers = <FieldAnswer>[];
    for (final MapEntry(key: id, value: f) in ids.entries) {
      final label = f.label.toLowerCase();
      final hit = _answers.entries.where((e) => label.contains(e.key)).firstOrNull;
      if (hit == null) continue;
      answers.add(
        FieldAnswer(
          fieldId: id,
          question: f.label,
          answer: f.role == FieldRole.checkboxes ? '' : hit.value,
          choices: f.role == FieldRole.checkboxes ? hit.value.split(', ') : const [],
          confidence: 0.9,
        ),
      );
    }
    return FormReply(answers);
  }

  @override
  Future<Offset?> locateOption(ScreenFrame frame, String label) async => null;

  @override
  Future<Map<int, String>> readValues(ScreenFrame frame, List<VisualCheck> checks) async => const {};
}

class _Host implements FormRunHost, FormRunTexts {
  @override
  bool get cancelled => false;
  @override
  void phase(FormPhase phase, {int? page, String? label}) {}
  @override
  void planned(FillPlan plan) {}
  @override
  void progress(int step, ItemStatus status, {String? note}) {}
  @override
  Future<bool> confirm(FormPhase phase, {String? label}) async => false;
  @override
  FillPlan edited(FillPlan plan, Map<String, FormField> ids, Offset? Function(Offset) toScreen) => plan;
  @override
  String couldNotFill() => 'could not fill';
  @override
  String blocked(SafetyReason reason) => 'blocked: ${reason.name}';
  @override
  String skipped(SkipReason reason) => 'skipped: ${reason.name}';
}

void main() {
  test('fill a fixture page through the tree', skip: _probe == null || !Platform.isWindows, () async {
    final driver = ProbeDriver();
    final vision = ScriptedVision();
    final first = await driver.read();
    final runner = FormRunner(driver: driver, vision: vision, host: _Host(), texts: _Host(), auto: true);
    final watch = Stopwatch()..start();
    final result = await runner.run();
    watch.stop();

    final out = StringBuffer()
      ..writeln('window: $_window')
      ..writeln('outcome: ${result.outcome}, ${watch.elapsed.inSeconds} s')
      ..writeln('model calls: ${runner.modelCalls} (answer ${vision.asked.length})')
      ..writeln(
        'asked: ${[for (final a in vision.asked) a.length]} fields per answer call; second+: ${vision.asked.skip(1).toList()}',
      )
      ..writeln('probe calls: ${driver.calls}')
      ..writeln()
      ..writeln('fields on the first read:');
    for (final f in first.fields) {
      out.writeln(
        '  ${f.role.name.padRight(10)} ${f.access.name.padRight(10)} '
        '${f.offscreen ? 'offscreen' : 'on screen'} ${f.sensitive ? 'SENSITIVE ' : ''}"${f.label}"',
      );
    }
    out
      ..writeln()
      ..writeln('results:');
    for (final f in result.fields) {
      out.writeln(
        '  ${f.status.name.padRight(8)} ${f.visual ? 'screen' : 'tree  '} "${f.question}" = "${f.answer}" ${f.note}',
      );
    }
    final path = _env['SOTTO_PROBE_OUT'];
    if (path != null) File(path).writeAsStringSync(out.toString());
    // ignore: avoid_print
    print(out);
  }, timeout: const Timeout(Duration(minutes: 10)));
}

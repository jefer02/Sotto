// Renders the App Lock's unlock screen to PNG for visual review, in both
// languages and both themes. Opt-in, like the other renders:
//   $env:SOTTO_RENDER=1; flutter test --no-pub test/visual/unlock_render_test.dart
// SOTTO_RENDER_OUT=folder (default build/unlock). Files are named
// <lang>-<theme>-<state>.png.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/app/standalone_app.dart';
import 'package:sotto/app/unlock_screen.dart';
import 'package:sotto/data/lock/recovery_key.dart';
import 'package:sotto/data/models/settings.dart';

import '../widgets/unlock_screen_test.dart' show FakeGate;

final _render = Platform.environment['SOTTO_RENDER'] != null;
final _out = Platform.environment['SOTTO_RENDER_OUT'] ?? 'build/unlock';

Future<void> _loadFonts() async {
  for (final (family, file) in const [
    ('Geist', 'assets/fonts/Geist-Variable.ttf'),
    ('GeistMono', 'assets/fonts/GeistMono-Variable.ttf'),
  ]) {
    final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(File(file).readAsBytesSync())));
    await loader.load();
  }
}

void main() {
  for (final lang in [AppLanguage.en, AppLanguage.es]) {
    for (final theme in [AppThemeMode.dark, AppThemeMode.light]) {
      final tag = '${lang.name}-${theme.name}';
      testWidgets('unlock screen $tag', skip: !_render, (tester) async {
        await tester.runAsync(_loadFonts);
        tester.view.physicalSize = const Size(1280, 820);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final key = GlobalKey();

        Future<void> open(FakeGate gate) async {
          await tester.pumpWidget(
            RepaintBoundary(
              key: key,
              child: StandaloneApp(
                settings: AppSettings(uiLanguage: lang, appTheme: theme, reduceMotion: true),
                home: UnlockScreen(key: UniqueKey(), gate: gate),
              ),
            ),
          );
          await tester.pump();
        }

        Future<void> shot(String name) async {
          // One frame starts the animations, the next one sees them end.
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          await tester.runAsync(() async {
            final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
            final image = await boundary.toImage();
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            File('$_out/$tag-$name.png')
              ..createSync(recursive: true)
              ..writeAsBytesSync(png!.buffer.asUint8List());
          });
        }

        Future<void> type(String text) async {
          await tester.enterText(find.byType(TextField).first, text);
          await tester.pump();
        }

        Future<void> press(String label) async {
          await tester.tap(find.text(label));
          await tester.pump();
          await tester.pump();
        }

        final es = lang == AppLanguage.es;

        await open(FakeGate());
        await shot('1-initial');

        await type('correct horse battery');
        await shot('2-typing');

        await open(FakeGate()..biometricMethod = 'Windows Hello');
        await shot('3-biometrics');

        await type('wrong guess');
        await press(es ? 'Desbloquear' : 'Unlock');
        await shot('4-error');

        await open(FakeGate()..throttleRemaining = const Duration(minutes: 4, seconds: 32));
        await shot('5-throttled');

        await open(FakeGate());
        await tester.sendKeyEvent(LogicalKeyboardKey.capsLock);
        await type('Password');
        await shot('6-caps-lock');
        await tester.sendKeyEvent(LogicalKeyboardKey.capsLock);

        final (_, key28) = RecoveryKey.generate();
        await open(FakeGate()..recovery = key28);
        await press(es ? '¿Has olvidado la contraseña?' : 'Forgot password?');
        await type(key28);
        await shot('7-recovery');

        await press(es ? 'Continuar' : 'Continue');
        await type('lantern velvet orchard');
        await shot('8-new-password');

        await open(FakeGate());
        await press(es ? '¿Has olvidado la contraseña?' : 'Forgot password?');
        await press(es ? 'Restablecer Sotto' : 'Reset Sotto');
        await shot('9-reset');

        await open(FakeGate()..vaultDamaged = true);
        await shot('10-damaged');
      });
    }
  }
}

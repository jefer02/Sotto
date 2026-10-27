// The App Lock's unlock screen: every state it can be in, driven through a
// fake gate (no vault, no Hive).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/app/app_session.dart';
import 'package:sotto/app/standalone_app.dart';
import 'package:sotto/app/unlock_screen.dart';
import 'package:sotto/core/widgets/password_field.dart';
import 'package:sotto/data/lock/recovery_key.dart';
import 'package:sotto/data/models/settings.dart';

class FakeGate implements UnlockGate {
  @override
  Duration throttleRemaining = Duration.zero;
  @override
  bool vaultDamaged = false;
  @override
  String? biometricMethod;

  final passwords = <String>[];
  final recoveryKeys = <String>[];
  String correct = 'correct horse';
  String? recovery;
  Completer<void>? hold;
  bool biometricsOk = false;
  int biometricTries = 0;
  ({Uint8List dek, String password})? reset;
  int resets = 0;

  /// After this many wrong passwords, the next wait starts.
  int throttleAfter = 99;

  @override
  Future<UnlockResult> unlockWithPassword(String password) async {
    passwords.add(password);
    await hold?.future;
    if (password == correct) return UnlockResult.unlocked;
    if (passwords.length >= throttleAfter) throttleRemaining = const Duration(seconds: 30);
    return UnlockResult.wrong;
  }

  @override
  Future<bool> unlockWithBiometrics() async {
    biometricTries++;
    return biometricsOk;
  }

  @override
  Future<(UnlockResult, Uint8List?)> checkRecoveryKey(String key) async {
    recoveryKeys.add(key);
    return key == recovery ? (UnlockResult.unlocked, Uint8List(32)) : (UnlockResult.wrong, null);
  }

  @override
  Future<void> resetPassword(Uint8List dek, String newPassword) async => reset = (dek: dek, password: newPassword);

  @override
  Future<void> resetEverything() async => resets++;
}

void main() {
  late FakeGate gate;
  setUp(() => gate = FakeGate());

  Future<void> show(
    WidgetTester tester, {
    AppLanguage language = AppLanguage.en,
    bool still = true,
    AppThemeMode theme = AppThemeMode.dark,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1280, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      StandaloneApp(
        settings: AppSettings(uiLanguage: language, reduceMotion: still, appTheme: theme),
        home: UnlockScreen(gate: gate),
      ),
    );
    await tester.pump();
  }

  Finder passwordField() => find.byType(PasswordField);
  EditableText editable(WidgetTester t) => t.widget<EditableText>(find.byType(EditableText).first);

  Future<void> type(WidgetTester t, String text) async {
    await t.enterText(find.byType(TextField).first, text);
    await t.pump();
  }

  testWidgets('opens on Welcome back with the password field focused', (tester) async {
    await show(tester);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Your scripts are locked on this computer.'), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(find.textContaining('Use '), findsNothing, reason: 'no biometric unlock unless it is on');
    expect(editable(tester).focusNode.hasFocus, isTrue);
    expect(editable(tester).obscureText, isTrue, reason: 'masked by default');
    expect(find.bySemanticsLabel('Password'), findsWidgets);
  });

  testWidgets('the eye shows and hides what was typed', (tester) async {
    await show(tester);
    await type(tester, 'secret words');
    expect(editable(tester).obscureText, isTrue);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(editable(tester).obscureText, isFalse);
    expect(find.byTooltip('Hide password'), findsOneWidget);
    await tester.tap(find.byTooltip('Hide password'));
    await tester.pump();
    expect(editable(tester).obscureText, isTrue);
  });

  testWidgets('says when Caps Lock is on', (tester) async {
    await show(tester);
    expect(find.text('Caps Lock is on'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.capsLock);
    await tester.pump();
    expect(find.text('Caps Lock is on'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.capsLock);
    await tester.pump();
    expect(find.text('Caps Lock is on'), findsNothing);
  });

  testWidgets('Enter unlocks and clears the field', (tester) async {
    await show(tester);
    await type(tester, 'correct horse');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(gate.passwords, ['correct horse']);
    expect(editable(tester).controller.text, isEmpty);
  });

  testWidgets('while the key is derived: a spinner, no second press, no layout jump', (tester) async {
    await show(tester);
    await type(tester, 'correct horse');
    final button = find.ancestor(of: find.text('Unlock'), matching: find.byType(AnimatedContainer)).first;
    final before = tester.getRect(button);
    gate.hold = Completer();

    await tester.tap(find.text('Unlock'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.getRect(button), before);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    await tester.tap(find.text('Unlock'), warnIfMissed: false);
    await tester.pump();
    expect(gate.passwords, hasLength(1));

    gate.hold!.complete();
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a wrong password: the message, the text kept and selected', (tester) async {
    await show(tester);
    await type(tester, 'wrong guess');
    await tester.tap(find.text('Unlock'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Incorrect password'), findsOneWidget);
    await tester.pump(); // the focus comes back once the field is enabled again
    final c = editable(tester).controller;
    expect(c.text, 'wrong guess');
    expect(c.selection, const TextSelection(baseOffset: 0, extentOffset: 11));
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    expect(FocusManager.instance.primaryFocus, editable(tester).focusNode, reason: 'typing goes into the field');
    expect(tester.testTextInput.hasAnyClients, isTrue);
    final live = tester.getSemantics(find.text('Incorrect password'));
    expect(live.getSemanticsData().flagsCollection.isLiveRegion, isTrue, reason: 'announced');

    await type(tester, 'again');
    expect(find.text('Incorrect password'), findsNothing, reason: 'typing clears it');
  });

  testWidgets('the field shakes on a wrong password, and stays still under reduced motion', (tester) async {
    double offset() {
      final t = tester.widget<Transform>(find.descendant(of: passwordField(), matching: find.byType(Transform)).first);
      return t.transform.getTranslation().x;
    }

    Future<double> wrongThenPeak() async {
      await type(tester, 'nope');
      await tester.tap(find.text('Unlock'));
      await tester.pump();
      await tester.pump();
      var peak = 0.0;
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 40));
        peak = peak < offset().abs() ? offset().abs() : peak;
      }
      await tester.pump(const Duration(milliseconds: 300));
      expect(offset(), 0);
      return peak;
    }

    await show(tester, still: false);
    expect(await wrongThenPeak(), greaterThan(1));
    await show(tester, still: true);
    expect(await wrongThenPeak(), 0);
  });

  testWidgets('throttled: a countdown and the field disabled', (tester) async {
    gate.throttleRemaining = const Duration(seconds: 30);
    await show(tester);
    expect(find.text('Too many attempts. Try again in 0:30.'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);

    gate.throttleRemaining = const Duration(seconds: 29);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Too many attempts. Try again in 0:29.'), findsOneWidget);

    gate.throttleRemaining = Duration.zero;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.textContaining('Too many attempts'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    expect(FocusManager.instance.primaryFocus, editable(tester).focusNode, reason: 'ready to type again');
  });

  testWidgets('the attempt that starts a wait shows the countdown', (tester) async {
    gate.throttleAfter = 1;
    await show(tester);
    await type(tester, 'wrong');
    await tester.tap(find.text('Unlock'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Too many attempts. Try again in 0:30.'), findsOneWidget);
  });

  testWidgets('Windows Hello shows only when it is on', (tester) async {
    gate.biometricMethod = 'Windows Hello';
    await show(tester);
    expect(find.text('Use Windows Hello'), findsOneWidget);
    await tester.tap(find.text('Use Windows Hello'));
    await tester.pump();
    await tester.pump();
    expect(gate.biometricTries, 1);
    expect(find.text("Windows Hello didn't unlock Sotto — use your password."), findsOneWidget);
  });

  testWidgets('forgot password: recovery key, then a new password', (tester) async {
    final (_, key) = RecoveryKey.generate();
    gate.recovery = key;
    await show(tester);
    await tester.tap(find.text('Forgot password?'));
    await tester.pump();
    expect(find.text('Use your recovery key'), findsOneWidget);
    expect(editable(tester).focusNode.hasFocus, isTrue);

    await type(tester, 'not a key');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('A recovery key is 28 letters and numbers, in groups of four'), findsOneWidget);
    expect(gate.recoveryKeys, isEmpty, reason: 'caught before trying it');

    final (_, other) = RecoveryKey.generate();
    await type(tester, other);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump();
    expect(find.text("That recovery key doesn't match this Sotto"), findsOneWidget);

    await type(tester, key);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Choose a new password'), findsOneWidget);
    expect(find.text('Use at least 8 characters'), findsOneWidget);

    await type(tester, 'short');
    await tester.tap(find.text('Set password and unlock'));
    await tester.pump();
    expect(gate.reset, isNull, reason: 'too short');

    await type(tester, 'a much longer passphrase');
    expect(find.text('Strong'), findsOneWidget);
    await tester.tap(find.text('Set password and unlock'));
    await tester.pump();
    await tester.pump();
    expect(gate.reset?.password, 'a much longer passphrase');
  });

  testWidgets('Esc goes back from the recovery step', (tester) async {
    await show(tester);
    await tester.tap(find.text('Forgot password?'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('Reset Sotto needs the word typed', (tester) async {
    await show(tester);
    await tester.tap(find.text('Forgot password?'));
    await tester.pump();
    await tester.tap(find.text('Reset Sotto'));
    await tester.pump();
    expect(find.text('Reset Sotto?'), findsOneWidget);
    expect(find.text('Your settings and your DeepSeek key stay.'), findsOneWidget);
    await tester.tap(find.text('Delete everything and reset'));
    await tester.pump();
    expect(gate.resets, 0);
    await type(tester, 'reset');
    await tester.tap(find.text('Delete everything and reset'));
    await tester.pump();
    await tester.pump();
    expect(gate.resets, 1);
  });

  testWidgets('a damaged vault goes straight to Reset', (tester) async {
    gate.vaultDamaged = true;
    await show(tester);
    expect(find.text("Sotto's lock can't be read"), findsOneWidget);
    expect(find.text('Back'), findsNothing);
    expect(find.text('Delete everything and reset'), findsOneWidget);
  });

  testWidgets('speaks Spanish, and the reset word is BORRAR', (tester) async {
    await show(tester, language: AppLanguage.es);
    expect(find.text('Hola de nuevo'), findsOneWidget);
    expect(find.text('Desbloquear'), findsOneWidget);
    await tester.tap(find.text('¿Has olvidado la contraseña?'));
    await tester.pump();
    await tester.tap(find.text('Restablecer Sotto'));
    await tester.pump();
    await type(tester, 'borrar');
    await tester.tap(find.text('Borrar todo y restablecer'));
    await tester.pump();
    await tester.pump();
    expect(gate.resets, 1);
  });

  testWidgets('fits a small window in both themes', (tester) async {
    for (final theme in [AppThemeMode.dark, AppThemeMode.light]) {
      await tester.binding.setSurfaceSize(const Size(960, 600));
      await tester.pumpWidget(
        StandaloneApp(
          settings: AppSettings(uiLanguage: AppLanguage.es, reduceMotion: true, appTheme: theme),
          home: UnlockScreen(gate: gate..biometricMethod = 'Windows Hello'),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(PasswordField)).width, lessThanOrEqualTo(UnlockScreen.cardWidth));
    }
    await tester.binding.setSurfaceSize(null);
  });
}

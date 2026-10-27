// Settings → Privacy → App lock, and its dialogs.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:sotto/app/app_session.dart';
import 'package:sotto/app/standalone_app.dart';
import 'package:sotto/core/platform/window_service.dart';
import 'package:sotto/core/widgets/stage_transitions.dart';
import 'package:sotto/data/lock/recovery_key.dart';
import 'package:sotto/data/lock/vault.dart';
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/data/repositories.dart';
import 'package:sotto/data/storage/local_store.dart';
import 'package:sotto/data/storage/storage_paths.dart';
import 'package:sotto/features/settings/pages/app_lock_section.dart';

const _fast = KdfParams(memoryKiB: 64, iterations: 1, parallelism: 1);

class _Window implements WindowService {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late Directory dir;
  late LocalStore store;
  late AppSession session;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sotto_lock_settings');
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Future<void> open(WidgetTester tester, {required bool on, Widget? home}) async {
    await tester.runAsync(() async {
      store = await LocalStore.open(path: dir.path);
      session = AppSession(
        paths: StoragePaths.inside(dir),
        settings: SettingsStore(store.settings),
        window: _Window(),
        screens: SessionScreens(
          locked: (_) => const SizedBox(),
          migrating: (_, _) => const SizedBox(),
          failure: (_, _) => const SizedBox(),
        ),
        startApp: (_) async {},
        kdf: _fast,
      );
    });
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          appSessionProvider.overrideWithValue(session),
          lockEnabledProvider.overrideWithValue(on),
        ],
        child: StandaloneApp(
          settings: const AppSettings(uiLanguage: AppLanguage.en, reduceMotion: true),
          home: Scaffold(body: SingleChildScrollView(child: home ?? const AppLockSection())),
        ),
      ),
    );
    await tester.pump();
  }

  /// Opens [dialog] from a button and returns what it pops.
  Future<List<Object?>> launch(WidgetTester tester, Widget dialog) async {
    final popped = <Object?>[];
    await open(
      tester,
      on: true,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => popped.add(
            await showSottoDialog<Object?>(context: context, barrierDismissible: false, builder: (_) => dialog),
          ),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    return popped;
  }

  Future<void> type(WidgetTester tester, String text, {int at = 0}) async {
    await tester.enterText(find.byType(TextField).at(at), text);
    await tester.pump();
  }

  testWidgets('off: one switch and what it does', (tester) async {
    await open(tester, on: false);
    expect(find.text('App lock'), findsOneWidget);
    expect(find.text('Lock Sotto with a password'), findsOneWidget);
    expect(find.textContaining('anyone using this computer account'), findsOneWidget);
    expect(find.text('Lock now'), findsNothing);
    expect(find.text('Auto-lock'), findsNothing);
  });

  testWidgets('on: lock now (with its shortcut), auto-lock, password and recovery key', (tester) async {
    await open(tester, on: true);
    expect(find.text('Lock now'), findsNWidgets(2));
    expect(find.textContaining('Ctrl+Alt+K'), findsOneWidget);
    expect(find.text('Auto-lock'), findsOneWidget);
    expect(find.text('15 min'), findsOneWidget, reason: 'the default once the lock is on');
    expect(find.text('Change password'), findsOneWidget);
    expect(find.text('Recovery key'), findsOneWidget);
    expect(find.textContaining('Unlock with'), findsNothing, reason: 'no Windows Hello here');
    expect(find.textContaining('DeepSeek key stays in the system keychain'), findsOneWidget);
  });

  testWidgets('turning it on: a password, then the recovery key, saved before anything is encrypted', (tester) async {
    final popped = await launch(tester, Builder(builder: (_) => EnableLockDialog(session: session)));
    expect(find.text('Create a password'), findsOneWidget);
    expect(find.text('Use at least 8 characters'), findsOneWidget);

    await type(tester, 'short');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('Create a password'), findsOneWidget, reason: 'too short to continue');

    await type(tester, 'lantern velvet orchard');
    await tester.runAsync(() async {
      await tester.tap(find.text('Continue'));
      await tester.pump();
      for (var i = 0; i < 50 && find.text('Save your recovery key').evaluate().isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    expect(find.text('Save your recovery key'), findsOneWidget);
    expect(find.textContaining('OneDrive'), findsOneWidget);

    // Seven Geist Mono blocks that read back as a valid key.
    final blocks = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .where((t) => RegExp(r'^[0-9A-Z]{4}$').hasMatch(t))
        .toList();
    expect(blocks, hasLength(7));
    expect(RecoveryKey.parse(blocks.join('-')), isNotNull);

    await tester.tap(find.text('Encrypt my data'));
    await tester.pump();
    expect(popped, isEmpty, reason: 'waits for "I\'ve saved my recovery key"');

    await tester.tap(find.text("I've saved my recovery key"));
    await tester.pump();
    await tester.tap(find.text('Encrypt my data'));
    await tester.pump();
    final setup = popped.single as VaultSetup;
    expect(setup.recoveryKey, blocks.join('-'));
    expect(await tester.runAsync(() => VaultCrypto.openWithPassword(setup.vault, 'lantern velvet orchard')), setup.dek);
  });

  testWidgets('Copy puts the recovery key on the clipboard', (tester) async {
    String? clip;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clip = (call.arguments as Map)['text'] as String;
      return null;
    });
    final (_, key) = RecoveryKey.generate();
    await launch(tester, RecoveryKeyDialog(recoveryKey: key, title: 'Recovery key', confirmSaved: false));
    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(clip, key);
    expect(find.text('Copied'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets('a new recovery key: Done waits for "saved"', (tester) async {
    final (_, key) = RecoveryKey.generate();
    final popped = await launch(tester, RecoveryKeyDialog(recoveryKey: key, title: 'New', confirmSaved: true));
    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(popped, isEmpty);
    await tester.tap(find.text("I've saved my recovery key"));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(popped, hasLength(1));
  });

  testWidgets('a password prompt: wrong says so, right closes, Esc cancels', (tester) async {
    final tried = <String>[];
    final popped = await launch(
      tester,
      PasswordPromptDialog(
        title: 'Turn off the lock?',
        body: 'body',
        action: 'Turn off',
        submit: (pw) async {
          tried.add(pw);
          return pw == 'right one';
        },
      ),
    );
    await type(tester, 'wrong one');
    await tester.tap(find.text('Turn off'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Incorrect password'), findsOneWidget);
    expect(popped, isEmpty);

    await type(tester, 'right one');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump();
    expect(tried, ['wrong one', 'right one']);
    expect(popped, [true]);

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Turn off the lock?'), findsNothing);
    expect(popped, [true, null]);
  });

  testWidgets('change password: Save waits for both fields', (tester) async {
    await launch(tester, Builder(builder: (_) => ChangePasswordDialog(session: session)));
    expect(find.text('Change password'), findsWidgets);
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Current password'), findsWidgets, reason: 'still open');
    await type(tester, 'old password', at: 0);
    await type(tester, 'short', at: 1);
    expect(find.text('Use at least 8 characters'), findsOneWidget);
    await type(tester, 'a new long passphrase', at: 1);
    expect(find.text('Strong'), findsOneWidget);
    // Enabled now: this session has no vault, so the current password is wrong.
    await tester.runAsync(() async {
      await tester.tap(find.text('Save'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(find.text('Incorrect password'), findsOneWidget);
  });
}

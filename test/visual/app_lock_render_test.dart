// Renders Settings → Privacy → App lock and its dialogs to PNG, in both
// languages and both themes. Opt-in:
//   $env:SOTTO_RENDER=1; flutter test --no-pub test/visual/app_lock_render_test.dart
// SOTTO_RENDER_OUT=folder (default build/app_lock).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:sotto/l10n/l10n.dart';

final _render = Platform.environment['SOTTO_RENDER'] != null;
final _out = Platform.environment['SOTTO_RENDER_OUT'] ?? 'build/app_lock';

class _Window implements WindowService {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

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
  setUpAll(() {
    // The busy check reads the live controller, which talks to these.
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in ['dev.leanflutter.plugins/hotkey_manager', 'dev.leanflutter.plugins/hotkey_manager_event']) {
      messenger.setMockMethodCallHandler(MethodChannel(name), (_) async => null);
    }
  });

  for (final lang in [AppLanguage.en, AppLanguage.es]) {
    for (final theme in [AppThemeMode.dark, AppThemeMode.light]) {
      final tag = '${lang.name}-${theme.name}';
      testWidgets('app lock settings $tag', skip: !_render, (tester) async {
        late Directory dir;
        late LocalStore store;
        late AppSession session;
        await tester.runAsync(() async {
          await _loadFonts();
          dir = await Directory.systemTemp.createTemp('sotto_lock_render');
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
            kdf: const KdfParams(memoryKiB: 64, iterations: 1, parallelism: 1),
          );
        });
        addTearDown(() async {
          await tester.runAsync(() async {
            await Hive.close();
            await dir.delete(recursive: true);
          });
        });
        tester.view.physicalSize = const Size(900, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final key = GlobalKey();
        L10n.current = lookupAppLocalizations(Locale(lang.name));

        Future<void> show(bool on) async {
          await tester.pumpWidget(
            RepaintBoundary(
              key: key,
              child: ProviderScope(
                key: UniqueKey(),
                overrides: [
                  localStoreProvider.overrideWithValue(store),
                  appSessionProvider.overrideWithValue(session),
                  lockEnabledProvider.overrideWithValue(on),
                ],
                child: StandaloneApp(
                  settings: AppSettings(uiLanguage: lang, appTheme: theme, reduceMotion: true),
                  home: Builder(
                    builder: (context) => Scaffold(
                      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                      body: const Padding(padding: EdgeInsets.all(40), child: AppLockSection()),
                    ),
                  ),
                ),
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

        Future<void> dialog(Widget child) async {
          final context = tester.element(find.byType(AppLockSection));
          unawaited(showSottoDialog<void>(context: context, barrierDismissible: false, builder: (_) => child));
          await tester.pump();
        }

        Future<void> type(String text, {int at = 0}) async {
          await tester.enterText(find.byType(TextField).at(at), text);
          await tester.pump();
        }

        await show(false);
        await shot('1-section-off');
        await show(true);
        await shot('2-section-on');

        await dialog(EnableLockDialog(session: session));
        await type('lantern velvet orchard');
        await shot('3-create-password');

        await tester.runAsync(() async {
          await tester.tap(find.text(L10n.current.continueAction));
          await tester.pump();
          for (var i = 0; i < 50 && find.byType(RecoveryKeyBlocks).evaluate().isEmpty; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            await tester.pump();
          }
        });
        await shot('4-save-recovery-key');
        await tester.tap(find.text(L10n.current.recoveryKeySaved));
        await shot('5-saved');

        await show(true);
        await dialog(ChangePasswordDialog(session: session));
        await type('old password');
        await type('new long passphrase', at: 1);
        await shot('6-change-password');

        await show(true);
        final l = L10n.current;
        await dialog(
          PasswordPromptDialog(
            title: l.newRecoveryKeyTitle,
            body: l.newRecoveryKeyBody,
            action: l.newRecoveryKey,
            destructive: true,
            submit: (_) async => false,
          ),
        );
        await type('wrong');
        await tester.tap(find.text(l.newRecoveryKey).last);
        await tester.pump();
        await tester.pump();
        await shot('7-password-prompt-error');

        await show(true);
        final (_, k) = RecoveryKey.generate();
        await dialog(RecoveryKeyDialog(recoveryKey: k, title: l.newRecoveryKeyReady, confirmSaved: true));
        await shot('8-new-recovery-key');
      });
    }
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/core/design/theme.dart';
import 'package:sotto/core/design/tokens.dart';
import 'package:sotto/core/platform/platform_features.dart';
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/data/repositories.dart';
import 'package:sotto/data/storage/local_store.dart';
import 'package:sotto/features/forms/forms_screen.dart';
import 'package:sotto/features/library/readiness.dart';
import 'package:sotto/features/settings/pages/answers_page.dart';
import 'package:sotto/features/settings/pages/forms_page.dart';
import 'package:sotto/features/settings/pages/general_pages.dart';
import 'package:sotto/features/settings/settings_screen.dart';
import 'package:sotto/l10n/l10n.dart';

final _linux = PlatformFeatures.forOs('linux');
final _l = lookupAppLocalizations(const Locale('en'));

class _Settings extends SettingsNotifier {
  _Settings(this.initial);
  final AppSettings initial;

  // The real clamp, over settings given by the test instead of the store.
  @override
  AppSettings build() => ref.read(platformFeaturesProvider).clamp(initial);
}

/// Everything switched on, as a settings file copied from Windows would be.
const _allOn = AppSettings(
  screenAwareness: true,
  attachSlideToAnswers: true,
  agentEnabled: true,
  formsEnabled: true,
  formsAutoFill: true,
  showFormsNav: true,
);

void _mockChannels() {
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final name in ['window_manager', 'com.llfbandit.record/messages', 'dev.leanflutter.plugins/hotkey_manager']) {
    m.setMockMethodCallHandler(MethodChannel(name), (call) async => call.method == 'listInputDevices' ? [] : null);
  }
  m.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (_) async => Directory.systemTemp.path,
  );
  m.setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async => call.method == 'readAll' ? <String, String>{} : null,
  );
}

Future<void> _pump(WidgetTester tester, Widget child, {PlatformFeatures? features}) async {
  _mockChannels();
  L10n.current = _l;
  tester.view.physicalSize = const Size(1280, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        platformFeaturesProvider.overrideWithValue(features ?? _linux),
        settingsProvider.overrideWith(() => _Settings(_allOn)),
        ttsVoicesProvider.overrideWith((ref) async => const <String>[]),
        sessionsProvider.overrideWith((ref) => Stream.value(const [])),
      ],
      child: MaterialApp(
        theme: buildSottoTheme(SottoPalette.houseLights),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  group('what each platform can do', () {
    test('Windows and macOS have every feature', () {
      for (final os in ['windows', 'macos']) {
        final f = PlatformFeatures.forOs(os);
        expect(
          [f.screenCapture, f.formFilling, f.agent, f.browserBridge, f.captureExclusion, f.readAloud],
          everyElement(isTrue),
          reason: os,
        );
        expect(f.clamp(_allOn), same(_allOn), reason: '$os keeps settings as they are');
      }
    });

    test('Linux keeps the core and drops what needs Windows or macOS', () {
      expect(_linux.isLinux, isTrue);
      expect([
        _linux.screenCapture,
        _linux.formFilling,
        _linux.agent,
        _linux.browserBridge,
        _linux.captureExclusion,
      ], everyElement(isFalse));
      expect(_linux.readAloud, isFalse);
    });

    test('Wayland is only reported on Linux', () {
      expect(PlatformFeatures.forOs('linux', wayland: true).wayland, isTrue);
      expect(PlatformFeatures.forOs('windows', wayland: true).wayland, isFalse);
    });

    test('settings that need Windows or macOS are switched off on Linux', () {
      final s = _linux.clamp(_allOn);
      expect(s.screenAwareness, isFalse);
      expect(s.attachSlideToAnswers, isFalse);
      expect(s.agentEnabled, isFalse);
      expect(s.formsEnabled, isFalse);
      expect(s.formsAutoFill, isFalse);
      expect(s.showFormsNav, isFalse);
    });
  });

  group('the settings store on Linux', () {
    late Directory dir;
    late LocalStore store;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('sotto_linux');
      store = await LocalStore.open(path: dir.path);
    });

    tearDown(() async {
      await store.close();
      dir.deleteSync(recursive: true);
    });

    test('saved settings from another machine load clamped, and toggling them on does nothing', () {
      store.settingsWrites.put('app', _allOn.toJson());
      final c = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store), platformFeaturesProvider.overrideWithValue(_linux)],
      );
      addTearDown(c.dispose);
      expect(c.read(settingsProvider).screenAwareness, isFalse);
      expect(c.read(settingsProvider).formsEnabled, isFalse);

      c.read(settingsProvider.notifier).update((s) => s.copyWith(agentEnabled: true, screenAwareness: true));
      expect(c.read(settingsProvider).agentEnabled, isFalse);
      expect(c.read(settingsProvider).screenAwareness, isFalse);
      // Everything else still saves.
      c.read(settingsProvider.notifier).update((s) => s.copyWith(wordsPerMinute: 130));
      expect(c.read(settingsProvider).wordsPerMinute, 130);
    });
  });

  group('Linux screens', () {
    testWidgets('the Forms page explains it is not available', (tester) async {
      await _pump(tester, const FormsScreen());
      expect(find.text(_l.formsUnavailableTitle), findsOneWidget);
      expect(find.text(_l.formsFillNow), findsNothing);
    });

    testWidgets('Settings › Forms explains it is not available', (tester) async {
      await _pump(tester, const FormsSettingsPage());
      expect(find.text(_l.formsUnavailableTitle), findsOneWidget);
      expect(find.text(_l.autofillToggle), findsNothing);
    });

    testWidgets('Forms is not listed among the Settings pages on Linux', (tester) async {
      expect(SettingsPage.forms.availableOn(_linux), isFalse);
      expect(SettingsPage.forms.availableOn(PlatformFeatures.forOs('windows')), isTrue);
      expect(SettingsPage.values.where((p) => p != SettingsPage.forms).every((p) => p.availableOn(_linux)), isTrue);
    });

    testWidgets('Privacy: screen reading and agent mode are disabled, saying why', (tester) async {
      await _pump(tester, const PrivacyPage());
      expect(find.text(_l.notOnLinux), findsNWidgets(2));
      expect(find.text(_l.attachSlide), findsNothing);
      expect(find.text(_l.agentAutonomy), findsNothing);
    });

    testWidgets('Answers: reading aloud says it is not available', (tester) async {
      await _pump(tester, const AnswersPage());
      await tester.scrollUntilVisible(find.text(_l.readAloudTitle), 300);
      expect(find.text(_l.notOnLinux), findsOneWidget);
      expect(find.text(_l.readAloudHeadphones), findsNothing);
    });

    testWidgets('General: the Forms sidebar switch is hidden', (tester) async {
      await _pump(tester, const GeneralPage());
      expect(find.text(_l.showFormsNav), findsNothing);
      await _pump(tester, const GeneralPage(), features: PlatformFeatures.forOs('windows'));
      expect(find.text(_l.showFormsNav), findsOneWidget);
    });
  });

  group('readiness on Linux', () {
    ProviderContainer container(PlatformFeatures f) {
      _mockChannels();
      L10n.current = _l;
      final c = ProviderContainer(
        overrides: [
          platformFeaturesProvider.overrideWithValue(f),
          settingsProvider.overrideWith(() => _Settings(const AppSettings())),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('the share check warns that the overlay shows in screen shares', () async {
      final r = await container(_linux).read(readinessProvider.future);
      expect(r.share.label, _l.readyShareVisible);
      expect(r.share.level, CheckLevel.warn);
    });

    test('on Wayland the shortcuts check says they need X11', () async {
      final r = await container(PlatformFeatures.forOs('linux', wayland: true)).read(readinessProvider.future);
      expect(r.hotkeys.label, _l.readyHotkeysWayland);
      expect(r.hotkeys.level, CheckLevel.warn);
    });

    test('Windows keeps the usual checks', () async {
      final r = await container(PlatformFeatures.forOs('windows')).read(readinessProvider.future);
      expect(r.share.label, _l.readyShareWindow);
    });
  });
}

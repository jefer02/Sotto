import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/design/theme.dart';
import '../core/design/tokens.dart';
import '../core/platform/window_service.dart';
import '../core/utils/frame_stats.dart';
import '../core/widgets/stage_transitions.dart';
import '../data/models/settings.dart';
import '../data/models/shortcut.dart';
import '../data/repositories.dart';
import '../l10n/l10n.dart';
import '../features/agent/agent_controller.dart';
import '../features/agent/agent_view.dart';
import '../features/chat/chat_controller.dart';
import '../features/forms/autofill_controller.dart';
import '../features/forms/autofill_view.dart';
import '../features/live/backdrop_tone_controller.dart';
import '../features/live/live_controller.dart';
import '../features/library/library_actions.dart';
import '../features/live/overlay_palette.dart';
import '../features/live/overlay_screen.dart';
import '../features/preflight/preflight_dialog.dart';
import '../features/questionnaire/questionnaire_controller.dart';
import '../features/questionnaire/questionnaire_view.dart';
import 'app_session.dart';
import 'auto_lock.dart';
import 'router.dart';
import '../core/platform/platform_features.dart';

/// The script a global ⌃⌥L should start: the one open in the editor, or
/// the library's "Up next".
class FocusedScript extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? id) => state = id;
}

final focusedScriptProvider = NotifierProvider<FocusedScript, String?>(FocusedScript.new);

/// The interface locale for a language setting.
Locale appLocale(AppLanguage language) => switch (language) {
  AppLanguage.en => const Locale('en'),
  AppLanguage.es => const Locale('es'),
  AppLanguage.system => L10n.resolve(WidgetsBinding.instance.platformDispatcher.locale),
};

class SottoApp extends ConsumerStatefulWidget {
  const SottoApp({super.key});

  @override
  ConsumerState<SottoApp> createState() => _SottoAppState();
}

class _SottoAppState extends ConsumerState<SottoApp> with WidgetsBindingObserver {
  // "System" language follows the OS, including changes while running.
  @override
  void didChangeLocales(List<Locale>? locales) => setState(() {});

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final live = ref.read(liveControllerProvider.notifier);
    live.onEnded = (record) {
      ref.read(routerProvider).go('/script/${record.scriptId}?tab=rehearsals');
      unawaited(_registerIdle());
    };
    WidgetsBinding.instance.addPostFrameCallback((_) => _registerIdle());
    if (FrameStats.enabled) {
      final router = ref.read(routerProvider);
      router.routerDelegate.addListener(() => FrameStats.label = router.routerDelegate.currentConfiguration.uri.path);
    }
  }

  Future<void> _registerIdle() => ref
      .read(liveControllerProvider.notifier)
      .registerIdleHotkeys(
        _openPreflightFromHotkey,
        extra: {
          // Linux has no form filling: the chord stays free for other apps.
          if (ref.read(platformFeaturesProvider).formFilling)
            LiveAction.fillForm: (
              onDown: () => unawaited(ref.read(autoFillControllerProvider.notifier).fillNow()),
              onUp: null,
            ),
          // Chord + Esc, outside a session too: whatever Sotto is doing on
          // screen stops at once, and auto-fill rests.
          LiveAction.agentStop: (onDown: _emergencyStop, onUp: null),
          // Chord + K locks Sotto — only with the App Lock on.
          if (ref.read(lockEnabledProvider))
            LiveAction.lockApp: (onDown: () => unawaited(ref.read(appSessionProvider)?.lock()), onUp: null),
          // The chat's shortcuts exist only with the chat turned on.
          if (ref.read(settingsProvider).showChat) ...{
            LiveAction.openChat: (onDown: () => unawaited(_openChat()), onUp: null),
            LiveAction.pushToTalk: (
              onDown: () =>
                  unawaited(_openChat().then((_) => ref.read(chatControllerProvider.notifier).startDictation())),
              onUp: () => unawaited(ref.read(chatControllerProvider.notifier).stopDictation()),
            ),
          },
        },
      );

  void _emergencyStop() {
    ref.read(agentControllerProvider.notifier).stop();
    ref.read(autoFillControllerProvider.notifier).emergencyStop();
  }

  /// Chord + C outside a session: the Chat page, in front.
  Future<void> _openChat() async {
    ref.read(routerProvider).go('/chat');
    await ref.read(windowServiceProvider).bringToFront();
  }

  void _openPreflightFromHotkey() {
    final id = ref.read(focusedScriptProvider);
    final context = rootNavigatorKey.currentContext;
    if (id == null || context == null) return;
    unawaited(showPreflight(context, ref, id));
  }

  @override
  Widget build(BuildContext context) {
    // Re-bind ⌃⌥L when the chord or its key changes in Settings — and the
    // chat's shortcuts when the chat is turned on or off.
    ref.listen(settingsProvider.select((s) => (s.chord, s.bindings, s.showChat)), (_, _) {
      if (!ref.read(liveControllerProvider).isLive) unawaited(_registerIdle());
    });
    final settings = ref.watch(settingsProvider);
    final isLive = ref.watch(liveControllerProvider.select((s) => s.isLive));
    // An agent task started from the main window turns it into an overlay too.
    final agentOverlay = ref.watch(agentControllerProvider.select((a) => a.active && a.standalone));
    final formOverlay = ref.watch(questionnaireControllerProvider.select((q) => q.active && q.standalone));
    // Auto-fill (or "Fill what's on screen now") outside a session.
    final autoFillOverlay = ref.watch(autoFillControllerProvider.select((a) => a.overlay));
    final locale = appLocale(settings.uiLanguage);
    // Controllers and services read strings without a BuildContext.
    L10n.current = lookupAppLocalizations(locale);
    Intl.defaultLocale = locale.languageCode;

    final themeMode = switch (settings.appTheme) {
      AppThemeMode.dark => ThemeMode.dark,
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.auto => ThemeMode.system,
    };

    if (FrameStats.enabled && (isLive || agentOverlay || formOverlay || autoFillOverlay)) FrameStats.label = 'overlay';
    if (isLive || agentOverlay || formOverlay || autoFillOverlay) {
      final platformDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
      final overlayDark = switch (settings.overlayTheme) {
        OverlayThemeMode.dark => true,
        OverlayThemeMode.light => false,
        OverlayThemeMode.matchApp =>
          settings.appTheme == AppThemeMode.dark || (settings.appTheme == AppThemeMode.auto && platformDark),
      };
      // Auto text color: what's behind the overlay, sampled on-device.
      final backdrop = isLive ? ref.watch(backdropToneProvider) : null;
      final overlay = overlayPaletteFor(settings, dark: overlayDark, backdrop: backdrop);
      return _AutoLockScope(
        child: MaterialApp(
          key: ValueKey(locale.languageCode),
          debugShowCheckedModeBanner: false,
          title: 'Sotto',
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          color: const Color(0x00000000),
          // A backdrop change crossfades the text color over 200 ms.
          themeAnimationDuration: const Duration(milliseconds: 200),
          themeAnimationCurve: Curves.easeInOut,
          theme: buildSottoTheme(
            overlayDark ? SottoPalette.stage : SottoPalette.houseLights,
            overlay: overlay,
          ).copyWith(scaffoldBackgroundColor: const Color(0x00000000), canvasColor: const Color(0x00000000)),
          home: isLive
              ? const OverlayScreen()
              : autoFillOverlay
              ? const AutoFillOverlayScreen()
              : (formOverlay ? const QuestionnaireOverlayScreen() : const AgentOverlayScreen()),
        ),
      );
    }

    // Keyed by language so every screen, including strings computed outside
    // widgets, rebuilds when the language changes.
    return _AutoLockScope(
      child: MaterialApp.router(
        key: ValueKey(locale.languageCode),
        debugShowCheckedModeBanner: false,
        title: 'Sotto',
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: buildSottoTheme(SottoPalette.houseLights),
        darkTheme: buildSottoTheme(SottoPalette.stage),
        themeMode: themeMode,
        // Light ↔ dark crossfades (SottoPalette.lerp); instant under reduce motion.
        themeAnimationDuration:
            settings.reduceMotion || WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations
            ? Duration.zero
            : Motion.panel,
        themeAnimationCurve: Motion.move,
        routerConfig: ref.watch(routerProvider),
        // "Reduce motion" (Settings › Appearance) calms the main window too,
        // not only the overlay: every effect checks disableAnimations.
        builder: (context, child) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(disableAnimations: media.disableAnimations || settings.reduceMotion),
            // The ground under every page: a page arriving fades in over it,
            // never over the bare window (transparent once the overlay has
            // run, so the desktop showed through mid-transition).
            child: ColoredBox(
              color: context.palette.ground,
              // The curtain rises on launch; the house lights come up after a show.
              child: LaunchCurtain(child: _GlobalShortcuts(child: child ?? const SizedBox.shrink())),
            ),
          );
        },
      ),
    );
  }
}

/// With the App Lock on: any key, click, scroll or pointer move in the
/// window keeps Sotto unlocked; after Settings → Privacy → Auto-lock
/// without any, it locks — never mid-session ([sessionBusyProvider]), but
/// right after, if the time is up by then. Above both the main window and
/// the overlay, so going live doesn't restart the count.
class _AutoLockScope extends ConsumerStatefulWidget {
  const _AutoLockScope({required this.child});
  final Widget child;

  @override
  ConsumerState<_AutoLockScope> createState() => _AutoLockScopeState();
}

class _AutoLockScopeState extends ConsumerState<_AutoLockScope> {
  /// Development: `--dart-define=SOTTO_AUTOLOCK_SECONDS=20` replaces any
  /// non-zero choice with that many seconds. Ignored in release builds.
  static const _devSeconds = int.fromEnvironment('SOTTO_AUTOLOCK_SECONDS');

  static Duration _timeout(int minutes) =>
      minutes > 0 && _devSeconds > 0 && !kReleaseMode ? Duration(seconds: _devSeconds) : Duration(minutes: minutes);

  AutoLock? _auto;

  @override
  void initState() {
    super.initState();
    if (!ref.read(lockEnabledProvider)) return;
    _arm();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  void _arm() {
    _auto?.dispose();
    _auto = AutoLock(timeout: _timeout(ref.read(settingsProvider).autoLockMinutes), onLock: _lock)
      ..busy = ref.read(sessionBusyProvider);
  }

  Future<void> _lock() async {
    // Something started in the same instant: count again from now.
    final locked = await ref.read(appSessionProvider)?.lock() ?? false;
    if (!locked && mounted) _arm();
  }

  bool _onKey(KeyEvent event) {
    _auto?.activity();
    return false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _auto?.dispose();
    super.dispose();
  }

  void _activity(PointerEvent _) => _auto?.activity();

  @override
  Widget build(BuildContext context) {
    if (_auto == null) return widget.child;
    ref.listen(sessionBusyProvider, (_, busy) => _auto?.busy = busy);
    ref.listen(settingsProvider.select((s) => s.autoLockMinutes), (_, m) => _auto?.timeout = _timeout(m));
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _activity,
      onPointerHover: _activity,
      onPointerMove: _activity,
      onPointerSignal: _activity,
      child: widget.child,
    );
  }
}

/// Main-window shortcuts: ⌘N new script, ⌘, settings (⌘K is handled by the
/// sidebar search field).
class _GlobalShortcuts extends ConsumerWidget {
  const _GlobalShortcuts({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.read(routerProvider);
    final isMac = Theme.of(context).platform == TargetPlatform.macOS;
    SingleActivator key(LogicalKeyboardKey k) => SingleActivator(k, meta: isMac, control: !isMac);
    return CallbackShortcuts(
      bindings: {
        key(LogicalKeyboardKey.comma): () => router.go('/settings/shortcuts'),
        key(LogicalKeyboardKey.keyN): () => unawaited(createScriptAndOpen(ref)),
      },
      child: child,
    );
  }
}

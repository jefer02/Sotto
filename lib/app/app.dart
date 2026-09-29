import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/design/theme.dart';
import '../core/design/tokens.dart';
import '../core/platform/window_service.dart';
import '../data/models/settings.dart';
import '../data/models/shortcut.dart';
import '../data/repositories.dart';
import '../l10n/l10n.dart';
import '../features/agent/agent_controller.dart';
import '../features/agent/agent_view.dart';
import '../features/chat/chat_controller.dart';
import '../features/live/live_controller.dart';
import '../features/library/library_actions.dart';
import '../features/live/overlay_palette.dart';
import '../features/live/overlay_screen.dart';
import '../features/preflight/preflight_dialog.dart';
import '../features/questionnaire/questionnaire_controller.dart';
import '../features/questionnaire/questionnaire_view.dart';
import 'router.dart';

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
  }

  Future<void> _registerIdle() => ref
      .read(liveControllerProvider.notifier)
      .registerIdleHotkeys(
        _openPreflightFromHotkey,
        extra: {
          LiveAction.fillForm: (
            onDown: () => unawaited(ref.read(questionnaireControllerProvider.notifier).start()),
            onUp: null,
          ),
          LiveAction.openChat: (onDown: () => unawaited(_openChat()), onUp: null),
          LiveAction.pushToTalk: (
            onDown: () =>
                unawaited(_openChat().then((_) => ref.read(chatControllerProvider.notifier).startDictation())),
            onUp: () => unawaited(ref.read(chatControllerProvider.notifier).stopDictation()),
          ),
        },
      );

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
    // Re-bind ⌃⌥L when the chord or its key changes in Settings.
    ref.listen(settingsProvider.select((s) => (s.chord, s.bindings)), (_, _) {
      if (!ref.read(liveControllerProvider).isLive) unawaited(_registerIdle());
    });
    final settings = ref.watch(settingsProvider);
    final isLive = ref.watch(liveControllerProvider.select((s) => s.isLive));
    // An agent task started from the main window turns it into an overlay too.
    final agentOverlay = ref.watch(agentControllerProvider.select((a) => a.active && a.standalone));
    final formOverlay = ref.watch(questionnaireControllerProvider.select((q) => q.active && q.standalone));
    final locale = appLocale(settings.uiLanguage);
    // Controllers and services read strings without a BuildContext.
    L10n.current = lookupAppLocalizations(locale);
    Intl.defaultLocale = locale.languageCode;

    final themeMode = switch (settings.appTheme) {
      AppThemeMode.dark => ThemeMode.dark,
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.auto => ThemeMode.system,
    };

    if (isLive || agentOverlay || formOverlay) {
      final platformDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
      final overlayDark = switch (settings.overlayTheme) {
        OverlayThemeMode.dark => true,
        OverlayThemeMode.light => false,
        OverlayThemeMode.matchApp =>
          settings.appTheme == AppThemeMode.dark || (settings.appTheme == AppThemeMode.auto && platformDark),
      };
      final overlay = overlayPaletteFor(settings, dark: overlayDark);
      return MaterialApp(
        key: ValueKey(locale.languageCode),
        debugShowCheckedModeBanner: false,
        title: 'Sotto',
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        color: const Color(0x00000000),
        theme: buildSottoTheme(
          overlayDark ? SottoPalette.stage : SottoPalette.houseLights,
          overlay: overlay,
        ).copyWith(scaffoldBackgroundColor: const Color(0x00000000), canvasColor: const Color(0x00000000)),
        home: isLive
            ? const OverlayScreen()
            : (formOverlay ? const QuestionnaireOverlayScreen() : const AgentOverlayScreen()),
      );
    }

    // Keyed by language so every screen, including strings computed outside
    // widgets, rebuilds when the language changes.
    return MaterialApp.router(
      key: ValueKey(locale.languageCode),
      debugShowCheckedModeBanner: false,
      title: 'Sotto',
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: buildSottoTheme(SottoPalette.houseLights),
      darkTheme: buildSottoTheme(SottoPalette.stage),
      themeMode: themeMode,
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => _GlobalShortcuts(child: child ?? const SizedBox.shrink()),
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

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../core/design/theme.dart';
import '../core/design/tokens.dart';
import '../core/widgets/stage_light.dart';
import '../core/widgets/window_chrome.dart';
import '../data/models/settings.dart';
import '../l10n/l10n.dart';
import 'app.dart';

/// A screen shown outside a session (unlocking, encrypting the data) in the
/// presenter's own theme, language and motion setting — read from the
/// settings box, which stays open while the rest is locked.
class StandaloneApp extends StatelessWidget {
  const StandaloneApp({super.key, required this.settings, required this.home});

  final AppSettings settings;
  final Widget home;

  @override
  Widget build(BuildContext context) {
    final locale = appLocale(settings.uiLanguage);
    return MaterialApp(
      key: ValueKey(locale.languageCode),
      debugShowCheckedModeBanner: false,
      title: 'Sotto',
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: buildSottoTheme(SottoPalette.houseLights),
      darkTheme: buildSottoTheme(SottoPalette.stage),
      themeMode: switch (settings.appTheme) {
        AppThemeMode.dark => ThemeMode.dark,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.auto => ThemeMode.system,
      },
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(disableAnimations: media.disableAnimations || settings.reduceMotion),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: home,
    );
  }
}

/// The ground, a strip that still moves the frameless window (with the
/// caption buttons on Windows and Linux), and [child] centered below.
class StandaloneScaffold extends StatelessWidget {
  const StandaloneScaffold({super.key, required this.child, this.glow = false});

  final Widget child;

  /// The stage's ambient light over the whole window, title strip included.
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final body = Column(
      children: [
        SizedBox(
          height: Layout.titleBar,
          child: Row(
            children: [
              const Expanded(child: DragToMoveArea(child: SizedBox.expand())),
              if (drawsCaptionButtons) const CaptionButtons(),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
    return Scaffold(
      backgroundColor: p.ground,
      body: glow ? StageGlow(child: body) : body,
    );
  }
}

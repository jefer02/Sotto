import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../core/design/icons.dart';
import '../core/design/theme.dart';
import '../core/design/tokens.dart';
import '../core/design/typography.dart';
import '../core/widgets/buttons.dart';
import '../l10n/l10n.dart';

/// Shown instead of a blank window when Sotto can't open its data at
/// startup — most often another copy still has it locked, or a sync app is
/// holding a file. [onRetry] tries again; the window has no title bar, so it
/// also offers Quit.
class StartupFailure extends StatelessWidget {
  const StartupFailure({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final device = WidgetsBinding.instance.platformDispatcher.locale;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildSottoTheme(SottoPalette.stage),
      locale: L10n.resolve(device),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: _Body(error: error, onRetry: onRetry),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    return Scaffold(
      backgroundColor: p.ground,
      body: Column(
        children: [
          // The window is frameless: this strip still moves it.
          const DragToMoveArea(
            child: SizedBox(height: Layout.titleBar, width: double.infinity),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SottoIcon(SottoIcons.alert, size: 22, color: p.caution),
                      const SizedBox(height: 14),
                      Text(l.startupFailedTitle, style: TypeScale.title2.copyWith(color: p.inkPrimary)),
                      const SizedBox(height: 8),
                      Text(l.startupFailedBody, style: TypeScale.body.copyWith(color: p.inkSecondary, height: 1.5)),
                      const SizedBox(height: 14),
                      SelectableText('$error', style: TypeScale.monoSmall.copyWith(color: p.inkTertiary)),
                      const SizedBox(height: 22),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          SottoButton.ghost(label: l.quit, onPressed: () => exit(0)),
                          const SizedBox(width: 8),
                          SottoButton.primary(label: l.retry, onPressed: onRetry),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

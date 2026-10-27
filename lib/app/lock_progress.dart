import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/design/icons.dart';
import '../core/design/theme.dart';
import '../core/design/tokens.dart';
import '../core/design/typography.dart';
import '../data/lock/migration.dart';
import '../data/models/settings.dart';
import '../data/storage/local_store.dart';
import '../l10n/l10n.dart';
import 'standalone_app.dart';

/// Shown while the App Lock encrypts or decrypts the data: Sotto is closed
/// to everything else for those seconds.
class LockProgressApp extends StatelessWidget {
  const LockProgressApp({super.key, required this.settings, required this.progress, required this.direction});

  final SettingsStore settings;
  final ValueListenable<double> progress;
  final LockDirection direction;

  @override
  Widget build(BuildContext context) => StandaloneApp(
    settings: AppSettings.fromJson(settings.writes.get(LocalStore.prefsSettingsKey) ?? const {}),
    home: LockProgressScreen(progress: progress, direction: direction),
  );
}

class LockProgressScreen extends StatelessWidget {
  const LockProgressScreen({super.key, required this.progress, required this.direction});

  final ValueListenable<double> progress;
  final LockDirection direction;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final title = direction == LockDirection.encrypt ? l.lockEncrypting : l.lockDecrypting;
    return StandaloneScaffold(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(Space.s6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SottoIcon(SottoIcons.lock, size: 22, color: p.primaryText),
                const SizedBox(height: Space.s4),
                Text(
                  title,
                  style: TypeScale.title2.copyWith(color: p.inkPrimary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Space.s2),
                Text(
                  l.lockProgressBody,
                  style: TypeScale.body.copyWith(color: p.inkSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Space.s6),
                ValueListenableBuilder<double>(
                  valueListenable: progress,
                  builder: (context, value, _) => Semantics(
                    label: title,
                    value: '${(value * 100).round()} %',
                    child: ClipRRect(
                      borderRadius: Radii.rXs,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: value),
                        duration: still ? Duration.zero : Motion.smooth,
                        curve: Motion.move,
                        builder: (context, v, _) => LinearProgressIndicator(
                          value: v,
                          minHeight: 4,
                          color: p.primary,
                          backgroundColor: p.primaryTrack,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

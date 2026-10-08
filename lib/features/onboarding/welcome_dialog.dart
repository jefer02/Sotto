import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/icons.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/display.dart';
import '../../core/widgets/interactive.dart';
import '../../data/repositories.dart';
import '../../l10n/l10n.dart';
import '../../services/speech/model_manager.dart';
import '../forms/browser_extension_rows.dart';
import '../library/library_actions.dart';
import '../settings/pages/voice_page.dart';

/// Shows the first-run welcome once. Answers need no setup (the DeepSeek key
/// is built in), so it only covers voice models, the optional browser
/// extension and the first script.
/// [ref] must outlive the dialog (the library shell's), since the chosen
/// action runs after it closes.
Future<void> showWelcomeIfNeeded(BuildContext context, WidgetRef ref) async {
  if (ref.read(settingsProvider).welcomeDone) return;
  final choice = await showDialog<WelcomeChoice>(
    context: context,
    barrierDismissible: false,
    barrierColor: const Color(0x99000000),
    builder: (_) => const WelcomeDialog(),
  );
  ref.read(settingsProvider.notifier).update((s) => s.copyWith(welcomeDone: true));
  switch (choice) {
    case WelcomeChoice.importFile:
      if (context.mounted) await importFiles(ref, context);
    case WelcomeChoice.paste:
      await importFromClipboard(ref);
    case WelcomeChoice.write:
      await createScriptAndOpen(ref);
    case null:
      break;
  }
}

enum WelcomeChoice { importFile, paste, write }

/// Models that make voice following work for the presenter's language.
List<SpeechModel> recommendedModels(String language) => [
  if (language.toLowerCase().startsWith('en')) ModelCatalog.streamingEnLight,
  ModelCatalog.whisperBase,
];

class WelcomeDialog extends ConsumerStatefulWidget {
  const WelcomeDialog({super.key});

  @override
  ConsumerState<WelcomeDialog> createState() => _WelcomeDialogState();
}

class _WelcomeDialogState extends ConsumerState<WelcomeDialog> {
  static const _steps = 3;
  int _step = 0;

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
      child: Focus(
        autofocus: true,
        child: Dialog(
          backgroundColor: p.raised,
          insetPadding: const EdgeInsets.all(40),
          shape: RoundedRectangleBorder(
            borderRadius: Radii.rXl,
            side: BorderSide(color: p.control),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(26, 22, 26, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(l.welcomeStep(_step + 1, _steps), style: TypeScale.monoSmall.copyWith(color: p.inkTertiary)),
                      const Spacer(),
                      SottoIconButton(icon: SottoIcons.close, tooltip: l.closeEsc, onPressed: _close),
                    ],
                  ),
                  const SizedBox(height: 8),
                  AnimatedSwitcher(
                    duration: Motion.snappy,
                    child: switch (_step) {
                      0 => _ModelsStep(key: const ValueKey(0)),
                      1 => const _BrowserStep(key: ValueKey(1)),
                      _ => _ScriptStep(key: const ValueKey(2)),
                    },
                  ),
                  const SizedBox(height: 20),
                  Divider(height: 1, color: p.hairline),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      for (var i = 0; i < _steps; i++)
                        Container(
                          width: 18,
                          height: 3,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: i == _step ? p.cueFill : p.control,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      const Spacer(),
                      if (_step == 0) ...[
                        SottoButton.ghost(label: l.welcomeSkip, onPressed: () => setState(() => _step = 1)),
                        const SizedBox(width: 8),
                        SottoButton.primary(label: l.welcomeNext, onPressed: () => setState(() => _step = 1)),
                      ] else if (_step == 1) ...[
                        SottoButton.ghost(label: l.welcomeBack, onPressed: () => setState(() => _step = 0)),
                        const SizedBox(width: 8),
                        SottoButton.ghost(label: l.welcomeSkip, onPressed: () => setState(() => _step = 2)),
                        const SizedBox(width: 8),
                        SottoButton.primary(label: l.welcomeNext, onPressed: () => setState(() => _step = 2)),
                      ] else ...[
                        SottoButton.ghost(label: l.welcomeBack, onPressed: () => setState(() => _step = 1)),
                        const SizedBox(width: 8),
                        SottoButton.primary(label: l.welcomeUseExample, onPressed: _close),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModelsStep extends ConsumerWidget {
  const _ModelsStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final l = context.l10n;
    final language = ref.watch(settingsProvider.select((s) => s.language));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.welcomeModelsTitle, style: TypeScale.title2.copyWith(color: p.inkPrimary)),
        const SizedBox(height: 6),
        Text(l.welcomeModelsBody, style: TypeScale.body.copyWith(color: p.inkSecondary)),
        const SizedBox(height: 16),
        SettingsGroup(
          footer: l.welcomeModelsFooter,
          children: [
            for (final m in recommendedModels(language))
              SettingRow(
                title: m.name,
                subtitle: '${m.description} · ${m.sizeMb} MB',
                trailing: ModelDownloadControl(model: m),
              ),
          ],
        ),
      ],
    );
  }
}

/// Optional: the Sotto Bridge extension, per browser.
class _BrowserStep extends StatelessWidget {
  const _BrowserStep({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.welcomeBrowserTitle, style: TypeScale.title2.copyWith(color: p.inkPrimary)),
        const SizedBox(height: 6),
        Text(l.welcomeBrowserBody, style: TypeScale.body.copyWith(color: p.inkSecondary)),
        const SizedBox(height: 16),
        const SettingsGroup(children: [BrowserExtensionRows()]),
      ],
    );
  }
}

class _ScriptStep extends StatelessWidget {
  const _ScriptStep({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    void choose(WelcomeChoice c) => Navigator.of(context).pop(c);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.welcomeScriptTitle, style: TypeScale.title2.copyWith(color: p.inkPrimary)),
        const SizedBox(height: 6),
        Text(l.welcomeScriptBody, style: TypeScale.body.copyWith(color: p.inkSecondary)),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _Choice(
                icon: SottoIcons.import,
                title: l.welcomeImportFile,
                body: l.welcomeImportFileSub,
                onTap: () => choose(WelcomeChoice.importFile),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Choice(
                icon: SottoIcons.doc,
                title: l.welcomePaste,
                body: l.welcomePasteSub,
                onTap: () => choose(WelcomeChoice.paste),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Choice(
                icon: SottoIcons.plus,
                title: l.welcomeWrite,
                body: l.welcomeWriteSub,
                onTap: () => choose(WelcomeChoice.write),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.icon, required this.title, required this.body, required this.onTap});
  final SottoIcons icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Interactive(
      onTap: onTap,
      builder: (context, s) => AnimatedContainer(
        duration: Motion.quick,
        height: 108,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: s.hovered ? p.float : p.panel,
          borderRadius: Radii.rL,
          border: Border.all(color: s.hovered ? p.emphasis : p.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SottoIcon(icon, size: 16, color: s.hovered ? p.cueText : p.inkSecondary),
            const SizedBox(height: 12),
            Text(title, style: TypeScale.bodyStrong.copyWith(color: p.inkPrimary)),
            const SizedBox(height: 4),
            Text(body, style: TypeScale.caption.copyWith(color: p.inkTertiary)),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/l10n.dart';

import '../../core/design/icons.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../core/platform/platform_keys.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/controls.dart';
import '../../core/widgets/display.dart';
import '../../core/widgets/nav.dart';
import '../../core/widgets/window_chrome.dart';
import '../library/library_shell.dart' show TitleBarDragSpacer;
import 'pages/answers_page.dart';
import 'pages/appearance_page.dart';
import 'pages/forms_page.dart';
import 'pages/general_pages.dart';
import 'pages/shortcuts_page.dart';
import 'pages/voice_page.dart';

enum SettingsPage {
  // Keywords in English and Spanish, so search works in either language.
  shortcuts(
    SottoIcons.keyboard,
    'keys hotkeys chord pause next ask hide click-through teclas atajos combinación pausa',
  ),
  appearance(
    SottoIcons.layers,
    'theme dark light text size opacity placement camera layout motion tema oscuro claro texto tamaño opacidad cámara',
  ),
  voice(SottoIcons.wave, 'microphone language engine model sensitivity pace wpm micrófono idioma motor modelo ritmo'),
  answers(
    SottoIcons.ask,
    'grounding sources length tone silence read aloud capture voice fuentes tono silencio respuestas captura voz',
  ),
  forms(
    SottoIcons.form,
    'forms questionnaire survey registration auto-fill fill scroll instructions history browser chrome edge formularios cuestionario encuesta registro autorrelleno rellenar historial navegador',
  ),
  general(
    SottoIcons.sliders,
    'pace storage reset version language chat sidebar ritmo almacenamiento versión idioma español english barra lateral',
  ),
  integrations(SottoIcons.plug, 'api key deepseek model vision clave modelo integraciones'),
  privacy(SottoIcons.shield, 'history retention delete capture keys historial borrar captura claves privacidad');

  const SettingsPage(this.icon, this.keywords);
  final SottoIcons icon;
  final String keywords;

  String get title {
    final l = L10n.current;
    return switch (this) {
      shortcuts => l.setShortcuts,
      appearance => l.setAppearance,
      voice => l.setVoice,
      answers => l.setAnswers,
      forms => l.setForms,
      general => l.setGeneral,
      integrations => l.setIntegrations,
      privacy => l.setPrivacy,
    };
  }

  bool get isLive => index <= SettingsPage.answers.index;
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, required this.page});
  final SettingsPage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    return Scaffold(
      // The sidebar is opaque; the light falls on the page beside it.
      body: StageGlow(
        alignment: const Alignment(0.1, -1.25),
        child: Row(
          children: [
            Container(
              width: Layout.sidebar,
              decoration: sidebarDecoration(p),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: Layout.titleBar,
                    child: TitleBarDragSpacer(width: trafficLightInset),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 12, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: BackLink(label: context.l10n.backToLibrary, onTap: () => context.go('/')),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 18, 12, 4),
                    child: Text(context.l10n.settings, style: TypeScale.title2.copyWith(color: p.inkPrimary)),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        NavHeading(context.l10n.groupLive),
                        for (final pg in SettingsPage.values.where((x) => x.isLive)) ...[
                          NavItem(
                            label: pg.title,
                            icon: pg.icon,
                            selected: pg == page,
                            onTap: () => context.go('/settings/${pg.name}'),
                          ),
                          const SizedBox(height: 2),
                        ],
                        NavHeading(context.l10n.groupApp),
                        for (final pg in SettingsPage.values.where((x) => !x.isLive)) ...[
                          NavItem(
                            label: pg.title,
                            icon: pg.icon,
                            selected: pg == page,
                            onTap: () => context.go('/settings/${pg.name}'),
                          ),
                          const SizedBox(height: 2),
                        ],
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 8, 12, 20),
                    child: Text(context.l10n.versionBuild, style: TypeScale.monoSmall.copyWith(color: p.inkTertiary)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  TitleBarArea(
                    showCaptionButtons: true,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 48, right: 12),
                      child: Row(
                        children: [
                          Text(context.l10n.settings, style: TypeScale.body.copyWith(color: p.inkTertiary)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text('›', style: TypeScale.body.copyWith(color: p.inkTertiary)),
                          ),
                          Text(page.title, style: TypeScale.bodyStrong.copyWith(color: p.inkPrimary)),
                          const Spacer(),
                          _SettingsSearch(current: page),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: switch (page) {
                      SettingsPage.shortcuts => const ShortcutsPage(),
                      SettingsPage.appearance => const AppearancePage(),
                      SettingsPage.voice => const VoicePage(),
                      SettingsPage.answers => const AnswersPage(),
                      SettingsPage.forms => const FormsSettingsPage(),
                      SettingsPage.general => const GeneralPage(),
                      SettingsPage.integrations => const IntegrationsPage(),
                      SettingsPage.privacy => const PrivacyPage(),
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Jumps to the first page whose keywords match.
class _SettingsSearch extends StatelessWidget {
  const _SettingsSearch({required this.current});
  final SettingsPage current;

  @override
  Widget build(BuildContext context) => SottoTextField(
    width: 240,
    placeholder: context.l10n.searchSettings,
    leading: SottoIcons.search,
    shortcutHint: '${PlatformKeys.primary}F',
    onSubmitted: (q) {
      final query = q.trim().toLowerCase();
      if (query.isEmpty) return;
      for (final pg in SettingsPage.values) {
        if (pg.title.toLowerCase().contains(query) || pg.keywords.contains(query)) {
          context.go('/settings/${pg.name}');
          return;
        }
      }
    },
  );
}

/// Title, description, optional action, then one or two columns.
class SettingsPageScaffold extends StatelessWidget {
  const SettingsPageScaffold({
    super.key,
    required this.title,
    required this.description,
    required this.left,
    this.right = const [],
    this.action,
  });

  final String title;
  final String description;
  final List<Widget> left;
  final List<Widget> right;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return LayoutBuilder(
      builder: (context, c) {
        final twoColumns = c.maxWidth > 980 && right.isNotEmpty;
        Widget col(List<Widget> children) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 24), children[i]],
          ],
        );
        return ListView(
          padding: const EdgeInsets.fromLTRB(48, 40, 48, 48),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TypeScale.title1.copyWith(color: p.inkPrimary)),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 620),
                        child: Text(description, style: TypeScale.body.copyWith(color: p.inkSecondary)),
                      ),
                    ],
                  ),
                ),
                ?action,
              ],
            ),
            const SizedBox(height: 28),
            if (twoColumns)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: col(left)),
                  const SizedBox(width: 40),
                  Expanded(child: col(right)),
                ],
              )
            else
              col([...left, ...right]),
          ],
        );
      },
    );
  }
}

/// "Reset" / "Reset to defaults" link in page headers.
class ResetLink extends StatelessWidget {
  const ResetLink({super.key, required this.onTap, this.label});
  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) =>
      SottoButton.ghost(label: label ?? context.l10n.resetToDefaults, onPressed: onTap);
}

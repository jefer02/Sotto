import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import '../../core/widgets/stage_light.dart';
import '../../core/widgets/stage_transitions.dart';
import '../../core/widgets/window_chrome.dart';
import '../library/library_shell.dart' show TitleBarDragSpacer;
import 'pages/answers_page.dart';
import 'pages/appearance_page.dart';
import 'pages/forms_page.dart';
import 'pages/general_pages.dart';
import 'pages/shortcuts_page.dart';
import 'pages/voice_page.dart';
import '../../core/platform/platform_features.dart';

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

  /// Forms needs native form access; elsewhere the page isn't listed (a
  /// deep link still opens it and explains why).
  bool availableOn(PlatformFeatures f) => this != forms || f.formFilling;
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, required this.page});
  final SettingsPage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final features = ref.watch(platformFeaturesProvider);
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
                        NavHighlight(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                              for (final pg in SettingsPage.values.where(
                                (x) => !x.isLive && x.availableOn(features),
                              )) ...[
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
                  // One route for every page: the old page goes at once and
                  // the new one fades in — never both.
                  Expanded(
                    child: ContentFadeIn(
                      key: ValueKey(page),
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
class _SettingsSearch extends ConsumerWidget {
  const _SettingsSearch({required this.current});
  final SettingsPage current;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SottoTextField(
    width: 240,
    placeholder: context.l10n.searchSettings,
    leading: SottoIcons.search,
    shortcutHint: '${PlatformKeys.primary}F',
    onSubmitted: (q) {
      final query = q.trim().toLowerCase();
      if (query.isEmpty) return;
      for (final pg in SettingsPage.values.where((x) => x.availableOn(ref.read(platformFeaturesProvider)))) {
        if (pg.title.toLowerCase().contains(query) || pg.keywords.contains(query)) {
          context.go('/settings/${pg.name}');
          return;
        }
      }
    },
  );
}

/// Title, description and optional action over the page's settings.
///
/// Settings read as one centered column at most [maxColumn] wide: a second
/// column of short asides left most of a wide window blank once the long
/// one scrolled. A page with something live to watch while its settings
/// change (the overlay preview, the mic test) passes it as [panel]: on a
/// wide window it sits beside the column and stays in view while the
/// column scrolls ([StickyPanelRow]); narrower, it leads the column.
class SettingsPageScaffold extends StatelessWidget {
  const SettingsPageScaffold({
    super.key,
    required this.title,
    required this.description,
    required this.sections,
    this.panel = const [],
    this.action,
  });

  final String title;
  final String description;
  final List<Widget> sections;
  final List<Widget> panel;
  final Widget? action;

  /// The settings column's widest.
  static const maxColumn = 720.0;

  /// The column's narrowest beside a panel; below it the panel goes on top.
  static const minColumn = 480.0;
  static const panelMin = 340.0;
  static const panelMax = 460.0;
  static const _gutter = Space.s10;
  static const _sides = Space.s12;

  /// Where the column and the panel are, for layout tests.
  static const columnKey = ValueKey('settings-column');
  static const panelKey = ValueKey('settings-panel');

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget stack(List<Widget> items, {Key? key}) => Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++) ...[if (i > 0) const SizedBox(height: Space.s6), items[i]],
      ],
    );
    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TypeScale.title1.copyWith(color: p.inkPrimary)),
              const SizedBox(height: Space.s2),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Text(description, style: TypeScale.body.copyWith(color: p.inkSecondary)),
              ),
            ],
          ),
        ),
        ?action,
      ],
    );
    return LayoutBuilder(
      builder: (context, c) {
        final inner = c.maxWidth - 2 * _sides;
        final beside = panel.isNotEmpty && inner >= minColumn + _gutter + panelMin;
        final panelWidth = beside ? (inner * 0.4).clamp(panelMin, panelMax) : 0.0;
        final column = beside
            ? math.min(maxColumn, inner - _gutter - panelWidth)
            : math.min(maxColumn, math.max(0.0, inner));
        final used = column + (beside ? _gutter + panelWidth : 0);
        // The column (and its panel) centered in the page.
        final side = _sides + math.max(0.0, (inner - used) / 2);
        return ListView(
          padding: EdgeInsets.fromLTRB(side, Space.s10, side, Space.s12),
          children: [
            header,
            const SizedBox(height: Space.s8),
            if (beside)
              StickyPanelRow(
                gap: _gutter,
                panelWidth: panelWidth,
                main: stack(sections, key: columnKey),
                panel: stack(panel, key: panelKey),
              )
            else
              stack([if (panel.isNotEmpty) stack(panel, key: panelKey), stack(sections, key: columnKey)]),
          ],
        );
      },
    );
  }
}

/// [main] and, [gap] to its right, [panel] — which stays in view while the
/// enclosing scroll view moves [main]: it scrolls with the row until its
/// top reaches the top of the view (less [margin]), holds there, and is
/// carried off again only by the end of the row. A panel taller than the
/// view scrolls until its bottom shows, then holds that.
class StickyPanelRow extends MultiChildRenderObjectWidget {
  StickyPanelRow({
    super.key,
    required Widget main,
    required Widget panel,
    required this.panelWidth,
    this.gap = Space.s10,
    this.margin = Space.s6,
  }) : super(children: [main, panel]);

  final double panelWidth;
  final double gap;
  final double margin;

  @override
  RenderStickyPanelRow createRenderObject(BuildContext context) => RenderStickyPanelRow(
    position: Scrollable.maybeOf(context)?.position,
    panelWidth: panelWidth,
    gap: gap,
    margin: margin,
  );

  @override
  void updateRenderObject(BuildContext context, RenderStickyPanelRow renderObject) => renderObject
    ..position = Scrollable.maybeOf(context)?.position
    ..panelWidth = panelWidth
    ..gap = gap
    ..margin = margin;
}

class _StickyParentData extends ContainerBoxParentData<RenderBox> {}

class RenderStickyPanelRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _StickyParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _StickyParentData> {
  RenderStickyPanelRow({this._position, required this._panelWidth, required this._gap, required this._margin});

  ScrollPosition? _position;
  set position(ScrollPosition? value) {
    if (identical(value, _position)) return;
    if (attached) _position?.removeListener(markNeedsPaint);
    _position = value;
    if (attached) _position?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  double _panelWidth;
  set panelWidth(double value) {
    if (value == _panelWidth) return;
    _panelWidth = value;
    markNeedsLayout();
  }

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  double _margin;
  set margin(double value) {
    if (value == _margin) return;
    _margin = value;
    markNeedsPaint();
  }

  RenderBox get _main => firstChild!;
  RenderBox get _panel => lastChild!;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _StickyParentData) child.parentData = _StickyParentData();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _position?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _position?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final mainWidth = math.max(0.0, width - _gap - _panelWidth);
    _main.layout(BoxConstraints.tightFor(width: mainWidth), parentUsesSize: true);
    _panel.layout(BoxConstraints.tightFor(width: _panelWidth), parentUsesSize: true);
    (_main.parentData! as _StickyParentData).offset = Offset.zero;
    size = constraints.constrain(Size(width, math.max(_main.size.height, _panel.size.height)));
    // Where it sits until painted: the shift needs the finished layout.
    (_panel.parentData! as _StickyParentData).offset = Offset(size.width - _panelWidth, 0);
  }

  /// How far down the row the panel is drawn right now.
  double get panelShift {
    final position = _position;
    final viewport = RenderAbstractViewport.maybeOf(this);
    if (position == null || viewport == null || !position.hasPixels || !position.hasViewportDimension) return 0;
    // The scroll offset that puts this row's top at the top of the view.
    final top = viewport.getOffsetToReveal(this, 0).offset;
    final into = position.pixels - top;
    final room = size.height - _panel.size.height;
    if (room <= 0) return 0;
    final view = position.viewportDimension;
    final shift = _panel.size.height + 2 * _margin <= view
        ? into + _margin
        : into + view - _margin - _panel.size.height;
    return shift.clamp(0.0, room);
  }

  Offset get _panelOffset => Offset(size.width - _panelWidth, panelShift);

  @override
  void paint(PaintingContext context, Offset offset) {
    context.paintChild(_main, offset);
    final at = _panelOffset;
    (_panel.parentData! as _StickyParentData).offset = at;
    context.paintChild(_panel, offset + at);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final at = _panelOffset;
    final hitPanel = result.addWithPaintOffset(
      offset: at,
      position: position,
      hitTest: (result, transformed) => _panel.hitTest(result, position: transformed),
    );
    return hitPanel || _main.hitTest(result, position: position);
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

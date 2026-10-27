import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/design/icons.dart';
import '../../../core/design/theme.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/typography.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/interactive.dart';
import '../../../core/widgets/stage_transitions.dart';
import '../../../data/models/settings.dart';
import '../../../data/repositories.dart';
import '../../../l10n/l10n.dart';
import '../../../services/system_fonts.dart';
import 'appearance_page.dart' show previewScriptProvider;

/// Whose script font is being chosen.
enum ScriptFontTarget { overlay, editor }

extension on ScriptFontTarget {
  ScriptFont of(AppSettings s) => this == ScriptFontTarget.overlay ? s.overlayFont : s.editorFont;
  ScriptFont get fallback => this == ScriptFontTarget.overlay ? ScriptFonts.overlayDefault : ScriptFonts.editorDefault;
  AppSettings apply(AppSettings s, ScriptFont f) =>
      this == ScriptFontTarget.overlay ? s.copyWith(overlayFont: f) : s.copyWith(editorFont: f);
}

/// The name shown for [font]: a bundled font's label, a system font's own.
String scriptFontLabel(ScriptFont font) => ScriptFonts.bundled(font.family)?.label ?? font.family;

Future<void> showScriptFontPicker(BuildContext context, ScriptFontTarget target) => showSottoDialog<void>(
  context: context,
  builder: (_) => ScriptFontPicker(target: target),
);

/// Pick the script's font: Sotto's own (free, with their licenses), or any
/// installed on this computer; its weight and letter spacing; previewed on a
/// real line of the script in the dark and light overlay styles.
class ScriptFontPicker extends ConsumerStatefulWidget {
  const ScriptFontPicker({super.key, required this.target});
  final ScriptFontTarget target;

  @override
  ConsumerState<ScriptFontPicker> createState() => _ScriptFontPickerState();
}

class _ScriptFontPickerState extends ConsumerState<ScriptFontPicker> {
  late ScriptFont _draft = widget.target.of(ref.read(settingsProvider));
  String _query = '';

  void _pick(ScriptFont f) => setState(() => _draft = f);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    final systemFonts = ref.watch(systemFontsProvider);
    final installed = systemFonts.value;
    final missing = _draft.isSystem && installed != null && !installed.contains(_draft.family);
    final bundled = ScriptFonts.bundled(_draft.family);
    final weights = bundled?.weights ?? const [300, 400, 500, 600, 700];

    return Dialog(
      backgroundColor: p.float,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.rL,
        side: BorderSide(color: p.control),
      ),
      child: SizedBox(
        width: 820,
        height: 600,
        child: Padding(
          padding: const EdgeInsets.all(Space.s5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.target == ScriptFontTarget.overlay ? l.scriptFontOverlayTitle : l.scriptFontEditorTitle,
                style: TypeScale.title2.copyWith(color: p.inkPrimary),
              ),
              const SizedBox(height: Space.s4),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 330, child: _list(context, systemFonts)),
                    const SizedBox(width: Space.s5),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _Preview(font: _draft, target: widget.target, missing: missing),
                          ),
                          const SizedBox(height: Space.s4),
                          Row(
                            children: [
                              Expanded(
                                child: Text(l.scriptFontWeight, style: TypeScale.body.copyWith(color: p.inkSecondary)),
                              ),
                              SottoSelect<int>(
                                width: 170,
                                value: ScriptFonts.clampWeight(bundled, _draft.weight),
                                options: [for (final w in weights) SelectOption(w, '$w')],
                                onChanged: (w) => _pick(_draft.copyWith(weight: w)),
                              ),
                            ],
                          ),
                          const SizedBox(height: Space.s3),
                          Row(
                            children: [
                              Expanded(
                                child: Text(l.scriptFontSpacing, style: TypeScale.body.copyWith(color: p.inkSecondary)),
                              ),
                              SottoSlider(
                                width: 170,
                                value: _draft.letterSpacing,
                                min: ScriptFonts.minSpacing,
                                max: ScriptFonts.maxSpacing,
                                divisions: 16,
                                label: '${NumberFormat('+0.00;-0.00', l.localeName).format(_draft.letterSpacing)} em',
                                onChanged: (v) => _pick(_draft.copyWith(letterSpacing: v)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.s4),
              Row(
                children: [
                  SottoButton.ghost(
                    label: l.scriptFontReset,
                    icon: SottoIcons.refresh,
                    onPressed: _draft == widget.target.fallback ? null : () => _pick(widget.target.fallback),
                  ),
                  const Spacer(),
                  SottoButton.ghost(label: l.cancel, onPressed: () => Navigator.pop(context)),
                  const SizedBox(width: Space.s2),
                  SottoButton.primary(
                    label: l.scriptFontApply,
                    onPressed: () {
                      final f = _draft;
                      ref.read(settingsProvider.notifier).update((s) => widget.target.apply(s, f));
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list(BuildContext context, AsyncValue<List<String>> systemFonts) {
    final p = context.palette;
    final l = context.l10n;
    final q = _query.trim().toLowerCase();
    final families = (systemFonts.value ?? const <String>[])
        .where((f) => q.isEmpty || f.toLowerCase().contains(q))
        .toList();
    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(4, Space.s3, 4, Space.s1_5),
      child: Text(text.toUpperCase(), style: TypeScale.monoLabel.copyWith(color: p.inkTertiary)),
    );
    return Container(
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: Radii.rM,
        border: Border.all(color: p.hairline),
      ),
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s2),
            sliver: SliverList.list(
              children: [
                header(l.scriptFontBundled),
                for (final f in ScriptFonts.all)
                  _FontRow(
                    label: f.label,
                    family: f.family,
                    detail: f.family == widget.target.fallback.family
                        ? '${l.scriptFontDefaultTag} · SIL OFL 1.1'
                        : 'SIL OFL 1.1',
                    selected: !_draft.isSystem && _draft.family == f.family,
                    onTap: () => _pick(
                      ScriptFont(
                        family: f.family,
                        weight: ScriptFonts.clampWeight(f, _draft.weight),
                        letterSpacing: _draft.letterSpacing,
                      ),
                    ),
                  ),
                header(l.scriptFontSystem),
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.s2),
                  child: SottoTextField(
                    placeholder: l.scriptFontSearch,
                    leading: SottoIcons.search,
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
              ],
            ),
          ),
          if (systemFonts.isLoading)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(Space.s3),
                child: Text(l.scriptFontLoading, style: TypeScale.caption.copyWith(color: p.inkTertiary)),
              ),
            )
          else if (families.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(Space.s3),
                child: Text(l.scriptFontNone, style: TypeScale.caption.copyWith(color: p.inkTertiary)),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(Space.s2, 0, Space.s2, Space.s2),
              sliver: SliverList.builder(
                itemCount: families.length,
                itemBuilder: (context, i) => _FontRow(
                  label: families[i],
                  family: families[i],
                  selected: _draft.isSystem && _draft.family == families[i],
                  onTap: () => _pick(
                    ScriptFont(
                      family: families[i],
                      source: FontSource.system,
                      weight: ScriptFonts.clampWeight(null, _draft.weight),
                      letterSpacing: _draft.letterSpacing,
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

/// One font in the list, its name drawn in the font itself.
class _FontRow extends StatelessWidget {
  const _FontRow({required this.label, required this.family, required this.selected, required this.onTap, this.detail});

  final String label;
  final String family;
  final String? detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Interactive(
      onTap: onTap,
      semanticLabel: label,
      builder: (context, st) => AnimatedContainer(
        duration: context.motion(Motion.quick),
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: Space.s3, vertical: Space.s2),
        decoration: BoxDecoration(
          color: selected ? p.primaryWash : (st.hovered ? p.pressWash : Colors.transparent),
          borderRadius: Radii.rS,
          border: Border.all(color: selected ? p.cueFill : Colors.transparent),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: family,
                  fontFamilyFallback: const [Fonts.interface],
                  fontSize: 17,
                  height: 1.3,
                  color: p.inkPrimary,
                ),
              ),
            ),
            if (detail != null) ...[
              const SizedBox(width: Space.s2),
              Text(detail!, style: TypeScale.micro.copyWith(color: p.inkTertiary)),
            ],
          ],
        ),
      ),
    );
  }
}

/// A real line of the script in [font]: on the overlay's dark and light
/// grounds (overlay font), or on the editor's page (editor font).
class _Preview extends ConsumerWidget {
  const _Preview({required this.font, required this.target, required this.missing});
  final ScriptFont font;
  final ScriptFontTarget target;
  final bool missing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final l = context.l10n;
    final script = ref.watch(previewScriptProvider);
    final line =
        script?.allBeats.map((b) => b.text.replaceAll('**', '')).where((t) => t.split(' ').length >= 6).firstOrNull ??
        l.scriptFontSample;
    final shown = missing ? target.fallback : font;
    final size = overlayFontSize(480, ref.watch(settingsProvider.select((s) => s.readingSize)));

    Widget overlay(OverlayPalette o, String label) => Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(Space.s4, Space.s3, Space.s4, Space.s3),
        decoration: BoxDecoration(
          color: Color.alphaBlend(o.ground, o.ink.computeLuminance() > 0.5 ? const Color(0xFF2A3140) : Colors.white),
          borderRadius: Radii.rM,
          border: Border.all(color: p.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(), style: TypeScale.monoLabel.copyWith(color: o.inkAt(0.5))),
            const SizedBox(height: Space.s2),
            Expanded(
              child: Text(
                line,
                maxLines: 3,
                overflow: TextOverflow.fade,
                style: ReadingType.live(size, font: shown).copyWith(color: o.ink),
              ),
            ),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (target == ScriptFontTarget.overlay) ...[
          overlay(OverlayPalette.dark, l.themeDark),
          const SizedBox(height: Space.s3),
          overlay(OverlayPalette.light, l.themeLight),
        ] else
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(Space.s4),
              decoration: BoxDecoration(
                color: p.raised,
                borderRadius: Radii.rM,
                border: Border.all(color: p.hairline),
              ),
              child: Text(line, style: ReadingType.editorIn(shown).copyWith(color: p.inkPrimary)),
            ),
          ),
        if (missing) ...[
          const SizedBox(height: Space.s2),
          Text(l.scriptFontMissing(font.family), style: TypeScale.caption.copyWith(color: p.caution)),
        ],
      ],
    );
  }
}

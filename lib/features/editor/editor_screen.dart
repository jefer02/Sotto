import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../l10n/l10n.dart';

import '../../app/app.dart';
import '../../core/design/icons.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../core/platform/platform_keys.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/controls.dart';
import '../../core/widgets/display.dart';
import '../../core/widgets/interactive.dart';
import '../../core/widgets/nav.dart';
import '../../core/widgets/window_chrome.dart';
import '../../data/models/script.dart';
import '../../data/models/shortcut.dart';
import '../../data/repositories.dart';
import '../library/library_actions.dart';
import '../library/library_shell.dart' show TitleBarDragSpacer;
import '../preflight/preflight_dialog.dart';
import 'editor_controller.dart';
import 'editor_inspector.dart';
import 'prep_tab.dart';
import 'rehearsals_tab.dart';
import 'write_tab.dart';

enum EditorTab { write, prep, rehearsals }

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key, required this.scriptId, this.tab = EditorTab.write});

  final String scriptId;
  final EditorTab tab;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  late EditorTab _tab = widget.tab;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(focusedScriptProvider.notifier).set(widget.scriptId);
    });
  }

  @override
  void didUpdateWidget(EditorScreen old) {
    super.didUpdateWidget(old);
    if (old.tab != widget.tab) _tab = widget.tab;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final e = ref.watch(editorProvider(widget.scriptId));
    final script = e.script;
    if (script == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.l10n.scriptMissing, style: TypeScale.body.copyWith(color: p.inkSecondary)),
              const SizedBox(height: 12),
              SottoButton(label: context.l10n.backToLibrary, onPressed: () => context.go('/')),
            ],
          ),
        ),
      );
    }
    final isMac = PlatformKeys.isMac;

    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.keyR, meta: isMac, control: !isMac): () =>
            unawaited(showPreflight(context, ref, script.id, rehearsal: true)),
      },
      child: Scaffold(
        body: Row(
          children: [
            _StructureSidebar(scriptId: widget.scriptId),
            Expanded(
              child: Column(
                children: [
                  _Header(
                    script: script,
                    save: e.save,
                    tab: _tab,
                    onTab: (t) => setState(() => _tab = t),
                    scriptId: widget.scriptId,
                  ),
                  Expanded(
                    child: switch (_tab) {
                      EditorTab.write => Row(
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                Expanded(child: WriteTab(scriptId: widget.scriptId)),
                                _Footer(scriptId: widget.scriptId),
                              ],
                            ),
                          ),
                          LayoutBuilder(
                            builder: (context, c) {
                              final wide = MediaQuery.sizeOf(context).width > 1180;
                              return wide ? EditorInspector(scriptId: widget.scriptId) : const SizedBox.shrink();
                            },
                          ),
                        ],
                      ),
                      EditorTab.prep => PrepTab(scriptId: widget.scriptId),
                      EditorTab.rehearsals => RehearsalsTab(scriptId: widget.scriptId),
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

class _Header extends ConsumerWidget {
  const _Header({
    required this.script,
    required this.save,
    required this.tab,
    required this.onTab,
    required this.scriptId,
  });
  final Script script;
  final SaveState save;
  final EditorTab tab;
  final ValueChanged<EditorTab> onTab;
  final String scriptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final settings = ref.watch(settingsProvider);
    final collections = ref.watch(collectionsProvider).value ?? const <Collection>[];
    final collection = collections.where((c) => c.id == script.collectionId).firstOrNull;
    return TitleBarArea(
      showCaptionButtons: true,
      child: Padding(
        padding: const EdgeInsets.only(left: 24, right: 12),
        child: Row(
          children: [
            // The breadcrumb yields space first — tabs and actions stay whole
            // in longer languages.
            if (collection != null) ...[
              Flexible(
                child: Interactive(
                  onTap: () => context.go('/collections/${collection.id}'),
                  builder: (context, s) => Text(
                    collection.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TypeScale.body.copyWith(color: s.hovered ? p.inkPrimary : p.inkTertiary),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('/', style: TypeScale.body.copyWith(color: p.inkDisabled)),
              ),
            ],
            Flexible(
              flex: 4,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: _TitleField(scriptId: scriptId, title: script.title),
              ),
            ),
            const SizedBox(width: 14),
            AnimatedSwitcher(
              duration: Motion.snappy,
              child: save == SaveState.saved
                  ? Row(
                      key: const ValueKey('saved'),
                      children: [
                        SottoIcon(SottoIcons.check, size: 12, color: p.inkTertiary),
                        const SizedBox(width: 5),
                        Text(context.l10n.saved, style: TypeScale.caption.copyWith(color: p.inkTertiary)),
                      ],
                    )
                  : Text(
                      context.l10n.editing,
                      key: const ValueKey('dirty'),
                      style: TypeScale.caption.copyWith(color: p.inkTertiary),
                    ),
            ),
            const Spacer(),
            SegmentedControl<EditorTab>(
              segments: [
                Segment(EditorTab.write, context.l10n.tabWrite),
                Segment(EditorTab.prep, context.l10n.tabQaPrep),
                Segment(EditorTab.rehearsals, context.l10n.tabRehearsals),
              ],
              value: tab,
              onChanged: onTab,
            ),
            const Spacer(),
            SottoButton(
              label: context.l10n.rehearse,
              icon: SottoIcons.rehearse,
              onPressed: () => unawaited(showPreflight(context, ref, script.id, rehearsal: true)),
            ),
            const SizedBox(width: 8),
            SottoButton.primary(
              label: context.l10n.goLive,
              icon: SottoIcons.play,
              shortcut: settings.shortcutFor(LiveAction.goLive),
              onPressed: () => unawaited(showPreflight(context, ref, script.id)),
            ),
          ],
        ),
      ),
    );
  }
}

class _TitleField extends ConsumerStatefulWidget {
  const _TitleField({required this.scriptId, required this.title});
  final String scriptId;
  final String title;

  @override
  ConsumerState<_TitleField> createState() => _TitleFieldState();
}

class _TitleFieldState extends ConsumerState<_TitleField> {
  late final _c = TextEditingController(text: widget.title);
  final _f = FocusNode();

  @override
  void didUpdateWidget(_TitleField old) {
    super.didUpdateWidget(old);
    if (!_f.hasFocus && _c.text != widget.title) _c.text = widget.title;
  }

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return IntrinsicWidth(
      child: TextField(
        controller: _c,
        focusNode: _f,
        style: TypeScale.bodyStrong.copyWith(color: p.inkPrimary),
        decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none),
        onChanged: (t) => ref
            .read(editorProvider(widget.scriptId).notifier)
            .update((s) => s.copyWith(title: t.trim().isEmpty ? L10n.current.untitledScript : t)),
      ),
    );
  }
}

class _StructureSidebar extends ConsumerWidget {
  const _StructureSidebar({required this.scriptId});
  final String scriptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final e = ref.watch(editorProvider(scriptId));
    final c = ref.read(editorProvider(scriptId).notifier);
    final settings = ref.watch(settingsProvider);
    final wpm = settings.wordsPerMinute;
    final script = e.script!;
    final timeline = Timeline(script, wpm);
    final target = script.targetSeconds;
    final sessions = ref.watch(sessionsProvider).value ?? const [];
    final rehearsals = sessions.where((r) => r.scriptId == script.id && r.rehearsal).length;
    final organizing = script.status == ScriptStatus.organizing;

    return Container(
      width: 264,
      decoration: BoxDecoration(
        color: p.panel,
        border: Border(right: BorderSide(color: p.hairline)),
      ),
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
              child: BackLink(label: context.l10n.library, onTap: () => context.go('/')),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 10, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(context.l10n.structure, style: TypeScale.title3.copyWith(color: p.inkPrimary)),
                ),
                SottoIconButton(
                  icon: SottoIcons.structure,
                  tooltip: context.l10n.organizeAgain,
                  size: 26,
                  onPressed: organizing ? null : () => unawaited(reorganize(ref, script)),
                ),
                SottoIconButton(
                  icon: SottoIcons.plus,
                  tooltip: context.l10n.addSection,
                  size: 26,
                  onPressed: () => c.addSection(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 2, 12, 12),
            child: Text(
              organizing
                  ? context.l10n.statusOrganizing
                  : context.l10n.structureSummary(script.sections.length, script.beatCount, script.cueCount),
              style: TypeScale.monoSmall.copyWith(color: p.inkTertiary),
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              buildDefaultDragHandles: false,
              itemCount: script.sections.length,
              onReorderItem: c.moveSection,
              proxyDecorator: (child, _, _) => Material(color: Colors.transparent, child: child),
              itemBuilder: (context, i) {
                final s = script.sections[i];
                final selected = i == e.section;
                return ReorderableDragStartListener(
                  key: ValueKey(s.id),
                  index: i,
                  child: _SectionItem(
                    index: i,
                    section: s,
                    seconds: s.estimatedSeconds(wpm),
                    selected: selected,
                    onTap: () => c.selectSection(i),
                    onDelete: script.sections.length > 1 ? () => c.deleteSection(i) : null,
                    onBudget: (secs) => c.updateSection(
                      i,
                      (x) => secs == null ? x.copyWith(clearBudget: true) : x.copyWith(budgetSeconds: secs),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: p.ground,
                borderRadius: Radii.rL,
                border: Border.all(color: p.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(context.l10n.timing, style: TypeScale.bodyStrong.copyWith(color: p.inkPrimary)),
                      ),
                      if (target != null)
                        Text(
                          '${timeline.total >= target ? '+' : '−'}${formatDuration((timeline.total - target).abs())}',
                          style: TypeScale.mono.copyWith(color: p.cueText),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SectionBar(
                    weights: [for (final s in script.sections) s.estimatedSeconds(wpm).toDouble().clamp(1, 1e9)],
                    highlight: e.section,
                    filled: e.section,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        context.l10n.plannedDuration(formatDuration(timeline.total)),
                        style: TypeScale.monoSmall.copyWith(color: p.inkTertiary),
                      ),
                      const Spacer(),
                      Interactive(
                        onTap: () => _editTarget(context, ref, script),
                        builder: (context, st) => Text(
                          target == null ? context.l10n.setTarget : context.l10n.targetDuration(formatDuration(target)),
                          style: TypeScale.monoSmall.copyWith(color: st.hovered ? p.inkPrimary : p.inkTertiary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    rehearsals > 0 ? context.l10n.paceNoteMeasured(rehearsals, wpm) : context.l10n.paceNote(wpm),
                    style: TypeScale.caption.copyWith(color: p.inkTertiary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editTarget(BuildContext context, WidgetRef ref, Script script) async {
    final v = await _promptDuration(context, context.l10n.targetLength, script.targetSeconds);
    if (v == null) return;
    ref
        .read(editorProvider(scriptId).notifier)
        .update((s) => v == 0 ? s.copyWith(clearTarget: true) : s.copyWith(targetSeconds: v));
  }
}

/// Asks for m:ss. Returns 0 to clear.
Future<int?> _promptDuration(BuildContext context, String title, int? current) async {
  final p = context.palette;
  final ctrl = TextEditingController(text: current == null ? '' : formatDuration(current));
  final result = await showDialog<int>(
    context: context,
    builder: (context) {
      void submit() {
        final parts = ctrl.text.trim().split(':');
        final m = int.tryParse(parts.first) ?? 0;
        final s = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
        Navigator.pop(context, m * 60 + s);
      }

      return AlertDialog(
        backgroundColor: p.float,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.rL,
          side: BorderSide(color: p.control),
        ),
        title: Text(title, style: TypeScale.title2.copyWith(color: p.inkPrimary)),
        content: SottoTextField(
          controller: ctrl,
          autofocus: true,
          mono: true,
          placeholder: context.l10n.durationPlaceholder,
          onSubmitted: (_) => submit(),
        ),
        actions: [
          SottoButton.ghost(label: context.l10n.cancel, onPressed: () => Navigator.pop(context)),
          SottoButton.primary(label: context.l10n.save, onPressed: submit),
        ],
      );
    },
  );
  ctrl.dispose();
  return result;
}

class _SectionItem extends StatelessWidget {
  const _SectionItem({
    required this.index,
    required this.section,
    required this.seconds,
    required this.selected,
    required this.onTap,
    required this.onDelete,
    required this.onBudget,
  });

  final int index;
  final Section section;
  final int seconds;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final ValueChanged<int?> onBudget;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Interactive(
        onTap: onTap,
        builder: (context, s) => AnimatedContainer(
          duration: Motion.quick,
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          decoration: BoxDecoration(
            color: selected ? p.float : (s.hovered ? p.hoverWash : Colors.transparent),
            borderRadius: Radii.rControl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 26,
                    child: Text(
                      (index + 1).toString().padLeft(2, '0'),
                      style: TypeScale.monoSmall.copyWith(color: selected ? p.cueText : p.inkTertiary),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      section.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: (selected ? TypeScale.bodyStrong : TypeScale.body).copyWith(
                        color: selected ? p.inkPrimary : p.inkSecondary,
                      ),
                    ),
                  ),
                  if (s.hovered && onDelete != null)
                    SottoIconButton(
                      icon: SottoIcons.close,
                      tooltip: context.l10n.deleteSection,
                      size: 20,
                      iconSize: 11,
                      onPressed: onDelete,
                    )
                  else
                    Interactive(
                      onTap: () async {
                        final v = await _promptDuration(
                          context,
                          context.l10n.timeForSection(section.title),
                          section.budgetSeconds ?? seconds,
                        );
                        if (v != null) onBudget(v == 0 ? null : v);
                      },
                      builder: (context, st) => Text(
                        formatDuration(seconds),
                        style: TypeScale.monoSmall.copyWith(
                          color: st.hovered
                              ? p.inkPrimary
                              : (section.budgetSeconds == null ? p.inkDisabled : p.inkTertiary),
                        ),
                      ),
                    ),
                ],
              ),
              if (selected && section.keyPoints.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  margin: const EdgeInsets.only(left: 26),
                  padding: const EdgeInsets.only(left: 12),
                  decoration: BoxDecoration(
                    border: Border(left: BorderSide(color: p.control)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final k in section.keyPoints.take(4))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(k, style: TypeScale.caption.copyWith(color: p.inkTertiary)),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        context.l10n.beatsAndCues(section.beats.length, section.cueCount),
                        style: TypeScale.monoSmall.copyWith(color: p.inkTertiary, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Footer extends ConsumerWidget {
  const _Footer({required this.scriptId});
  final String scriptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final e = ref.watch(editorProvider(scriptId));
    final wpm = ref.watch(settingsProvider.select((s) => s.wordsPerMinute));
    final script = e.script!;
    final si = e.section.clamp(0, script.sections.length - 1);
    final section = script.sections[si];
    final bi = section.beats.indexWhere((b) => b.id == e.focusedBeat);
    final words = section.wordCount;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.hairline)),
      ),
      child: Row(
        children: [
          Text(
            context.l10n.wordsAtPace(words, formatDuration((words * 60 / wpm).round()), wpm),
            style: TypeScale.monoSmall.copyWith(color: p.inkTertiary),
          ),
          const Spacer(),
          if (bi >= 0)
            Text(
              context.l10n.beatWords(si + 1, bi + 1, section.beats[bi].wordCount),
              style: TypeScale.monoSmall.copyWith(color: p.inkTertiary),
            ),
        ],
      ),
    );
  }
}

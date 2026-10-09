import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

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
import '../../data/models/script.dart';
import '../../data/models/shortcut.dart';
import '../../data/repositories.dart';
import '../preflight/preflight_dialog.dart';
import 'library_actions.dart';
import 'organize_jobs.dart';
import 'library_shell.dart';

class LibraryFilter {
  const LibraryFilter.all() : collectionId = null, archive = false;
  const LibraryFilter.archive() : collectionId = null, archive = true;
  const LibraryFilter.collection(String this.collectionId) : archive = false;

  final String? collectionId;
  final bool archive;
}

enum _StatusFilter { all, drafts, ready }

/// Wraps library pages: drop files anywhere, or paste with ⌘V.
class _ImportSurface extends ConsumerStatefulWidget {
  const _ImportSurface({required this.child, this.collectionId});
  final Widget child;
  final String? collectionId;

  @override
  ConsumerState<_ImportSurface> createState() => _ImportSurfaceState();
}

class _ImportSurfaceState extends ConsumerState<_ImportSurface> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final isMac = PlatformKeys.isMac;
    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.keyV, meta: isMac, control: !isMac): () =>
            unawaited(importFromClipboard(ref, collectionId: widget.collectionId)),
      },
      child: Focus(
        autofocus: true,
        child: DropTarget(
          onDragEntered: (_) => setState(() => _dragging = true),
          onDragExited: (_) => setState(() => _dragging = false),
          onDragDone: (d) {
            setState(() => _dragging = false);
            unawaited(
              importFiles(ref, context, paths: [for (final f in d.files) f.path], collectionId: widget.collectionId),
            );
          },
          child: _DraggingScope(dragging: _dragging, child: widget.child),
        ),
      ),
    );
  }
}

class _DraggingScope extends InheritedWidget {
  const _DraggingScope({required this.dragging, required super.child});
  final bool dragging;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DraggingScope>()?.dragging ?? false;

  @override
  bool updateShouldNotify(_DraggingScope old) => old.dragging != dragging;
}

List<Widget> _headerActions(BuildContext context, WidgetRef ref, {String? collectionId}) => [
  SottoButton(
    label: context.l10n.import,
    icon: SottoIcons.import,
    onPressed: () => unawaited(importFiles(ref, context, collectionId: collectionId)),
  ),
  SottoButton.primary(
    label: context.l10n.newScript,
    icon: SottoIcons.plus,
    shortcutText: '${PlatformKeys.primary}N',
    onPressed: () => unawaited(createScriptAndOpen(ref, collectionId: collectionId)),
  ),
];

// ───────────────────────────── Home ─────────────────────────────

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  _StatusFilter _filter = _StatusFilter.all;
  bool _grid = true;

  static Script? upNext(List<Script> scripts) {
    final now = DateTime.now();
    final active = scripts.where((s) => !s.archived && s.status != ScriptStatus.organizing).toList();
    final scheduled = active
        .where((s) => s.scheduledAt != null && s.scheduledAt!.isAfter(now.subtract(const Duration(hours: 1))))
        .sortedBy((s) => s.scheduledAt!);
    // Nothing scheduled: the latest script with something to read.
    return scheduled.firstOrNull ?? active.where((s) => s.wordCount > 0).sortedBy((s) => s.updatedAt).lastOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final scripts = ref.watch(scriptsProvider).value ?? const <Script>[];
    final next = upNext(scripts);
    // The global ⌃⌥L starts "Up next" from the library.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(focusedScriptProvider.notifier).set(next?.id);
    });

    final recent = scripts
        .where((s) => !s.archived)
        .where(
          (s) => switch (_filter) {
            _StatusFilter.all => true,
            _StatusFilter.drafts => s.status == ScriptStatus.draft || s.status == ScriptStatus.organizing,
            _StatusFilter.ready => s.status == ScriptStatus.structured || s.status == ScriptStatus.ready,
          },
        );

    return _ImportSurface(
      child: Column(
        children: [
          LibraryHeader(title: context.l10n.navHome, actions: _headerActions(context, ref)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(40, 32, 40, 40),
              children: [
                _Greeting(scripts: scripts),
                const SizedBox(height: 32),
                if (next != null) ...[
                  Align(alignment: Alignment.centerLeft, child: SectionHeading(context.l10n.upNext)),
                  const SizedBox(height: 12),
                  _UpNextCard(script: next),
                  const SizedBox(height: 36),
                ],
                Row(
                  children: [
                    SectionHeading(context.l10n.recentScripts),
                    const Spacer(),
                    SegmentedControl<_StatusFilter>(
                      height: 26,
                      segments: [
                        Segment(_StatusFilter.all, context.l10n.filterAll),
                        Segment(_StatusFilter.drafts, context.l10n.filterDrafts),
                        Segment(_StatusFilter.ready, context.l10n.filterReady),
                      ],
                      value: _filter,
                      onChanged: (v) => setState(() => _filter = v),
                    ),
                    const SizedBox(width: 10),
                    SottoIconButton(
                      icon: SottoIcons.layers,
                      tooltip: context.l10n.gridView,
                      selected: _grid,
                      onPressed: () => setState(() => _grid = true),
                    ),
                    SottoIconButton(
                      icon: SottoIcons.structure,
                      tooltip: context.l10n.listView,
                      selected: !_grid,
                      onPressed: () => setState(() => _grid = false),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (recent.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: emptyState(
                      context,
                      icon: SottoIcons.doc,
                      title: context.l10n.emptyNoScriptsHere,
                      body: context.l10n.emptyWriteOrDrop,
                    ),
                  )
                else
                  ScriptCollectionView(scripts: recent.take(9).toList(), grid: _grid),
                const SizedBox(height: 20),
                ImportDropHint(
                  active: _DraggingScope.of(context),
                  onBrowse: () => unawaited(importFiles(ref, context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Good afternoon" over today's date and a one-line read of the library,
/// its figures lit in tungsten.
class _Greeting extends ConsumerWidget {
  const _Greeting({required this.scripts});
  final List<Script> scripts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final l = context.l10n;
    final wpm = ref.watch(settingsProvider).wordsPerMinute;
    final now = DateTime.now();
    final active = scripts.where((s) => !s.archived).toList();
    final ready = active
        .where((s) => (s.status == ScriptStatus.structured || s.status == ScriptStatus.ready) && s.wordCount > 0)
        .length;
    final minutes = (active.fold<int>(0, (a, s) => a + s.estimatedSeconds(wpm)) / 60).round();
    final greeting = now.hour < 12
        ? l.greetingMorning
        : now.hour < 19
        ? l.greetingAfternoon
        : l.greetingEvening;

    final figure = TypeScale.bodyStrong.copyWith(color: p.primaryText);
    final words = TypeScale.body.copyWith(color: p.inkSecondary);
    final dot = TextSpan(
      text: '   ·   ',
      style: words.copyWith(color: p.inkTertiary),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          toBeginningOfSentenceCase(DateFormat.MMMMEEEEd(l.localeName).format(now)),
          style: TypeScale.mono.copyWith(color: p.inkTertiary),
        ),
        const SizedBox(height: 8),
        Text(greeting, style: TypeScale.display.copyWith(color: p.inkPrimary)),
        const SizedBox(height: 10),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: '${active.length} ', style: figure),
              TextSpan(text: l.homeStatScripts(active.length), style: words),
              dot,
              TextSpan(text: '$ready ', style: figure),
              TextSpan(text: l.homeStatReady(ready), style: words),
              dot,
              TextSpan(text: '$minutes ', style: figure),
              TextSpan(text: l.homeStatMinutes, style: words),
            ],
          ),
        ),
      ],
    );
  }
}

class _UpNextCard extends ConsumerWidget {
  const _UpNextCard({required this.script});
  final Script script;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final settings = ref.watch(settingsProvider);
    final wpm = settings.wordsPerMinute;
    final sessions = ref.watch(sessionsProvider).value ?? const [];
    final last = sessions.firstWhereOrNull((s) => s.scriptId == script.id && s.rehearsal);
    final total = script.targetSeconds ?? script.estimatedSeconds(wpm);
    final now = DateTime.now();
    final at = script.scheduledAt;

    String when() {
      if (at == null) return relativeTime(script.updatedAt, edited: true);
      final sameDay = at.year == now.year && at.month == now.month && at.day == now.day;
      return '${sameDay ? context.l10n.timeToday : relativeTime(at)} · ${clockTime(at)}';
    }

    final minutesAway = at?.difference(now).inMinutes;

    // The featured script stands in its own spotlight.
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: p.panel,
        gradient: RadialGradient(
          center: const Alignment(-1, -1.4),
          radius: 1.6,
          colors: [
            Color.alphaBlend(p.primary.withValues(alpha: p.isDark ? 0.13 : 0.16), p.raised),
            p.panel,
          ],
        ),
        borderRadius: Radii.rL,
        border: Border.all(color: p.primary.withValues(alpha: p.isDark ? 0.22 : 0.32)),
        boxShadow: [
          BoxShadow(color: p.primary.withValues(alpha: p.isDark ? 0.07 : 0.10), blurRadius: 40, spreadRadius: -6),
          BoxShadow(
            color: Color(p.isDark ? 0x80000000 : 0x1A1C1916),
            offset: const Offset(0, 12),
            blurRadius: 28,
            spreadRadius: -12,
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(when(), style: TypeScale.mono.copyWith(color: p.primaryText)),
                      if (minutesAway != null && minutesAway > 0 && minutesAway < 24 * 60) ...[
                        const SizedBox(width: 10),
                        StatusChip(
                          minutesAway < 60
                              ? context.l10n.inMinutes(minutesAway)
                              : context.l10n.inHours((minutesAway / 60).round()),
                          tone: ChipTone.cue,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  Interactive(
                    onTap: () => context.go('/script/${script.id}'),
                    builder: (context, s) => Text(
                      script.title,
                      style: TypeScale.title1.copyWith(color: s.hovered ? p.cueText : p.inkPrimary),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    [
                      context.l10n.sectionsCount(script.sections.length),
                      context.l10n.atYourPace(formatMinutes(total), wpm),
                      if (script.rehearsalCount > 0) context.l10n.rehearsedTimes(script.rehearsalCount),
                      if (script.prepDocs.isNotEmpty) context.l10n.prepDocsCount(script.prepDocs.length),
                    ].join(' · '),
                    style: TypeScale.body.copyWith(color: p.inkSecondary),
                  ),
                  const SizedBox(height: 22),
                  SectionBar(
                    weights: [for (final s in script.sections) s.estimatedSeconds(wpm).toDouble().clamp(1, 1e9)],
                    labels: [for (final s in script.sections) s.title],
                    height: 3,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 24),
            VerticalDivider(width: 1, thickness: 1, color: p.hairline),
            const SizedBox(width: 32),
            SizedBox(
              width: 212,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SottoButton.primary(
                    label: context.l10n.goLive,
                    icon: SottoIcons.play,
                    size: ButtonSize.large,
                    expand: true,
                    shortcut: settings.shortcutFor(LiveAction.goLive),
                    onPressed: () => unawaited(showPreflight(context, ref, script.id)),
                  ),
                  const SizedBox(height: 10),
                  SottoButton(
                    label: context.l10n.rehearse,
                    icon: SottoIcons.rehearse,
                    size: ButtonSize.large,
                    expand: true,
                    onPressed: () => unawaited(showPreflight(context, ref, script.id, rehearsal: true)),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    last == null
                        ? context.l10n.notRehearsedYet
                        : context.l10n.lastRehearsal(formatDuration(last.durationSeconds)) +
                              (last.plannedSeconds == null
                                  ? ''
                                  : ' · ${last.durationSeconds >= last.plannedSeconds! ? '+' : '−'}${formatDuration((last.durationSeconds - last.plannedSeconds!).abs())}'),
                    textAlign: TextAlign.center,
                    style: TypeScale.caption.copyWith(color: p.inkTertiary),
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

// ───────────────────────────── Lists ─────────────────────────────

class ScriptListScreen extends ConsumerStatefulWidget {
  const ScriptListScreen({super.key, required this.filter});
  final LibraryFilter filter;

  @override
  ConsumerState<ScriptListScreen> createState() => _ScriptListScreenState();
}

class _ScriptListScreenState extends ConsumerState<ScriptListScreen> {
  bool _grid = true;

  @override
  Widget build(BuildContext context) {
    final f = widget.filter;
    final query = ref.watch(librarySearchProvider).trim().toLowerCase();
    final collections = ref.watch(collectionsProvider).value ?? const <Collection>[];
    final all = ref.watch(scriptsProvider).value ?? const <Script>[];
    final collection = collections.firstWhereOrNull((c) => c.id == f.collectionId);

    final scripts = all.where((s) {
      if (f.archive != s.archived) return false;
      if (f.collectionId != null && s.collectionId != f.collectionId) return false;
      if (query.isEmpty) return true;
      return s.title.toLowerCase().contains(query) || s.allBeats.any((b) => b.plainText.toLowerCase().contains(query));
    }).toList();

    final title = f.archive
        ? context.l10n.navArchive
        : (collection?.name ?? (query.isEmpty ? context.l10n.navAllScripts : context.l10n.search));

    return _ImportSurface(
      collectionId: f.collectionId,
      child: Column(
        children: [
          LibraryHeader(
            title: title,
            actions: [
              if (collection != null)
                SottoButton.ghost(
                  label: context.l10n.deleteCollection,
                  onPressed: () async {
                    await ref.read(scriptRepositoryProvider).deleteCollection(collection.id);
                    if (context.mounted) context.go('/scripts');
                  },
                ),
              if (!f.archive) ..._headerActions(context, ref, collectionId: f.collectionId),
            ],
          ),
          Expanded(
            child: scripts.isEmpty
                ? emptyState(
                    context,
                    icon: f.archive
                        ? SottoIcons.archive
                        : query.isEmpty
                        ? (f.collectionId != null ? SottoIcons.folder : SottoIcons.doc)
                        : SottoIcons.search,
                    title: f.archive
                        ? context.l10n.emptyNothingArchived
                        : (query.isEmpty ? context.l10n.emptyNoScripts : context.l10n.emptyNoMatches),
                    body: f.archive
                        ? context.l10n.emptyArchivedHint
                        : query.isEmpty
                        ? context.l10n.emptyWriteOrDrop
                        : context.l10n.emptyNoMatchesHint(query),
                    action: f.archive || query.isNotEmpty
                        ? null
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SottoButton(
                                label: context.l10n.import,
                                icon: SottoIcons.import,
                                onPressed: () => unawaited(importFiles(ref, context, collectionId: f.collectionId)),
                              ),
                              const SizedBox(width: 8),
                              SottoButton.primary(
                                label: context.l10n.newScript,
                                icon: SottoIcons.plus,
                                onPressed: () => unawaited(createScriptAndOpen(ref, collectionId: f.collectionId)),
                              ),
                            ],
                          ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(40, 28, 40, 40),
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (collection != null) ...[
                            _ToneDot(color: context.palette.collectionColor(collection.tone)),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TypeScale.display.copyWith(fontSize: 26, color: context.palette.inkPrimary),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Text(
                                  context.l10n.scriptsCount(scripts.length),
                                  style: TypeScale.mono.copyWith(color: context.palette.inkTertiary),
                                ),
                              ],
                            ),
                          ),
                          SottoIconButton(
                            icon: SottoIcons.layers,
                            tooltip: context.l10n.gridView,
                            selected: _grid,
                            onPressed: () => setState(() => _grid = true),
                          ),
                          SottoIconButton(
                            icon: SottoIcons.structure,
                            tooltip: context.l10n.listView,
                            selected: !_grid,
                            onPressed: () => setState(() => _grid = false),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      ScriptCollectionView(scripts: scripts, grid: _grid),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// A collection's color as a small lit lamp beside its title.
class _ToneDot extends StatelessWidget {
  const _ToneDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color,
      boxShadow: [BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 10)],
    ),
  );
}

class ScriptCollectionView extends StatelessWidget {
  const ScriptCollectionView({super.key, required this.scripts, required this.grid});

  final List<Script> scripts;
  final bool grid;

  @override
  Widget build(BuildContext context) {
    if (!grid) {
      return Column(children: [for (final s in scripts) ScriptRow(script: s)]);
    }
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth > 900 ? 3 : (c.maxWidth > 560 ? 2 : 1);
        const gap = 14.0;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final s in scripts)
              SizedBox(
                width: w,
                child: ScriptCard(script: s),
              ),
          ],
        );
      },
    );
  }
}

class ScriptCard extends ConsumerWidget {
  const ScriptCard({super.key, required this.script});
  final Script script;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final wpm = ref.watch(settingsProvider).wordsPerMinute;
    final collections = ref.watch(collectionsProvider).value ?? const <Collection>[];
    final collection = collections.firstWhereOrNull((c) => c.id == script.collectionId);
    final organizing = script.status == ScriptStatus.organizing;
    final progress = organizing ? ref.watch(organizeProgressProvider(script.id)) : null;
    final tone = p.collectionColor(collection?.tone);

    return ScriptContextMenu(
      script: script,
      child: Interactive(
        onTap: () => context.go('/script/${script.id}'),
        builder: (context, s) => SurfaceCard(
          hovered: s.hovered,
          accent: collection == null ? null : tone,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 20,
                child: Row(
                  children: [
                    SottoIcon(SottoIcons.folder, size: 13, color: tone),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        collection?.name ?? context.l10n.noCollection,
                        overflow: TextOverflow.ellipsis,
                        style: TypeScale.caption.copyWith(color: p.inkTertiary),
                      ),
                    ),
                    StatusChip.forScript(context, script),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                script.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TypeScale.title3.copyWith(color: p.inkPrimary),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 40,
                child: Text(
                  organizing && script.excerpt.isEmpty
                      ? context.l10n.importedFinding(script.sourceName ?? context.l10n.importedFromText)
                      : (script.excerpt.isEmpty ? context.l10n.emptyScript : script.excerpt),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TypeScale.body.copyWith(color: p.inkSecondary),
                ),
              ),
              const SizedBox(height: 14),
              if (organizing)
                progress == null ? const _OrganizingBar() : RefineProgressBar(fraction: progress.fraction)
              else
                SectionBar(
                  weights: [for (final sec in script.sections) sec.estimatedSeconds(wpm).toDouble().clamp(1, 1e9)],
                  trackColor: collection == null ? null : tone.withValues(alpha: p.isDark ? 0.42 : 0.45),
                ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    organizing
                        ? (progress == null
                              ? context.l10n.statusOrganizing
                              : context.l10n.refiningProgress(progress.done, progress.total))
                        : '${formatMinutes(script.estimatedSeconds(wpm))} · ${context.l10n.sectionsCount(script.sections.length)}',
                    style: TypeScale.monoSmall.copyWith(color: p.inkTertiary),
                  ),
                  const Spacer(),
                  Text(
                    organizing ? context.l10n.timeJustNow : relativeTime(script.updatedAt),
                    style: TypeScale.caption.copyWith(color: p.inkTertiary),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chunks refined so far, as a filling hairline.
class RefineProgressBar extends StatelessWidget {
  const RefineProgressBar({super.key, required this.fraction});
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: fraction.clamp(0.0, 1.0)),
      duration: Motion.smooth,
      builder: (context, t, _) => ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          height: 3,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: p.control),
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: t,
                child: ColoredBox(color: p.cueFill),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Animated tungsten segments while a script is being organized.
class _OrganizingBar extends StatefulWidget {
  const _OrganizingBar();

  @override
  State<_OrganizingBar> createState() => _OrganizingBarState();
}

class _OrganizingBarState extends State<_OrganizingBar> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Row(
        children: [
          for (var i = 0; i < 6; i++)
            Expanded(
              child: Container(
                height: 3,
                margin: EdgeInsets.only(right: i == 5 ? 0 : 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: Color.lerp(
                    p.control,
                    p.cueFill.withValues(alpha: 0.7),
                    (1 - ((_c.value * 6 - i).abs() % 6) / 2).clamp(0.0, 1.0),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ScriptRow extends ConsumerWidget {
  const ScriptRow({super.key, required this.script});
  final Script script;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final wpm = ref.watch(settingsProvider).wordsPerMinute;
    final collections = ref.watch(collectionsProvider).value ?? const <Collection>[];
    final collection = collections.firstWhereOrNull((c) => c.id == script.collectionId);
    return ScriptContextMenu(
      script: script,
      child: Interactive(
        onTap: () => context.go('/script/${script.id}'),
        builder: (context, s) => AnimatedContainer(
          duration: Motion.quick,
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: s.hovered ? p.raised : Colors.transparent,
            borderRadius: Radii.rM,
            border: Border(bottom: BorderSide(color: s.hovered ? Colors.transparent : p.hairline)),
          ),
          child: Row(
            children: [
              SottoIcon(SottoIcons.doc, size: 15, color: p.collectionColor(collection?.tone)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  script.title,
                  overflow: TextOverflow.ellipsis,
                  style: TypeScale.bodyStrong.copyWith(color: p.inkPrimary),
                ),
              ),
              StatusChip.forScript(context, script),
              const SizedBox(width: 20),
              SizedBox(
                width: 150,
                child: Text(
                  '${formatMinutes(script.estimatedSeconds(wpm))} · ${context.l10n.sectionsCount(script.sections.length)}',
                  style: TypeScale.monoSmall.copyWith(color: p.inkTertiary),
                ),
              ),
              SizedBox(
                width: 110,
                child: Text(
                  relativeTime(script.updatedAt),
                  textAlign: TextAlign.right,
                  style: TypeScale.caption.copyWith(color: p.inkTertiary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── Context menu ─────────────────────────────

/// Right-click menu from the component sheet: Open, Rehearse, Go live,
/// Duplicate, Move to collection, Export, Delete.
class ScriptContextMenu extends ConsumerStatefulWidget {
  const ScriptContextMenu({super.key, required this.script, required this.child});

  final Script script;
  final Widget child;

  @override
  ConsumerState<ScriptContextMenu> createState() => _ScriptContextMenuState();
}

class _ScriptContextMenuState extends ConsumerState<ScriptContextMenu> {
  final _controller = MenuController();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = widget.script;
    final repo = ref.read(scriptRepositoryProvider);
    final collections = ref.watch(collectionsProvider).value ?? const <Collection>[];
    final settings = ref.watch(settingsProvider);

    Widget item(String label, SottoIcons icon, VoidCallback onTap, {String? shortcut, bool danger = false}) =>
        MenuItemButton(
          onPressed: onTap,
          leadingIcon: SottoIcon(icon, size: 14, color: danger ? p.liveCapture : p.inkSecondary),
          trailingIcon: shortcut == null
              ? null
              : Text(shortcut, style: TypeScale.keycap.copyWith(color: p.inkTertiary, fontSize: 10)),
          style: _menuItemStyle(p),
          child: Text(label, style: TypeScale.body.copyWith(color: danger ? p.liveCapture : p.inkPrimary)),
        );

    return MenuAnchor(
      controller: _controller,
      style: _menuStyle(p),
      menuChildren: [
        item(context.l10n.menuOpen, SottoIcons.doc, () => context.go('/script/${s.id}'), shortcut: '↩'),
        item(
          context.l10n.rehearse,
          SottoIcons.rehearse,
          () => unawaited(showPreflight(context, ref, s.id, rehearsal: true)),
          shortcut: '${PlatformKeys.primary}R',
        ),
        item(
          context.l10n.goLive,
          SottoIcons.play,
          () => unawaited(showPreflight(context, ref, s.id)),
          shortcut: PlatformKeys.describe(settings.shortcutFor(LiveAction.goLive)),
        ),
        item(
          context.l10n.menuDuplicate,
          SottoIcons.copy,
          () => unawaited(repo.duplicate(s)),
          shortcut: '${PlatformKeys.primary}D',
        ),
        Divider(height: 9, color: p.control),
        SubmenuButton(
          style: _menuItemStyle(p),
          menuStyle: _menuStyle(p),
          leadingIcon: SottoIcon(SottoIcons.folder, size: 14, color: p.inkSecondary),
          menuChildren: [
            for (final c in collections)
              MenuItemButton(
                style: _menuItemStyle(p),
                onPressed: () => unawaited(repo.save(s.copyWith(collectionId: c.id, updatedAt: s.updatedAt))),
                trailingIcon: c.id == s.collectionId ? SottoIcon(SottoIcons.check, size: 13, color: p.cueText) : null,
                child: Text(c.name, style: TypeScale.body.copyWith(color: p.inkPrimary)),
              ),
            MenuItemButton(
              style: _menuItemStyle(p),
              onPressed: () => unawaited(repo.save(s.copyWith(clearCollection: true, updatedAt: s.updatedAt))),
              child: Text(context.l10n.noCollection, style: TypeScale.body.copyWith(color: p.inkSecondary)),
            ),
          ],
          child: Text(context.l10n.menuMoveToCollection, style: TypeScale.body.copyWith(color: p.inkPrimary)),
        ),
        item(context.l10n.menuSchedule, SottoIcons.calendar, () => unawaited(_schedule(context, s))),
        item(context.l10n.menuExportMarkdown, SottoIcons.import, () => unawaited(_export(s))),
        item(
          s.archived ? context.l10n.menuUnarchive : context.l10n.menuArchive,
          SottoIcons.archive,
          () => unawaited(repo.save(s.copyWith(archived: !s.archived, updatedAt: s.updatedAt))),
        ),
        Divider(height: 9, color: p.control),
        item(
          context.l10n.delete,
          SottoIcons.close,
          () => unawaited(_confirmDelete(context, s)),
          shortcut: '${PlatformKeys.primary}⌫',
          danger: true,
        ),
      ],
      child: GestureDetector(
        onSecondaryTapUp: (d) => _controller.open(position: d.localPosition),
        onLongPressStart: (d) => _controller.open(position: d.localPosition),
        child: widget.child,
      ),
    );
  }

  Future<void> _export(Script s) async {
    final md = StringBuffer('# ${s.title}\n\n');
    for (final sec in s.sections) {
      md.writeln('## ${sec.title}\n');
      for (final k in sec.keyPoints) {
        md.writeln('- $k');
      }
      if (sec.keyPoints.isNotEmpty) md.writeln();
      for (final b in sec.beats) {
        md.writeln('${b.cue == null ? '' : '${b.cue!.token} '}${b.text}');
      }
      md.writeln();
    }
    await FilePicker.saveFile(
      fileName: '${s.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-')}.md',
      bytes: utf8.encode(md.toString()),
      mimeType: 'text/markdown',
      dialogTitle: context.l10n.exportScript,
    );
  }

  Future<void> _schedule(BuildContext context, Script s) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: s.scheduledAt ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(s.scheduledAt ?? now.add(const Duration(hours: 1))),
    );
    if (time == null) return;
    await ref
        .read(scriptRepositoryProvider)
        .save(
          s.copyWith(
            scheduledAt: DateTime(date.year, date.month, date.day, time.hour, time.minute),
            updatedAt: s.updatedAt,
          ),
        );
  }

  Future<void> _confirmDelete(BuildContext context, Script s) async {
    final p = context.palette;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: p.float,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.rL,
          side: BorderSide(color: p.control),
        ),
        title: Text(context.l10n.deleteScriptTitle(s.title), style: TypeScale.title2.copyWith(color: p.inkPrimary)),
        content: Text(context.l10n.deleteScriptBody, style: TypeScale.body.copyWith(color: p.inkSecondary)),
        actions: [
          SottoButton.ghost(label: context.l10n.cancel, onPressed: () => Navigator.pop(context, false)),
          SottoButton(label: context.l10n.delete, onPressed: () => Navigator.pop(context, true)),
        ],
      ),
    );
    if (ok == true) await ref.read(scriptRepositoryProvider).delete(s.id);
  }
}

MenuStyle _menuStyle(SottoPalette p) => MenuStyle(
  backgroundColor: WidgetStatePropertyAll(p.float),
  surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
  padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(
      borderRadius: Radii.rM,
      side: BorderSide(color: p.control),
    ),
  ),
  elevation: const WidgetStatePropertyAll(10),
  shadowColor: const WidgetStatePropertyAll(Color(0x99000000)),
);

ButtonStyle _menuItemStyle(SottoPalette p) => ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(Size(220, 30)),
  padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
  shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: Radii.rS)),
  backgroundColor: WidgetStateProperty.resolveWith(
    (s) => s.contains(WidgetState.hovered) || s.contains(WidgetState.focused) ? p.pressWash : Colors.transparent,
  ),
  overlayColor: const WidgetStatePropertyAll(Colors.transparent),
);

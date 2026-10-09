import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import '../../l10n/l10n.dart';

import '../../core/design/icons.dart';
import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../core/platform/platform_keys.dart';
import '../../core/utils/ids.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/controls.dart';
import '../../core/widgets/display.dart';
import '../../core/widgets/interactive.dart';
import '../../core/widgets/nav.dart';
import '../../core/widgets/window_chrome.dart';
import '../../data/models/script.dart';
import '../../data/repositories.dart';
import '../onboarding/welcome_dialog.dart';
import 'readiness.dart';

/// Search text shared by the sidebar field and the script lists.
class LibrarySearch extends Notifier<String> {
  @override
  String build() => '';

  void set(String q) => state = q;
}

final librarySearchProvider = NotifierProvider<LibrarySearch, String>(LibrarySearch.new);

class LibraryShell extends ConsumerStatefulWidget {
  const LibraryShell({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LibraryShell> createState() => _LibraryShellState();
}

class _LibraryShellState extends ConsumerState<LibraryShell> {
  bool _collapsed = false;
  final _searchFocus = FocusNode();
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(showWelcomeIfNeeded(context, ref));
    });
  }

  @override
  void dispose() {
    _searchFocus.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isMac = PlatformKeys.isMac;
    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.keyK, meta: isMac, control: !isMac): () {
          setState(() => _collapsed = false);
          _searchFocus.requestFocus();
        },
      },
      child: Scaffold(
        body: Row(
          children: [
            AnimatedContainer(
              duration: Motion.smooth,
              curve: Motion.shiftMove,
              width: _collapsed ? Layout.sidebarCollapsed : Layout.sidebar,
              decoration: sidebarDecoration(p),
              child: ClipRect(
                child: _Sidebar(
                  collapsed: _collapsed,
                  onToggle: () => setState(() => _collapsed = !_collapsed),
                  searchFocus: _searchFocus,
                  search: _search,
                ),
              ),
            ),
            Expanded(child: StageGlow(child: widget.child)),
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.collapsed, required this.onToggle, required this.searchFocus, required this.search});

  final bool collapsed;
  final VoidCallback onToggle;
  final FocusNode searchFocus;
  final TextEditingController search;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final location = GoRouterState.of(context).uri.path;
    final scripts = ref.watch(scriptsProvider).value ?? const <Script>[];
    final sessions = ref.watch(sessionsProvider).value ?? const [];
    final collections = ref.watch(collectionsProvider).value ?? const <Collection>[];
    final active = scripts.where((s) => !s.archived).toList();
    final showChat = ref.watch(settingsProvider.select((s) => s.showChat));
    final showForms = ref.watch(settingsProvider.select((s) => s.showFormsNav));

    void go(String path) => context.go(path);
    final toggle = SottoIconButton(
      icon: SottoIcons.onTop,
      tooltip: collapsed ? context.l10n.sidebarShow : context.l10n.sidebarHide,
      onPressed: onToggle,
      iconSize: 15,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Traffic lights live in the hidden title bar on macOS.
        SizedBox(
          height: Layout.titleBar,
          child: Row(
            children: [
              Expanded(
                child: collapsed
                    ? const TitleBarDragSpacer(width: 0)
                    : DragToMoveArea(
                        child: Padding(
                          padding: EdgeInsets.only(left: PlatformKeys.isMac ? trafficLightInset : 22),
                          child: const Align(alignment: Alignment.centerLeft, child: SottoBrand()),
                        ),
                      ),
              ),
              if (!(collapsed && PlatformKeys.isMac))
                Padding(
                  padding: EdgeInsets.only(right: collapsed ? 13 : 12),
                  child: toggle,
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.symmetric(horizontal: collapsed ? 10 : 12),
            children: [
              // Collapsed on macOS, the top row belongs to the traffic lights.
              if (collapsed && PlatformKeys.isMac) ...[toggle, const SizedBox(height: 8)],
              if (!collapsed)
                SottoTextField(
                  controller: search,
                  focusNode: searchFocus,
                  placeholder: context.l10n.search,
                  leading: SottoIcons.search,
                  shortcutHint: '${PlatformKeys.primary}K',
                  onChanged: (q) {
                    ref.read(librarySearchProvider.notifier).set(q);
                    if (q.isNotEmpty && location != '/scripts') go('/scripts');
                  },
                ),
              const SizedBox(height: 14),
              NavItem(
                label: context.l10n.navHome,
                icon: SottoIcons.home,
                selected: location == '/',
                collapsed: collapsed,
                onTap: () => go('/'),
              ),
              const SizedBox(height: 2),
              NavItem(
                label: context.l10n.navAllScripts,
                icon: SottoIcons.scripts,
                trailing: '${active.length}',
                selected: location == '/scripts',
                collapsed: collapsed,
                onTap: () => go('/scripts'),
              ),
              const SizedBox(height: 2),
              NavItem(
                label: context.l10n.navSessions,
                icon: SottoIcons.sessions,
                trailing: '${sessions.length}',
                selected: location == '/sessions',
                collapsed: collapsed,
                onTap: () => go('/sessions'),
              ),
              const SizedBox(height: 2),
              // Opt-in (Settings → General → Show chat).
              if (showChat) ...[
                NavItem(
                  label: context.l10n.navChat,
                  icon: SottoIcons.chat,
                  selected: location == '/chat',
                  collapsed: collapsed,
                  onTap: () => go('/chat'),
                ),
                const SizedBox(height: 2),
              ],
              // Settings → General → Show Forms in sidebar (on by default).
              if (showForms) ...[
                NavItem(
                  label: context.l10n.navForms,
                  icon: SottoIcons.form,
                  selected: location == '/forms',
                  collapsed: collapsed,
                  onTap: () => go('/forms'),
                ),
                const SizedBox(height: 2),
              ],
              NavItem(
                label: context.l10n.navArchive,
                icon: SottoIcons.archive,
                selected: location == '/archive',
                collapsed: collapsed,
                onTap: () => go('/archive'),
              ),
              if (!collapsed) NavHeading(context.l10n.navCollections),
              if (collapsed) const SizedBox(height: 16),
              for (final c in collections) ...[
                NavItem(
                  label: c.name,
                  icon: SottoIcons.folder,
                  iconColor: p.collectionColor(c.tone),
                  trailing: '${active.where((s) => s.collectionId == c.id).length}',
                  selected: location == '/collections/${c.id}',
                  collapsed: collapsed,
                  onTap: () => go('/collections/${c.id}'),
                ),
                const SizedBox(height: 2),
              ],
              if (!collapsed) const _NewCollection(),
            ],
          ),
        ),
        if (!collapsed) const Padding(padding: EdgeInsets.fromLTRB(12, 8, 12, 8), child: _ReadinessCard()),
        Padding(
          padding: EdgeInsets.fromLTRB(collapsed ? 10 : 12, 0, collapsed ? 10 : 12, 12),
          child: NavItem(
            label: context.l10n.navSettings,
            icon: SottoIcons.sliders,
            trailing: '${PlatformKeys.primary},',
            collapsed: collapsed,
            onTap: () => go('/settings/shortcuts'),
          ),
        ),
      ],
    );
  }
}

/// The cue mark and wordmark, the lamp lit.
class SottoBrand extends StatelessWidget {
  const SottoBrand({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: p.primary.withValues(alpha: p.isDark ? 0.28 : 0.22), blurRadius: 16)],
          ),
          child: CueMark(size: 22, ink: p.inkPrimary, cue: p.primary),
        ),
        const SizedBox(width: 8),
        Text(
          context.l10n.appTitle,
          style: withWeight(TypeScale.title3, 650).copyWith(color: p.inkPrimary, letterSpacing: -0.2, height: 1),
        ),
      ],
    );
  }
}

/// Empty draggable area beside the traffic lights.
class TitleBarDragSpacer extends StatelessWidget {
  const TitleBarDragSpacer({super.key, required this.width});
  final double width;

  @override
  Widget build(BuildContext context) => DragToMoveArea(
    child: SizedBox(width: width, height: Layout.titleBar),
  );
}

class _NewCollection extends ConsumerStatefulWidget {
  const _NewCollection();

  @override
  ConsumerState<_NewCollection> createState() => _NewCollectionState();
}

class _NewCollectionState extends ConsumerState<_NewCollection> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    if (!_editing) {
      return NavItem(
        label: context.l10n.newCollection,
        icon: SottoIcons.plus,
        muted: true,
        onTap: () => setState(() => _editing = true),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Focus(
        onFocusChange: (f) {
          if (!f) setState(() => _editing = false);
        },
        child: SottoTextField(
          autofocus: true,
          placeholder: context.l10n.collectionName,
          onSubmitted: (name) {
            final n = name.trim();
            if (n.isNotEmpty) {
              final existing = ref.read(collectionsProvider).value ?? const <Collection>[];
              unawaited(
                ref
                    .read(scriptRepositoryProvider)
                    .saveCollection(Collection(id: newId(), name: n, tone: Collection.nextTone(existing))),
              );
            }
            setState(() => _editing = false);
          },
        ),
      ),
    );
  }
}

class _ReadinessCard extends ConsumerWidget {
  const _ReadinessCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final r = ref.watch(readinessProvider).value;
    return Interactive(
      onTap: () => context.go('/settings/voice'),
      builder: (context, s) => AnimatedContainer(
        duration: Motion.quick,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        decoration: BoxDecoration(
          color: s.hovered ? p.raised : p.ground,
          borderRadius: Radii.rL,
          border: Border.all(color: p.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(context.l10n.liveReadiness, style: TypeScale.bodyStrong.copyWith(color: p.inkPrimary)),
                ),
                Text(
                  r == null ? '…' : context.l10n.readinessCount(r.passed, 4),
                  style: TypeScale.caption.copyWith(color: p.inkTertiary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (r != null) ...[
              _row(
                context,
                SottoIcons.mic,
                r.mic,
                trailing: r.mic.level == CheckLevel.ok ? const LevelMeter(level: 0.55, bars: 7) : null,
              ),
              _row(context, SottoIcons.wave, r.voice),
              _row(context, SottoIcons.keyboard, r.hotkeys),
              _row(context, SottoIcons.eyeOff, r.share),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, SottoIcons icon, ReadinessItem item, {Widget? trailing}) {
    final p = context.palette;
    final status = switch (item.level) {
      CheckLevel.ok => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(shape: BoxShape.circle, color: p.confirmed),
      ),
      CheckLevel.warn => SottoIcon(SottoIcons.alert, size: 13, color: p.cueText),
      CheckLevel.missing => SottoIcon(SottoIcons.alert, size: 13, color: p.inkTertiary),
    };
    return Tooltip(
      message: item.detail ?? '',
      child: SizedBox(
        height: 26,
        child: Row(
          children: [
            SottoIcon(icon, size: 13, color: p.inkTertiary),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TypeScale.caption.copyWith(color: p.inkSecondary),
              ),
            ),
            trailing ?? SizedBox(width: 14, child: Center(child: status)),
          ],
        ),
      ),
    );
  }
}

/// Header shared by library pages: title left, actions right.
class LibraryHeader extends StatelessWidget {
  const LibraryHeader({super.key, required this.title, this.actions = const []});

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return TitleBarArea(
      showCaptionButtons: true,
      child: Padding(
        padding: const EdgeInsets.only(left: 24, right: 12),
        child: Row(
          children: [
            Text(title, style: TypeScale.bodyStrong.copyWith(color: p.inkPrimary)),
            const Spacer(),
            for (final a in actions) ...[const SizedBox(width: 8), a],
          ],
        ),
      ),
    );
  }
}

/// Drop target banner at the bottom of the library.
class ImportDropHint extends StatelessWidget {
  const ImportDropHint({super.key, required this.onBrowse, this.active = false});

  final VoidCallback onBrowse;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final base = TypeScale.body.copyWith(color: p.inkSecondary);
    final strong = TypeScale.bodyStrong.copyWith(color: p.inkPrimary);
    return CustomPaint(
      painter: _DashedBorder(color: active ? p.cueFill : p.control, radius: Radii.l),
      child: AnimatedContainer(
        duration: Motion.quick,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: active ? p.cueFill.withValues(alpha: 0.06) : Colors.transparent,
          borderRadius: Radii.rL,
        ),
        child: Row(
          children: [
            SottoIcon(SottoIcons.import, size: 16, color: p.inkTertiary),
            const SizedBox(width: 14),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: base,
                  children: [
                    TextSpan(text: context.l10n.dropHintDrop),
                    TextSpan(text: '.docx', style: strong),
                    const TextSpan(text: ', '),
                    TextSpan(text: '.pdf', style: strong),
                    const TextSpan(text: ', '),
                    TextSpan(text: '.md', style: strong),
                    TextSpan(text: context.l10n.dropHintOr),
                    TextSpan(text: '.txt', style: strong),
                    TextSpan(text: context.l10n.dropHintPaste),
                    WidgetSpan(alignment: PlaceholderAlignment.middle, child: _KeyHint('${PlatformKeys.primary}V')),
                    TextSpan(text: context.l10n.dropHintOrganize),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            SottoButton.ghost(label: context.l10n.browseFiles, onPressed: onBrowse),
          ],
        ),
      ),
    );
  }
}

class _KeyHint extends StatelessWidget {
  const _KeyHint(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: p.float,
        borderRadius: Radii.rXs,
        border: Border.all(color: p.control),
      ),
      child: Text(label, style: TypeScale.keycap.copyWith(color: p.inkSecondary, fontSize: 10)),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
        d += 7;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}

Widget emptyState(
  BuildContext context, {
  required SottoIcons icon,
  required String title,
  required String body,
  Widget? action,
}) {
  final p = context.palette;
  return Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SottoIcon(icon, size: 20, color: p.inkTertiary),
          const SizedBox(height: 12),
          Text(title, style: TypeScale.title3.copyWith(color: p.inkPrimary)),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TypeScale.body.copyWith(color: p.inkTertiary),
          ),
          if (action != null) ...[const SizedBox(height: 16), action],
        ],
      ),
    ),
  );
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';

import '../../../core/design/icons.dart';
import '../../../core/design/theme.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/typography.dart';
import '../../../core/platform/hotkey_service.dart';
import '../../../core/platform/platform_keys.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/display.dart';
import '../../../core/widgets/interactive.dart';
import '../../../core/widgets/keycap.dart';
import '../../../data/models/settings.dart';
import '../../../data/models/shortcut.dart';
import '../../../data/repositories.dart';
import '../../live/live_controller.dart';
import '../settings_screen.dart';

class ShortcutsPage extends ConsumerStatefulWidget {
  const ShortcutsPage({super.key});

  @override
  ConsumerState<ShortcutsPage> createState() => _ShortcutsPageState();
}

class _ShortcutsPageState extends ConsumerState<ShortcutsPage> {
  String _filter = '';
  ShortcutGroup? _group;

  bool _visible(LiveAction a) =>
      (_group == null || a.group == _group) &&
      (_filter.isEmpty ||
          a.title.toLowerCase().contains(_filter) ||
          (a.subtitle ?? '').toLowerCase().contains(_filter));

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    List<Widget> rows(ShortcutGroup g) => [
      for (final a in LiveAction.values.where((a) => a.group == g && _visible(a)))
        ShortcutRow(action: a, settings: settings),
    ];

    final live = rows(ShortcutGroup.live);
    final answers = rows(ShortcutGroup.answers);
    final overlay = rows(ShortcutGroup.overlay);

    return SettingsPageScaffold(
      title: context.l10n.setShortcuts,
      description: context.l10n.shortcutsDescription,
      action: ResetLink(
        onTap: () => notifier.update((s) => s.copyWith(bindings: const {}, chord: PlatformKeys.defaultChord)),
      ),
      left: [
        Row(
          children: [
            Expanded(
              child: SottoTextField(
                placeholder: context.l10n.filterShortcuts,
                leading: SottoIcons.search,
                onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
              ),
            ),
            const SizedBox(width: 12),
            SegmentedControl<ShortcutGroup?>(
              segments: [
                Segment(null, context.l10n.filterAll),
                Segment(ShortcutGroup.live, context.l10n.groupLive),
                Segment(ShortcutGroup.answers, context.l10n.setAnswers),
                Segment(ShortcutGroup.overlay, context.l10n.groupOverlay),
              ],
              value: _group,
              onChanged: (g) => setState(() => _group = g),
            ),
          ],
        ),
        if (live.isNotEmpty) SettingsGroup(title: context.l10n.groupLive, children: live),
        if (answers.isNotEmpty) SettingsGroup(title: context.l10n.setAnswers, children: answers),
      ],
      right: [
        SettingsGroup(
          title: context.l10n.chord,
          children: [
            SettingRow(
              title: context.l10n.sottoChord,
              subtitle: context.l10n.sottoChordSub,
              trailing: SottoSelect<String>(
                width: 200,
                value: _chordKey(settings.chord),
                options: [for (final c in _chords) SelectOption(_chordKey(c), _chordLabel(c))],
                onChanged: (k) =>
                    notifier.update((s) => s.copyWith(chord: _chords.firstWhere((c) => _chordKey(c) == k))),
              ),
            ),
            if (!PlatformKeys.isMac)
              SettingRow(title: context.l10n.altGrLayouts, subtitle: context.l10n.altGrLayoutsSub),
          ],
        ),
        if (overlay.isNotEmpty) SettingsGroup(title: context.l10n.groupOverlay, children: overlay),
      ],
    );
  }

  static List<Set<ShortcutModifier>> get _chords => [
    {ShortcutModifier.control, ShortcutModifier.alt},
    {ShortcutModifier.control, ShortcutModifier.shift},
    {ShortcutModifier.alt, ShortcutModifier.shift},
    if (PlatformKeys.isMac) {ShortcutModifier.meta, ShortcutModifier.alt},
    {ShortcutModifier.control, ShortcutModifier.alt, ShortcutModifier.shift},
  ];

  static String _chordKey(Set<ShortcutModifier> c) => (c.map((m) => m.name).toList()..sort()).join('+');

  static String _chordLabel(Set<ShortcutModifier> c) {
    const order = ShortcutModifier.values;
    final mods = order.where(c.contains);
    return '${mods.map(PlatformKeys.modifierSymbol).join(PlatformKeys.isMac ? '' : '+')}   ${mods.map(PlatformKeys.modifierName).join(' + ')}';
  }
}

/// Known system shortcuts, to explain a conflict in plain words.
String? _systemMeaning(Shortcut s) {
  final mods = s.modifiers;
  final key = s.key;
  if (PlatformKeys.isMac) {
    if (key == PhysicalKeyboardKey.space && mods.length == 1 && mods.contains(ShortcutModifier.control)) {
      return L10n.current.sysPrevInputSource;
    }
    if (key == PhysicalKeyboardKey.space && mods.contains(ShortcutModifier.meta)) return 'Spotlight';
    if ((key == PhysicalKeyboardKey.arrowLeft || key == PhysicalKeyboardKey.arrowRight) &&
        mods.length == 1 &&
        mods.contains(ShortcutModifier.control)) {
      return L10n.current.sysMoveSpaces;
    }
  } else {
    if (key == PhysicalKeyboardKey.delete && mods.containsAll({ShortcutModifier.control, ShortcutModifier.alt})) {
      return L10n.current.sysSecurityOptions;
    }
  }
  return null;
}

class ShortcutRow extends ConsumerStatefulWidget {
  const ShortcutRow({super.key, required this.action, required this.settings});
  final LiveAction action;
  final AppSettings settings;

  @override
  ConsumerState<ShortcutRow> createState() => _ShortcutRowState();
}

class _ShortcutRowState extends ConsumerState<ShortcutRow> {
  bool _recording = false;
  String? _conflict;
  int? _pendingKey;
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _start() {
    setState(() {
      _recording = true;
      _conflict = null;
      _pendingKey = null;
    });
    // The recording Focus only exists after this rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  Future<void> _captured(PhysicalKeyboardKey key) async {
    final s = widget.settings;
    final shortcut = Shortcut(s.chord, key.usbHidUsage);
    final clash = LiveAction.values.where((a) => a != widget.action && s.keyFor(a) == key).firstOrNull;
    String? conflict;
    if (clash != null) {
      conflict = L10n.current.conflictAlreadyUsed(clash.title);
    } else if (_systemMeaning(shortcut) case final meaning?) {
      conflict = L10n.current.conflictSystem(PlatformKeys.isMac ? 'macOS' : 'Windows', meaning);
    } else if (!ref.read(liveControllerProvider).isLive && widget.action != LiveAction.goLive) {
      if (!await HotkeyService.isAvailable(shortcut)) conflict = L10n.current.conflictOtherApp;
    }
    if (!mounted) return;
    if (conflict == null) {
      _save(key.usbHidUsage);
    } else {
      setState(() {
        _recording = false;
        _conflict = conflict;
        _pendingKey = key.usbHidUsage;
      });
    }
  }

  void _save(int key) {
    ref.read(settingsProvider.notifier).update((s) {
      final b = {...s.bindings};
      if (key == widget.action.defaultKey.usbHidUsage) {
        b.remove(widget.action.name);
      } else {
        b[widget.action.name] = key;
      }
      return s.copyWith(bindings: b);
    });
    setState(() {
      _recording = false;
      _conflict = null;
      _pendingKey = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final a = widget.action;
    final s = widget.settings;

    Widget recorder;
    if (_recording) {
      recorder = Focus(
        focusNode: _focus,
        onFocusChange: (f) {
          if (!f && _recording) setState(() => _recording = false);
        },
        onKeyEvent: (node, e) {
          if (e is! KeyDownEvent) return KeyEventResult.handled;
          if (e.physicalKey == PhysicalKeyboardKey.escape) {
            setState(() => _recording = false);
          } else if (!PlatformKeys.isModifierKey(e.physicalKey)) {
            unawaited(_captured(e.physicalKey));
          }
          return KeyEventResult.handled;
        },
        child: Container(
          height: 30,
          padding: const EdgeInsets.only(left: 10, right: 6),
          decoration: BoxDecoration(
            color: p.cueFill.withValues(alpha: 0.08),
            borderRadius: Radii.rControl,
            border: Border.all(color: p.cueFill.withValues(alpha: 0.7)),
            boxShadow: [BoxShadow(color: p.cueFill.withValues(alpha: 0.14), spreadRadius: 3)],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(shape: BoxShape.circle, color: p.cueFill),
              ),
              const SizedBox(width: 8),
              Text(context.l10n.pressAKey, style: TypeScale.bodyStrong.copyWith(color: p.cueText)),
              const SizedBox(width: 10),
              const Keycap('esc', compact: true),
            ],
          ),
        ),
      );
    } else {
      recorder = Interactive(
        onTap: _start,
        semanticLabel: context.l10n.changeShortcutFor(a.title),
        builder: (context, st) => AnimatedContainer(
          duration: Motion.quick,
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: st.hovered ? p.raised : Colors.transparent,
            borderRadius: Radii.rControl,
            border: Border.all(
              color: _conflict != null
                  ? p.cueFill.withValues(alpha: 0.6)
                  : (st.hovered ? p.control : Colors.transparent),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              KeyCombo(s.shortcutFor(a)),
              if (_conflict != null) ...[
                const SizedBox(width: 6),
                SottoIcon(SottoIcons.alert, size: 14, color: p.cueText),
              ],
            ],
          ),
        ),
      );
    }

    final extra = switch (a) {
      LiveAction.ask => SottoSelect<CaptureMode>(
        width: 156,
        value: s.captureMode,
        options: [
          SelectOption(CaptureMode.toggle, context.l10n.pressToToggle),
          SelectOption(CaptureMode.hold, context.l10n.holdToTalk),
        ],
        onChanged: (m) => ref.read(settingsProvider.notifier).update((x) => x.copyWith(captureMode: m)),
      ),
      LiveAction.sendToChat => Text(context.l10n.hold, style: TypeScale.caption.copyWith(color: p.inkTertiary)),
      _ => null,
    };

    return SettingRow(
      title: a.title,
      subtitle: a.subtitle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (extra != null) ...[extra, const SizedBox(width: 12)],
          recorder,
        ],
      ),
      below: _conflict == null
          ? null
          : Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: BoxDecoration(color: p.cueFill.withValues(alpha: 0.1), borderRadius: Radii.rM),
              child: Row(
                children: [
                  SottoIcon(SottoIcons.alert, size: 14, color: p.cueText),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${PlatformKeys.describe(Shortcut(s.chord, _pendingKey ?? 0))} ',
                            style: TypeScale.mono.copyWith(color: p.inkPrimary),
                          ),
                          TextSpan(
                            text: _conflict,
                            style: TypeScale.bodyStrong.copyWith(color: p.inkPrimary),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SottoButton.ghost(
                    label: context.l10n.useAnyway,
                    size: ButtonSize.small,
                    onPressed: () => _save(_pendingKey!),
                  ),
                  const SizedBox(width: 6),
                  SottoButton(label: context.l10n.chooseAnother, size: ButtonSize.small, onPressed: _start),
                ],
              ),
            ),
    );
  }
}

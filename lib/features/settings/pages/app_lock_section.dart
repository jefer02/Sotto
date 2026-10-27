import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_session.dart';
import '../../../core/design/icons.dart';
import '../../../core/design/theme.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/typography.dart';
import '../../../core/platform/platform_features.dart';
import '../../../core/platform/platform_keys.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/display.dart';
import '../../../core/widgets/password_field.dart';
import '../../../core/widgets/stage_transitions.dart';
import '../../../data/lock/recovery_key.dart';
import '../../../data/lock/vault.dart';
import '../../../data/models/settings.dart';
import '../../../data/models/shortcut.dart';
import '../../../data/repositories.dart';
import '../../../l10n/l10n.dart';

/// Settings → Privacy → App lock: turning the lock on and off, the
/// password, the recovery key, auto-lock, Windows Hello / Touch ID and
/// Lock now. Hidden without a session (renders and tests of other pages).
class AppLockSection extends ConsumerWidget {
  const AppLockSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(appSessionProvider);
    if (session == null) return const SizedBox.shrink();
    final l = context.l10n;
    final on = ref.watch(lockEnabledProvider);
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final busy = ref.watch(sessionBusyProvider);
    final keys = PlatformKeys.describe(s.shortcutFor(LiveAction.lockApp));
    final method = session.biometrics?.method;
    final showBiometrics = ref.watch(platformFeaturesProvider).biometrics && session.biometricsAvailable;

    return SettingsGroup(
      title: l.appLock,
      footer: on ? l.appLockFooterOn : l.appLockFooterOff,
      children: [
        SettingRow(
          title: l.appLockToggle,
          subtitle: l.appLockToggleSub,
          trailing: SottoToggle(
            value: on,
            label: l.appLockToggle,
            onChanged: busy ? null : (v) => v ? _enable(context, session) : _disable(context, session),
          ),
        ),
        if (on) ...[
          SettingRow(
            title: l.lockNow,
            subtitle: l.lockNowSub(keys),
            trailing: SottoButton(
              label: l.lockNow,
              icon: SottoIcons.lock,
              size: ButtonSize.small,
              onPressed: busy ? null : () => unawaited(session.lock()),
            ),
          ),
          SettingRow(
            title: l.autoLock,
            subtitle: l.autoLockSub,
            trailing: SottoSelect<int>(
              width: 140,
              value: s.autoLockMinutes,
              options: [
                for (final m in AppSettings.autoLockChoices)
                  SelectOption(m, m == 0 ? l.autoLockOff : l.autoLockMinutes(m)),
              ],
              onChanged: (v) => n.update((x) => x.copyWith(autoLockMinutes: v)),
            ),
          ),
          if (showBiometrics && method != null)
            SettingRow(
              title: l.unlockWithBiometrics(method),
              subtitle: l.biometricsSub,
              trailing: SottoToggle(
                value: s.lockBiometrics,
                label: l.unlockWithBiometrics(method),
                onChanged: (v) async {
                  if (v) {
                    if (await session.enableBiometrics()) n.update((x) => x.copyWith(lockBiometrics: true));
                  } else {
                    await session.disableBiometrics();
                    n.update((x) => x.copyWith(lockBiometrics: false));
                  }
                },
              ),
            ),
          SettingRow(
            title: l.changePassword,
            trailing: SottoButton(
              label: l.change,
              size: ButtonSize.small,
              onPressed: () => showSottoDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => ChangePasswordDialog(session: session),
              ),
            ),
          ),
          SettingRow(
            title: l.recoveryKeyLabel,
            subtitle: l.recoveryKeySub,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SottoButton(label: l.show, size: ButtonSize.small, onPressed: () => _showRecoveryKey(context, session)),
                const SizedBox(width: Space.s2),
                SottoButton(
                  label: l.newRecoveryKey,
                  size: ButtonSize.small,
                  onPressed: () => _regenerateRecoveryKey(context, session),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _enable(BuildContext context, AppSession session) async {
    final setup = await showSottoDialog<VaultSetup>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EnableLockDialog(session: session),
    );
    // Encrypting replaces the app with its progress, then reopens it here.
    if (setup != null) await session.enable(setup);
  }

  Future<void> _disable(BuildContext context, AppSession session) => showSottoDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      final l = context.l10n;
      return PasswordPromptDialog(
        title: l.disableLockTitle,
        body: l.disableLockBody,
        action: l.disableLockAction,
        // Right: the data is decrypted and the app reopens unlocked.
        submit: session.disable,
      );
    },
  );

  Future<void> _showRecoveryKey(BuildContext context, AppSession session) async {
    String? key;
    final l = context.l10n;
    final ok = await showSottoDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PasswordPromptDialog(
        title: l.showRecoveryKeyTitle,
        body: l.showRecoveryKeyBody,
        action: l.show,
        submit: (pw) async => (key = await session.recoveryKey(pw)) != null,
      ),
    );
    if (ok != true || key == null || !context.mounted) return;
    await showSottoDialog<void>(
      context: context,
      builder: (_) => RecoveryKeyDialog(recoveryKey: key!, title: l.recoveryKeyLabel, confirmSaved: false),
    );
  }

  Future<void> _regenerateRecoveryKey(BuildContext context, AppSession session) async {
    String? key;
    final l = context.l10n;
    final ok = await showSottoDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PasswordPromptDialog(
        title: l.newRecoveryKeyTitle,
        body: l.newRecoveryKeyBody,
        action: l.newRecoveryKey,
        destructive: true,
        submit: (pw) async => (key = await session.regenerateRecoveryKey(pw)) != null,
      ),
    );
    if (ok != true || key == null || !context.mounted) return;
    await showSottoDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RecoveryKeyDialog(recoveryKey: key!, title: l.newRecoveryKeyReady, confirmSaved: true),
    );
  }
}

// ─────────────────────────── Dialog frame ───────────────────────────

/// A settings dialog: title, body, actions; Esc closes it unless [busy].
class LockDialogFrame extends StatelessWidget {
  const LockDialogFrame({
    super.key,
    required this.title,
    required this.children,
    required this.actions,
    this.busy = false,
  });

  final String title;
  final List<Widget> children;
  final List<Widget> actions;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (!busy) Navigator.of(context).maybePop();
        },
      },
      child: Dialog(
        backgroundColor: p.float,
        insetPadding: const EdgeInsets.all(Space.s6),
        shape: RoundedRectangleBorder(
          borderRadius: Radii.rL,
          side: BorderSide(color: p.control),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.s6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(title, style: TypeScale.title2.copyWith(color: p.inkPrimary)),
                ),
                const SizedBox(height: Space.s3),
                ...children,
                const SizedBox(height: Space.s5),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (final (i, a) in actions.indexed) ...[if (i > 0) const SizedBox(width: Space.s2), a],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _body(BuildContext context, String text) =>
    Text(text, style: TypeScale.body.copyWith(color: context.palette.inkSecondary));

// ─────────────────────────── Turning it on ───────────────────────────

/// Create a password → see the recovery key and confirm it is saved →
/// pops the new vault, which the caller encrypts the data with.
class EnableLockDialog extends StatefulWidget {
  const EnableLockDialog({super.key, required this.session});

  final AppSession session;

  @override
  State<EnableLockDialog> createState() => _EnableLockDialogState();
}

class _EnableLockDialogState extends State<EnableLockDialog> {
  final _password = TextEditingController();
  VaultSetup? _setup;
  bool _busy = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  bool get _longEnough => passwordStrength(_password.text) != PasswordStrength.tooShort;

  Future<void> _create() async {
    if (!_longEnough || _busy) return;
    setState(() => _busy = true);
    final setup = await widget.session.createVault(_password.text);
    if (!mounted) return;
    _password.clear();
    setState(() {
      _setup = setup;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = context.palette;
    final setup = _setup;
    if (setup == null) {
      return LockDialogFrame(
        title: l.enableLockTitle,
        busy: _busy,
        actions: [
          SottoButton.ghost(label: l.cancel, onPressed: _busy ? null : () => Navigator.pop(context)),
          SottoButton.primary(label: l.continueAction, loading: _busy, onPressed: _longEnough ? _create : null),
        ],
        children: [
          _body(context, l.enableLockBody),
          const SizedBox(height: Space.s4),
          PasswordField(
            controller: _password,
            label: l.newPasswordLabel,
            autofocus: true,
            enabled: !_busy,
            onSubmitted: (_) => _create(),
          ),
          PasswordStrengthMeter(password: _password.text),
        ],
      );
    }
    final windows = PlatformFeatures.current.os == 'windows';
    return LockDialogFrame(
      title: l.saveRecoveryKeyTitle,
      actions: [
        SottoButton.ghost(label: l.cancel, onPressed: () => Navigator.pop(context)),
        SottoButton.primary(label: l.encryptMyData, onPressed: _saved ? () => Navigator.pop(context, setup) : null),
      ],
      children: [
        _body(context, l.saveRecoveryKeyBody),
        const SizedBox(height: Space.s4),
        RecoveryKeyBlocks(recoveryKey: setup.recoveryKey),
        const SizedBox(height: Space.s4),
        _Warning(text: l.recoveryKeyWarning),
        if (windows) ...[
          const SizedBox(height: Space.s2),
          Text(l.oneDriveNote, style: TypeScale.caption.copyWith(color: p.inkTertiary)),
        ],
        const SizedBox(height: Space.s4),
        _SavedCheck(value: _saved, onChanged: (v) => setState(() => _saved = v)),
      ],
    );
  }
}

// ─────────────────────────── Password prompts ───────────────────────────

/// Asks for the password, then runs [submit] with it; pops true when that
/// returns true, says "Incorrect password" when it returns false.
class PasswordPromptDialog extends StatefulWidget {
  const PasswordPromptDialog({
    super.key,
    required this.title,
    required this.body,
    required this.action,
    required this.submit,
    this.destructive = false,
  });

  final String title;
  final String body;
  final String action;
  final Future<bool> Function(String password) submit;
  final bool destructive;

  @override
  State<PasswordPromptDialog> createState() => _PasswordPromptDialogState();
}

class _PasswordPromptDialogState extends State<PasswordPromptDialog> {
  final _password = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;
  String? _error;
  int _shake = 0;

  @override
  void dispose() {
    _password.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_busy || _password.text.isEmpty) return;
    setState(() => _busy = true);
    final ok = await widget.submit(_password.text);
    if (!mounted) return;
    if (ok) {
      _password.clear();
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _busy = false;
      _error = context.l10n.unlockWrongPassword;
      _shake++;
    });
    PasswordField.retry(_password, _focus);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = context.palette;
    return LockDialogFrame(
      title: widget.title,
      busy: _busy,
      actions: [
        SottoButton.ghost(label: l.cancel, onPressed: _busy ? null : () => Navigator.pop(context)),
        widget.destructive
            ? SottoButton(label: widget.action, tone: p.caution, loading: _busy, onPressed: _go)
            : SottoButton.primary(label: widget.action, loading: _busy, onPressed: _go),
      ],
      children: [
        _body(context, widget.body),
        const SizedBox(height: Space.s4),
        PasswordField(
          controller: _password,
          focusNode: _focus,
          label: l.unlockPasswordLabel,
          placeholder: l.unlockPasswordPlaceholder,
          autofocus: true,
          enabled: !_busy,
          error: _error,
          shakeTick: _shake,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _go(),
        ),
      ],
    );
  }
}

class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({super.key, required this.session});

  final AppSession session;

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _currentFocus = FocusNode();
  bool _busy = false;
  String? _error;
  int _shake = 0;

  @override
  void initState() {
    super.initState();
    _next.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _currentFocus.dispose();
    super.dispose();
  }

  bool get _ready => _current.text.isNotEmpty && passwordStrength(_next.text) != PasswordStrength.tooShort;

  Future<void> _save() async {
    if (_busy || !_ready) return;
    setState(() => _busy = true);
    final ok = await widget.session.changePassword(_current.text, _next.text);
    if (!mounted) return;
    if (ok) {
      _current.clear();
      _next.clear();
      Navigator.pop(context);
      return;
    }
    setState(() {
      _busy = false;
      _error = context.l10n.unlockWrongPassword;
      _shake++;
    });
    PasswordField.retry(_current, _currentFocus);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = context.palette;
    return LockDialogFrame(
      title: l.changePassword,
      busy: _busy,
      actions: [
        SottoButton.ghost(label: l.cancel, onPressed: _busy ? null : () => Navigator.pop(context)),
        SottoButton.primary(label: l.save, loading: _busy, onPressed: _ready ? _save : null),
      ],
      children: [
        _body(context, l.changePasswordBody),
        const SizedBox(height: Space.s4),
        Text(l.currentPassword, style: TypeScale.captionStrong.copyWith(color: p.inkSecondary)),
        const SizedBox(height: Space.s1_5),
        PasswordField(
          controller: _current,
          focusNode: _currentFocus,
          label: l.currentPassword,
          autofocus: true,
          enabled: !_busy,
          error: _error,
          shakeTick: _shake,
          onChanged: (_) => setState(() => _error = null),
        ),
        Text(l.newPasswordLabel, style: TypeScale.captionStrong.copyWith(color: p.inkSecondary)),
        const SizedBox(height: Space.s1_5),
        PasswordField(controller: _next, label: l.newPasswordLabel, enabled: !_busy, onSubmitted: (_) => _save()),
        PasswordStrengthMeter(password: _next.text),
      ],
    );
  }
}

// ─────────────────────────── Recovery key ───────────────────────────

class RecoveryKeyDialog extends StatefulWidget {
  const RecoveryKeyDialog({super.key, required this.recoveryKey, required this.title, required this.confirmSaved});

  final String recoveryKey;
  final String title;

  /// A new key: Done waits for "I've saved it".
  final bool confirmSaved;

  @override
  State<RecoveryKeyDialog> createState() => _RecoveryKeyDialogState();
}

class _RecoveryKeyDialogState extends State<RecoveryKeyDialog> {
  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return LockDialogFrame(
      title: widget.title,
      actions: [
        SottoButton.primary(
          label: l.done,
          onPressed: !widget.confirmSaved || _saved ? () => Navigator.pop(context) : null,
        ),
      ],
      children: [
        if (widget.confirmSaved) ...[_body(context, l.newRecoveryKeyReadyBody), const SizedBox(height: Space.s4)],
        RecoveryKeyBlocks(recoveryKey: widget.recoveryKey),
        const SizedBox(height: Space.s4),
        _Warning(text: l.recoveryKeyWarning),
        if (widget.confirmSaved) ...[
          const SizedBox(height: Space.s4),
          _SavedCheck(value: _saved, onChanged: (v) => setState(() => _saved = v)),
        ],
      ],
    );
  }
}

/// The key in Geist Mono, one block per group, with Copy.
class RecoveryKeyBlocks extends StatefulWidget {
  const RecoveryKeyBlocks({super.key, required this.recoveryKey});

  final String recoveryKey;

  @override
  State<RecoveryKeyBlocks> createState() => _RecoveryKeyBlocksState();
}

class _RecoveryKeyBlocksState extends State<RecoveryKeyBlocks> {
  bool _copied = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.recoveryKey));
    if (!mounted) return;
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    final groups = widget.recoveryKey.split('-');
    assert(groups.join().length == RecoveryKey.length);
    return Container(
      padding: const EdgeInsets.all(Space.s4),
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: Radii.rM,
        border: Border.all(color: p.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: '${l.recoveryKeyLabel}: ${groups.map((g) => g.split('').join(' ')).join(', ')}',
            child: ExcludeSemantics(
              child: SelectionArea(
                // Two even rows (4 + 3) rather than whatever wraps.
                child: Column(
                  children: [
                    for (final (r, row) in [groups.take(4), groups.skip(4)].indexed) ...[
                      if (r > 0) const SizedBox(height: Space.s2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (final (i, g) in row.indexed) ...[
                            if (i > 0) const SizedBox(width: Space.s2),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: Space.s2, vertical: Space.s1_5),
                              decoration: BoxDecoration(
                                color: p.raised,
                                borderRadius: Radii.rS,
                                border: Border.all(color: p.hairline),
                              ),
                              child: Text(
                                g,
                                style: TypeScale.mono.copyWith(fontSize: 16, letterSpacing: 1.6, color: p.inkPrimary),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: Space.s3),
          Center(
            child: SottoButton(
              label: _copied ? l.copied : l.copy,
              icon: _copied ? SottoIcons.check : SottoIcons.copy,
              size: ButtonSize.small,
              onPressed: _copy,
            ),
          ),
        ],
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(Space.s3),
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: Radii.rM,
        border: Border.all(color: p.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: SottoIcon(SottoIcons.alert, size: 14, color: p.caution),
          ),
          const SizedBox(width: Space.s2),
          Expanded(
            child: Text(text, style: TypeScale.body.copyWith(color: p.inkPrimary)),
          ),
        ],
      ),
    );
  }
}

class _SavedCheck extends StatelessWidget {
  const _SavedCheck({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    return MergeSemantics(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: Row(
          children: [
            SottoCheckbox(value: value, onChanged: onChanged),
            const SizedBox(width: Space.s2),
            Expanded(
              child: Text(l.recoveryKeySaved, style: TypeScale.bodyStrong.copyWith(color: p.inkPrimary)),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/design/icons.dart';
import '../core/design/theme.dart';
import '../core/design/tokens.dart';
import '../core/design/typography.dart';
import '../core/widgets/buttons.dart';
import '../core/widgets/display.dart';
import '../core/widgets/password_field.dart';
import '../data/lock/recovery_key.dart';
import '../data/models/settings.dart';
import '../data/storage/local_store.dart';
import '../l10n/l10n.dart';
import 'app_session.dart';
import 'standalone_app.dart';

/// The unlock screen as its own app, in the presenter's theme and language.
class UnlockApp extends StatelessWidget {
  const UnlockApp({super.key, required this.session});

  final AppSession session;

  @override
  Widget build(BuildContext context) => StandaloneApp(
    settings: AppSettings.fromJson(session.settings.writes.get(LocalStore.prefsSettingsKey) ?? const {}),
    home: UnlockScreen(gate: session),
  );
}

enum _Step { password, recovery, newPassword, reset }

/// "Welcome back": the password (or Windows Hello / Touch ID), and behind
/// "Forgot password?" the recovery key, a new password — and, with both
/// lost, Reset Sotto.
class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key, required this.gate});

  final UnlockGate gate;

  /// Narrower windows let the card fill the width, less the gutters.
  static const cardWidth = 400.0;

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _password = TextEditingController();
  final _recovery = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirm = TextEditingController();
  final _passwordFocus = FocusNode();
  final _recoveryFocus = FocusNode();

  late _Step _step = widget.gate.vaultDamaged ? _Step.reset : _Step.password;
  bool _busy = false;
  String? _error;
  int _shake = 0;
  Uint8List? _dek;
  Timer? _countdown;

  @override
  void initState() {
    super.initState();
    _watchThrottle();
    for (final c in [_newPassword, _confirm]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _countdown?.cancel();
    for (final c in [_password, _recovery, _newPassword, _confirm]) {
      c.dispose();
    }
    _passwordFocus.dispose();
    _recoveryFocus.dispose();
    _dek = null;
    super.dispose();
  }

  bool get _throttled => widget.gate.throttleRemaining > Duration.zero;

  /// Ticks the countdown once a second while attempts are on hold.
  void _watchThrottle() {
    _countdown?.cancel();
    if (!_throttled) return;
    _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() {});
      if (!_throttled) {
        t.cancel();
        PasswordField.retry(_password, _passwordFocus);
      }
    });
  }

  String _clock(Duration d) {
    final s = d.inSeconds + (d.inMilliseconds % 1000 > 0 ? 1 : 0);
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  void _go(_Step step) => setState(() {
    _step = step;
    _error = null;
  });

  /// Wrong: say so, keep the text but select it, so typing replaces it.
  void _wrong(String message, TextEditingController c, FocusNode focus) {
    setState(() {
      _busy = false; // enabled again before the focus returns
      _error = message;
      _shake++;
    });
    PasswordField.retry(c, focus);
  }

  Future<void> _run(Future<void> Function() work) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await work();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlock() => _run(() async {
    if (_throttled || _password.text.isEmpty) return;
    final result = await widget.gate.unlockWithPassword(_password.text);
    if (!mounted) return;
    switch (result) {
      case UnlockResult.unlocked:
        _password.clear();
      case UnlockResult.wrong when _throttled:
        setState(() => _error = null);
        _watchThrottle();
      case UnlockResult.wrong:
        _wrong(context.l10n.unlockWrongPassword, _password, _passwordFocus);
      case UnlockResult.throttled:
        _watchThrottle();
        setState(() {});
      case UnlockResult.damaged:
        _go(_Step.reset);
    }
  });

  Future<void> _biometrics(String method) => _run(() async {
    final ok = await widget.gate.unlockWithBiometrics();
    if (!ok && mounted) setState(() => _error = context.l10n.unlockBiometricFailed(method));
  });

  Future<void> _checkRecovery() => _run(() async {
    if (_throttled) return;
    final l = context.l10n;
    if (RecoveryKey.parse(_recovery.text) == null) return _wrong(l.recoveryMalformed, _recovery, _recoveryFocus);
    final (result, dek) = await widget.gate.checkRecoveryKey(_recovery.text);
    if (!mounted) return;
    switch (result) {
      case UnlockResult.unlocked:
        _dek = dek;
        _recovery.clear();
        _go(_Step.newPassword);
      case UnlockResult.wrong when _throttled:
        setState(() => _error = null);
        _watchThrottle();
      case UnlockResult.wrong:
        _wrong(l.recoveryWrong, _recovery, _recoveryFocus);
      case UnlockResult.throttled:
        _watchThrottle();
        setState(() {});
      case UnlockResult.damaged:
        _go(_Step.reset);
    }
  });

  Future<void> _setNewPassword() => _run(() async {
    final dek = _dek;
    if (dek == null || passwordStrength(_newPassword.text) == PasswordStrength.tooShort) return;
    await widget.gate.resetPassword(dek, _newPassword.text);
    _newPassword.clear();
    _dek = null;
  });

  bool get _resetConfirmed => _confirm.text.trim().toUpperCase() == context.l10n.resetWord.toUpperCase();

  Future<void> _reset() => _run(() async {
    if (!_resetConfirmed) return;
    await widget.gate.resetEverything();
  });

  @override
  Widget build(BuildContext context) {
    final step = switch (_step) {
      _Step.password => _passwordStep(context),
      _Step.recovery => _recoveryStep(context),
      _Step.newPassword => _newPasswordStep(context),
      _Step.reset => _resetStep(context),
    };
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final canGoBack = !_busy && (_step == _Step.recovery || (_step == _Step.reset && !widget.gate.vaultDamaged));
    return StandaloneScaffold(
      glow: true,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (canGoBack) _go(_step == _Step.reset ? _Step.recovery : _Step.password);
          },
        },
        child: FocusTraversalGroup(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Layout.titleBar),
              child: _Entrance(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: UnlockScreen.cardWidth),
                  child: SurfaceCard(
                    padding: const EdgeInsets.fromLTRB(Space.s8, Space.s8, Space.s8, Space.s6),
                    child: _Resize(
                      child: AnimatedSwitcher(
                        duration: still ? Duration.zero : Motion.snappy,
                        switchInCurve: Motion.standard,
                        switchOutCurve: Motion.exit,
                        layoutBuilder: (current, previous) =>
                            Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
                        child: KeyedSubtree(key: ValueKey(_step), child: step),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────── Steps ───────────────────────────

  Widget _passwordStep(BuildContext context) {
    final l = context.l10n;
    final throttled = _throttled;
    final method = widget.gate.biometricMethod;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Center(child: _BrandMark()),
        const SizedBox(height: Space.s6),
        _Heading(title: l.unlockWelcome, body: l.unlockSubtitle, center: true),
        const SizedBox(height: Space.s6),
        PasswordField(
          controller: _password,
          focusNode: _passwordFocus,
          label: l.unlockPasswordLabel,
          placeholder: l.unlockPasswordPlaceholder,
          autofocus: true,
          enabled: !throttled && !_busy,
          error: throttled ? null : _error,
          note: throttled ? l.unlockThrottled(_clock(widget.gate.throttleRemaining)) : null,
          shakeTick: _shake,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _unlock(),
        ),
        const SizedBox(height: Space.s2),
        SottoButton.primary(
          label: l.unlock,
          size: ButtonSize.large,
          expand: true,
          loading: _busy,
          onPressed: throttled ? null : _unlock,
        ),
        if (method != null) ...[
          const SizedBox(height: Space.s2),
          SottoButton(
            label: l.unlockUseBiometrics(method),
            icon: SottoIcons.shield,
            size: ButtonSize.large,
            expand: true,
            onPressed: _busy ? null : () => _biometrics(method),
          ),
        ],
        const SizedBox(height: Space.s5),
        Center(child: TextLink(l.unlockForgot, muted: true, onTap: _busy ? null : () => _go(_Step.recovery))),
      ],
    );
  }

  Widget _recoveryStep(BuildContext context) {
    final l = context.l10n;
    final throttled = _throttled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Heading(icon: SottoIcons.lock, title: l.recoveryTitle, body: l.recoveryBody),
        const SizedBox(height: Space.s5),
        PasswordField(
          controller: _recovery,
          focusNode: _recoveryFocus,
          label: l.recoveryKeyLabel,
          placeholder: 'XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX',
          autofocus: true,
          mono: true,
          obscure: false,
          enabled: !throttled && !_busy,
          error: throttled ? null : _error,
          note: throttled ? l.unlockThrottled(_clock(widget.gate.throttleRemaining)) : null,
          shakeTick: _shake,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _checkRecovery(),
        ),
        const SizedBox(height: Space.s2),
        _Actions(
          back: _busy ? null : () => _go(_Step.password),
          primary: SottoButton.primary(
            label: l.continueAction,
            loading: _busy,
            onPressed: throttled ? null : _checkRecovery,
          ),
        ),
        const SizedBox(height: Space.s5),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Space.s1_5,
          children: [
            Text(l.resetLink, style: TypeScale.body.copyWith(color: context.palette.inkTertiary)),
            TextLink(l.resetSotto, muted: true, onTap: _busy ? null : () => _go(_Step.reset)),
          ],
        ),
      ],
    );
  }

  Widget _newPasswordStep(BuildContext context) {
    final l = context.l10n;
    final ok = passwordStrength(_newPassword.text) != PasswordStrength.tooShort;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Heading(icon: SottoIcons.lock, title: l.newPasswordTitle, body: l.newPasswordBody),
        const SizedBox(height: Space.s5),
        PasswordField(
          controller: _newPassword,
          label: l.newPasswordLabel,
          autofocus: true,
          enabled: !_busy,
          onSubmitted: (_) => _setNewPassword(),
        ),
        PasswordStrengthMeter(password: _newPassword.text),
        const SizedBox(height: Space.s5),
        SottoButton.primary(
          label: l.setPasswordAndUnlock,
          size: ButtonSize.large,
          expand: true,
          loading: _busy,
          onPressed: ok ? _setNewPassword : null,
        ),
      ],
    );
  }

  Widget _resetStep(BuildContext context) {
    final l = context.l10n;
    final p = context.palette;
    final damaged = widget.gate.vaultDamaged;
    final word = l.resetWord;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (damaged) ...[
          _Heading(icon: SottoIcons.alert, iconColor: p.caution, title: l.vaultDamagedTitle, body: l.vaultDamagedBody),
          const SizedBox(height: Space.s5),
          Container(height: 1, color: p.hairline),
          const SizedBox(height: Space.s5),
        ],
        _Heading(icon: damaged ? null : SottoIcons.alert, iconColor: p.caution, title: l.resetTitle, body: l.resetBody),
        const SizedBox(height: Space.s3),
        Text(l.resetKeeps, style: TypeScale.body.copyWith(color: p.inkPrimary)),
        const SizedBox(height: Space.s5),
        Text(l.resetTypeToConfirm(word), style: TypeScale.captionStrong.copyWith(color: p.inkSecondary)),
        const SizedBox(height: Space.s1_5),
        PasswordField(
          controller: _confirm,
          label: l.resetConfirmLabel,
          placeholder: word,
          autofocus: true,
          obscure: false,
          enabled: !_busy,
          onSubmitted: (_) => _reset(),
        ),
        SottoButton(
          label: l.resetButton,
          tone: p.liveCapture,
          size: ButtonSize.large,
          expand: true,
          loading: _busy,
          onPressed: _resetConfirmed ? _reset : null,
        ),
        if (!damaged) ...[
          const SizedBox(height: Space.s2),
          Center(
            child: SottoButton.ghost(label: l.back, onPressed: _busy ? null : () => _go(_Step.recovery)),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────── Parts ───────────────────────────

/// The cue mark with its lamp lit, and the wordmark.
class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      label: 'Sotto',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: p.primary.withValues(alpha: p.isDark ? 0.32 : 0.24), blurRadius: 22)],
              ),
              child: CueMark(size: 30, ink: p.inkPrimary, cue: p.primary),
            ),
            const SizedBox(width: Space.s2 + Space.s0_5),
            Text(
              'Sotto',
              style: withWeight(TypeScale.title2, 650).copyWith(color: p.inkPrimary, letterSpacing: -0.2, height: 1),
            ),
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.title, required this.body, this.icon, this.iconColor, this.center = false});

  final String title;
  final String body;
  final SottoIcons? icon;
  final Color? iconColor;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final align = center ? TextAlign.center : TextAlign.start;
    return Column(
      crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          SottoIcon(icon!, size: 20, color: iconColor ?? p.primaryText),
          const SizedBox(height: Space.s3),
        ],
        Semantics(
          header: true,
          child: Text(
            title,
            textAlign: align,
            style: (center ? TypeScale.title1 : TypeScale.title2).copyWith(color: p.inkPrimary),
          ),
        ),
        const SizedBox(height: Space.s1_5),
        Text(
          body,
          textAlign: align,
          style: TypeScale.body.copyWith(color: p.inkSecondary),
        ),
      ],
    );
  }
}

/// Back on the left, the step's action on the right.
class _Actions extends StatelessWidget {
  const _Actions({required this.primary, this.back});

  final Widget primary;
  final VoidCallback? back;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (back != null) SottoButton.ghost(label: context.l10n.back, onPressed: back),
      const Spacer(),
      primary,
    ],
  );
}

/// The card follows its step's height; at once under reduced motion
/// (a zero-length AnimatedSize re-dirties itself mid-layout).
class _Resize extends StatelessWidget {
  const _Resize({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    return AnimatedSize(duration: Motion.panel, curve: Motion.move, alignment: Alignment.topCenter, child: child);
  }
}

/// The card arrives: a short fade as it rises a few pixels. Instant under
/// reduced motion.
class _Entrance extends StatelessWidget {
  const _Entrance({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: still ? 1 : 0, end: 1),
      duration: still ? Duration.zero : Motion.smooth,
      curve: Motion.glideEnter,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
      ),
      child: child,
    );
  }
}

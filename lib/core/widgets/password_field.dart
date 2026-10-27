import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/icons.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../../l10n/l10n.dart';
import 'buttons.dart';

/// A password (or recovery key) input: masked by default with an eye to
/// show it, a Caps Lock note while it has focus, an inline error that
/// screen readers announce, and a short shake when [shakeTick] changes —
/// still under reduced motion.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.focusNode,
    this.placeholder,
    this.error,
    this.note,
    this.autofocus = false,
    this.enabled = true,
    this.mono = false,
    this.revealable = true,
    this.obscure = true,
    this.shakeTick = 0,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;

  /// What the field is, for screen readers ("Password", "Recovery key").
  final String label;
  final FocusNode? focusNode;
  final String? placeholder;
  final String? error;

  /// A quiet line under the field when there's no error (a countdown).
  final String? note;
  final bool autofocus;
  final bool enabled;

  /// Geist Mono, for recovery keys.
  final bool mono;
  final bool revealable;
  final bool obscure;
  final int shakeTick;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  static const height = 36.0;

  /// After a wrong entry: focus back in the field with its text selected,
  /// so typing replaces it. Waits a frame — a field disabled while the key
  /// was checked gave up its focus and can't take it back until it is
  /// enabled again.
  static void retry(TextEditingController controller, FocusNode focus) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!focus.canRequestFocus || focus.context == null) return;
      focus.requestFocus();
      controller.selection = TextSelection(baseOffset: 0, extentOffset: controller.text.length);
    });
  }

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> with SingleTickerProviderStateMixin {
  late final FocusNode _focus = widget.focusNode ?? FocusNode();
  late final _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
  bool _revealed = false;
  bool _capsLock = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
    HardwareKeyboard.instance.addHandler(_onKey);
    _capsLock = _capsOn;
  }

  @override
  void didUpdateWidget(PasswordField old) {
    super.didUpdateWidget(old);
    if (widget.shakeTick != old.shakeTick && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      _shake.forward(from: 0);
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _focus.removeListener(_onFocus);
    if (widget.focusNode == null) _focus.dispose();
    _shake.dispose();
    super.dispose();
  }

  static bool get _capsOn => HardwareKeyboard.instance.lockModesEnabled.contains(KeyboardLockMode.capsLock);

  void _onFocus() => setState(() => _capsLock = _capsOn);

  bool _onKey(KeyEvent event) {
    if (_capsOn != _capsLock && mounted) setState(() => _capsLock = _capsOn);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    final focused = _focus.hasFocus;
    final hasError = widget.error != null;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final masked = widget.obscure && !_revealed;
    final style = (widget.mono ? TypeScale.mono.copyWith(fontSize: 14, letterSpacing: 0.6) : TypeScale.body).copyWith(
      color: widget.enabled ? p.inkPrimary : p.inkDisabled,
    );

    final field = AnimatedContainer(
      duration: still ? Duration.zero : Motion.quick,
      height: PasswordField.height,
      padding: const EdgeInsets.only(left: Space.s3, right: Space.s1),
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: Radii.rControl,
        border: Border.all(
          color: hasError
              ? p.liveCapture
              : focused
              ? p.cueFill.withValues(alpha: 0.7)
              : p.control,
        ),
        boxShadow: focused && !hasError ? [BoxShadow(color: p.cueFill.withValues(alpha: 0.16), spreadRadius: 3)] : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              label: widget.label,
              textField: true,
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                autofocus: widget.autofocus,
                enabled: widget.enabled,
                obscureText: masked,
                enableSuggestions: false,
                autocorrect: false,
                keyboardType: TextInputType.visiblePassword,
                onChanged: widget.onChanged,
                onSubmitted: widget.onSubmitted,
                style: style,
                cursorWidth: 1.5,
                cursorHeight: 16,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: widget.placeholder,
                  hintStyle: style.copyWith(color: p.inkTertiary),
                ),
              ),
            ),
          ),
          if (widget.revealable && widget.obscure)
            SottoIconButton(
              icon: _revealed ? SottoIcons.eyeOff : SottoIcons.eye,
              tooltip: _revealed ? l.passwordHide : l.passwordShow,
              size: 28,
              onPressed: widget.enabled ? () => setState(() => _revealed = !_revealed) : null,
            ),
        ],
      ),
    );

    final below = hasError
        ? _Line(text: widget.error!, color: p.liveCapture, icon: SottoIcons.alert, live: true)
        : widget.note != null
        ? _Line(text: widget.note!, color: p.inkSecondary, icon: SottoIcons.timer, live: true)
        : _capsLock && focused
        ? _Line(text: l.capsLockOn, color: p.caution, icon: SottoIcons.up)
        : null;

    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        // Three damped swings, 6 px at most.
        final t = _shake.value;
        final dx = t == 0 || t == 1 ? 0.0 : math.sin(t * math.pi * 6) * 6 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          field,
          // The line's room is always kept, so a message never moves the button.
          SizedBox(height: Space.s6, child: below),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.text, required this.color, required this.icon, this.live = false});

  final String text;
  final Color color;
  final SottoIcons icon;
  final bool live;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: live,
    child: Padding(
      padding: const EdgeInsets.only(top: Space.s1_5),
      child: Row(
        children: [
          SottoIcon(icon, size: 12, color: color),
          const SizedBox(width: Space.s1_5),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TypeScale.caption.copyWith(color: color),
            ),
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────── Strength ───────────────────────────

enum PasswordStrength { tooShort, weak, fair, good, strong }

/// A rough guess at how hard [password] is to guess: its length times the
/// variety of characters it uses, with repeats counted less. No rules to
/// satisfy — a long passphrase of plain words rates well.
PasswordStrength passwordStrength(String password, {int minLength = 8}) {
  final chars = password.runes.toList();
  if (chars.length < minLength) return PasswordStrength.tooShort;
  var pool = 0;
  if (RegExp('[a-z]').hasMatch(password)) pool += 26;
  if (RegExp('[A-Z]').hasMatch(password)) pool += 26;
  if (RegExp('[0-9]').hasMatch(password)) pool += 10;
  if (RegExp(r'[^a-zA-Z0-9]').hasMatch(password)) pool += 33;
  final unique = chars.toSet().length;
  final effective = math.min(chars.length, unique * 2);
  final bits = effective * math.log(math.max(pool, 10)) / math.ln2;
  return bits < 40
      ? PasswordStrength.weak
      : bits < 60
      ? PasswordStrength.fair
      : bits < 80
      ? PasswordStrength.good
      : PasswordStrength.strong;
}

/// Four bars and a short hint under a new password.
class PasswordStrengthMeter extends StatelessWidget {
  const PasswordStrengthMeter({super.key, required this.password, this.minLength = 8});

  final String password;
  final int minLength;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final s = passwordStrength(password, minLength: minLength);
    final (int lit, Color color, String hint) = switch (s) {
      PasswordStrength.tooShort => (0, p.inkTertiary, l.passwordTooShort(minLength)),
      PasswordStrength.weak => (1, p.caution, l.passwordWeak),
      PasswordStrength.fair => (2, p.caution, l.passwordFair),
      PasswordStrength.good => (3, p.confirmed, l.passwordGood),
      PasswordStrength.strong => (4, p.confirmed, l.passwordStrong),
    };
    return Semantics(
      liveRegion: true,
      label: hint,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                for (var i = 0; i < 4; i++) ...[
                  if (i > 0) const SizedBox(width: Space.s1),
                  Expanded(
                    child: AnimatedContainer(
                      duration: still ? Duration.zero : Motion.microOut,
                      height: 3,
                      decoration: BoxDecoration(color: i < lit ? color : p.control, borderRadius: Radii.rXs),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: Space.s1_5),
            Text(hint, style: TypeScale.caption.copyWith(color: p.inkSecondary)),
          ],
        ),
      ),
    );
  }
}

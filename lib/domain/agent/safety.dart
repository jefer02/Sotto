import 'agent_action.dart';

/// How much the presenter wants to supervise.
enum AgentMode {
  /// Every action waits for Enter (run) or Esc (stop). The default.
  confirmEach,

  /// Actions run on their own — except anything that submits, sends, pays,
  /// deletes or purchases, which still waits for confirmation.
  auto,
}

/// What the focused control is, from UI Automation / the AX API.
class FocusInfo {
  const FocusInfo({this.isPassword = false, this.name = '', this.role = ''});
  final bool isPassword;
  final String name;
  final String role;
}

/// Why an action was blocked or needs confirmation. The UI localizes it;
/// [english] is what the model is told.
enum SafetyReason {
  passwordField('the focused field is a password field'),
  secretField('it looks like a password or security-code field'),
  paymentField('it looks like a payment field'),
  cardNumber('the text looks like a card number'),
  irreversible('it may submit, send, pay or delete'),
  submitKey('it may submit or delete');

  const SafetyReason(this.english);
  final String english;
}

sealed class SafetyVerdict {
  const SafetyVerdict();
}

class Allow extends SafetyVerdict {
  const Allow();
}

/// Needs Enter from the presenter; [sensitive] means it would submit, send,
/// pay, delete or purchase — confirmed even in [AgentMode.auto].
class Confirm extends SafetyVerdict {
  const Confirm({this.sensitive = false, this.reason});
  final bool sensitive;
  final SafetyReason? reason;
}

/// Never runs, whatever the mode.
class Block extends SafetyVerdict {
  const Block(this.reason);
  final SafetyReason reason;
}

/// The mandatory rules: never type into password fields, never handle
/// payment data, always confirm irreversible actions.
abstract final class SafetyGate {
  static final _secret = RegExp(
    r'pass(word|code|phrase)|contrase(ñ|n)a|passwort|mot de passe|\bpin\b|\bsecret\b|one[- ]time code|\b2fa\b|\botp\b',
    caseSensitive: false,
  );

  static final _payment = RegExp(
    r'card ?number|credit|debit|\bcvv\b|\bcvc\b|\bcsc\b|security code|expir|\biban\b|\bswift\b|routing|account number|'
    r'tarjeta|caducidad|vencimiento|c[oó]digo de seguridad|n[uú]mero de cuenta|titular',
    caseSensitive: false,
  );

  static final _irreversible = RegExp(
    r'\b(submit|send|pay|payment|purchase|buy|order|checkout|check out|place|delete|remove|erase|discard|confirm|'
    r'transfer|publish|post|sign|book|donate|subscribe|unsubscribe|uninstall|format|empty trash|'
    r'enviar|env[ií]a|pagar|paga|comprar|compra|pedido|eliminar|elimina|borrar|borra|suprimir|confirmar|confirma|'
    r'transferir|publicar|publica|firmar|reservar|donar|suscrib|vaciar)\b',
    caseSensitive: false,
  );

  /// A password, PIN or one-time-code field, by its label.
  static bool isSecretLabel(String label) => _secret.hasMatch(label);

  /// A card, bank-account or other payment field, by its label.
  static bool isPaymentLabel(String label) => _payment.hasMatch(label);

  /// Card numbers pass the Luhn check; 13–19 digits once spaces and dashes
  /// are gone.
  static bool looksLikeCardNumber(String text) {
    for (final m in RegExp(r'(?:\d[ -]?){13,19}').allMatches(text)) {
      final digits = m.group(0)!.replaceAll(RegExp(r'[ -]'), '');
      if (digits.length < 13 || digits.length > 19) continue;
      var sum = 0;
      var dbl = false;
      for (var i = digits.length - 1; i >= 0; i--) {
        var d = digits.codeUnitAt(i) - 48;
        if (dbl) {
          d *= 2;
          if (d > 9) d -= 9;
        }
        sum += d;
        dbl = !dbl;
      }
      if (sum % 10 == 0) return true;
    }
    return false;
  }

  static SafetyVerdict check(AgentAction action, {required AgentMode mode, FocusInfo? focus}) {
    final label = '${action.target} ${focus?.name ?? ''}';
    switch (action) {
      case TypeTextAction(:final text):
        if (focus?.isPassword ?? false) return const Block(SafetyReason.passwordField);
        if (_secret.hasMatch(label)) return const Block(SafetyReason.secretField);
        if (_payment.hasMatch(label)) return const Block(SafetyReason.paymentField);
        if (looksLikeCardNumber(text)) return const Block(SafetyReason.cardNumber);
      case ClickAction(:final target) || MoveAction(:final target) when _irreversible.hasMatch(target):
        if (action is ClickAction) return const Confirm(sensitive: true, reason: SafetyReason.irreversible);
      case PressKeysAction(:final keys):
        final submits = keys.contains('enter') || keys.contains('return') || keys.contains('delete');
        if (submits || _irreversible.hasMatch(action.target)) {
          return const Confirm(sensitive: true, reason: SafetyReason.submitKey);
        }
      case DoneAction() || ScreenshotAction() || WaitAction():
        return const Allow();
      default:
        break;
    }
    return mode == AgentMode.confirmEach ? const Confirm() : const Allow();
  }
}

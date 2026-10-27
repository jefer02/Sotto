import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

/// Windows Hello / Touch ID for the App Lock. It only answers yes or no —
/// the data key itself comes from the keychain afterwards.
class Biometrics {
  Biometrics({required this.os, LocalAuthentication? auth}) : _auth = auth ?? LocalAuthentication();

  final String os;
  final LocalAuthentication _auth;

  /// What the presenter calls it: a product name, the same in every language.
  String get method => os == 'macos' ? 'Touch ID' : 'Windows Hello';

  /// Set up on this computer (a Hello PIN or face, a Touch ID finger).
  Future<bool> available() async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (e) {
      debugPrint('[lock] biometrics unavailable: ${e.runtimeType}');
      return false;
    }
  }

  /// Shows the system prompt with [reason]. False when it is cancelled or
  /// fails for any reason.
  Future<bool> confirm(String reason) async {
    try {
      return await _auth.authenticate(localizedReason: reason, persistAcrossBackgrounding: true);
    } catch (e) {
      debugPrint('[lock] biometric prompt failed: ${e.runtimeType}');
      return false;
    }
  }
}

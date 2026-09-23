import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum SecretKey { anthropicApiKey, openaiApiKey, compatibleApiKey, cloudSttApiKey }

/// API keys are the user's own and never touch the Hive database: they go to
/// the macOS Keychain / Windows Credential Manager.
class SecretStore {
  SecretStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // The legacy login keychain works for unsigned development
            // builds; the data-protection keychain needs an access group.
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );

  final FlutterSecureStorage _storage;
  final Map<SecretKey, String?> _cache = {};

  Future<String?> read(SecretKey key) async {
    if (_cache.containsKey(key)) return _cache[key];
    final value = await _storage.read(key: 'sotto.${key.name}');
    _cache[key] = value;
    return value;
  }

  Future<void> write(SecretKey key, String? value) async {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await _storage.delete(key: 'sotto.${key.name}');
      _cache[key] = null;
    } else {
      await _storage.write(key: 'sotto.${key.name}', value: trimmed);
      _cache[key] = trimmed;
    }
  }

  Future<void> wipe() async {
    for (final k in SecretKey.values) {
      await write(k, null);
    }
  }
}

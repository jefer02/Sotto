import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum SecretKey {
  deepseekApiKey,

  /// The App Lock's data key, only while "Unlock with Windows Hello /
  /// Touch ID" is on. Not an API key: "Remove API keys" leaves it alone.
  appLockKey,
}

/// Keychain entries of features that no longer exist (other AI providers,
/// cloud speech recognition). Only ever deleted — see [SecretStore.purgeLegacy].
const _legacyKeys = ['anthropicApiKey', 'openaiApiKey', 'compatibleApiKey', 'cloudSttApiKey'];

/// API keys the user saves never touch the Hive database: they go to
/// the macOS Keychain / Windows Credential Manager.
class SecretStore {
  SecretStore([FlutterSecureStorage? storage, this.lockKeyPrefix = 'sotto.'])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // The legacy login keychain works for unsigned development
            // builds; the data-protection keychain needs an access group.
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );

  final FlutterSecureStorage _storage;
  final Map<SecretKey, String?> _cache = {};

  /// The lock key's prefix: `sotto.dev.` under SOTTO_DATA_ROOT
  /// (`StoragePaths.keychainPrefix`), so a test run has its own.
  final String lockKeyPrefix;

  String _name(SecretKey key) => '${key == SecretKey.appLockKey ? lockKeyPrefix : 'sotto.'}${key.name}';

  Future<String?> read(SecretKey key) async {
    if (_cache.containsKey(key)) return _cache[key];
    final value = await _storage.read(key: _name(key));
    // The lock's data key is read only to unlock, and never kept around.
    if (key != SecretKey.appLockKey) _cache[key] = value;
    return value;
  }

  Future<void> write(SecretKey key, String? value) async {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await _storage.delete(key: _name(key));
      _cache[key] = null;
    } else {
      await _storage.write(key: _name(key), value: trimmed);
      if (key != SecretKey.appLockKey) _cache[key] = trimmed;
    }
  }

  Future<void> wipe() async {
    for (final k in SecretKey.values) {
      if (k != SecretKey.appLockKey) await write(k, null);
    }
    await purgeLegacy();
  }

  /// Deletes keys older versions saved, so none linger in the keychain
  /// after an update. Runs at startup; best effort.
  Future<void> purgeLegacy() async {
    for (final k in _legacyKeys) {
      try {
        await _storage.delete(key: 'sotto.$k');
      } catch (_) {}
    }
  }
}

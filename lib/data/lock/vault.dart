import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

import 'atomic_file.dart';
import 'recovery_key.dart';

/// Argon2id cost. Stored in the vault, so a later version can raise it and
/// every existing vault still opens with the cost it was made with.
class KdfParams {
  const KdfParams({required this.memoryKiB, required this.iterations, required this.parallelism});

  /// 64 MiB, 2 passes: about 600 ms on a mid-range Windows laptop in a
  /// release build (64 MiB × 3 took about 930 ms, over the 800 ms budget).
  /// OWASP's floor is 19 MiB × 2.
  static const standard = KdfParams(memoryKiB: 64 * 1024, iterations: 2, parallelism: 1);

  static const name = 'argon2id';
  static const keyLength = 32;

  final int memoryKiB;
  final int iterations;
  final int parallelism;

  Map<String, Object> toJson() => {
    'name': name,
    'memoryKiB': memoryKiB,
    'iterations': iterations,
    'parallelism': parallelism,
    'length': keyLength,
  };

  /// Bounds keep a tampered file from asking for gigabytes or hours.
  factory KdfParams.fromJson(Map<String, dynamic> j) {
    if (j['name'] != name || j['length'] != keyLength) throw const FormatException('unsupported kdf');
    final p = KdfParams(
      memoryKiB: j['memoryKiB'] as int,
      iterations: j['iterations'] as int,
      parallelism: j['parallelism'] as int,
    );
    if (p.memoryKiB < 8 || p.memoryKiB > 1024 * 1024) throw const FormatException('kdf memory out of range');
    if (p.iterations < 1 || p.iterations > 16) throw const FormatException('kdf iterations out of range');
    if (p.parallelism < 1 || p.parallelism > 8) throw const FormatException('kdf parallelism out of range');
    return p;
  }
}

/// One AES-256-GCM sealed value: a 12-byte nonce and the ciphertext with
/// its 16-byte tag.
class VaultSlot {
  const VaultSlot(this.nonce, this.data);

  final Uint8List nonce;
  final Uint8List data;

  Map<String, String> toJson() => {'nonce': base64Encode(nonce), 'data': base64Encode(data)};

  factory VaultSlot.fromJson(Map<String, dynamic> j) {
    final slot = VaultSlot(base64Decode(j['nonce'] as String), base64Decode(j['data'] as String));
    if (slot.nonce.length != 12 || slot.data.length < 16) throw const FormatException('bad slot');
    return slot;
  }
}

/// `lock_vault.json`: the data key (DEK) the Hive boxes are encrypted with,
/// wrapped twice — by a key derived from the password (Argon2id) and by one
/// derived from the recovery key (HKDF) — plus the recovery key itself,
/// sealed under the DEK so it can be shown again after a password check.
///
/// Every slot is bound to the header (format, KDF and its parameters, the
/// salt) as GCM associated data: editing any of them fails authentication
/// instead of quietly changing how the key is derived.
class LockVault {
  const LockVault({
    required this.params,
    required this.salt,
    required this.password,
    required this.recovery,
    required this.recoveryKey,
    required this.createdAt,
  });

  static const format = 1;

  final KdfParams params;
  final Uint8List salt;
  final VaultSlot password;
  final VaultSlot recovery;
  final VaultSlot recoveryKey;
  final DateTime createdAt;

  Map<String, Object> toJson() => {
    'format': format,
    'kdf': params.toJson(),
    'salt': base64Encode(salt),
    'password': password.toJson(),
    'recovery': recovery.toJson(),
    'recoveryKey': recoveryKey.toJson(),
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  /// Throws [FormatException] for anything that isn't a vault this version
  /// can read.
  factory LockVault.fromJson(Map<String, dynamic> j) {
    try {
      if (j['format'] != format) throw const FormatException('unsupported vault format');
      final salt = base64Decode(j['salt'] as String);
      if (salt.length != 16) throw const FormatException('bad salt');
      return LockVault(
        params: KdfParams.fromJson((j['kdf'] as Map).cast<String, dynamic>()),
        salt: salt,
        password: VaultSlot.fromJson((j['password'] as Map).cast<String, dynamic>()),
        recovery: VaultSlot.fromJson((j['recovery'] as Map).cast<String, dynamic>()),
        recoveryKey: VaultSlot.fromJson((j['recoveryKey'] as Map).cast<String, dynamic>()),
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('malformed vault: ${e.runtimeType}');
    }
  }

  /// What every slot is bound to, plus the slot's own name so slots can't
  /// be swapped for one another.
  static Uint8List _aad(KdfParams params, List<int> salt, String slot) => utf8.encode(
    'sotto-vault|$format|${KdfParams.name}|${params.memoryKiB}|${params.iterations}|'
    '${params.parallelism}|${KdfParams.keyLength}|${base64Encode(salt)}|$slot',
  );
}

/// What setting up the lock produces: the vault to save, the DEK to encrypt
/// the boxes with, and the recovery key to show once.
typedef VaultSetup = ({LockVault vault, Uint8List dek, String recoveryKey});

/// The vault's cryptography. Keys are `Uint8List`s the caller drops (and
/// may [forget]) as soon as it is done; Dart can't promise a copy isn't left
/// behind in memory, which the architecture notes say.
abstract final class VaultCrypto {
  static final _aes = AesGcm.with256bits();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  static const dekLength = 32;

  static Uint8List _random(int n) {
    final rng = Random.secure();
    return Uint8List.fromList([for (var i = 0; i < n; i++) rng.nextInt(256)]);
  }

  /// A new vault for [password] around a fresh DEK.
  static Future<VaultSetup> create(String password, {KdfParams params = KdfParams.standard}) async {
    final dek = _random(dekLength);
    final (recovery, recoveryText) = RecoveryKey.generate();
    final vault = await _build(
      dek: dek,
      password: password,
      recovery: recovery,
      params: params,
      createdAt: DateTime.now(),
    );
    return (vault: vault, dek: dek, recoveryKey: recoveryText);
  }

  /// The DEK, or null when [password] is wrong (or the vault was altered).
  static Future<Uint8List?> openWithPassword(LockVault vault, String password) async {
    final kek = await deriveKek(password, vault.salt, vault.params);
    return _open(vault.password, kek, LockVault._aad(vault.params, vault.salt, 'password'));
  }

  /// The DEK, or null when [recoveryKey] is malformed or not this vault's.
  static Future<Uint8List?> openWithRecovery(LockVault vault, String recoveryKey) async {
    final raw = RecoveryKey.parse(recoveryKey);
    if (raw == null) return null;
    final kek = await _recoveryKek(raw);
    return _open(vault.recovery, kek, LockVault._aad(vault.params, vault.salt, 'recovery'));
  }

  /// Whether [dek] is this vault's — for a key read back from the keychain,
  /// which must never open the boxes unchecked (Hive doesn't check keys).
  static Future<bool> verifyKey(LockVault vault, List<int> dek) async => await _recoveryBytes(vault, dek) != null;

  /// The recovery key, shown again after the password was checked.
  static Future<String?> recoveryKeyOf(LockVault vault, List<int> dek) async {
    final raw = await _recoveryBytes(vault, dek);
    return raw == null ? null : RecoveryKey.format(raw);
  }

  /// The same DEK under [newPassword] with a new salt; the recovery key
  /// stays valid. The data itself is untouched.
  static Future<LockVault> withPassword(LockVault vault, List<int> dek, String newPassword) async {
    final recovery = await _recoveryBytes(vault, dek);
    if (recovery == null) throw StateError('key does not match the vault');
    return _build(
      dek: dek,
      password: newPassword,
      recovery: recovery,
      params: vault.params,
      createdAt: vault.createdAt,
    );
  }

  /// A new recovery key; the old one stops working the moment the returned
  /// vault replaces the saved one. The password slot is carried over.
  static Future<(LockVault, String)> withNewRecoveryKey(LockVault vault, List<int> dek) async {
    if (!await verifyKey(vault, dek)) throw StateError('key does not match the vault');
    final (recovery, text) = RecoveryKey.generate();
    final next = LockVault(
      params: vault.params,
      salt: vault.salt,
      password: vault.password,
      recovery: await _seal(dek, await _recoveryKek(recovery), LockVault._aad(vault.params, vault.salt, 'recovery')),
      recoveryKey: await _seal(recovery, dek, LockVault._aad(vault.params, vault.salt, 'recoveryKey')),
      createdAt: vault.createdAt,
    );
    return (next, text);
  }

  /// A key for one purpose, derived from the DEK (HKDF-SHA256, [info] as
  /// the label) — e.g. the organize cache's HMAC key.
  static Future<Uint8List> subkey(List<int> dek, String info) async {
    final key = await _hkdf.deriveKey(secretKey: SecretKeyData(dek), nonce: const <int>[], info: utf8.encode(info));
    return Uint8List.fromList(await key.extractBytes());
  }

  /// Argon2id(password), off the UI thread: about 600 ms of work at
  /// [KdfParams.standard].
  static Future<Uint8List> deriveKek(String password, List<int> salt, KdfParams params) {
    final pw = utf8.encode(password);
    final s = Uint8List.fromList(salt);
    return Isolate.run(() async {
      final argon = DartArgon2id(
        parallelism: params.parallelism,
        memory: params.memoryKiB,
        iterations: params.iterations,
        hashLength: KdfParams.keyLength,
      );
      final key = await argon.deriveKey(secretKey: SecretKeyData(pw), nonce: s);
      return Uint8List.fromList(await key.extractBytes());
    });
  }

  /// Zero-fills a key the caller is done with. Best effort: copies made by
  /// the crypto library or the GC may survive.
  static void forget(List<int>? key) {
    if (key is Uint8List) key.fillRange(0, key.length, 0);
  }

  // ─────────────────────────── Internals ───────────────────────────

  static Future<LockVault> _build({
    required List<int> dek,
    required String password,
    required List<int> recovery,
    required KdfParams params,
    required DateTime createdAt,
  }) async {
    final salt = _random(16);
    final kek = await deriveKek(password, salt, params);
    try {
      return LockVault(
        params: params,
        salt: salt,
        password: await _seal(dek, kek, LockVault._aad(params, salt, 'password')),
        recovery: await _seal(dek, await _recoveryKek(recovery), LockVault._aad(params, salt, 'recovery')),
        recoveryKey: await _seal(recovery, dek, LockVault._aad(params, salt, 'recoveryKey')),
        createdAt: createdAt,
      );
    } finally {
      forget(kek);
    }
  }

  static Future<Uint8List?> _recoveryBytes(LockVault vault, List<int> dek) =>
      _open(vault.recoveryKey, dek, LockVault._aad(vault.params, vault.salt, 'recoveryKey'));

  /// The recovery key is already 128 random bits: HKDF only stretches it to
  /// a wrapping key, no password hashing needed.
  static Future<Uint8List> _recoveryKek(List<int> recovery) => subkey(recovery, 'sotto-recovery-wrap');

  static Future<VaultSlot> _seal(List<int> plain, List<int> key, List<int> aad) async {
    final box = await _aes.encrypt(plain, secretKey: SecretKeyData(key), nonce: _random(12), aad: aad);
    return VaultSlot(Uint8List.fromList(box.nonce), box.concatenation(nonce: false));
  }

  static Future<Uint8List?> _open(VaultSlot slot, List<int> key, List<int> aad) async {
    try {
      final box = SecretBox.fromConcatenation(slot.data, nonceLength: 0, macLength: 16);
      final plain = await _aes.decrypt(
        SecretBox(box.cipherText, nonce: slot.nonce, mac: box.mac),
        secretKey: SecretKeyData(key),
        aad: aad,
      );
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      return null;
    }
  }
}

/// The vault on disk. A file that exists but can't be read is [damaged] —
/// never "no lock": the boxes it protects are still encrypted.
class VaultFile {
  VaultFile(this.file);

  final File file;

  bool get exists => file.existsSync();

  /// Null when there is no vault; throws [VaultDamaged] when there is one
  /// that can't be read.
  Future<LockVault?> read() async {
    if (!await file.exists()) return null;
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) throw const FormatException('not an object');
      return LockVault.fromJson(json.cast<String, dynamic>());
    } on FormatException catch (e) {
      throw VaultDamaged(e.message);
    } on FileSystemException catch (e) {
      throw VaultDamaged(e.message);
    }
  }

  Future<void> write(LockVault vault) =>
      writeFileAtomic(file, const JsonEncoder.withIndent('  ').convert(vault.toJson()));

  Future<void> delete() async {
    if (await file.exists()) await file.delete();
  }
}

class VaultDamaged implements Exception {
  const VaultDamaged(this.reason);
  final String reason;

  @override
  String toString() => 'The lock vault could not be read ($reason).';
}

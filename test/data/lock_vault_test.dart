import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/data/lock/recovery_key.dart';
import 'package:sotto/data/lock/vault.dart';

/// Cheap Argon2id for tests; the real cost is covered once below.
const _fast = KdfParams(memoryKiB: 64, iterations: 1, parallelism: 1);

void main() {
  group('Recovery key', () {
    test('reads as 7 groups of 4 Crockford characters and parses back', () {
      final (raw, text) = RecoveryKey.generate(Random(7));
      expect(text, matches(RegExp(r'^[0-9A-HJKMNP-TV-Z]{4}(-[0-9A-HJKMNP-TV-Z]{4}){6}$')));
      expect(RecoveryKey.parse(text), raw);
    });

    test('forgives case, spaces, missing dashes and O / I / L', () {
      final (raw, text) = RecoveryKey.generate(Random(3));
      final loose = text.toLowerCase().replaceAll('-', ' ').replaceAll('0', 'o').replaceAll('1', 'l');
      expect(RecoveryKey.parse(loose), raw);
      expect(RecoveryKey.parse(text.replaceAll('-', '')), raw);
    });

    test('a typo fails the checksum', () {
      final rng = Random(11);
      var caught = 0;
      for (var i = 0; i < 200; i++) {
        final (_, text) = RecoveryKey.generate(rng);
        final at = text.indexOf(RegExp('[0-9A-Z]'), rng.nextInt(text.length - 1));
        final swapped = text[at] == '7' ? '8' : '7';
        if (RecoveryKey.parse(text.replaceRange(at, at + 1, swapped)) == null) caught++;
      }
      // 12 check bits: a slip gets through about 1 time in 4096.
      expect(caught, greaterThanOrEqualTo(199));
    });

    test('rejects the wrong length and letters outside the alphabet', () {
      final (_, text) = RecoveryKey.generate(Random(1));
      expect(RecoveryKey.parse(text.substring(0, text.length - 1)), isNull);
      expect(RecoveryKey.parse('${text.substring(0, text.length - 1)}U'), isNull);
      expect(RecoveryKey.parse(''), isNull);
    });
  });

  group('Vault', () {
    test('wraps and unwraps the data key with the password', () async {
      final setup = await VaultCrypto.create('correct horse battery', params: _fast);
      expect(setup.dek, hasLength(32));
      expect(await VaultCrypto.openWithPassword(setup.vault, 'correct horse battery'), setup.dek);
    });

    test('a wrong password fails cleanly', () async {
      final setup = await VaultCrypto.create('correct horse battery', params: _fast);
      expect(await VaultCrypto.openWithPassword(setup.vault, 'correct horse batterY'), isNull);
      expect(await VaultCrypto.openWithPassword(setup.vault, ''), isNull);
    });

    test('the recovery key opens it too, and is the one shown', () async {
      final setup = await VaultCrypto.create('pw-12345678', params: _fast);
      expect(await VaultCrypto.openWithRecovery(setup.vault, setup.recoveryKey), setup.dek);
      expect(await VaultCrypto.openWithRecovery(setup.vault, setup.recoveryKey.toLowerCase()), setup.dek);
      expect(await VaultCrypto.recoveryKeyOf(setup.vault, setup.dek), setup.recoveryKey);

      final (_, other) = RecoveryKey.generate();
      expect(await VaultCrypto.openWithRecovery(setup.vault, other), isNull);
      expect(await VaultCrypto.openWithRecovery(setup.vault, 'not a key'), isNull);
    });

    test('changing the password keeps the data key and the recovery key', () async {
      final setup = await VaultCrypto.create('old password', params: _fast);
      final next = await VaultCrypto.withPassword(setup.vault, setup.dek, 'new password');
      expect(next.salt, isNot(setup.vault.salt));
      expect(await VaultCrypto.openWithPassword(next, 'old password'), isNull);
      expect(await VaultCrypto.openWithPassword(next, 'new password'), setup.dek);
      expect(await VaultCrypto.openWithRecovery(next, setup.recoveryKey), setup.dek);
      expect(next.createdAt, setup.vault.createdAt);
    });

    test('forgot password: recovery key, then a new password', () async {
      final setup = await VaultCrypto.create('forgotten', params: _fast);
      final dek = (await VaultCrypto.openWithRecovery(setup.vault, setup.recoveryKey))!;
      final next = await VaultCrypto.withPassword(setup.vault, dek, 'remembered');
      expect(await VaultCrypto.openWithPassword(next, 'remembered'), setup.dek);
    });

    test('a new recovery key replaces the old one', () async {
      final setup = await VaultCrypto.create('password1', params: _fast);
      final (next, fresh) = await VaultCrypto.withNewRecoveryKey(setup.vault, setup.dek);
      expect(fresh, isNot(setup.recoveryKey));
      expect(await VaultCrypto.openWithRecovery(next, setup.recoveryKey), isNull);
      expect(await VaultCrypto.openWithRecovery(next, fresh), setup.dek);
      expect(await VaultCrypto.openWithPassword(next, 'password1'), setup.dek);
      expect(await VaultCrypto.recoveryKeyOf(next, setup.dek), fresh);
    });

    test('only its own data key verifies', () async {
      final setup = await VaultCrypto.create('password1', params: _fast);
      expect(await VaultCrypto.verifyKey(setup.vault, setup.dek), isTrue);
      expect(await VaultCrypto.verifyKey(setup.vault, List.filled(32, 7)), isFalse);
      await expectLater(VaultCrypto.withPassword(setup.vault, List.filled(32, 7), 'x'), throwsStateError);
    });

    test('subkeys are stable per purpose and differ between purposes', () async {
      final dek = List.generate(32, (i) => i);
      final a = await VaultCrypto.subkey(dek, 'sotto-organize-cache');
      expect(a, hasLength(32));
      expect(await VaultCrypto.subkey(dek, 'sotto-organize-cache'), a);
      expect(await VaultCrypto.subkey(dek, 'something-else'), isNot(a));
    });

    test('parameters round-trip through JSON', () async {
      final setup = await VaultCrypto.create('password1', params: _fast);
      final json = jsonDecode(jsonEncode(setup.vault.toJson())) as Map<String, dynamic>;
      expect(json['format'], 1);
      expect(json['kdf'], {'name': 'argon2id', 'memoryKiB': 64, 'iterations': 1, 'parallelism': 1, 'length': 32});
      final back = LockVault.fromJson(json);
      expect(back.params.memoryKiB, 64);
      expect(back.salt, setup.vault.salt);
      expect(await VaultCrypto.openWithPassword(back, 'password1'), setup.dek);
    });

    test('the standard cost is 64 MiB × 2 passes and opens', () async {
      expect(KdfParams.standard.memoryKiB, 65536);
      expect(KdfParams.standard.iterations, 2);
      expect(KdfParams.standard.parallelism, 1);
      final setup = await VaultCrypto.create('real cost');
      expect(await VaultCrypto.openWithPassword(setup.vault, 'real cost'), setup.dek);
    }, timeout: const Timeout(Duration(minutes: 2)));

    group('a tampered vault is rejected', () {
      late VaultSetup setup;
      late Map<String, dynamic> json;
      setUp(() async {
        setup = await VaultCrypto.create('password1', params: _fast);
        json = jsonDecode(jsonEncode(setup.vault.toJson())) as Map<String, dynamic>;
      });

      Future<Object?> openEdited(void Function(Map<String, dynamic> j) edit) async {
        edit(json);
        return VaultCrypto.openWithPassword(LockVault.fromJson(json), 'password1');
      }

      String flip(String b64) {
        final bytes = base64Decode(b64);
        bytes[bytes.length ~/ 2] ^= 1;
        return base64Encode(bytes);
      }

      test('wrapped key', () async {
        expect(await openEdited((j) => j['password']['data'] = flip(j['password']['data'] as String)), isNull);
      });
      test('nonce', () async {
        expect(await openEdited((j) => j['password']['nonce'] = flip(j['password']['nonce'] as String)), isNull);
      });
      test('salt', () async {
        expect(await openEdited((j) => j['salt'] = flip(j['salt'] as String)), isNull);
      });
      test('KDF parameters', () async {
        expect(await openEdited((j) => j['kdf']['iterations'] = 2), isNull);
      });
      test('slots swapped', () async {
        expect(await openEdited((j) => j['password'] = j['recovery']), isNull);
      });
      test('recovery slot', () async {
        json['recovery']['data'] = flip(json['recovery']['data'] as String);
        expect(await VaultCrypto.openWithRecovery(LockVault.fromJson(json), setup.recoveryKey), isNull);
      });

      test('malformed or out-of-range fields', () {
        Map<String, dynamic> copy() => jsonDecode(jsonEncode(setup.vault.toJson())) as Map<String, dynamic>;
        expect(() => LockVault.fromJson(copy()..['format'] = 2), throwsFormatException);
        expect(() => LockVault.fromJson(copy()..['salt'] = 'AAAA'), throwsFormatException);
        expect(() => LockVault.fromJson(copy()..remove('recovery')), throwsFormatException);
        expect(() => LockVault.fromJson(copy()..['kdf']['memoryKiB'] = 1 << 30), throwsFormatException);
        expect(() => LockVault.fromJson(copy()..['kdf']['name'] = 'pbkdf2'), throwsFormatException);
        expect(() => LockVault.fromJson(copy()..['password']['nonce'] = 'AAAA'), throwsFormatException);
      });
    });
  });

  group('Vault file', () {
    late Directory dir;
    late VaultFile file;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('sotto_vault');
      file = VaultFile(File('${dir.path}/lock_vault.json'));
    });
    tearDown(() => dir.delete(recursive: true));

    test('missing reads as no lock', () async {
      expect(file.exists, isFalse);
      expect(await file.read(), isNull);
    });

    test('writes, replaces and reads back, leaving no temp file', () async {
      final a = await VaultCrypto.create('first', params: _fast);
      await file.write(a.vault);
      final b = await VaultCrypto.withPassword(a.vault, a.dek, 'second');
      await file.write(b);
      final read = (await file.read())!;
      expect(await VaultCrypto.openWithPassword(read, 'second'), a.dek);
      expect(dir.listSync().map((e) => e.uri.pathSegments.last), ['lock_vault.json']);
    });

    test('an unreadable file is damaged, not "no lock"', () async {
      await file.file.writeAsString('{"format": 1, "salt": ');
      await expectLater(file.read(), throwsA(isA<VaultDamaged>()));
      await file.file.writeAsString('[]');
      await expectLater(file.read(), throwsA(isA<VaultDamaged>()));
    });

    test('delete removes it', () async {
      await file.write((await VaultCrypto.create('x', params: _fast)).vault);
      await file.delete();
      expect(file.exists, isFalse);
      await file.delete();
    });
  });
}

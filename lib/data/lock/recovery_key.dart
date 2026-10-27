import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The App Lock's recovery key: 128 random bits shown once, as 28 Crockford
/// Base32 characters in groups of four (`7KQ2-M9XD-…`). The last 12 bits
/// are a checksum (the start of SHA-256 of the key), so a mistyped key is
/// caught before any decryption is tried.
///
/// Input is forgiving: any case, spaces or dashes, and O / I / L read as
/// 0 / 1 / 1, as Crockford's alphabet intends.
abstract final class RecoveryKey {
  static const bytes = 16;
  static const length = 28;
  static const group = 4;

  static const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static const _checkBits = length * 5 - bytes * 8; // 12

  /// A fresh key from the platform CSPRNG: the raw bytes and how they read.
  static (Uint8List, String) generate([Random? random]) {
    final rng = random ?? Random.secure();
    final raw = Uint8List.fromList([for (var i = 0; i < bytes; i++) rng.nextInt(256)]);
    return (raw, format(raw));
  }

  /// [raw] as grouped text.
  static String format(List<int> raw) {
    assert(raw.length == bytes);
    var bits = BigInt.zero;
    for (final b in raw) {
      bits = (bits << 8) | BigInt.from(b);
    }
    bits = (bits << _checkBits) | BigInt.from(_checksum(raw));
    final chars = List.filled(length, '');
    for (var i = length - 1; i >= 0; i--) {
      chars[i] = _alphabet[(bits & BigInt.from(31)).toInt()];
      bits >>= 5;
    }
    final out = StringBuffer();
    for (var i = 0; i < length; i++) {
      if (i > 0 && i % group == 0) out.write('-');
      out.write(chars[i]);
    }
    return out.toString();
  }

  /// The key's bytes, or null if [text] isn't a well-formed key (wrong
  /// length, a letter outside the alphabet, or a checksum that fails).
  static Uint8List? parse(String text) {
    final clean = text.toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');
    if (clean.length != length) return null;
    var bits = BigInt.zero;
    for (final c in clean.split('')) {
      final v = _alphabet.indexOf(switch (c) {
        'O' => '0',
        'I' || 'L' => '1',
        _ => c,
      });
      if (v < 0) return null;
      bits = (bits << 5) | BigInt.from(v);
    }
    final check = (bits & BigInt.from((1 << _checkBits) - 1)).toInt();
    bits >>= _checkBits;
    final raw = Uint8List(bytes);
    for (var i = bytes - 1; i >= 0; i--) {
      raw[i] = (bits & BigInt.from(255)).toInt();
      bits >>= 8;
    }
    return _checksum(raw) == check ? raw : null;
  }

  static int _checksum(List<int> raw) {
    final d = sha256.convert(raw).bytes;
    return ((d[0] << 8) | d[1]) >> (16 - _checkBits);
  }
}

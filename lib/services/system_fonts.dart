import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/design/script_fonts.dart';
import '../data/repositories.dart';

/// Font families installed on this computer, for the script font picker.
///
/// Windows and macOS: every font file in the system and user font folders,
/// named by its own `name` table (the typographic family, else the family),
/// so "Segoe UI Semibold" lists as "Segoe UI". Linux: fontconfig's list.
/// Runs in an isolate; reads only each file's table directory and `name`
/// table (a few KB), never whole fonts.
abstract final class SystemFonts {
  static Future<List<String>> families() => Isolate.run(_scan);

  static Future<List<String>> _scan() async {
    if (Platform.isLinux) {
      try {
        final r = await Process.run('fc-list', [':', 'family']);
        if (r.exitCode == 0) {
          return _sorted([
            for (final line in const LineSplitter().convert(r.stdout as String))
              // "DejaVu Sans,DejaVu Sans Condensed": the first is the family.
              if (line.split(',').first.trim() case final f when f.isNotEmpty) f,
          ]);
        }
      } on ProcessException {
        // No fontconfig: read the folders below.
      }
    }
    final names = <String>[];
    for (final dir in _folders()) {
      final d = Directory(dir);
      if (!d.existsSync()) continue;
      for (final f in d.listSync(recursive: true, followLinks: false).whereType<File>()) {
        final ext = p.extension(f.path).toLowerCase();
        if (ext != '.ttf' && ext != '.otf' && ext != '.ttc' && ext != '.otc') continue;
        try {
          names.addAll(familiesInFile(f));
        } catch (_) {
          // A damaged or unreadable font: skip it.
        }
      }
    }
    return _sorted(names);
  }

  static List<String> _sorted(Iterable<String> names) {
    final unique = {for (final n in names) n.trim()}..removeWhere((n) => n.isEmpty || n.startsWith('.'));
    return unique.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  static List<String> _folders() {
    final env = Platform.environment;
    if (Platform.isWindows) {
      return [
        p.join(env['WINDIR'] ?? r'C:\Windows', 'Fonts'),
        if (env['LOCALAPPDATA'] case final local?) p.join(local, 'Microsoft', 'Windows', 'Fonts'),
      ];
    }
    final home = env['HOME'] ?? '';
    if (Platform.isMacOS) {
      return [
        '/System/Library/Fonts',
        '/System/Library/Fonts/Supplemental',
        '/Library/Fonts',
        p.join(home, 'Library', 'Fonts'),
      ];
    }
    return ['/usr/share/fonts', '/usr/local/share/fonts', p.join(home, '.fonts'), p.join(home, '.local/share/fonts')];
  }

  /// The family of each font in [file] (one, or several in a collection).
  static List<String> familiesInFile(File file) {
    final raf = file.openSync();
    try {
      final head = _read(raf, 0, 12);
      if (String.fromCharCodes(head.buffer.asUint8List(head.offsetInBytes, 4)) == 'ttcf') {
        final count = head.getUint32(8);
        final offsets = _read(raf, 12, 4 * count);
        return [for (var i = 0; i < count; i++) ?_familyAt(raf, offsets.getUint32(4 * i))];
      }
      return [?_familyAt(raf, 0)];
    } finally {
      raf.closeSync();
    }
  }

  static ByteData _read(RandomAccessFile raf, int at, int length) {
    raf.setPositionSync(at);
    final bytes = raf.readSync(length);
    if (bytes.length < length) throw const FormatException('truncated font');
    return ByteData.sublistView(bytes);
  }

  /// The family named in the font whose table directory is at [at].
  static String? _familyAt(RandomAccessFile raf, int at) {
    final numTables = _read(raf, at + 4, 2).getUint16(0);
    final dir = _read(raf, at + 12, 16 * numTables);
    for (var t = 0; t < numTables; t++) {
      final tag = String.fromCharCodes(dir.buffer.asUint8List(dir.offsetInBytes + 16 * t, 4));
      if (tag != 'name') continue;
      final offset = dir.getUint32(16 * t + 8), length = dir.getUint32(16 * t + 12);
      return familyFromNameTable(_read(raf, offset, length));
    }
    return null;
  }

  /// The typographic family (name ID 16), else the family (ID 1): English
  /// Windows names first, then any Windows name, then Macintosh names.
  static String? familyFromNameTable(ByteData name) {
    final count = name.getUint16(2), strings = name.getUint16(4);
    String? best;
    var bestRank = 1 << 30;
    for (var r = 0; r < count; r++) {
      final at = 6 + 12 * r;
      if (at + 12 > name.lengthInBytes) break;
      final platform = name.getUint16(at), language = name.getUint16(at + 4), id = name.getUint16(at + 6);
      if (id != 16 && id != 1) continue;
      final rank =
          (id == 16 ? 0 : 10) +
          switch (platform) {
            3 when language == 0x409 => 0,
            3 => 1,
            1 => 2,
            _ => 9,
          };
      if (rank >= bestRank) continue;
      final length = name.getUint16(at + 8), offset = strings + name.getUint16(at + 10);
      if (offset + length > name.lengthInBytes) continue;
      final raw = name.buffer.asUint8List(name.offsetInBytes + offset, length);
      final text = platform == 3 || platform == 0
          ? String.fromCharCodes([for (var i = 0; i + 1 < raw.length; i += 2) (raw[i] << 8) | raw[i + 1]])
          : latin1.decode(raw, allowInvalid: true);
      if (text.trim().isEmpty) continue;
      best = text.trim();
      bestRank = rank;
    }
    return best;
  }
}

/// The installed families, scanned once per run.
final systemFontsProvider = FutureProvider<List<String>>((ref) async {
  try {
    return await SystemFonts.families();
  } catch (_) {
    return const [];
  }
});

/// The overlay's script font as it will be drawn: a system font that is no
/// longer installed falls back to the default (the scan only runs when a
/// system font is chosen).
final overlayScriptFontProvider = Provider<ScriptFont>(
  (ref) => _resolved(ref, ref.watch(settingsProvider.select((s) => s.overlayFont)), ScriptFonts.overlayDefault),
);

/// The editor's script font, resolved the same way.
final editorScriptFontProvider = Provider<ScriptFont>(
  (ref) => _resolved(ref, ref.watch(settingsProvider.select((s) => s.editorFont)), ScriptFonts.editorDefault),
);

ScriptFont _resolved(Ref ref, ScriptFont font, ScriptFont fallback) {
  final installed = font.isSystem ? ref.watch(systemFontsProvider).value?.toSet() : null;
  return ScriptFonts.resolve(font, installed: installed, fallback: fallback);
}

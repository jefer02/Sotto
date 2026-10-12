import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive_ce.dart';

import '../../core/utils/ids.dart';
import '../models/script.dart';

/// AI organizing results keyed by a hash of the text (and the model and
/// prompt version), so importing the same file again is instant.
class OrganizeCache {
  OrganizeCache(this._box, {this.maxEntries = 40});

  final Box<Map> _box;
  final int maxEntries;

  /// Bump when the prompt or the rebuild changes what a result means.
  static const version = 1;

  static String keyFor(String text, String model) =>
      sha256.convert(utf8.encode('v$version\u0000$model\u0000$text')).toString();

  /// The cached sections, with fresh ids (they become a new script).
  List<Section>? get(String key) {
    final raw = _box.get(key);
    final list = raw?['sections'];
    if (list is! List) return null;
    try {
      return [
        for (final m in list)
          () {
            final s = Section.fromJson(m as Map);
            return Section(
              id: newId(),
              title: s.title,
              keyPoints: s.keyPoints,
              budgetSeconds: s.budgetSeconds,
              beats: [for (final b in s.beats) Beat(id: newId(), text: b.text, cue: b.cue)],
            );
          }(),
      ];
    } catch (_) {
      return null; // an old or damaged entry: organize again
    }
  }

  Future<void> put(String key, List<Section> sections) async {
    await _box.put(key, {
      'at': DateTime.now().toIso8601String(),
      'sections': [for (final s in sections) s.toJson()],
    });
    if (_box.length > maxEntries) {
      final byAge = _box.keys.toList()..sort((a, b) => '${_box.get(a)?['at']}'.compareTo('${_box.get(b)?['at']}'));
      await _box.deleteAll(byAge.take(_box.length - maxEntries));
    }
  }
}

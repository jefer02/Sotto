import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:sotto/data/storage/write_buffer.dart';

/// Counts the writes that would reach disk.
class _SpyBox extends Fake implements Box<Map> {
  final data = <Object, Map>{};
  final putAlls = <Map<Object, Map>>[];
  final deleteAlls = <List<Object>>[];
  var singleWrites = 0;

  @override
  Map? get(dynamic key, {Map? defaultValue}) => data[key] ?? defaultValue;

  @override
  Future<void> put(dynamic key, Map value) async => singleWrites++;

  @override
  Future<void> delete(dynamic key) async => singleWrites++;

  @override
  Future<void> putAll(Map<dynamic, Map> entries) async {
    putAlls.add(Map.of(entries.cast<Object, Map>()));
    data.addAll(entries.cast<Object, Map>());
  }

  @override
  Future<void> deleteAll(Iterable<dynamic> keys) async {
    deleteAlls.add(keys.cast<Object>().toList());
    for (final k in keys) {
      data.remove(k);
    }
  }
}

void main() {
  test('many writes within 200 ms reach the box as one batch', () {
    fakeAsync((time) {
      final box = _SpyBox();
      final writes = BoxWriteBuffer(box);
      var saved = 0;
      // A fill cycle logging field after field into the session record.
      for (var i = 1; i <= 12; i++) {
        writes.put('session', {'fields': i}).then((_) => saved++);
        time.elapse(const Duration(milliseconds: 10));
      }
      writes.put('other', {'x': 1}).then((_) => saved++);
      expect(box.putAlls, isEmpty, reason: 'nothing written before the window closes');
      expect(writes.get('session'), {'fields': 12}, reason: 'reads see pending writes');

      time.elapse(const Duration(milliseconds: 200));
      expect(box.putAlls, hasLength(1));
      expect(box.putAlls.single, {
        'session': {'fields': 12},
        'other': {'x': 1},
      });
      expect(box.singleWrites, 0);
      expect(saved, 13, reason: 'every caller learns its write is on disk');
    });
  });

  test('writes after a flush start a new batch', () {
    fakeAsync((time) {
      final box = _SpyBox();
      final writes = BoxWriteBuffer(box);
      writes.put('a', {'v': 1});
      time.elapse(const Duration(milliseconds: 250));
      writes.put('a', {'v': 2});
      writes.put('b', {'v': 1});
      time.elapse(const Duration(milliseconds: 250));
      expect(box.putAlls, hasLength(2));
      expect(box.data, {
        'a': {'v': 2},
        'b': {'v': 1},
      });
    });
  });

  test('deletes are batched too, and the last write to a key wins', () {
    fakeAsync((time) {
      final box = _SpyBox()..data['old'] = {'v': 0};
      final writes = BoxWriteBuffer(box);
      writes.put('x', {'v': 1});
      writes.delete('x');
      writes.delete('old');
      writes.put('y', {'v': 1});
      expect(writes.get('old'), isNull);
      time.elapse(const Duration(milliseconds: 200));
      expect(box.putAlls.single, {
        'y': {'v': 1},
      });
      expect(box.deleteAlls.single, unorderedEquals(['x', 'old']));
      expect(box.data, {
        'y': {'v': 1},
      });
    });
  });

  test('flush writes at once (on exit); discard drops what is pending (delete all data)', () {
    fakeAsync((time) {
      final box = _SpyBox();
      final writes = BoxWriteBuffer(box);
      writes.put('a', {'v': 1});
      writes.flush();
      time.flushMicrotasks();
      expect(box.data.keys, ['a']);

      writes.put('b', {'v': 1});
      writes.discard();
      time.elapse(const Duration(seconds: 1));
      expect(box.data.keys, ['a']);
      expect(writes.hasPending, isFalse);
    });
  });
}

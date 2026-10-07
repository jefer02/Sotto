import 'dart:async';

import 'package:hive_ce/hive_ce.dart';

/// Coalesces writes to one box: puts and deletes gather for [window] and
/// go to disk as one `putAll` + one `deleteAll`; a key written twice keeps
/// only its last value. [get] sees pending writes, so callers read their
/// own changes at once — box watchers hear of them on the flush.
///
/// A crash inside the window loses its writes; the app flushes on exit.
class BoxWriteBuffer {
  BoxWriteBuffer(this.box, {this.window = const Duration(milliseconds: 200)});

  final Box<Map> box;
  final Duration window;

  /// Key → the value to write, or null to delete.
  final _pending = <Object, Map?>{};
  Timer? _timer;
  Completer<void>? _flushed;

  bool get hasPending => _pending.isNotEmpty;

  /// Completes once the write is on disk.
  Future<void> put(Object key, Map value) => _queue(key, value);

  Future<void> delete(Object key) => _queue(key, null);

  Map? get(Object key) => _pending.containsKey(key) ? _pending[key] : box.get(key);

  Future<void> _queue(Object key, Map? value) {
    _pending[key] = value;
    _timer ??= Timer(window, () => unawaited(flush()));
    return (_flushed ??= Completer<void>()).future;
  }

  /// Writes what is pending now.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    final done = _flushed;
    _flushed = null;
    if (_pending.isEmpty) {
      done?.complete();
      return;
    }
    final puts = <Object, Map>{};
    final deletes = <Object>[];
    for (final e in _pending.entries) {
      final v = e.value;
      v == null ? deletes.add(e.key) : puts[e.key] = v;
    }
    _pending.clear();
    try {
      if (puts.isNotEmpty) await box.putAll(puts);
      if (deletes.isNotEmpty) await box.deleteAll(deletes);
      done?.complete();
    } catch (e, st) {
      done?.completeError(e, st);
      if (done == null) rethrow;
    }
  }

  /// Drops what is pending ("delete all local data").
  void discard() {
    _timer?.cancel();
    _timer = null;
    _pending.clear();
    final done = _flushed;
    _flushed = null;
    done?.complete();
  }
}

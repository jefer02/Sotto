import 'dart:async';

import 'package:flutter/foundation.dart';

/// Locks Sotto after [timeout] without input to its window — never in the
/// middle of something (a live session or rehearsal, an agent run, a
/// questionnaire, a fill, an organize job): then it locks as soon as that
/// ends, if the time is up by then.
class AutoLock {
  AutoLock({required Duration timeout, required this.onLock, DateTime Function()? now}) : _now = now ?? DateTime.now {
    _timeout = timeout;
    _restart();
  }

  final VoidCallback onLock;
  final DateTime Function() _now;

  late Duration _timeout;
  Timer? _timer;
  bool _busy = false;
  bool _disposed = false;
  late DateTime _lastInput = _now();

  /// Zero turns it off.
  Duration get timeout => _timeout;
  set timeout(Duration value) {
    if (value == _timeout) return;
    _timeout = value;
    _restart();
  }

  bool get _due => _timeout > Duration.zero && _now().difference(_lastInput) >= _timeout;

  /// A key, click, scroll or pointer move in the window.
  void activity() {
    _lastInput = _now();
    _restart();
  }

  /// Something that must not be interrupted started or ended.
  set busy(bool value) {
    if (value == _busy) return;
    _busy = value;
    if (!value) _check();
  }

  void _restart() {
    _timer?.cancel();
    _timer = null;
    if (_disposed || _timeout <= Duration.zero) return;
    final left = _timeout - _now().difference(_lastInput);
    _timer = Timer(left.isNegative ? Duration.zero : left, _check);
  }

  void _check() {
    if (_disposed || _busy || !_due) return;
    dispose();
    onLock();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}

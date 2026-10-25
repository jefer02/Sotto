import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../../domain/following/script_aligner.dart';
import 'reading_view.dart' show splitWords;

/// Where the reading is, in characters of the script — continuous, so the
/// column scrolls and the highlight sweeps letter by letter instead of
/// jumping a burst of words at once.
///
/// A streaming recognizer confirms words a few at a time, about every
/// 1.3 s. The cursor walks through them at the presenter's measured pace
/// ([moveTo]'s rate), a little faster when it has fallen behind, and it
/// never passes the end of the last word confirmed as said: the highlight is
/// never ahead of the voice. Far moves (a relock, a manual jump) and moves
/// back are placed at once; the scroll glides those on its own spring.
///
/// One ticker, running only while there is ground to cover. Per frame: O(1).
class ReadingCursor extends ValueNotifier<double> {
  ReadingCursor(TickerProvider vsync) : super(0) {
    _ticker = vsync.createTicker(_tick);
  }

  late final Ticker _ticker;
  double _target = 0;
  double _rate = defaultRate;

  /// Characters a second towards [_target]: the pace, or faster if that
  /// wouldn't arrive within [catchUp].
  double _speed = defaultRate;
  Duration _last = Duration.zero;

  /// Characters a second when nothing is measured yet: about 150 words a
  /// minute of six characters (spaces included).
  static const defaultRate = 15.0;

  /// A backlog is caught up within this long, whatever the pace.
  static const catchUp = Duration(milliseconds: 900);

  /// Further than this (or backwards) is a jump, not reading.
  static const farChars = 160.0;

  double get target => _target;
  bool get moving => _ticker.isActive;

  /// Places the cursor at once.
  void jumpTo(double chars) {
    _ticker.stop();
    _target = chars;
    value = chars;
  }

  /// Heads for [chars] at [rate] characters a second.
  void moveTo(double chars, {double? rate}) {
    _rate = (rate ?? defaultRate).clamp(4.0, 40.0);
    if (chars < value - 0.5 || chars - value > farChars) {
      jumpTo(chars);
      return;
    }
    _target = math.max(chars, value);
    if (_target - value < 0.01) return;
    _speed = math.max(_rate, (_target - value) / (catchUp.inMicroseconds / 1e6));
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    // A stalled frame must not become one long step.
    final dt = math.min((elapsed - _last).inMicroseconds / 1e6, 1 / 20);
    _last = elapsed;
    if (dt <= 0) return;
    final backlog = _target - value;
    final step = math.min(backlog, _speed * dt);
    if (backlog - step < 0.01) {
      value = _target;
      _ticker.stop();
    } else {
      value += step;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

/// Character offsets of the script as the reading view lays it out: each
/// beat is one paragraph, a cue chip takes one placeholder character, and
/// every word but the last is followed by one space.
class ScriptChars {
  ScriptChars(FlatScript flat) {
    var c = 0;
    for (final b in flat.beats) {
      final words = splitWords(b.beat.text);
      final cue = b.beat.cue == null ? 0 : 1;
      beatStart.add(c);
      final starts = <int>[];
      var local = cue;
      for (final w in words) {
        starts.add(local);
        local += w.text.length + 1;
      }
      wordStart.add(starts);
      wordLength.add([for (final w in words) w.text.length]);
      cueLength.add(cue);
      c += math.max(cue, local);
    }
    total = c;
  }

  /// Global offset of each beat's first character.
  final beatStart = <int>[];

  /// Each word's first character within its beat's paragraph.
  final wordStart = <List<int>>[];
  final wordLength = <List<int>>[];
  final cueLength = <int>[];
  late final int total;

  /// The global character just past the last of [said] words of [beat] —
  /// the beat's start when none is said yet.
  double saidEnd(int beat, int said) {
    if (beat < 0 || beat >= beatStart.length) return 0;
    final starts = wordStart[beat];
    if (said <= 0 || starts.isEmpty) return (beatStart[beat] + cueLength[beat]).toDouble();
    final w = math.min(said, starts.length) - 1;
    return (beatStart[beat] + starts[w] + wordLength[beat][w]).toDouble();
  }

  /// The beat holding global character [c].
  int beatOf(double c) {
    var lo = 0, hi = beatStart.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (beatStart[mid] <= c) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// The word of [beat] holding local character [local], or −1 before the
  /// first word.
  int wordAt(int beat, double local) {
    final starts = wordStart[beat];
    var w = -1;
    for (var k = 0; k < starts.length && starts[k] <= local; k++) {
      w = k;
    }
    return w;
  }
}

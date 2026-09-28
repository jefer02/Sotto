import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:record/record.dart';

import '../../l10n/l10n.dart';

/// 16 kHz mono PCM from the chosen microphone, as float samples in [-1, 1].
/// Presenter audio never leaves the device.
class AudioCapture {
  static const sampleRate = 16000;

  final _recorder = AudioRecorder();
  final _samples = StreamController<Float32List>.broadcast();
  final _level = StreamController<double>.broadcast();
  StreamSubscription<Uint8List>? _sub;
  bool _running = false;

  Stream<Float32List> get samples => _samples.stream;

  /// Smoothed input level, 0..1 (≈ −60…0 dBFS).
  Stream<double> get level => _level.stream;

  bool get isRunning => _running;

  Future<List<InputDevice>> devices() => _recorder.listInputDevices();

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<void> start({String? deviceId, bool noiseSuppression = true}) async {
    if (_running) return;
    if (!await _recorder.hasPermission()) {
      throw StateError(L10n.current.micPermission);
    }
    InputDevice? device;
    if (deviceId != null) {
      final all = await _recorder.listInputDevices();
      for (final d in all) {
        if (d.id == deviceId) device = d;
      }
    }
    final stream = await _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        device: device,
        noiseSuppress: noiseSuppression,
        echoCancel: noiseSuppression,
        autoGain: true,
      ),
    );
    _running = true;
    var smoothed = 0.0;
    var carry = <int>[];
    _sub = stream.listen((bytes) {
      // PCM16 little-endian; a chunk can end on an odd byte.
      final data = carry.isEmpty ? bytes : Uint8List.fromList([...carry, ...bytes]);
      final whole = data.length & ~1;
      carry = data.length == whole ? <int>[] : [data[data.length - 1]];
      final view = ByteData.sublistView(data, 0, whole);
      final out = Float32List(whole ~/ 2);
      var sum = 0.0;
      for (var i = 0; i < out.length; i++) {
        final v = view.getInt16(i * 2, Endian.little) / 32768.0;
        out[i] = v;
        sum += v * v;
      }
      if (out.isEmpty) return;
      _samples.add(out);
      final rms = math.sqrt(sum / out.length);
      final db = rms <= 0 ? -60.0 : (20 * math.log(rms) / math.ln10).clamp(-60.0, 0.0);
      final lvl = (db + 60) / 60;
      smoothed = lvl > smoothed ? lvl : smoothed * 0.85 + lvl * 0.15;
      _level.add(smoothed);
    });
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _sub?.cancel();
    _sub = null;
    await _recorder.stop();
    _level.add(0);
  }

  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
    await _samples.close();
    await _level.close();
  }
}

/// Energy-based voice activity with an adaptive noise floor. Used for the
/// question silence ring and for segmenting audio for Whisper. Cheap enough
/// to run on every 30 ms frame.
class EnergyVad {
  EnergyVad({this.frameSamples = 480});

  final int frameSamples;
  double _floor = 0.004;
  double _speechMs = 0;
  double _silenceMs = 0;
  bool _speaking = false;
  final _pending = <double>[];

  bool get speaking => _speaking;

  /// Milliseconds of continuous silence since speech last stopped.
  double get silenceMs => _silenceMs;

  double get speechMs => _speechMs;

  void reset() {
    _speechMs = 0;
    _silenceMs = 0;
    _speaking = false;
    _pending.clear();
  }

  void accept(Float32List samples) {
    _pending.addAll(samples);
    const frameMs = 30.0;
    while (_pending.length >= frameSamples) {
      var sum = 0.0;
      for (var i = 0; i < frameSamples; i++) {
        sum += _pending[i] * _pending[i];
      }
      _pending.removeRange(0, frameSamples);
      final rms = math.sqrt(sum / frameSamples);

      final voiced = rms > math.max(_floor * 3.2, 0.012);
      // The floor follows quiet frames quickly and loud frames very slowly.
      _floor = voiced ? _floor * 0.999 + rms * 0.001 : _floor * 0.95 + rms * 0.05;
      _floor = _floor.clamp(0.001, 0.05);

      if (voiced) {
        _speechMs += frameMs;
        if (_speechMs > 90) {
          _speaking = true;
          _silenceMs = 0;
        }
      } else {
        _silenceMs += frameMs;
        if (_silenceMs > 240) _speechMs = 0;
        if (_silenceMs > 300) _speaking = false;
      }
    }
  }
}

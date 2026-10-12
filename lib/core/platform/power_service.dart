import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the machine is saving battery — Windows battery saver
/// (GetSystemPowerStatus), macOS Low Power Mode or a low battery
/// (IOPSCopyPowerSourcesInfo). Background polling slows down then.
class PowerService {
  static const _channel = MethodChannel('app.sotto/power');

  /// False when unknown (no battery, no plugin).
  Future<bool> saving() async {
    try {
      return await _channel.invokeMethod<bool>('saver') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

final powerServiceProvider = Provider<PowerService>((ref) => PowerService());

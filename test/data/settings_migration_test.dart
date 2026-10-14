import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/data/models/settings.dart';

void main() {
  test('settings saved with the cloud speech engine still load', () {
    final s = AppSettings.fromJson({
      'engine': 'cloud',
      'cloudSttProvider': 'openaiCompatible',
      'cloudSttModel': 'whisper-1',
      'cloudSttBaseUrl': 'http://localhost:8000/v1',
      'language': 'es-ES',
      'wordsPerMinute': 160,
    });
    expect(s.language, 'es-ES');
    expect(s.wordsPerMinute, 160);
    final json = s.toJson();
    expect(json.keys.where((k) => k.startsWith('cloudStt') || k == 'engine'), isEmpty);
  });

  group('form filling is off until the presenter turns it on', () {
    test('a new install neither watches for forms nor fills without asking', () {
      const s = AppSettings();
      expect(s.formsAutoFill, isFalse);
      expect(s.formsMode, FormFillMode.showFirst);
    });

    test('"Reset all settings" puts both back off', () {
      final reset = AppSettings.fromJson(const AppSettings(onboarded: true).toJson());
      expect(reset.formsAutoFill, isFalse);
      expect(reset.formsMode, FormFillMode.showFirst);
    });

    test('settings saved before the field existed load with it off', () {
      final s = AppSettings.fromJson({'language': 'es-ES'});
      expect(s.formsAutoFill, isFalse);
      expect(s.formsMode, FormFillMode.showFirst);
    });

    test('a value the presenter saved is kept', () {
      final s = AppSettings.fromJson({'formsAutoFill': true, 'formsMode': 'fillAutomatically'});
      expect(s.formsAutoFill, isTrue);
      expect(s.formsMode, FormFillMode.fillAutomatically);
    });
  });
}

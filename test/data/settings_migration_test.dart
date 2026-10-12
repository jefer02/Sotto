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
}

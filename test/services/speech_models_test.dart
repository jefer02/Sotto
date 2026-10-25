import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sotto/l10n/l10n.dart';
import 'package:sotto/services/speech/model_manager.dart';
import 'package:sotto/services/speech/speech_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory support;

  setUp(() {
    L10n.current = lookupAppLocalizations(const Locale('en'));
    support = Directory.systemTemp.createTempSync('sotto_models');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => support.path,
    );
  });
  tearDown(() => support.deleteSync(recursive: true));

  group('catalog', () {
    test('every model pins its archive size and SHA-256', () {
      for (final m in ModelCatalog.all) {
        expect(m.sha256, matches(RegExp(r'^[0-9a-f]{64}$')), reason: m.id);
        expect(m.bytes, greaterThan(10 * 1024 * 1024), reason: m.id);
        expect(m.url, startsWith('https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/'));
      }
      expect({for (final m in ModelCatalog.all) m.sha256}.length, ModelCatalog.all.length);
    });

    test('Spanish, French and German follow with a streaming model; the CC BY-SA ones say so', () {
      expect(ModelCatalog.streamingFor('es-419'), [ModelCatalog.streamingEs]);
      expect(ModelCatalog.streamingFor('es-ES'), [ModelCatalog.streamingEs]);
      expect(ModelCatalog.streamingFor('fr-FR'), [ModelCatalog.streamingFr]);
      expect(ModelCatalog.streamingFor('de-DE'), [ModelCatalog.streamingDe]);
      expect(ModelCatalog.streamingFor('en-US').first, ModelCatalog.streamingEn);
      expect(ModelCatalog.streamingFor('pt-BR'), isEmpty);
      for (final m in [ModelCatalog.streamingEs, ModelCatalog.streamingFr, ModelCatalog.streamingDe]) {
        expect(m.attribution, contains('CC BY-SA'), reason: m.id);
      }
    });
  });

  group('download', () {
    // A tiny stand-in for a model archive.
    final bytes = Uint8List.fromList(List.generate(4096, (i) => i % 251));
    SpeechModel modelFor(Uint8List archive, {String? sha}) => SpeechModel(
      id: 'test-model',
      role: ModelRole.streaming,
      bytes: archive.length,
      sha256: sha ?? sha256.convert(archive).toString(),
      languages: const ['es'],
    );
    http.Client serving(Uint8List body) => MockClient((_) async => http.Response.bytes(body, 200));

    test('only the exact size and digest verify', () {
      final m = modelFor(bytes);
      expect(ModelManager.verified(m, bytes.length, sha256.convert(bytes)), isTrue);
      expect(ModelManager.verified(m, bytes.length - 1, sha256.convert(bytes)), isFalse);
      final other = Uint8List.fromList([...bytes]..[100] ^= 1);
      expect(ModelManager.verified(m, other.length, sha256.convert(other)), isFalse);
    });

    test('an archive that does not match its checksum is discarded before extracting', () async {
      final tampered = Uint8List.fromList([...bytes]..[7] ^= 0xFF);
      final model = modelFor(bytes);
      final statuses = await ModelManager().download(model, client: serving(tampered)).toList();
      final last = statuses.last;
      expect(last, isA<ModelFailed>());
      expect((last as ModelFailed).error, L10n.current.modelChecksumFailed);
      expect(statuses.whereType<ModelDownloading>().any((s) => s.extracting), isFalse);
      // Nothing left behind: no partial archive, no model folder.
      final left = Directory('${support.path}/models').listSync().map((e) => e.path).toList();
      expect(left, isEmpty);
    });

    test('a truncated download fails the same way', () async {
      final model = modelFor(bytes);
      final last = await ModelManager().download(model, client: serving(bytes.sublist(0, 1000))).last;
      expect(last, isA<ModelFailed>());
    });
  });

  group('which model follows', () {
    const es = 'es-419';
    final kroko = ModelCatalog.streamingEs.id, base = ModelCatalog.whisperBase.id, turbo = ModelCatalog.whisperTurbo.id;

    test('Spanish follows with the streaming model when it is installed', () {
      final plan = planFollowing(es, {kroko, base, turbo});
      expect(plan.why, FollowingWhy.streaming);
      expect(plan.model, ModelCatalog.streamingEs);
    });

    test('without it, Whisper Base follows and the streaming model is recommended', () {
      final plan = planFollowing(es, {base, turbo});
      expect(plan.why, FollowingWhy.whisperUntilStreamingInstalled);
      expect(plan.model, ModelCatalog.whisperBase, reason: 'the fastest Whisper re-reads the open phrase');
      expect(plan.recommended, ModelCatalog.streamingEs);
    });

    test('a language with no streaming model follows with Whisper alone', () {
      final plan = planFollowing('pt-BR', {turbo});
      expect(plan.why, FollowingWhy.whisperOnly);
      expect(plan.model, ModelCatalog.whisperTurbo);
      expect(plan.recommended, isNull);
    });

    test('nothing installed: nothing follows, and the right download is named', () {
      final plan = planFollowing(es, {});
      expect(plan.why, FollowingWhy.none);
      expect(plan.recommended, ModelCatalog.streamingEs);
    });

    test('English prefers the full streaming model over the light one', () {
      final plan = planFollowing('en-US', {ModelCatalog.streamingEnLight.id, ModelCatalog.streamingEn.id});
      expect(plan.model, ModelCatalog.streamingEn);
    });
  });
}

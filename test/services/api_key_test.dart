import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/data/storage/secret_store.dart';
import 'package:sotto/l10n/l10n.dart';
import 'package:sotto/services/ai/llm_client.dart';

/// The keychain, in memory.
final _keychain = <String, String>{};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  L10n.current = lookupAppLocalizations(const Locale('en'));

  setUp(() {
    _keychain.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        final args = (call.arguments as Map?) ?? const {};
        final key = args['key'] as String?;
        switch (call.method) {
          case 'read':
            return _keychain[key];
          case 'write':
            _keychain[key!] = args['value'] as String;
            return null;
          case 'delete':
            _keychain.remove(key);
            return null;
          case 'readAll':
            return Map<String, String>.of(_keychain);
        }
        return null;
      },
    );
  });

  group('which key DeepSeek calls use', () {
    test('no saved key and no built-in key: no client, so features ask for a key', () async {
      final secrets = SecretStore();
      expect(await resolveDeepSeekCredential(secrets, embedded: ''), isNull);
      expect(await LlmClient.forSettings(const AppSettings(), secrets, embedded: ''), isNull);
    });

    test('the built-in key is the fallback', () async {
      final c = await resolveDeepSeekCredential(SecretStore(), embedded: 'sk-built-in');
      expect(c?.key, 'sk-built-in');
      expect(c?.source, KeySource.builtIn);
    });

    test("the user's own key overrides the built-in one", () async {
      final secrets = SecretStore();
      await secrets.write(SecretKey.deepseekApiKey, '  sk-mine  ');
      final c = await resolveDeepSeekCredential(secrets, embedded: 'sk-built-in');
      expect(c?.key, 'sk-mine');
      expect(c?.source, KeySource.user);

      final client = await LlmClient.forSettings(const AppSettings(), secrets, embedded: 'sk-built-in');
      final deepSeek = client! as DeepSeekClient;
      expect(deepSeek.apiKey, 'sk-mine');
      expect(deepSeek.builtInKey, isFalse);
    });

    test('clearing the own key falls back to the built-in one', () async {
      final secrets = SecretStore();
      await secrets.write(SecretKey.deepseekApiKey, 'sk-mine');
      await secrets.write(SecretKey.deepseekApiKey, '');
      expect((await resolveDeepSeekCredential(secrets, embedded: 'sk-built-in'))?.source, KeySource.builtIn);
    });
  });

  group('a key DeepSeek turns down', () {
    DeepSeekClient client({required bool builtIn, required int status}) => DeepSeekClient(
      apiKey: 'sk-x',
      model: 'deepseek-flash',
      builtInKey: builtIn,
      httpClient: MockClient.streaming(
        (req, body) async =>
            http.StreamedResponse(Stream.value('{"error":{"message":"Authentication Fails"}}'.codeUnits), status),
      ),
    );

    Future<LlmException> failure(DeepSeekClient c) async {
      try {
        await c.complete(system: 's', user: 'u');
      } on LlmException catch (e) {
        return e;
      }
      fail('expected an LlmException');
    }

    test('an invalid own key says to check it', () async {
      final e = await failure(client(builtIn: false, status: 401));
      expect(e.message, L10n.current.llmBadKey('DeepSeek'));
    });

    test('an invalid or empty built-in key asks for an own key instead', () async {
      for (final status in [401, 402, 403]) {
        final e = await failure(client(builtIn: true, status: status));
        expect(e.message, L10n.current.llmBuiltInKeyFailed, reason: '$status');
        expect(e.statusCode, status);
      }
    });

    test('an own key out of balance says to top up', () async {
      final e = await failure(client(builtIn: false, status: 402));
      expect(e.message, L10n.current.llmNoBalance);
    });

    test('the message is localized', () async {
      L10n.current = lookupAppLocalizations(const Locale('es'));
      addTearDown(() => L10n.current = lookupAppLocalizations(const Locale('en')));
      final e = await failure(client(builtIn: true, status: 401));
      expect(e.message, contains('Ajustes → Integraciones'));
    });
  });
}

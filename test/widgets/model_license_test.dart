import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/core/design/theme.dart';
import 'package:sotto/core/design/tokens.dart';
import 'package:sotto/features/settings/pages/voice_page.dart';
import 'package:sotto/l10n/l10n.dart';
import 'package:sotto/services/speech/model_manager.dart';

class _Models extends ModelStatusNotifier {
  final downloads = <String>[];

  @override
  Map<String, ModelStatus> build() => {for (final m in ModelCatalog.all) m.id: const ModelMissing()};

  @override
  void download(SpeechModel model) => downloads.add(model.id);
}

void main() {
  late _Models models;

  Future<void> pump(WidgetTester tester, SpeechModel model) async {
    L10n.current = lookupAppLocalizations(const Locale('en'));
    models = _Models();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [modelStatusProvider.overrideWith(() => models)],
        child: MaterialApp(
          theme: buildSottoTheme(SottoPalette.stage),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(child: ModelDownloadControl(model: model)),
          ),
        ),
      ),
    );
  }

  testWidgets('the Kroko license and attribution show before the download, which waits for consent', (tester) async {
    await pump(tester, ModelCatalog.streamingEs);
    await tester.tap(find.text(L10n.current.download));
    await tester.pumpAndSettle();
    expect(find.text(L10n.current.modelLicenseTitle(ModelCatalog.streamingEs.name)), findsOneWidget);
    expect(find.text(ModelCatalog.streamingEs.attribution!), findsOneWidget);
    expect(find.textContaining('huggingface.co/Banafo/Kroko-ASR'), findsWidgets);
    expect(models.downloads, isEmpty, reason: 'nothing downloads before consent');

    await tester.tap(find.text(L10n.current.cancel));
    await tester.pumpAndSettle();
    expect(models.downloads, isEmpty);

    await tester.tap(find.text(L10n.current.download));
    await tester.pumpAndSettle();
    await tester.tap(find.text(L10n.current.modelLicenseAccept));
    await tester.pumpAndSettle();
    expect(models.downloads, [ModelCatalog.streamingEs.id]);
  });

  testWidgets('models without an attribution download straight away', (tester) async {
    await pump(tester, ModelCatalog.whisperBase);
    expect(find.text(L10n.current.modelLicenseView), findsNothing);
    await tester.tap(find.text(L10n.current.download));
    await tester.pumpAndSettle();
    expect(models.downloads, [ModelCatalog.whisperBase.id]);
  });
}

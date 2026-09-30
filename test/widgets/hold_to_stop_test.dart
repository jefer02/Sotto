import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/core/design/theme.dart';
import 'package:sotto/core/design/tokens.dart';
import 'package:sotto/features/forms/autofill_view.dart';
import 'package:sotto/l10n/app_localizations.dart';

void main() {
  testWidgets('Stop turns auto-fill off only after a one-second hold', (tester) async {
    var stopped = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildSottoTheme(SottoPalette.stage),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Material(
          child: Center(child: HoldToStopButton(onConfirmed: () => stopped++)),
        ),
      ),
    );
    final button = find.byType(HoldToStopButton);

    // A tap does nothing.
    await tester.tap(button);
    await tester.pump(const Duration(milliseconds: 50));
    expect(stopped, 0);

    // Half a second, let go: nothing — the countdown shows meanwhile.
    var g = await tester.startGesture(tester.getCenter(button));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.textContaining(RegExp(r'^\d\.\d s$')), findsOneWidget);
    await g.up();
    await tester.pump();
    expect(stopped, 0);

    // A full second: stopped, once.
    g = await tester.startGesture(tester.getCenter(button));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await g.up();
    await tester.pump();
    expect(stopped, 1);
  });
}

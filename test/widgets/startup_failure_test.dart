// When the local data can't be opened at startup, the window explains why
// and offers Retry and Quit instead of staying blank.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/app/startup_failure.dart';

void main() {
  testWidgets('explains the failure, shows the error and retries on demand', (tester) async {
    tester.platformDispatcher.localeTestValue = const Locale('en', 'US');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    var retries = 0;
    await tester.pumpWidget(
      StartupFailure(error: const FileSystemLockProbe('settings.lock is locked'), onRetry: () => retries++),
    );
    await tester.pumpAndSettle();

    expect(find.text("Sotto couldn't open your data"), findsOneWidget);
    expect(find.textContaining('settings.lock is locked'), findsOneWidget);
    expect(find.text('Quit'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(retries, 1);
  });

  testWidgets('speaks the device language', (tester) async {
    tester.platformDispatcher.localeTestValue = const Locale('es', 'MX');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    await tester.pumpWidget(StartupFailure(error: 'x', onRetry: () {}));
    await tester.pumpAndSettle();

    expect(find.text('Sotto no pudo abrir tus datos'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.text('Salir'), findsOneWidget);
  });
}

/// Stands in for the FileSystemException Hive throws on a locked box.
class FileSystemLockProbe {
  const FileSystemLockProbe(this.message);
  final String message;

  @override
  String toString() => message;
}

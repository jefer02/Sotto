// Renders the agent panel mid-task to build/agent_view.png for review.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/core/design/theme.dart';
import 'package:sotto/core/design/tokens.dart';
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/data/repositories.dart';
import 'package:sotto/domain/agent/agent_action.dart';
import 'package:sotto/domain/agent/agent_loop.dart';
import 'package:sotto/domain/agent/safety.dart';
import 'package:sotto/features/agent/agent_controller.dart';
import 'package:sotto/features/agent/agent_view.dart';
import 'package:sotto/l10n/app_localizations.dart';

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings(agentEnabled: true);
}

class _Agent extends AgentController {
  @override
  AgentState build() => AgentState(
    phase: AgentPhase.confirming,
    task: 'Fill the registration form with my details from the prep docs',
    step: 4,
    pending: const PendingAction(
      action: ClickAction(812, 440, target: 'Submit'),
      step: 4,
      point: Offset(1249, 677),
      sensitive: true,
      reason: SafetyReason.irreversible,
    ),
    log: [
      AgentLogEntry(at: DateTime(2026), action: 'Click “Full name” at 420,212', outcome: AgentOutcome.done),
      AgentLogEntry(at: DateTime(2026), action: 'Type “Ana García” into Full name', outcome: AgentOutcome.done),
      AgentLogEntry(
        at: DateTime(2026),
        action: 'Type “••••” into Password',
        outcome: AgentOutcome.blocked,
        note: 'the focused field is a password field',
      ),
    ],
  );
}

Future<void> _loadFonts() async {
  for (final (family, file) in const [
    ('Geist', 'assets/fonts/Geist-Variable.ttf'),
    ('GeistMono', 'assets/fonts/GeistMono-Variable.ttf'),
  ]) {
    final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(File(file).readAsBytesSync())));
    await loader.load();
  }
}

void main() {
  testWidgets('agent panel waiting for a sensitive confirmation', (tester) async {
    await tester.runAsync(_loadFonts);
    final key = GlobalKey();
    tester.view.physicalSize = const Size(560, 360);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsProvider.overrideWith(_Settings.new), agentControllerProvider.overrideWith(_Agent.new)],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildSottoTheme(SottoPalette.stage),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Material(
            color: const Color(0xFF15181D),
            child: RepaintBoundary(
              key: key,
              child: Container(
                color: Color.alphaBlend(OverlayPalette.dark.ground, const Color(0xFF15181D)),
                child: const AgentView(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final png = await (await boundary.toImage()).toByteData(format: ui.ImageByteFormat.png);
      File('build/agent_view.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(png!.buffer.asUint8List());
    });
    expect(find.text('AGENT IN CONTROL'), findsOneWidget);
    expect(find.textContaining('Submit'), findsWidgets);
    expect(find.text('Run'), findsOneWidget);
    expect(find.text('Stop task'), findsOneWidget);
  });
}

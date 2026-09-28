// Renders the live answer card with the real fonts to a PNG for visual
// review against the "Live — answer" board: `flutter test test/widgets`.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/core/design/theme.dart';
import 'package:sotto/core/design/tokens.dart';
import 'package:sotto/data/models/qa_entry.dart';
import 'package:sotto/data/models/script.dart';
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/data/repositories.dart';
import 'package:sotto/domain/following/script_aligner.dart';
import 'package:sotto/features/live/live_state.dart';
import 'package:sotto/features/live/overlay/meta_strip.dart';
import 'package:sotto/features/live/overlay/qa_views.dart';
import 'package:sotto/l10n/app_localizations.dart';
import 'package:sotto/services/ai/answer_service.dart';

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();
}

Future<void> _loadFonts() async {
  for (final (family, file) in const [
    ('Geist', 'assets/fonts/Geist-Variable.ttf'),
    ('GeistMono', 'assets/fonts/GeistMono-Variable.ttf'),
    ('AtkinsonHyperlegibleNext', 'assets/fonts/AtkinsonHyperlegibleNext-Variable.ttf'),
  ]) {
    final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(File(file).readAsBytesSync())));
    await loader.load();
  }
}

void main() {
  for (final textOnly in [false, true]) {
    testWidgets(textOnly ? 'answer card, text only' : 'answer card', (tester) async {
      await tester.runAsync(_loadFonts);
      final now = DateTime(2026);
      final script = Script(
        id: 's',
        title: 'Q3',
        createdAt: now,
        updatedAt: now,
        sections: [
          Section(id: 'a', title: 'Revenue & margin', beats: [Beat.create('Revenue landed at 48.2 million.')]),
        ],
      );
      const draft = AnswerDraft(
        sources: [
          SourceRef(kind: SourceKind.section, label: 'Revenue & margin', code: '§3'),
          SourceRef(kind: SourceKind.section, label: 'H2 priorities', code: '§5'),
          SourceRef(kind: SourceKind.prep, label: 'Carrier contracts.pdf', code: 'Prep'),
        ],
        headline: 'We’ve planned for it — margin holds at 31–32% even if freight stays high through Q1.',
        points: [
          AnswerPoint(
            lead: '60% of volume',
            rest: 'is locked at Q3 rates until June, through the August carrier contracts.',
          ),
          AnswerPoint(
            lead: 'About 0.8 pts of margin',
            rest: 'is the remaining exposure, and it is already in the H2 plan.',
          ),
          AnswerPoint(lead: 'Regional consolidation', rest: '(§5) is the next lever if costs keep climbing.'),
        ],
        complete: true,
      );
      final state = LiveState(
        phase: LivePhase.answer,
        script: script,
        flat: FlatScript.from(script),
        questionText: 'How are you thinking about margin pressure if freight stays elevated through Q1?',
        draft: draft,
        draftMillis: 1400,
        currentQa: QaEntry(id: 'q', scriptId: 's', askedAt: now, question: 'q', headline: draft.headline),
        elapsed: const Duration(minutes: 7, seconds: 42),
      );

      final key = GlobalKey();
      tester.view.physicalSize = const Size(560, 424);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [settingsProvider.overrideWith(_Settings.new)],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildSottoTheme(
              SottoPalette.stage,
              overlay: textOnly
                  ? OverlayPalette.textOnly(
                      ink: const Color(0xFFFFFFFF),
                      outline: const Color(0xFF000000),
                      outlineWidth: 2,
                      shadowStrength: 0.6,
                    )
                  : null,
            ),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Material(
              // Text only is checked on the worst case: a white slide.
              color: textOnly ? const Color(0xFFF4F4F2) : const Color(0xFF15181D),
              child: RepaintBoundary(
                key: key,
                child: Builder(
                  builder: (context) {
                    final o = context.overlayPalette;
                    return Container(
                      decoration: BoxDecoration(
                        color: textOnly ? null : Color.alphaBlend(o.ground, const Color(0xFF15181D)),
                        borderRadius: Radii.rXl,
                      ),
                      child: DefaultTextStyle.merge(
                        style: TextStyle(shadows: o.textShadows(1, true)),
                        child: Column(
                          children: [
                            MetaStrip(state: state),
                            Expanded(child: AnswerView(state: state)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      // Let the staggered points finish their entrance.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.runAsync(() async {
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final out = File(textOnly ? 'build/answer_card_text_only.png' : 'build/answer_card.png')
          ..createSync(recursive: true);
        out.writeAsBytesSync(png!.buffer.asUint8List());
      });
      expect(find.text('Dismiss'), findsOneWidget);
      expect(find.textContaining('drafted in 1.4 s'), findsOneWidget);
    });
  }
}

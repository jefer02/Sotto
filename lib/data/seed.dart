import '../core/utils/ids.dart';
import '../l10n/l10n.dart';
import 'models/script.dart';
import 'repositories.dart';

/// First-launch content, so the library isn't empty and the overlay can be
/// tried immediately. Taken from the design's running example, in the
/// interface language.
Future<void> seedIfEmpty(ScriptRepository repo) async {
  if (!repo.isEmpty) return;

  final spanish = L10n.current.localeName == 'es';
  String t(String en, String es) => spanish ? es : en;

  final board = Collection(id: newId(), name: t('Board & investors', 'Consejo e inversores'));
  final webinars = Collection(id: newId(), name: 'Webinars');
  final talks = Collection(id: newId(), name: t('Conference talks', 'Conferencias'));
  for (final c in [
    board,
    webinars,
    talks,
    Collection(id: newId(), name: t('Sales demos', 'Demos de ventas')),
    Collection(id: newId(), name: t('Training', 'Formación')),
  ]) {
    await repo.saveCollection(c);
  }

  Section s(String title, int budget, List<String> beats, {List<String> keyPoints = const []}) => Section(
    id: newId(),
    title: title,
    budgetSeconds: budget,
    keyPoints: keyPoints,
    beats: [
      for (final b in beats)
        () {
          final (cue, text) = Cue.parseLeading(b);
          return Beat.create(text.trim(), cue: cue);
        }(),
    ],
  );

  final now = DateTime.now();
  final q3 = Script(
    id: newId(),
    title: t('Q3 Board Review', 'Revisión del tercer trimestre'),
    collectionId: board.id,
    status: ScriptStatus.structured,
    createdAt: now.subtract(const Duration(days: 6)),
    updatedAt: now.subtract(const Duration(hours: 2)),
    hintWords: spanish
        ? const ['Kestrel', '48,2 millones', '31,4 %', 'Serie C', 'primer trimestre']
        : const ['Kestrel', '\$48.2 million', '31.4%', 'Series C', 'Q1'],
    sections: [
      s(t('Opening', 'Apertura'), 90, [
        t('Thank you all for making the time today.', 'Gracias a todos por dedicarnos este tiempo hoy.'),
        t(
          "I'll keep this tight: where we landed, what we learned, and what we need from you.",
          'Seré breve: dónde terminamos, qué aprendimos y qué necesitamos de ustedes.',
        ),
        t("We'll leave fifteen minutes at the end for questions.", 'Dejaremos quince minutos al final para preguntas.'),
      ]),
      s(t('Q3 at a glance', 'El trimestre en resumen'), 180, [
        t(
          '[SLIDE 3] This was the quarter the plan started paying off.',
          '[DIAPOSITIVA 3] Este fue el trimestre en que el plan empezó a dar frutos.',
        ),
        t(
          'We closed **eleven new logos**, including our first two enterprise logistics accounts.',
          'Cerramos **once clientes nuevos**, entre ellos nuestras dos primeras cuentas corporativas de logística.',
        ),
        t(
          'Net retention came in at 118%, up from 111% last quarter.',
          'La retención neta llegó al 118 %, frente al 111 % del trimestre anterior.',
        ),
      ]),
      s(
        t('Revenue & margin', 'Ingresos y margen'),
        240,
        [
          t("Let's start with the number everyone's been asking about.", 'Empecemos por la cifra que todos esperan.'),
          t(
            'Revenue landed at **\$48.2 million** — up 12% on Q2.',
            'Los ingresos llegaron a **48,2 millones de dólares** — un 12 % más que el segundo trimestre.',
          ),
          t(
            "It's our strongest quarter since we began reporting to this board.",
            'Es nuestro mejor trimestre desde que empezamos a informar a este consejo.',
          ),
          t(
            '[SLIDE 7] Gross margin held at **31.4%**, even with freight up 9%.',
            '[DIAPOSITIVA 7] El margen bruto se mantuvo en **31,4 %**, aun con el flete un 9 % más caro.',
          ),
          t(
            'Two things drove that: renewals we pulled forward from Q4, and the carrier contracts we renegotiated in August.',
            'Dos cosas lo impulsaron: las renovaciones que adelantamos del cuarto trimestre y los contratos de transporte que renegociamos en agosto.',
          ),
          t(
            'Both were deliberate, and both will show up again next quarter.',
            'Ambas fueron deliberadas, y ambas volverán a notarse el próximo trimestre.',
          ),
          t(
            '[PAUSE] So what does that mean for the next two quarters?',
            '[PAUSA] ¿Y qué significa eso para los próximos dos trimestres?',
          ),
        ],
        keyPoints: [
          t('\$48.2M revenue, up 12% on Q2', 'Ingresos de 48,2 millones, un 12 % más que el segundo trimestre'),
          t('Gross margin 31.4% despite freight +9%', 'Margen bruto del 31,4 % pese al flete +9 %'),
          t(
            'Two drivers: renewals pulled forward, carrier contracts',
            'Dos motores: renovaciones adelantadas, contratos de transporte',
          ),
        ],
      ),
      s(t('Pipeline & risks', 'Cartera y riesgos'), 210, [
        t(
          'Pipeline for Q4 stands at 2.8 times coverage, which is healthy but not generous.',
          'La cartera del cuarto trimestre cubre 2,8 veces el objetivo, lo cual es sano pero no holgado.',
        ),
        t(
          'The biggest risk is the Kestrel renewal, which we expect to close in November.',
          'El mayor riesgo es la renovación de Kestrel, que esperamos cerrar en noviembre.',
        ),
        t(
          'If it slips, we still land inside the guidance range.',
          'Si se retrasa, seguimos dentro del rango previsto.',
        ),
      ]),
      s(t('H2 priorities', 'Prioridades del segundo semestre'), 180, [
        t('Three priorities for the second half.', 'Tres prioridades para el segundo semestre.'),
        t(
          'First, finish the regional consolidation, which takes another point out of freight cost.',
          'Primero, terminar la consolidación regional, que recorta otro punto del costo de flete.',
        ),
        t(
          'Second, launch Atlas 2.0 to the enterprise segment.',
          'Segundo, lanzar Atlas 2.0 al segmento corporativo.',
        ),
        t(
          'Third, hire the two senior sales leaders we discussed in July.',
          'Tercero, contratar a los dos líderes de ventas que hablamos en julio.',
        ),
      ]),
      s(t('Board asks', 'Solicitudes al consejo'), 120, [
        t('We have two asks for you today.', 'Hoy tenemos dos solicitudes para ustedes.'),
        t(
          'Approval of the Series C timeline, and introductions to logistics leaders in your networks.',
          'La aprobación del calendario de la Serie C y presentaciones con líderes de logística de sus redes.',
        ),
      ]),
      s(t('Q&A', 'Preguntas'), 300, [
        t('With that, I would love to hear your questions.', 'Con esto, me encantaría escuchar sus preguntas.'),
      ]),
    ],
    prepDocs: [
      PrepDoc(
        id: newId(),
        name: t('Carrier contracts.pdf', 'Contratos de transporte.pdf'),
        text: t(
          'Carrier contracts renegotiated in August lock 60% of shipping volume at Q3 rates until June.\n\n'
              'Remaining exposure to spot freight is roughly 0.8 points of gross margin, already included in the H2 plan.\n\n'
              'Regional consolidation (section 5) is the next lever if freight costs keep climbing.',
          'Los contratos de transporte renegociados en agosto fijan el 60 % del volumen a las tarifas del tercer trimestre hasta junio.\n\n'
              'La exposición restante al flete spot es de unos 0,8 puntos de margen bruto, ya incluidos en el plan del segundo semestre.\n\n'
              'La consolidación regional (sección 5) es la siguiente palanca si el flete sigue subiendo.',
        ),
      ),
    ],
    prepQuestions: [
      PrepQuestion(
        id: newId(),
        question: t(
          'Does the 12% growth include the one-off Kestrel renewal?',
          '¿El crecimiento del 12 % incluye la renovación puntual de Kestrel?',
        ),
        answer: t(
          'No — Kestrel renews in November, so it is not in Q3. Excluding every renewal pulled forward, growth was still 9%.',
          'No — Kestrel renueva en noviembre, así que no está en el tercer trimestre. Sin las renovaciones adelantadas, el crecimiento fue igualmente del 9 %.',
        ),
      ),
    ],
  );

  final atlas = Script(
    id: newId(),
    title: t('Atlas 2.0 launch webinar', 'Webinar de lanzamiento de Atlas 2.0'),
    collectionId: webinars.id,
    status: ScriptStatus.structured,
    createdAt: now.subtract(const Duration(days: 2)),
    updatedAt: now.subtract(const Duration(days: 1)),
    sections: [
      s(t('Welcome', 'Bienvenida'), 60, [
        t(
          "Thanks for joining. In the next thirty minutes I'll show you three things Atlas does today that it couldn't last week.",
          'Gracias por acompañarnos. En los próximos treinta minutos les mostraré tres cosas que Atlas hace hoy y que no podía hacer la semana pasada.',
        ),
      ]),
      s(t('Live routing', 'Rutas en tiempo real'), 300, [
        t('[DEMO] Let me start with live routing.', '[DEMO] Empiezo con las rutas en tiempo real.'),
        t(
          'Every route now updates the moment a driver reports a delay.',
          'Cada ruta se actualiza en el momento en que un conductor reporta un retraso.',
        ),
      ]),
    ],
  );

  final attention = Script(
    id: newId(),
    title: t('Designing for attention', 'Diseñar para la atención'),
    collectionId: talks.id,
    status: ScriptStatus.structured,
    createdAt: now.subtract(const Duration(days: 12)),
    updatedAt: now.subtract(const Duration(days: 11)),
    sections: [
      s(t('Opening', 'Apertura'), 90, [
        t('Every interface is asking for something.', 'Toda interfaz nos pide algo.'),
        t('The question is whether it gives anything back.', 'La pregunta es si nos da algo a cambio.'),
      ]),
    ],
  );

  for (final script in [q3, atlas, attention]) {
    await repo.save(script);
  }
}

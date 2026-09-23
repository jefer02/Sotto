import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/data/models/script.dart';
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/domain/following/follow_engine.dart';
import 'package:sotto/domain/following/script_aligner.dart';
import 'package:sotto/domain/following/text_normalizer.dart';

Script _script() {
  final now = DateTime(2026);
  return Script(
    id: 's',
    title: 'Q3',
    createdAt: now,
    updatedAt: now,
    sections: [
      Section(
        id: 'a',
        title: 'Revenue & margin',
        beats: [
          Beat.create("Let's start with the number everyone's been asking about."),
          Beat.create('Revenue landed at **\$48.2 million** — up 12% on Q2.'),
          Beat.create("It's our strongest quarter since we began reporting to this board."),
        ],
      ),
      Section(
        id: 'b',
        title: 'Pipeline',
        beats: [
          Beat.create('Gross margin held at 31.4%, even with freight up 9%.'),
          Beat.create('Two things drove that: renewals we pulled forward from Q4.'),
        ],
      ),
    ],
  );
}

void main() {
  group('TextNormalizer', () {
    test('expands money, percentages and alphanumerics', () {
      expect(TextNormalizer.spokenForms('\$48.2'), ['forty', 'eight', 'point', 'two']);
      expect(TextNormalizer.spokenForms('12%'), ['twelve', 'percent']);
      expect(TextNormalizer.spokenForms('Q2.'), ['q', 'two']);
      expect(TextNormalizer.spokenForms('2026'), ['twenty', 'twenty', 'six']);
      expect(TextNormalizer.spokenForms('3rd'), ['third']);
      expect(TextNormalizer.spokenForms('1,250'), ['one', 'thousand', 'two', 'hundred', 'fifty']);
    });

    test('reads Spanish numbers the way they are said', () {
      List<String> es(String w) => TextNormalizer.spokenForms(w, language: 'es-419');
      expect(es('48,2'), ['cuarenta', 'y', 'ocho', 'coma', 'dos']);
      expect(es('31,4'), ['treinta', 'y', 'uno', 'coma', 'cuatro']);
      expect(es('%'), ['por', 'ciento']);
      expect(es('12%'), ['doce', 'por', 'ciento']);
      expect(es('2026'), ['dos', 'mil', 'veintiseis']);
      expect(es('1.250'), ['mil', 'doscientos', 'cincuenta']);
      expect(es('100'), ['cien']);
      expect(es('Q2'), ['q', 'dos']);
      expect(es('Revisión'), ['revision']);
      // Recognizers sometimes write the decimal point English-style.
      expect(es('48.2'), ['cuarenta', 'y', 'ocho', 'coma', 'dos']);
      expect(TextNormalizer.spokenForms('48,2'), ['forty', 'eight', 'point', 'two']);
    });

    test('keeps display-word indices', () {
      final t = TextNormalizer.tokenize('Revenue landed at \$48.2 million');
      expect(t.first.displayIndex, 0);
      expect(t.where((x) => x.displayIndex == 3).map((x) => x.text).toList(), ['forty', 'eight', 'point', 'two']);
    });

    test('similarity tolerates recognizer near-misses', () {
      expect(TextNormalizer.similarity('renegotiated', 'renegotiate'), greaterThan(0.78));
      expect(TextNormalizer.similarity('margin', 'revenue'), lessThan(0.78));
    });
  });

  group('FollowEngine', () {
    late FlatScript flat;
    setUp(() => flat = FlatScript.from(_script()));

    test('dims confirmed words inside the current beat', () {
      final e = FollowEngine(flat, settings: const AppSettings());
      e.jumpTo(1);
      final ev = e.onHeard('revenue landed at forty');
      expect(ev, FollowEvent.dimmed);
      expect(e.position.beat, 1);
      expect(e.position.spokenWords, 4);
    });

    test('advances at 80% of a beat', () {
      final e = FollowEngine(flat, settings: const AppSettings());
      e.jumpTo(1);
      final ev = e.onHeard('revenue landed at forty eight point two million up twelve percent on');
      expect(ev, FollowEvent.advanced);
      expect(e.position.beat, 2);
    });

    test('ignores unrelated speech and holds after 6 s', () {
      var now = DateTime(2026, 1, 1, 10);
      final e = FollowEngine(flat, settings: const AppSettings(), clock: () => now);
      e.jumpTo(1);
      expect(e.onHeard('by the way the weather is lovely today'), FollowEvent.none);
      now = now.add(const Duration(seconds: 7));
      expect(e.onHeard('as i was saying about my dog'), FollowEvent.heldStill);
      expect(e.position.holding, isTrue);
      expect(e.onHeard('strongest quarter since we began'), FollowEvent.relocked);
      expect(e.position.beat, 2);
    });

    test('advances once, not again on the same transcript tail', () {
      final e = FollowEngine(flat, settings: const AppSettings());
      e.jumpTo(1);
      const heard = 'revenue landed at forty eight point two million up twelve percent on q two';
      expect(e.onHeard(heard), FollowEvent.advanced);
      expect(e.onHeard(heard), FollowEvent.none);
      expect(e.position.beat, 2);
      // …and the next beat's first word is picked up, not the old tail.
      expect(e.onHeard('$heard its'), FollowEvent.dimmed);
      expect(e.position.beat, 2);
      expect(e.position.spokenWords, 1);
    });

    test('does move back on a clear re-read', () {
      final e = FollowEngine(flat, settings: const AppSettings());
      e.jumpTo(3);
      e.onHeard("let's start with the number everyone's been");
      expect(e.position.beat, 0);
    });

    test('does not scroll back on a short guess', () {
      final e = FollowEngine(flat, settings: const AppSettings());
      e.jumpTo(3);
      expect(e.onHeard('the number'), FollowEvent.none);
      expect(e.position.beat, 3);
    });

    test('follows a Spanish script read aloud', () {
      final now = DateTime(2026);
      final script = Script(id: 'es', title: 'T3', createdAt: now, updatedAt: now, sections: [
        Section(id: 'a', title: 'Ingresos', beats: [
          Beat.create('Empecemos por la cifra que todos esperan.'),
          Beat.create('Los ingresos llegaron a **48,2 millones** de dólares — un 12 % más.'),
          Beat.create('Es nuestro mejor trimestre desde que empezamos.'),
        ]),
      ]);
      final e = FollowEngine(FlatScript.from(script, language: 'es-419'), settings: const AppSettings())..jumpTo(1);
      // What a recognizer writes, with its own accents and digits.
      e.onHeard('los ingresos llegaron a cuarenta y ocho coma dos millones');
      expect(e.position.beat, 1);
      expect(e.position.spokenWords, greaterThanOrEqualTo(5));
      expect(e.onHeard('los ingresos llegaron a 48,2 millones de dólares un 12 por ciento más'), FollowEvent.advanced);
      expect(e.position.beat, 2);
    });

    test('follows a skip to another section', () {
      final e = FollowEngine(flat, settings: const AppSettings());
      e.jumpTo(0);
      e.onHeard('two things drove that renewals we pulled');
      expect(e.position.beat, 4);
    });
  });
}

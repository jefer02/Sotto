// Markers a generated script leaves to check ("[CHECK: …]", "[REVISAR: …]")
// are notes, never said: voice following skips their words, a beat ending
// in one finishes on its last real word, a beat that is only a marker is
// passed over, and hiding them for the live view keeps everything else.
import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/data/models/script.dart';
import 'package:sotto/data/models/settings.dart';
import 'package:sotto/domain/following/follow_engine.dart';
import 'package:sotto/domain/following/script_aligner.dart';
import 'package:sotto/domain/structuring/check_markers.dart';
import 'package:sotto/features/live/overlay/reading_view.dart' show splitWords;

Script _script(List<List<String>> sections) {
  final now = DateTime(2026);
  return Script(
    id: 's',
    title: 'Q3',
    createdAt: now,
    updatedAt: now,
    sections: [
      for (var i = 0; i < sections.length; i++)
        Section(id: 'sec$i', title: 'S$i', beats: [for (final t in sections[i]) Beat.create(t)]),
    ],
  );
}

final _beats = [
  'Thanks for coming, everyone.',
  'Revenue grew [CHECK: quarterly figure from finance] this quarter across all regions.',
  'Our margin held at 48.2% [CHECK: confirm the margin with finance]',
  'Next we open the warehouse in Monterrey.',
  '[CHECK: opening date]',
  'Thank you all for listening today.',
];

void main() {
  group('CheckMarkers', () {
    test('finds markers in both languages, case-insensitively', () {
      expect(CheckMarkers.count('a [CHECK: x] b [revisar: y] c [Verificar: z]'), 3);
      expect(CheckMarkers.has('[SLIDE 3] no markers [NOTE pause]'), isFalse);
      expect(CheckMarkers.has('[CHECK x] needs a colon'), isFalse);
    });

    test('strips and removes with tidy spacing and punctuation', () {
      expect(CheckMarkers.strip('Revenue grew [CHECK: figure] this quarter.'), 'Revenue grew this quarter.');
      expect(CheckMarkers.strip('Held at 48.2% [CHECK: confirm].'), 'Held at 48.2%.');
      const text = 'We open in [REVISAR: fecha] marzo, [CHECK: x] then.';
      final m = CheckMarkers.pattern.allMatches(text).last;
      expect(CheckMarkers.removeAt(text, m.start, m.end), 'We open in [REVISAR: fecha] marzo, then.');
    });

    test('marks exactly the display words inside a marker, bold or not', () {
      expect(CheckMarkers.wordMask('**Revenue** grew [CHECK: Q3 figure] fast.'), [
        false,
        false,
        true,
        true,
        true,
        false,
      ]);
      expect(CheckMarkers.wordMask('No markers here.'), [false, false, false]);
    });

    test('the overlay draws exactly the marker words apart, bold and glue intact', () {
      final words = splitWords('Revenue grew **12%** [CHECK: Q3 figure] this quarter.');
      expect(
        [
          for (final w in words)
            if (w.marker) w.text,
        ],
        ['[CHECK:', 'Q3', 'figure]'],
      );
      expect(words.firstWhere((w) => w.text == '12%').bold, isTrue);
      expect(words.length, 8);
    });

    test('lists markers in reading order with where they are', () {
      final markers = CheckMarkers.inScript(_script([_beats.sublist(0, 3), _beats.sublist(3)]));
      expect(markers.map((m) => (m.section, m.note)), [
        (0, 'quarterly figure from finance'),
        (0, 'confirm the margin with finance'),
        (1, 'opening date'),
      ]);
      final first = markers.first;
      expect(_beats[1].substring(first.start, first.end), first.text);
    });

    test('hidden for the live view: markers gone, a marker-only beat dropped, ids kept', () {
      final script = _script([_beats]);
      final live = CheckMarkers.stripScript(script);
      expect(live.allBeats.map((b) => b.text), [
        'Thanks for coming, everyone.',
        'Revenue grew this quarter across all regions.',
        'Our margin held at 48.2%',
        'Next we open the warehouse in Monterrey.',
        'Thank you all for listening today.',
      ]);
      expect(live.allBeats.first.id, script.allBeats.first.id);
      expect(CheckMarkers.countIn(live.sections), 0);
    });
  });

  group('alignment', () {
    final flat = FlatScript.from(_script([_beats]));

    test('marker words have no tokens; display indexes still point at the words shown', () {
      final beat = flat.beats[1];
      final tokens = flat.tokens.sublist(beat.firstToken, beat.endToken);
      expect(tokens.map((t) => t.text), ['revenue', 'grew', 'this', 'quarter', 'across', 'all', 'regions']);
      expect(beat.displayWords[tokens[2].displayIndex], 'this');
      expect(flat.tokens.any((t) => t.text == 'check' || t.text == 'finance'), isFalse);
      expect(flat.beats[4].tokenCount, 0, reason: 'a beat that is only a marker has nothing to say');
      expect(flat.beats[2].wordsToSay, 5, reason: 'the trailing marker is not said');
      expect(flat.beats[1].wordsToSay, flat.beats[1].displayWords.length);
    });

    test('reading a marker aloud never moves the script', () {
      final e = FollowEngine(flat, settings: const AppSettings())..jumpTo(1);
      e.onHeard('check quarterly figure from finance');
      expect((e.position.beat, e.position.spokenWords), (1, 0));
      e.onHeard('check quarterly figure from finance confirm the margin with finance');
      expect(e.position.beat, 1);
    });

    test('the words around a marker follow as if it were not there', () {
      final e = FollowEngine(flat, settings: const AppSettings())..jumpTo(1);
      e.onHeard('revenue grew this quarter across all regions');
      expect(e.position.beat, 2);
      expect(e.position.saidBeat, 2, reason: 'the beat was said in full: the marker is not part of it');
    });

    test('a beat ending in a marker is finished by its last real word', () {
      final e = FollowEngine(flat, settings: const AppSettings())..jumpTo(2);
      e.onHeard('our margin held at forty eight point two percent');
      expect(e.position.beat, 3);
      expect((e.position.saidBeat, e.position.saidWords), (3, 0));
    });

    test('a beat that is only a marker is passed over', () {
      final e = FollowEngine(flat, settings: const AppSettings())..jumpTo(3);
      e.onHeard('next we open the warehouse in monterrey');
      expect(e.position.beat, 5);
    });

    test('Spanish markers too', () {
      final es = FlatScript.from(
        _script([
          ['Abrimos el almacén en [REVISAR: fecha de apertura] marzo.', 'Gracias a todos.'],
        ]),
        language: 'es-ES',
      );
      final tokens = es.tokens.where((t) => t.beat == 0).map((t) => t.text);
      expect(tokens, ['abrimos', 'el', 'almacen', 'en', 'marzo']);
      final e = FollowEngine(es, settings: const AppSettings(language: 'es-ES'))..jumpTo(0);
      e.onHeard('revisar fecha de apertura');
      expect(e.position.beat, 0);
      e.onHeard('abrimos el almacen en marzo');
      expect(e.position.beat, 1);
    });
  });
}

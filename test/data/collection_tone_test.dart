import 'package:flutter_test/flutter_test.dart';
import 'package:sotto/data/models/script.dart';

void main() {
  test('nextTone picks the least-used color, lowest index on ties', () {
    expect(Collection.nextTone(const []), 0);
    expect(
      Collection.nextTone(const [
        Collection(id: 'a', name: 'A', tone: 0),
        Collection(id: 'b', name: 'B', tone: 1),
        Collection(id: 'c', name: 'C'),
      ]),
      2,
    );
    final full = [for (var i = 0; i < Collection.toneCount; i++) Collection(id: '$i', name: '$i', tone: i)];
    expect(Collection.nextTone([...full, const Collection(id: 'x', name: 'X', tone: 0)]), 1);
  });

  test('tone round-trips through JSON and stays optional', () {
    const toned = Collection(id: 'a', name: 'A', tone: 4);
    expect(Collection.fromJson(toned.toJson()).tone, 4);
    expect(const Collection(id: 'b', name: 'B').toJson().containsKey('tone'), isFalse);
    expect(Collection.fromJson({'id': 'c', 'name': 'C'}).tone, isNull);
  });
}

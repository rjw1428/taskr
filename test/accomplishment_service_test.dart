import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/accomplishment.service.dart';
import 'package:taskr/services/auth.service.dart';
import 'package:taskr/services/models.dart';

void main() {
  late FakeFirebaseFirestore fake;
  late AccomplishmentService service;
  const uid = 'u1';

  Future<void> seed(String id, String date, {String? title}) {
    return fake
        .collection('todos')
        .doc(uid)
        .collection('accomplishments')
        .doc(id)
        .set({
      'title': title ?? id,
      'date': date,
      'difficultyScore': 5,
    });
  }

  setUp(() {
    fake = FakeFirebaseFirestore();
    AuthService().user = MockUser(uid: uid);
    service = AccomplishmentService()..db = fake;
  });

  group('writes', _writeTests);

  group('getAccomplishments', () {
    test('returns entries newest-first without client-side sorting', () async {
      // Seeded out of order; ordering must come from the query.
      await seed('b', '2026-03-02T10:00:00.000');
      await seed('d', '2026-08-14T10:00:00.000');
      await seed('a', '2026-01-09T10:00:00.000');
      await seed('c', '2026-05-21T10:00:00.000');

      final result = await service.getAccomplishments().first;

      expect(result.map((a) => a.id), ['d', 'c', 'b', 'a']);
    });

    test('a limited request yields exactly the N most recent entries', () async {
      await seed('a', '2026-01-09T10:00:00.000');
      await seed('b', '2026-03-02T10:00:00.000');
      await seed('c', '2026-05-21T10:00:00.000');
      await seed('d', '2026-08-14T10:00:00.000');

      final result = await service.getAccomplishments(limit: 2).first;

      expect(result.map((a) => a.id), ['d', 'c']);
    });

    test('an unlimited request yields everything, newest-first', () async {
      await seed('a', '2026-01-09T10:00:00.000');
      await seed('b', '2026-03-02T10:00:00.000');
      await seed('c', '2026-05-21T10:00:00.000');

      final result = await service.getAccomplishments().first;

      expect(result.map((a) => a.id), ['c', 'b', 'a']);
    });

    test('a limit larger than the collection yields everything', () async {
      await seed('a', '2026-01-09T10:00:00.000');
      await seed('b', '2026-03-02T10:00:00.000');

      final result = await service.getAccomplishments(limit: 20).first;

      expect(result.map((a) => a.id), ['b', 'a']);
    });

    test('returns an empty list when unauthenticated', () async {
      AuthService().user = null;

      expect(await service.getAccomplishments().first, isEmpty);
    });
  });

  group('getAccomplishment', () {
    test('emits the document, then its updates, then null on delete', () async {
      await seed('a', '2026-01-09T10:00:00.000', title: 'Original');

      final emissions = <String?>[];
      final sub = service.getAccomplishment('a').listen((a) => emissions.add(a?.title));

      // Let each write land as its own snapshot.
      await Future<void>.delayed(Duration.zero);
      await service.updateAccomplishment(
        (await service.getAccomplishment('a').first)!..title = 'Edited',
      );
      await Future<void>.delayed(Duration.zero);
      await service.deleteAccomplishment('a');
      await Future<void>.delayed(Duration.zero);

      await sub.cancel();

      expect(emissions.first, 'Original');
      expect(emissions.contains('Edited'), isTrue);
      expect(emissions.last, isNull);
    });

    test('emits null for a document that never existed', () async {
      expect(await service.getAccomplishment('nope').first, isNull);
    });

    test('emits null when unauthenticated', () async {
      AuthService().user = null;

      expect(await service.getAccomplishment('a').first, isNull);
    });
  });
}

// ── Added coverage: writes and the unauthenticated guards ─────────────────────

void _writeTests() {
  late FakeFirebaseFirestore fake;
  late AccomplishmentService service;
  const uid = 'u1';

  setUp(() {
    fake = FakeFirebaseFirestore();
    AuthService().user = MockUser(uid: uid);
    service = AccomplishmentService()..db = fake;
  });

  Future<List<Map<String, dynamic>>> rows() async =>
      (await fake.collection('todos').doc(uid).collection('accomplishments').get())
          .docs
          .map((d) => {...d.data(), 'id': d.id})
          .toList();

  test('addAccomplishment stores the entry under the signed-in user', () async {
    await service.addAccomplishment(
      Accomplishment(title: 'Ran 5k', description: 'Morning', date: '2026-09-10T08:00:00.000', difficultyScore: 4),
    );

    final stored = await rows();
    expect(stored, hasLength(1));
    expect(stored.single['title'], 'Ran 5k');
    expect(stored.single['description'], 'Morning');
    expect(stored.single['difficultyScore'], 4);
  });

  test('updateAccomplishment and deleteAccomplishment act on the id', () async {
    await service.addAccomplishment(Accomplishment(title: 'one', date: '2026-01-01T00:00:00.000'));
    final id = (await rows()).single['id'] as String;

    await service.updateAccomplishment(Accomplishment(id: id, title: 'two', date: '2026-01-01T00:00:00.000'));
    expect((await rows()).single['title'], 'two');

    await service.deleteAccomplishment(id);
    expect(await rows(), isEmpty);
  });

  test('every write throws when unauthenticated', () async {
    AuthService().user = null;
    final a = Accomplishment(id: 'x', title: 'one', date: '2026-01-01T00:00:00.000');

    expect(() => service.addAccomplishment(a), throwsA(isA<Exception>()));
    expect(() => service.updateAccomplishment(a), throwsA(isA<Exception>()));
    expect(() => service.deleteAccomplishment('x'), throwsA(isA<Exception>()));
  });
}

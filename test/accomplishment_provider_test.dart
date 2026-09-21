import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/accomplishment.provider.dart';
import 'package:taskr/services/models.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  late AccomplishmentProvider provider;

  setUp(() async {
    env = await TestEnv.create();
    provider = AccomplishmentProvider();
  });
  tearDown(() => env.dispose());

  Future<List<Map<String, dynamic>>> stored() async =>
      (await env.col('accomplishments').get()).docs.map((d) => {...d.data(), 'id': d.id}).toList();

  test('addAccomplishment writes the entry under the signed-in user', () async {
    await provider.addAccomplishment(
      Accomplishment(title: 'Ran 5k', description: 'Morning run', date: '2026-09-10T08:00:00.000', difficultyScore: 4),
    );

    final rows = await stored();
    expect(rows, hasLength(1));
    expect(rows.single['title'], 'Ran 5k');
    expect(rows.single['difficultyScore'], 4);
  });

  test('getAccomplishments streams newest-first and honours the limit', () async {
    await provider.addAccomplishment(Accomplishment(title: 'old', date: '2026-01-01T00:00:00.000'));
    await provider.addAccomplishment(Accomplishment(title: 'mid', date: '2026-05-01T00:00:00.000'));
    await provider.addAccomplishment(Accomplishment(title: 'new', date: '2026-09-01T00:00:00.000'));

    final all = await provider.getAccomplishments().first;
    expect(all.map((a) => a.title), ['new', 'mid', 'old']);

    final two = await provider.getAccomplishments(limit: 2).first;
    expect(two.map((a) => a.title), ['new', 'mid']);
  });

  test('getAccomplishment tracks a single entry by id', () async {
    await provider.addAccomplishment(Accomplishment(title: 'one', date: '2026-01-01T00:00:00.000'));
    final id = (await stored()).single['id'] as String;

    final a = await provider.getAccomplishment(id).first;
    expect(a?.id, id);
    expect(a?.title, 'one');
    expect(await provider.getAccomplishment('missing').first, isNull);
  });

  test('updateAccomplishment rewrites the document', () async {
    await provider.addAccomplishment(Accomplishment(title: 'one', date: '2026-01-01T00:00:00.000'));
    final id = (await stored()).single['id'] as String;

    await provider.updateAccomplishment(
      Accomplishment(id: id, title: 'edited', description: 'd', date: '2026-01-01T00:00:00.000', difficultyScore: 9),
    );

    final row = (await stored()).single;
    expect(row['title'], 'edited');
    expect(row['description'], 'd');
    expect(row['difficultyScore'], 9);
  });

  test('deleteAccomplishment removes the document', () async {
    await provider.addAccomplishment(Accomplishment(title: 'one', date: '2026-01-01T00:00:00.000'));
    final id = (await stored()).single['id'] as String;

    await provider.deleteAccomplishment(id);

    expect(await stored(), isEmpty);
  });
}

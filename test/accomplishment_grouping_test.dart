import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/accomplishments/accomplishment_grouping.dart';
import 'package:taskr/services/models.dart';

void main() {
  Accomplishment at(String date, {String title = 'x'}) =>
      Accomplishment(title: title, date: date, difficultyScore: 5);

  test('groups consecutive entries sharing a month', () {
    final groups = groupByMonth([
      at('2026-08-14T10:00:00.000', title: 'a'),
      at('2026-08-02T10:00:00.000', title: 'b'),
      at('2026-07-28T10:00:00.000', title: 'c'),
    ]);

    expect(groups.length, 2);
    expect(groups[0].label, 'August 2026');
    expect(groups[0].accomplishments.map((a) => a.title), ['a', 'b']);
    expect(groups[1].label, 'July 2026');
    expect(groups[1].accomplishments.map((a) => a.title), ['c']);
  });

  test('preserves input order across and within groups', () {
    final groups = groupByMonth([
      at('2026-08-14T10:00:00.000', title: 'a'),
      at('2026-07-28T10:00:00.000', title: 'b'),
      at('2026-06-01T10:00:00.000', title: 'c'),
    ]);

    expect(groups.map((g) => g.label), ['August 2026', 'July 2026', 'June 2026']);
  });

  test('distinguishes the same month in different years', () {
    final groups = groupByMonth([
      at('2026-08-14T10:00:00.000'),
      at('2025-08-14T10:00:00.000'),
    ]);

    expect(groups.length, 2);
    expect(groups.map((g) => g.label), ['August 2026', 'August 2025']);
  });

  test('an unparseable date groups under Undated instead of throwing', () {
    final groups = groupByMonth([
      at('2026-08-14T10:00:00.000', title: 'good'),
      at('not-a-date', title: 'bad'),
    ]);

    expect(groups.length, 2);
    expect(groups[1].label, 'Undated');
    expect(groups[1].accomplishments.single.title, 'bad');
  });

  test('an empty input yields no groups', () {
    expect(groupByMonth([]), isEmpty);
  });

  test('a single entry yields one group', () {
    final groups = groupByMonth([at('2026-08-14T10:00:00.000')]);

    expect(groups.single.label, 'August 2026');
    expect(groups.single.accomplishments.length, 1);
  });
}

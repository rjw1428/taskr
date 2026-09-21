import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/people/person_avatar.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  setUp(() async => env = await TestEnv.create());
  tearDown(() => env.dispose());

  test('personInitials handles empty, single and multi-word names', () {
    expect(personInitials(''), '?');
    expect(personInitials('   '), '?');
    expect(personInitials('ada'), 'A');
    expect(personInitials('Ada Lovelace'), 'AL');
    expect(personInitials('  grace   brewster hopper '), 'GB');
  });

  testWidgets('renders initials at the default size', (tester) async {
    await pumpApp(tester, const PersonAvatar(name: 'Ada Lovelace'), wrapInScaffold: true);
    expect(find.text('AL'), findsOneWidget);
    final box = tester.getSize(find.byType(PersonAvatar));
    expect(box, const Size(44, 44));
  });

  testWidgets('renders a compact variant below 40px', (tester) async {
    await pumpApp(tester, const PersonAvatar(name: 'Ada Lovelace'), wrapInScaffold: true);
    final regularFont = tester.widget<Text>(find.text('AL')).style!.fontSize!;

    await pumpApp(tester, const PersonAvatar(name: 'Bob', size: 28), wrapInScaffold: true);
    expect(find.text('B'), findsOneWidget);
    expect(tester.getSize(find.byType(PersonAvatar)), const Size(28, 28));
    expect(tester.widget<Text>(find.text('B')).style!.fontSize!, lessThan(regularFont),
        reason: 'the compact avatar uses a smaller initials style');
  });

  testWidgets('renders a placeholder for a blank name', (tester) async {
    await pumpApp(tester, const PersonAvatar(name: ''), wrapInScaffold: true);
    expect(find.text('?'), findsOneWidget);
  });
}

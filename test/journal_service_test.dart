import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;

  setUp(() async => env = await TestEnv.create());
  tearDown(() => env.dispose());

  test('saveEntry writes the day document without nulls or an id', () async {
    await JournalService().saveEntry(JournalEntry(id: 'ignored', date: '2026-01-05', thinking: 'deep', feeling: ''));
    final doc = await env.col('journal').doc('2026-01-05').get();
    expect(doc.data(), {'date': '2026-01-05', 'thinking': 'deep'});
  });

  test('getEntry reads an entry back with its id, or null', () async {
    expect(await JournalService().getEntry('2026-01-05'), isNull);
    await JournalService().saveEntry(JournalEntry(date: '2026-01-05', gratitude: 'sun'));
    final entry = await JournalService().getEntry('2026-01-05');
    expect(entry!.id, '2026-01-05');
    expect(entry.gratitude, 'sun');
  });

  test('streamEntry follows the document', () async {
    final seen = <JournalEntry?>[];
    final sub = JournalService().streamEntry('2026-01-06').listen(seen.add);
    await Future<void>.delayed(Duration.zero);
    await JournalService().saveEntry(JournalEntry(date: '2026-01-06', feeling: 'calm'));
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(seen.first, isNull);
    expect(seen.last!.feeling, 'calm');
  });

  test('an injected database is used', () async {
    final other = FakeFirebaseFirestore();
    JournalService().db = other;
    await JournalService().saveEntry(JournalEntry(date: 'd', thinking: 't'));
    expect((await other.collection('todos').doc(env.uid).collection('journal').doc('d').get()).exists, isTrue);
    expect(await env.col('journal').get().then((s) => s.docs), isEmpty);
  });

  test('signed out: reads are empty and writes are refused', () async {
    AuthService().user = null;
    expect(await JournalService().getEntry('2026-01-05'), isNull);
    expect(await JournalService().streamEntry('2026-01-05').first, isNull);
    expect(() => JournalService().saveEntry(JournalEntry(date: '2026-01-05')), throwsA(isA<Exception>()));
  });
}

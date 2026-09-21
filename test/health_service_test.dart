import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;

  setUp(() async => env = await TestEnv.create());
  tearDown(() => env.dispose());

  test('streamEntry parses the day document, dropping the sync timestamp', () async {
    final seen = <HealthEntry?>[];
    final sub = HealthService().streamEntry('2026-01-06').listen(seen.add);
    await Future<void>.delayed(Duration.zero);
    await env.col('health').doc('2026-01-06').set({
      'date': '2026-01-06',
      'steps': 8000,
      'sleepSeconds': 25000,
      'updatedAt': Timestamp.now(),
    });
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(seen.first, isNull);
    expect(seen.last!.id, '2026-01-06');
    expect(seen.last!.steps, 8000);
    expect(seen.last!.hasData, isTrue);
  });

  test('an injected database is used', () async {
    final other = FakeFirebaseFirestore();
    await other.collection('todos').doc(env.uid).collection('health').doc('d').set({'date': 'd', 'steps': 1});
    HealthService().db = other;
    expect((await HealthService().streamEntry('d').first)!.steps, 1);
  });

  test('signed out streams null', () async {
    AuthService().user = null;
    expect(await HealthService().streamEntry('2026-01-06').first, isNull);
  });
}

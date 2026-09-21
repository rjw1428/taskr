import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/services/tag.provider.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  setUp(() async => env = await TestEnv.create());
  tearDown(() => env.dispose());

  Future<void> flush() async {
    for (var i = 0; i < 3; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('streams the user\'s live tags sorted by label, hiding "Other" and deleted ones', () async {
    await env.col('tags').add({'label': 'Work', 'deleted': false, 'archived': false});
    await env.col('tags').add({'label': 'Home', 'deleted': false, 'archived': false});
    await env.col('tags').add({'label': 'Other', 'deleted': false, 'archived': false});
    await env.col('tags').add({'label': 'Gone', 'deleted': true, 'archived': false});

    final provider = TagProvider();
    var notified = 0;
    provider.addListener(() => notified++);
    await flush();

    expect(provider.tags.map((t) => t.label), ['Home', 'Work']);
    expect(notified, greaterThan(0));
    provider.dispose();
  });

  test('addTag, updateTag and deleteTag round-trip through Firestore', () async {
    final provider = TagProvider();
    await flush();

    await provider.addTag('Errands');
    await flush();
    expect(provider.tags.map((t) => t.label), ['Errands']);

    final id = provider.tags.single.id;
    await provider.updateTag(id, 'Chores');
    await flush();
    expect(provider.tags.single.label, 'Chores');

    await provider.deleteTag(id);
    await flush();
    expect(provider.tags, isEmpty);
    expect((await env.col('tags').doc(id).get()).data()?['deleted'], isTrue);
    provider.dispose();
  });

  test('clears the tags on sign out and refuses writes', () async {
    await env.col('tags').add({'label': 'Work', 'deleted': false, 'archived': false});
    final provider = TagProvider();
    await flush();
    expect(provider.tags, hasLength(1));

    await env.auth.signOut();
    await flush();
    expect(provider.tags, isEmpty);

    AuthService().user = null;
    expect(() => provider.addTag('x'), throwsA(isA<String>()));
    expect(() => provider.deleteTag('x'), throwsA(isA<String>()));
    expect(() => provider.updateTag('x', 'y'), throwsA(isA<String>()));
    provider.dispose();
  });
}

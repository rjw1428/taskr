
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/ai.service.dart';
import 'package:taskr/services/models.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  const fallback = 'Good Job!!! Nothing for you today...';

  /// What the `callGemini` callable hands back, or an exception to throw.
  final requests = <Map<String, dynamic>>[];
  late Object? reply;

  setUp(() async {
    env = await TestEnv.create();
    requests.clear();
    reply = {'text': '  Great work today!  '};
    env.functions['callGemini'] = (payload) {
      requests.add(Map<String, dynamic>.from(payload as Map));
      final r = reply;
      if (r is Exception) throw r;
      return r;
    };
  });
  tearDown(() => env.dispose());

  Task task(String title, {required bool completed, List<Tag> tags = const []}) =>
      Task(added: 1, title: title, description: 'desc', completed: completed, tags: tags);

  group('giveFeedback', () {
    test('sends completed and missed tasks with the coaching instruction and trims the reply', () async {
      final tags = [Tag(id: 'w', label: 'Work'), Tag(id: 'h', label: 'Home')];
      final reply = await AIService().giveFeedback([
        task('Ship it', completed: true, tags: tags),
        task('Gym', completed: false),
      ]);
      expect(reply, 'Great work today!');

      final req = requests.single;
      expect(req['kind'], 'coach');
      expect(req.keys, unorderedEquals(['kind', 'prompt']), reason: 'no key or instruction leaves the client');
      final prompt = req['prompt'] as String;
      expect(prompt, contains('I completed the following tasks today: Ship it - desc relating to my Work,Home'));
      expect(prompt, contains('I was unable to do the following tasks today: Gym - desc'));
    });

    test('says so when everything is done', () async {
      await AIService().giveFeedback([task('a', completed: true)]);
      final prompt = requests.single['prompt'] as String;
      expect(prompt, contains('I completed all my tasks today!'));
    });

    test('falls back when the callable fails', () async {
      reply = Exception('Gemini API error 500');
      expect(await AIService().giveFeedback([task('a', completed: true)]), fallback);
    });

    test('falls back on an empty or malformed reply', () async {
      reply = {'text': ''};
      expect(await AIService().giveFeedback([task('a', completed: true)]), fallback);
      reply = {};
      expect(await AIService().giveFeedback([task('a', completed: true)]), fallback);
      reply = 'not a map';
      expect(await AIService().giveFeedback([task('a', completed: true)]), fallback);
    });

    test('falls back when the callable is not wired', () async {
      env.functions.remove('callGemini');
      expect(await AIService().giveFeedback([task('a', completed: true)]), fallback);
    });
  });

  group('stored feedback', () {
    test('storeFeedback writes the day document and getFeedback reads it back', () async {
      await AIService().storeFeedback(env.uid, '2026-01-01', 'Nice');
      final doc = await env.col('feedback').doc('2026-01-01').get();
      expect(doc.exists, isTrue);

      await env.col('feedback').doc('2026-01-02').set({'feedback': 'Keep going'});
      expect(await AIService().getFeedback(env.uid, '2026-01-02'), 'Keep going');
    });

    test('setEndOfDayNotification is inert', () {
      AIService().setEndOfDayNotification(const []);
    });

    test('an injected database is used for feedback', () async {
      final other = FakeFirebaseFirestore();
      AIService().db = other;
      await AIService().storeFeedback(env.uid, '2026-01-03', 'x');
      expect((await other.collection('todos').doc(env.uid).collection('feedback').doc('2026-01-03').get()).exists, isTrue);
    });
  });
}

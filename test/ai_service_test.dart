import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/ai.service.dart';
import 'package:taskr/services/models.dart';

import 'helpers/harness.dart';

/// Stands in for the Gemini generateContent endpoint.
class _StubGemini {
  late HttpServer _server;
  final List<({String query, Map<String, dynamic> body})> requests = [];
  int status = 200;
  String text = '  Great work today!  ';
  String? rawBody;

  Future<String> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(_server.forEach((request) async {
      final raw = await utf8.decoder.bind(request).join();
      requests.add((query: request.uri.query, body: jsonDecode(raw) as Map<String, dynamic>));
      request.response.statusCode = status;
      request.response.write(rawBody ??
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': text}
                  ]
                }
              }
            ]
          }));
      await request.response.close();
    }));
    return 'http://${_server.address.host}:${_server.port}/generate';
  }

  Future<void> stop() => _server.close(force: true);
}

void main() {
  late TestEnv env;
  late _StubGemini stub;
  const fallback = 'Good Job!!! Nothing for you today...';

  setUp(() async {
    env = await TestEnv.create();
    stub = _StubGemini();
    AIService.geminiEndpoint = await stub.start();
  });
  tearDown(() async {
    await stub.stop();
    env.dispose();
  });

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

      final req = stub.requests.single;
      expect(req.query, 'key=gemini-key');
      expect(req.body['system_instruction']['parts'][0]['text'], contains('personal coach'));
      final prompt = req.body['contents'][0]['parts'][0]['text'] as String;
      expect(prompt, contains('I completed the following tasks today: Ship it - desc relating to my Work,Home'));
      expect(prompt, contains('I was unable to do the following tasks today: Gym - desc'));
    });

    test('says so when everything is done', () async {
      await AIService().giveFeedback([task('a', completed: true)]);
      final prompt = stub.requests.single.body['contents'][0]['parts'][0]['text'] as String;
      expect(prompt, contains('I completed all my tasks today!'));
    });

    test('falls back on a non-200 answer', () async {
      stub.status = 500;
      expect(await AIService().giveFeedback([task('a', completed: true)]), fallback);
    });

    test('falls back on an empty reply', () async {
      stub.text = '';
      expect(await AIService().giveFeedback([task('a', completed: true)]), fallback);
      stub.rawBody = '{}';
      expect(await AIService().giveFeedback([task('a', completed: true)]), fallback);
    });

    test('falls back when the server is unreachable', () async {
      await stub.stop();
      expect(await AIService().giveFeedback([task('a', completed: true)]), fallback);
    });

    test('falls back without an API key', () async {
      env.dispose();
      env = await TestEnv.create(env: {'GEMINI_API_KEY': ''});
      expect(await AIService().giveFeedback([task('a', completed: true)]), fallback);
      expect(stub.requests, isEmpty);
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

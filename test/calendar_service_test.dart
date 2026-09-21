import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';

import 'helpers/harness.dart';

/// Stands in for the Google Calendar events endpoint.
class _StubCalendar {
  late HttpServer _server;
  final List<({String method, String path, String? auth, Map<String, dynamic> body})> requests = [];
  int status = 200;
  String responseBody = '{"id": "evt-1"}';

  Future<String> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(_server.forEach((request) async {
      final raw = await utf8.decoder.bind(request).join();
      requests.add((
        method: request.method,
        path: request.uri.path,
        auth: request.headers.value(HttpHeaders.authorizationHeader),
        body: raw.isEmpty ? const {} : jsonDecode(raw) as Map<String, dynamic>,
      ));
      request.response.statusCode = status;
      request.response.write(responseBody);
      await request.response.close();
    }));
    return 'http://${_server.address.host}:${_server.port}/events';
  }

  Future<void> stop() => _server.close(force: true);
}

void main() {
  late TestEnv env;
  late _StubCalendar stub;
  late CalendarService service;

  setUp(() async {
    env = await TestEnv.create();
    stub = _StubCalendar();
    calendarEventsUrl = await stub.start();
    env.google.silent[GoogleSignInProfile.calendar] = const GoogleAuthResult(accessToken: 'tok', email: 'e');
    service = CalendarService();
  });
  tearDown(() async {
    await stub.stop();
    env.dispose();
  });

  Task task({String? date = '2026-08-01', String? id = 't1', String? description, String? eventId, String? template}) =>
      Task(
        id: id,
        added: 1,
        title: 'Dentist',
        dueDate: date,
        description: description,
        calendarEventId: eventId,
        recurringTemplateId: template,
      );

  group('connection state', () {
    test('watchConnected reflects the calendarConnectedAt flag, deduplicated and shared', () async {
      final seen = <bool>[];
      final stream = service.watchConnected(env.uid);
      expect(identical(stream, service.watchConnected(env.uid)), isTrue);
      final sub = stream.listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      await env.db.collection('todos').doc(env.uid).update({'currentScore': 5});
      await env.db.collection('todos').doc(env.uid).update({'calendarConnectedAt': Timestamp.now()});
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(seen, [false, true]);
    });

    test('an injected database is used', () async {
      final other = FakeFirebaseFirestore();
      await other.collection('todos').doc('x').set({'calendarConnectedAt': Timestamp.fromDate(DateTime(2026))});
      service.db = other;
      expect(await service.connectedAt('x'), DateTime(2026));
    });

    test('connectedAt reads the timestamp, or null', () async {
      expect(await service.connectedAt(env.uid), isNull);
      final at = DateTime(2026, 1, 2, 3, 4);
      await env.db.collection('todos').doc(env.uid).update({'calendarConnectedAt': Timestamp.fromDate(at)});
      expect(await service.connectedAt(env.uid), at);
      expect(await service.connectedAt('nobody'), isNull);
    });

    test('connect exchanges the server auth code through the callable', () async {
      await service.connect();
      expect(env.functionCalls.single.name, 'exchangeCalendarAuthCode');
      expect(env.functionCalls.single.payload, {'code': 'code'});
    });

    test('connect throws when the picker is dismissed', () async {
      env.google.interactive[GoogleSignInProfile.calendar] = null;
      expect(() => service.connect(), throwsA(isA<Exception>()));
    });

    test('disconnect revokes consent even when the callable fails', () async {
      await service.disconnect();
      expect(env.functionCalls.single.name, 'disconnectCalendar');
      expect(env.google.log, contains('disconnect:calendar'));

      env.google.log.clear();
      env.functions['disconnectCalendar'] = (_) => throw Exception('down');
      await expectLater(service.disconnect(), throwsA(isA<Exception>()));
      expect(env.google.log, contains('disconnect:calendar'));
    });
  });

  group('sendTaskToCalendar', () {
    test('creates an all-day event and stores the event id on the task', () async {
      final id = await TaskService().addTask(task(id: null, description: 'bring x-rays'));
      final eventId = await service.sendTaskToCalendar(task(id: id, description: 'bring x-rays'));
      expect(eventId, 'evt-1');

      final req = stub.requests.single;
      expect(req.method, 'POST');
      expect(req.path, '/events');
      expect(req.auth, 'Bearer tok');
      expect(req.body['summary'], 'Dentist');
      expect(req.body['description'], 'bring x-rays');
      expect(req.body['start'], {'date': '2026-08-01'});
      expect(req.body['end'], {'date': '2026-08-02'});
      expect(req.body['extendedProperties'], {
        'private': {'taskrId': id}
      });
      expect(req.body.containsKey('recurrence'), isFalse);

      final stored = await env.col('tasks').doc('2026-08-01').collection('items').doc(id).get();
      expect(stored.data()!['calendarEventId'], 'evt-1');
    });

    test('patches an existing event without rewriting the task', () async {
      await service.sendTaskToCalendar(task(eventId: 'evt-9'));
      final req = stub.requests.single;
      expect(req.method, 'PATCH');
      expect(req.path, '/events/evt-9');
      expect(req.body.containsKey('description'), isFalse);
      expect(req.body['extendedProperties']['private']['taskrId'], 't1');
    });

    test('a task with no id sends an empty taskrId', () async {
      await service.sendTaskToCalendar(task(id: null, eventId: 'evt-9'));
      expect(stub.requests.single.body['extendedProperties']['private']['taskrId'], '');
    });

    test('rejects a task with no due date', () async {
      expect(() => service.sendTaskToCalendar(task(date: null)), throwsA(isA<Exception>()));
    });

    test('a non-2xx answer is an error', () async {
      stub.status = 403;
      stub.responseBody = 'nope';
      expect(() => service.sendTaskToCalendar(task(eventId: 'evt-9')), throwsA(isA<Exception>()));
    });

    test('a server error is rejected even when its body looks like an event', () async {
      stub.status = 500;
      await expectLater(
        service.sendTaskToCalendar(task(eventId: 'evt-9')),
        throwsA(predicate((e) => e.toString().contains('Calendar API 500'))),
      );
      expect((await env.col('tasks').doc('2026-08-01').collection('items').doc('t1').get()).exists, isFalse);
    });

    test('a 300 is outside the success range', () async {
      stub.status = 300;
      await expectLater(
        service.sendTaskToCalendar(task(eventId: 'evt-9')),
        throwsA(predicate((e) => e.toString().contains('Calendar API 300'))),
      );
    });

    test('falls back to an interactive sign-in for the access token', () async {
      env.google.silent[GoogleSignInProfile.calendar] = null;
      await service.sendTaskToCalendar(task(eventId: 'evt-9'));
      expect(stub.requests.single.auth, 'Bearer cal-at');
      expect(env.google.log, ['silent:calendar', 'signIn:calendar']);
    });

    test('throws when no session can be established', () async {
      env.google.silent[GoogleSignInProfile.calendar] = null;
      env.google.interactive[GoogleSignInProfile.calendar] = null;
      expect(() => service.sendTaskToCalendar(task(eventId: 'evt-9')), throwsA(isA<Exception>()));
    });

    group('recurrence', () {
      Future<String> seedTemplate(RecurringTask t) async {
        final ref = await env.col('recurring').add(t.toJson()..remove('id'));
        return ref.id;
      }

      Future<List<dynamic>?> recurrenceFor(RecurringTask t) async {
        final id = await seedTemplate(t);
        await service.sendTaskToCalendar(task(eventId: 'evt-9', template: id));
        return stub.requests.last.body['recurrence'] as List<dynamic>?;
      }

      test('daily with an interval and an end date', () async {
        final rr = await recurrenceFor(RecurringTask(
          recurrenceType: 'Daily',
          frequency: 2,
          endDate: DateTime.utc(2026, 12, 31, 12),
        ));
        expect(rr, ['RRULE:FREQ=DAILY;INTERVAL=2;UNTIL=20261231T235959Z']);
      });

      test('weekly with selected days', () async {
        final rr = await recurrenceFor(RecurringTask(
          recurrenceType: 'weekly',
          daysOfWeek: {'Su': true, 'Mo': true, 'Tu': true, 'We': true, 'Th': true, 'Fr': true, 'Sa': true, 'Xx': true},
        ));
        expect(rr, ['RRULE:FREQ=WEEKLY;BYDAY=SU,MO,TU,WE,TH,FR,SA']);
      });

      test('weekly with no days selected', () async {
        final rr = await recurrenceFor(RecurringTask(recurrenceType: 'Weekly', daysOfWeek: {'Mo': false}));
        expect(rr, ['RRULE:FREQ=WEEKLY']);
      });

      test('weekly with a null day map', () async {
        final rr = await recurrenceFor(RecurringTask(recurrenceType: 'Weekly'));
        expect(rr, ['RRULE:FREQ=WEEKLY']);
      });

      test('monthly on a day of the month', () async {
        final rr = await recurrenceFor(RecurringTask(recurrenceType: 'Monthly', dayOfMonth: 15));
        expect(rr, ['RRULE:FREQ=MONTHLY;BYMONTHDAY=15']);
      });

      test('monthly with the stored defaults', () async {
        // A template read back from Firestore always carries a day of month
        // (the parser defaults it to 1) and a frequency of 1.
        final rr = await recurrenceFor(RecurringTask(recurrenceType: 'Monthly', dayOfMonth: null, frequency: null));
        expect(rr, ['RRULE:FREQ=MONTHLY;BYMONTHDAY=1']);
      });

      test('an unknown cadence sends no recurrence', () async {
        expect(await recurrenceFor(RecurringTask(recurrenceType: 'Yearly')), isNull);
      });

      test('a missing template sends no recurrence', () async {
        await service.sendTaskToCalendar(task(eventId: 'evt-9', template: 'gone'));
        expect(stub.requests.single.body.containsKey('recurrence'), isFalse);
      });
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';

const _calendarEventsUrl = 'https://www.googleapis.com/calendar/v3/calendars/primary/events';

class CalendarService {
  CalendarService._internal();
  static final _instance = CalendarService._internal();
  factory CalendarService() => _instance;

  final _db = FirebaseFirestore.instance;
  final _functions = FirebaseFunctions.instance;
  final _taskService = TaskService();

  Stream<bool> watchConnected(String userId) {
    return _db.collection('todos').doc(userId).snapshots().map((snap) {
      final data = snap.data();
      return data != null && data['calendarConnectedAt'] != null;
    });
  }

  Future<DateTime?> connectedAt(String userId) async {
    final snap = await _db.collection('todos').doc(userId).get();
    final raw = snap.data()?['calendarConnectedAt'];
    if (raw is Timestamp) return raw.toDate();
    return null;
  }

  Future<void> connect() async {
    final consent = await AuthService().requestCalendarConsent();
    if (consent == null) {
      throw Exception('Connection cancelled');
    }
    final callable = _functions.httpsCallable('exchangeCalendarAuthCode');
    await callable.call<Map<String, dynamic>>({
      'code': consent.serverAuthCode,
    });
  }

  Future<void> disconnect() async {
    final callable = _functions.httpsCallable('disconnectCalendar');
    try {
      await callable.call();
    } finally {
      await AuthService().revokeCalendarConsent();
    }
  }

  Future<String> sendTaskToCalendar(Task task) async {
    if (task.dueDate == null) {
      throw Exception('Task has no due date');
    }
    final accessToken = await _getAccessToken();
    final eventBody = await _buildEventBody(task);

    final existingId = task.calendarEventId;
    final uri = existingId != null
        ? Uri.parse('$_calendarEventsUrl/$existingId')
        : Uri.parse(_calendarEventsUrl);

    final client = HttpClient();
    try {
      final request = existingId != null
          ? await client.openUrl('PATCH', uri)
          : await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.headers.set('Authorization', 'Bearer $accessToken');
      request.write(jsonEncode(eventBody));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Calendar API ${response.statusCode}: $body');
      }
      final data = jsonDecode(body) as Map<String, dynamic>;
      final eventId = data['id'] as String;

      if (existingId == null) {
        await _taskService.updateTaskByKey({'calendarEventId': eventId}, task);
      }
      return eventId;
    } finally {
      client.close();
    }
  }

  Future<String> _getAccessToken() async {
    final silent = await AuthService().getCalendarAccessToken(silent: true);
    if (silent != null) return silent;
    final interactive = await AuthService().getCalendarAccessToken(silent: false);
    if (interactive == null) {
      throw Exception('Calendar not connected — please reconnect in Settings');
    }
    return interactive;
  }

  Future<Map<String, dynamic>> _buildEventBody(Task task) async {
    final dueDate = task.dueDate!;
    final start = DateService().getDate(dueDate);
    final end = start.add(const Duration(days: 1));
    final body = <String, dynamic>{
      'summary': task.title,
      if (task.description != null && task.description!.isNotEmpty)
        'description': task.description,
      'start': {'date': _yyyyMmDd(start)},
      'end': {'date': _yyyyMmDd(end)},
      'extendedProperties': {
        'private': {
          'taskrId': task.id ?? '',
        },
      },
    };

    final rrule = await _rruleFor(task);
    if (rrule != null) {
      body['recurrence'] = [rrule];
    }

    return body;
  }

  Future<String?> _rruleFor(Task task) async {
    if (task.recurringTemplateId == null) return null;
    try {
      final template = await _taskService.getRecurringTemplate(task.recurringTemplateId!);
      return _rruleFromTemplate(template);
    } catch (e) {
      debugPrint('Could not load recurring template: $e');
      return null;
    }
  }

  static String? _rruleFromTemplate(RecurringTask t) {
    final parts = <String>[];
    final type = t.recurrenceType.toLowerCase();
    switch (type) {
      case 'daily':
        parts.add('FREQ=DAILY');
        break;
      case 'weekly':
        parts.add('FREQ=WEEKLY');
        final days = (t.daysOfWeek ?? const <String, bool>{})
            .entries
            .where((e) => e.value)
            .map((e) => _dayCodeToRrule(e.key))
            .whereType<String>()
            .toList();
        if (days.isNotEmpty) {
          parts.add('BYDAY=${days.join(",")}');
        }
        break;
      case 'monthly':
        parts.add('FREQ=MONTHLY');
        if (t.dayOfMonth != null) {
          parts.add('BYMONTHDAY=${t.dayOfMonth}');
        }
        break;
      default:
        return null;
    }

    final interval = t.frequency ?? 1;
    if (interval > 1) {
      parts.add('INTERVAL=$interval');
    }

    if (t.endDate != null) {
      final until = t.endDate!.toUtc();
      final s = '${until.year.toString().padLeft(4, '0')}'
          '${until.month.toString().padLeft(2, '0')}'
          '${until.day.toString().padLeft(2, '0')}'
          'T235959Z';
      parts.add('UNTIL=$s');
    }

    return 'RRULE:${parts.join(";")}';
  }

  static String? _dayCodeToRrule(String code) {
    switch (code) {
      case 'Su':
        return 'SU';
      case 'Mo':
        return 'MO';
      case 'Tu':
        return 'TU';
      case 'We':
        return 'WE';
      case 'Th':
        return 'TH';
      case 'Fr':
        return 'FR';
      case 'Sa':
        return 'SA';
    }
    return null;
  }

  static String _yyyyMmDd(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
}

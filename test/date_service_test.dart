import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/date.service.dart';

void main() {
  final ds = DateService();

  group('DateService.isTimeLessThan', () {
    test('earlier hour is less', () {
      expect(ds.isTimeLessThan(const TimeOfDay(hour: 9, minute: 0), const TimeOfDay(hour: 11, minute: 0)), isTrue);
    });
    test('same hour, earlier minute is less', () {
      expect(ds.isTimeLessThan(const TimeOfDay(hour: 9, minute: 15), const TimeOfDay(hour: 9, minute: 30)), isTrue);
    });
    test('equal times are not less', () {
      expect(ds.isTimeLessThan(const TimeOfDay(hour: 9, minute: 0), const TimeOfDay(hour: 9, minute: 0)), isFalse);
    });
    test('later is not less', () {
      expect(ds.isTimeLessThan(const TimeOfDay(hour: 14, minute: 0), const TimeOfDay(hour: 9, minute: 0)), isFalse);
    });
  });

  group('DateService.getTime', () {
    test('parses 24h db format', () {
      final time = ds.getTime('13:45');
      expect(time.hour, 13);
      expect(time.minute, 45);
    });
  });

  group('DateService date math', () {
    test('increment/decrement round-trip', () {
      final start = ds.getDate('2026-08-01');
      final next = ds.incrementDate(start); // '2026-08-02'
      expect(next, '2026-08-02');
      expect(ds.decrementDate(ds.getDate(next)), '2026-08-01');
    });

    test('increment rolls over month end', () {
      expect(ds.incrementDate(ds.getDate('2026-08-31')), '2026-09-01');
    });

    test('isDateLessThan compares chronologically', () {
      expect(ds.isDateLessThan('2026-08-01', '2026-08-02'), isTrue);
      expect(ds.isDateLessThan('2026-08-02', '2026-08-01'), isFalse);
    });
  });
}

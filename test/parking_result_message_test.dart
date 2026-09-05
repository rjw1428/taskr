import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/parking_notifications.dart';

void main() {
  group('parkingResultMessage', () {
    test('prefers the wording the service composed', () {
      final message = parkingResultMessage({
        'status': 'paid',
        'title': 'Parking paid',
        'body': '\$2.00 at SOMERT (Somerton Station) for ZXC9751, until 2:00 AM.',
      });

      expect(message.title, 'Parking paid');
      expect(message.body, contains('\$2.00'));
      expect(message.body, contains('ZXC9751'));
      expect(message.body, contains('2:00 AM'));
    });

    test('keeps the notification and the inbox entry identical', () {
      // Android draws the notification block itself when the app is
      // backgrounded; the inbox entry is rendered from data. Both must say the
      // same thing or the record contradicts the notification it mirrors.
      const body = 'ZXC9751 is already covered until 2:00 AM. Nothing bought.';
      final message = parkingResultMessage({
        'status': 'skipped',
        'title': 'Parking already active',
        'body': body,
      });

      expect(message.body, body);
    });

    // Older pushes, and anything that loses the composed text, still have to
    // produce something truthful rather than an empty notification.
    test('falls back to status wording when no text is sent', () {
      final message = parkingResultMessage({'status': 'paid'});

      expect(message.title, 'Parking paid');
      expect(message.body, isNotEmpty);
    });

    test('falls back when the sent text is empty', () {
      final message = parkingResultMessage({
        'status': 'skipped',
        'title': '',
        'body': '',
      });

      expect(message.title, 'Parking already active');
      expect(message.body, isNotEmpty);
    });

    test('an unknown status never claims anything was charged', () {
      final message = parkingResultMessage({'status': 'something-new'});

      expect(message.title, 'Parking failed');
      expect(message.body.toLowerCase(), contains('nothing was charged'));
    });
  });
}

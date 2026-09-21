import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/push_gateway.dart';

import 'helpers/harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => PushGateway.override = null);

  test('an installed override is what instance resolves to', () {
    final fake = FakePushGateway();
    PushGateway.override = fake;
    expect(identical(PushGateway.instance, fake), isTrue);
  });

  test('without an override the Firebase gateway is shared and needs a Firebase app', () async {
    final gateway = PushGateway.instance;
    expect(identical(gateway, PushGateway.instance), isTrue);
    // No Firebase app exists under `flutter test`, so every call that reaches
    // FirebaseMessaging.instance fails; the static streams need no app.
    expect(() => gateway.requestPermission(), throwsA(anything));
    expect(() => gateway.getToken(), throwsA(anything));
    expect(() => gateway.onTokenRefresh, throwsA(anything));
    expect(() => gateway.getInitialMessage(), throwsA(anything));
    expect(() => gateway.setAutoInitEnabled(true), throwsA(anything));
    expect(gateway.onMessage, isNotNull);
    expect(gateway.onMessageOpenedApp, isNotNull);
  });
}

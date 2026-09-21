import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/firebase_refs.dart';

import 'helpers/harness.dart';

void main() {
  tearDown(FirebaseRefs.reset);

  test('overrides are what the getters return', () async {
    final db = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth();
    FirebaseRefs.override(firestore: db, auth: auth, callFunction: (name, payload) async => '$name:$payload');
    expect(identical(FirebaseRefs.firestore, db), isTrue);
    expect(identical(FirebaseRefs.auth, auth), isTrue);
    expect(await FirebaseRefs.callFunction('ping', 1), 'ping:1');
    expect(await FirebaseRefs.callFunction('ping'), 'ping:null');
  });

  test('a partial override leaves the other handles alone', () async {
    final db = FakeFirebaseFirestore();
    FirebaseRefs.override(firestore: db);
    FirebaseRefs.override(auth: MockFirebaseAuth());
    expect(identical(FirebaseRefs.firestore, db), isTrue);
  });

  test('reset drops the overrides so the real instances are resolved', () {
    FirebaseRefs.override(firestore: FakeFirebaseFirestore(), auth: MockFirebaseAuth());
    FirebaseRefs.reset();
    // No Firebase app exists under `flutter test`, so falling through to the
    // real handle is what proves the override is gone.
    expect(() => FirebaseRefs.firestore, throwsA(anything));
    expect(() => FirebaseRefs.auth, throwsA(anything));
    expect(FirebaseRefs.callFunction('ping'), throwsA(anything));
  });
}

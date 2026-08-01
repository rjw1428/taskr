import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/services.dart';

void main() {
  late FakeFirebaseFirestore fake;

  setUp(() {
    fake = FakeFirebaseFirestore();
    AuthService().db = fake;
    AuthService().user = MockUser(uid: 'newbie', email: 'n@example.com');
  });

  test('ensureUserDoc provisions a new user with currentScore 0', () async {
    await AuthService().ensureUserDoc();
    final doc = await fake.collection('todos').doc('newbie').get();
    expect(doc.exists, isTrue);
    expect(doc.data()!['currentScore'], 0);
    expect(doc.data()!['email'], 'n@example.com');
  });

  test('ensureUserDoc never overwrites an existing user (no score reset)', () async {
    await fake.collection('todos').doc('newbie').set({'currentScore': 42});
    await AuthService().ensureUserDoc();
    final doc = await fake.collection('todos').doc('newbie').get();
    expect(doc.data()!['currentScore'], 42);
  });

  test('ensureUserDoc is a no-op with no signed-in user', () async {
    AuthService().user = null;
    await AuthService().ensureUserDoc();
    final snap = await fake.collection('todos').get();
    expect(snap.docs, isEmpty);
  });
}

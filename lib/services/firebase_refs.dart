import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Signature of a Cloud Functions call: the callable's name and its payload,
/// resolving to the callable's `data`.
typedef CloudCall = Future<dynamic> Function(String name, dynamic payload);

/// The one place the app resolves its Firebase handles.
///
/// Production code reads [firestore], [auth] and [callFunction]; nothing else
/// touches `FirebaseFirestore.instance` and friends directly. Tests swap all
/// three with [override] before the first read, so every service and screen
/// runs against `fake_cloud_firestore` / `firebase_auth_mocks` without Firebase
/// ever being initialized in the test process. Production never sets an
/// override, so the getters cost one null check.
class FirebaseRefs {
  FirebaseRefs._();

  static FirebaseFirestore? _firestore;
  static FirebaseAuth? _auth;
  static CloudCall? _call;

  static FirebaseFirestore get firestore => _firestore ?? FirebaseFirestore.instance;
  static FirebaseAuth get auth => _auth ?? FirebaseAuth.instance;

  /// Invokes the callable [name] with [payload] and returns its `data`.
  static Future<dynamic> callFunction(String name, [dynamic payload]) async {
    final call = _call;
    if (call != null) return call(name, payload);
    final result = await FirebaseFunctions.instance.httpsCallable(name).call(payload);
    return result.data;
  }

  @visibleForTesting
  static void override({FirebaseFirestore? firestore, FirebaseAuth? auth, CloudCall? callFunction}) {
    if (firestore != null) _firestore = firestore;
    if (auth != null) _auth = auth;
    if (callFunction != null) _call = callFunction;
  }

  @visibleForTesting
  static void reset() {
    _firestore = null;
    _auth = null;
    _call = null;
  }
}

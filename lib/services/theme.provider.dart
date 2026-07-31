import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Holds the app's [ThemeMode] and persists the user's choice.
///
/// Defaults to [ThemeMode.system] (follow the OS) until the user overrides it
/// from Settings. The choice is stored per-user in Firestore at
/// `todos/{uid}/settings/preferences` (covered by the existing owner-only
/// security rule), so it survives restarts and follows the account across
/// devices. Reverts to System when signed out.
class ThemeProvider extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _docSub;

  ThemeProvider() {
    _authSub = _auth.authStateChanges().listen(_onAuth);
    _onAuth(_auth.currentUser);
  }

  DocumentReference<Map<String, dynamic>> _ref(String uid) =>
      _db.collection('todos').doc(uid).collection('settings').doc('preferences');

  void _onAuth(User? user) {
    _docSub?.cancel();
    if (user == null) {
      _setMode(ThemeMode.system);
      return;
    }
    _docSub = _ref(user.uid).snapshots().listen((snap) {
      final stored = snap.data()?['themeMode'] as String?;
      _setMode(ThemeMode.values.firstWhere(
        (m) => m.name == stored,
        orElse: () => ThemeMode.system,
      ));
    }, onError: (_) {/* keep current mode on read error */});
  }

  void _setMode(ThemeMode mode) {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
  }

  /// Persist and apply the user's appearance choice. Updates immediately, then
  /// writes to Firestore (the snapshot listener will confirm it).
  Future<void> setMode(ThemeMode mode) async {
    _setMode(mode);
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await _ref(user.uid).set({'themeMode': mode.name}, SetOptions(merge: true));
    } catch (_) {
      // Write failed (e.g. offline); the in-memory choice still applies and
      // will re-sync on the next successful write.
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _docSub?.cancel();
    super.dispose();
  }
}

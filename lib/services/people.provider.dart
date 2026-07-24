import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/people.service.dart';

class PeopleProvider extends ChangeNotifier {
  final PeopleService _service = PeopleService();
  StreamSubscription<List<Person>>? _subscription;

  List<Person> _people = [];
  List<Person> get people => _people;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  PeopleProvider() {
    _initializePeople();
  }

  // The Firestore snapshot stream is the single source of truth for [_people].
  // Mutation methods below only perform the write; the resulting snapshot flows
  // back through this listener and updates the list exactly once. (Mutating
  // _people directly in those methods as well caused duplicate/stale entries,
  // because latency compensation delivers the write through here too.)
  void _initializePeople() {
    _isLoading = true;
    notifyListeners();

    _subscription = _service.getPeople().listen((people) {
      _people = people;
      _isLoading = false;
      _error = null;
      notifyListeners();
    }, onError: (error) {
      _error = error.toString();
      _isLoading = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> addPerson(Person person) async {
    await _service.addPerson(person);
  }

  Future<void> updatePerson(Person person) async {
    await _service.updatePerson(person.id!, person);
  }

  Future<void> deletePerson(String personId) async {
    await _service.deletePerson(personId);
  }

  Future<void> addLog(String personId, ConversationLog log) async {
    await _service.addLog(personId, log);
  }

  Future<void> updateLog(String personId, String logId, ConversationLog log) async {
    await _service.updateLog(personId, logId, log);
  }

  Future<void> deleteLog(String personId, String logId) async {
    await _service.deleteLog(personId, logId);
  }
}

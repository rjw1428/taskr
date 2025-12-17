import 'package:flutter/material.dart';
import 'package:taskr/services/accomplishment.service.dart';
import 'package:taskr/services/models.dart';

class AccomplishmentProvider with ChangeNotifier {
  final AccomplishmentService _accomplishmentService = AccomplishmentService();
  List<Accomplishment> _accomplishments = [];

  List<Accomplishment> get accomplishments => _accomplishments;

  AccomplishmentProvider() {
    _accomplishmentService.getAccomplishments().listen((accomplishments) {
      _accomplishments = accomplishments;
      notifyListeners();
    });
  }

  Future<void> addAccomplishment(Accomplishment accomplishment) {
    return _accomplishmentService.addAccomplishment(accomplishment);
  }

  Future<void> updateAccomplishment(Accomplishment accomplishment) {
    return _accomplishmentService.updateAccomplishment(accomplishment);
  }

  Future<void> deleteAccomplishment(String accomplishmentId) {
    return _accomplishmentService.deleteAccomplishment(accomplishmentId);
  }
}

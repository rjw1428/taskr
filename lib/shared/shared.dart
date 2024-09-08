export 'loading.dart';
export 'error.dart';
export 'bottom_nav.dart';
export 'constants.dart';

Map<String, dynamic> removeNulls(Map<String, dynamic> obj) {
  obj.removeWhere((key, value) => value == null || value == '');
  return obj;
}

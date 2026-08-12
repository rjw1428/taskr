export 'loading.dart';
export 'error.dart';
export 'error_reporting.dart';
export 'write_ack.dart';
export 'constants.dart';
export 'design/tokens.dart';
export 'design/motion.dart';
export 'design/components.dart';

Map<String, dynamic> removeNulls(Map<String, dynamic> obj) {
  obj.removeWhere((key, value) => value == null || value == '');
  return obj;
}

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/firebase_options.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('resolves the options for each supported platform', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(DefaultFirebaseOptions.currentPlatform, DefaultFirebaseOptions.android);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(DefaultFirebaseOptions.currentPlatform, DefaultFirebaseOptions.ios);
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(DefaultFirebaseOptions.currentPlatform, DefaultFirebaseOptions.macos);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(DefaultFirebaseOptions.currentPlatform, DefaultFirebaseOptions.windows);
  });

  test('every platform points at the same project', () {
    for (final o in [
      DefaultFirebaseOptions.web,
      DefaultFirebaseOptions.android,
      DefaultFirebaseOptions.ios,
      DefaultFirebaseOptions.macos,
      DefaultFirebaseOptions.windows,
    ]) {
      expect(o.projectId, 'taskr-1428');
      expect(o.messagingSenderId, '1070956843093');
    }
  });

  test('unconfigured platforms throw', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(() => DefaultFirebaseOptions.currentPlatform, throwsUnsupportedError);
    debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
    expect(() => DefaultFirebaseOptions.currentPlatform, throwsUnsupportedError);
  });
}

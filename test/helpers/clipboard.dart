import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Captures Clipboard.setData calls; the last text is in [text].
class ClipboardSpy {
  String? text;
  int calls = 0;

  ClipboardSpy(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        calls++;
        text = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:taskr/about/about.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  setUp(() async {
    PackageInfo.setMockInitialValues(
      appName: 'taskr',
      packageName: 'com.example.taskr',
      version: '9.8.7',
      buildNumber: '42',
      buildSignature: '',
    );
    env = await TestEnv.create();
  });
  tearDown(() => env.dispose());

  testWidgets('shows the app name, version and commit', (tester) async {
    await pumpApp(tester, const AboutPage());
    expect(find.text('About'), findsOneWidget);
    expect(find.text(AboutPage.appName), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Version: 9.8.7+42'), findsOneWidget);
    expect(find.text('Commit: ${AboutPage.appCommit}'), findsOneWidget);
  });
}

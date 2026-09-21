import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/about/about.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  setUp(() async => env = await TestEnv.create());
  tearDown(() => env.dispose());

  testWidgets('shows the app name, version and commit', (tester) async {
    await pumpApp(tester, const AboutPage());
    expect(find.text('About'), findsOneWidget);
    expect(find.text(AboutPage.appName), findsOneWidget);
    expect(find.text('Version: ${AboutPage.appVersion}'), findsOneWidget);
    expect(find.text('Commit: ${AboutPage.appCommit}'), findsOneWidget);
  });
}

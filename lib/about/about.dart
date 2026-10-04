import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:taskr/shared/shared.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const appName = 'taskr';

  /// Injected at build time by `tool/flutterw.sh` (`--dart-define=GIT_COMMIT=`).
  static const appCommit =
      String.fromEnvironment('GIT_COMMIT', defaultValue: 'dev');

  /// Reads `version+build` from the built app (sourced from pubspec.yaml).
  static Future<String> loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.buildNumber.isEmpty
        ? info.version
        : '${info.version}+${info.buildNumber}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.appTokens;
    return ContentColumn(child: Scaffold(
      appBar: AppBar(
        title: const Text('About'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              appName,
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: Insets.sm),
            FutureBuilder<String>(
              future: loadVersion(),
              builder: (context, snapshot) => Text(
                'Version: ${snapshot.data ?? ''}',
                style:
                    theme.textTheme.titleMedium?.copyWith(color: t.textMuted),
              ),
            ),
            const SizedBox(height: Insets.sm),
            Text(
              'Commit: $appCommit',
              style: theme.textTheme.titleMedium?.copyWith(color: t.textMuted),
            ),
          ],
        ),
      ),
    ));
  }
}

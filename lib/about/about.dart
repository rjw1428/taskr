import 'package:flutter/material.dart';
import 'package:taskr/shared/shared.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const appName = 'taskr';
  static const appVersion = '1.1.0+3';
  static const appCommit = '071eabb';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.appTokens;
    return Scaffold(
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
            Text(
              'Version: $appVersion',
              style: theme.textTheme.titleMedium?.copyWith(color: t.textMuted),
            ),
            const SizedBox(height: Insets.sm),
            Text(
              'Commit: $appCommit',
              style: theme.textTheme.titleMedium?.copyWith(color: t.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

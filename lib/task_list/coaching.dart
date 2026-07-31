import 'package:flutter/material.dart';
import 'package:taskr/shared/shared.dart';

class CoachingDialog extends StatelessWidget {
  final String response;
  const CoachingDialog({super.key, required this.response});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
        padding: const EdgeInsets.all(Insets.xl),
        child: Material(
            color: Colors.transparent,
            child: Center(
                child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(Corners.md),
                    ),
                    child: Padding(
                        padding: const EdgeInsets.all(Insets.xl),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Words from your coach',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.headlineMedium),
                            const SizedBox(height: Insets.md),
                            Text(response, style: theme.textTheme.bodyLarge),
                            const SizedBox(height: Insets.md),
                            ElevatedButton(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                },
                                child: const Text('Close'))
                          ],
                        ))))));
  }
}

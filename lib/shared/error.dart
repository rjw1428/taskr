import 'package:flutter/material.dart';
import 'package:taskr/shared/design/tokens.dart';

class ErrorMessage extends StatelessWidget {
  final String message;
  const ErrorMessage({super.key, this.message = ''});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(Insets.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withAlpha(25),
        borderRadius: BorderRadius.circular(Corners.md),
      ),
      child: Text(
        message,
        style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.error),
      ),
    );
  }
}

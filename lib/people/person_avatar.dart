import 'package:flutter/material.dart';
import 'package:taskr/shared/shared.dart';

String personInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();
  return (parts.first.characters.first + parts[1].characters.first).toUpperCase();
}

/// Accent-tinted rounded avatar showing a person's initials.
class PersonAvatar extends StatelessWidget {
  final String name;
  final double size;

  const PersonAvatar({super.key, required this.name, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, Color.alphaBlend(accent.withAlpha(140), theme.colorScheme.surface)],
        ),
        borderRadius: BorderRadius.circular(size < 40 ? Corners.sm : Corners.md),
      ),
      child: Text(
        personInitials(name),
        style: (size < 40 ? theme.textTheme.labelLarge : theme.textTheme.titleMedium)?.copyWith(
          color: theme.colorScheme.onPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

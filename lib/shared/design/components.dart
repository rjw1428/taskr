import 'package:flutter/material.dart';
import 'package:taskr/shared/design/tokens.dart';

/// Reusable, themed building blocks for the redesign. Screens compose from
/// these instead of re-implementing chrome, so everything tracks the active
/// light/dark theme and tokens automatically.

/// An elevated surface container — the default card for content sections.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final double radius;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Insets.lg),
    this.onTap,
    this.color,
    this.radius = Corners.lg,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.appTokens;
    final shape = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? theme.colorScheme.surface,
        borderRadius: shape,
        border: Border.all(color: t.hairline),
        boxShadow: t.raisedShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: shape,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// A small uppercase section label with an optional trailing widget.
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const SectionHeader(this.title, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(Insets.xs, Insets.lg, Insets.xs, Insets.sm)});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 1.6,
                color: theme.appTokens.textMuted,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Primary call-to-action. Full-width by default.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  const PrimaryButton(this.label, {super.key, this.onPressed, this.icon, this.expand = true});

  @override
  Widget build(BuildContext context) {
    final btn = icon != null
        ? FilledButton.icon(onPressed: onPressed, icon: Icon(icon, size: 18), label: Text(label))
        : FilledButton(onPressed: onPressed, child: Text(label));
    return expand ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

/// Secondary action — outlined, quiet.
class SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  const SecondaryButton(this.label, {super.key, this.onPressed, this.icon, this.expand = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = OutlinedButton.styleFrom(
      foregroundColor: theme.colorScheme.onSurface,
      side: BorderSide(color: theme.appTokens.hairline),
      textStyle: theme.textTheme.labelLarge,
      padding: const EdgeInsets.symmetric(horizontal: Insets.xl, vertical: Insets.md),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corners.md)),
    );
    final btn = icon != null
        ? OutlinedButton.icon(onPressed: onPressed, icon: Icon(icon, size: 18), label: Text(label), style: style)
        : OutlinedButton(onPressed: onPressed, style: style, child: Text(label));
    return expand ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

/// A centered empty-state: icon, message, and an optional action.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Insets.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: theme.appTokens.textFaint),
            const SizedBox(height: Insets.lg),
            Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
            if (message != null) ...[
              const SizedBox(height: Insets.sm),
              Text(message!, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
            ],
            if (action != null) ...[const SizedBox(height: Insets.xl), action!],
          ],
        ),
      ),
    );
  }
}

/// A bottom-sheet shell: rounded top, a grab handle, and a scroll-safe body
/// that lifts above the keyboard. Wrap modal content in this for consistency.
class AppBottomSheet extends StatelessWidget {
  final Widget child;
  final String? title;
  final EdgeInsetsGeometry padding;

  const AppBottomSheet({
    super.key,
    required this.child,
    this.title,
    this.padding = const EdgeInsets.fromLTRB(Insets.lg, Insets.sm, Insets.lg, Insets.lg),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Corners.rMd),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: Insets.md, bottom: Insets.xs),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.appTokens.textFaint.withAlpha(90),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.sm, Insets.lg, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(title!, style: theme.textTheme.titleLarge),
                  ),
                ),
              Flexible(child: Padding(padding: padding, child: child)),
            ],
          ),
        ),
      ),
    );
  }
}

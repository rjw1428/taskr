import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/shared/shared.dart';

class DividerItem extends StatelessWidget {
  final Task divider;
  final int index;
  final Function(Task) onDelete;

  const DividerItem({
    super.key,
    required this.divider,
    required this.index,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.appTokens;
    final hasLabel = divider.title.isNotEmpty;
    return SizedBox(
      height: 32,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Insets.sm),
        child: Row(
          children: [
            Expanded(child: Divider(color: t.hairline, thickness: 1)),
            if (hasLabel)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Insets.sm),
                child: Text(
                  divider.title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: t.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            if (hasLabel) Expanded(child: Divider(color: t.hairline, thickness: 1)),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onDelete(divider),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Insets.sm, vertical: Insets.xs),
                child: Icon(FontAwesomeIcons.xmark, size: 14, color: t.textFaint),
              ),
            ),
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Insets.xs),
                child: Icon(FontAwesomeIcons.gripLines, size: 16, color: t.textFaint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

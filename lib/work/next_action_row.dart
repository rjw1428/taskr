import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/shared/link_text.dart';
import 'package:taskr/shared/shared.dart';

/// One open next action. Actionable rows get a checkbox; waiting rows get an
/// hourglass, muted ink, and a "Waiting on X" line, and complete via the
/// overflow instead so a waiting step is not ticked off by accident. A
/// trailing thumbtack pins the action to the top of the Work page when
/// [onTogglePin] is provided.
class NextActionRow extends StatelessWidget {
  final NextAction action;
  final VoidCallback onComplete;
  final VoidCallback onEdit;
  final VoidCallback? onTogglePin;

  const NextActionRow({
    super.key,
    required this.action,
    required this.onComplete,
    required this.onEdit,
    this.onTogglePin,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.appTokens;
    final waiting = action.isWaiting;
    final ink = waiting ? t.textMuted : theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (waiting)
            Padding(
              padding: const EdgeInsets.only(top: 2, right: Insets.sm, left: 2),
              child: Icon(FontAwesomeIcons.hourglassHalf, key: const Key('waiting-glyph'), size: 16, color: t.textMuted),
            )
          else
            SizedBox(
              width: 28,
              height: 24,
              child: Checkbox(
                key: Key('complete-${action.id}'),
                value: false,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (_) => onComplete(),
              ),
            ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onEdit,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinkText(action.text, style: theme.textTheme.bodyMedium?.copyWith(color: ink)),
                  if (waiting)
                    Text(
                      'Waiting on ${action.waitingOn}',
                      style: theme.textTheme.bodySmall?.copyWith(color: t.textFaint, fontStyle: FontStyle.italic),
                    ),
                ],
              ),
            ),
          ),
          if (onTogglePin != null)
            SizedBox(
              width: 28,
              height: 28,
              child: IconButton(
                key: Key('pin-${action.id}'),
                padding: EdgeInsets.zero,
                iconSize: 14,
                tooltip: action.isPinned ? 'Unpin' : 'Pin to top',
                icon: Icon(
                  FontAwesomeIcons.thumbtack,
                  color: action.isPinned ? t.pinned.accent : t.textFaint.withValues(alpha: 0.5),
                ),
                onPressed: onTogglePin,
              ),
            ),
          if (waiting)
            SizedBox(
              width: 28,
              height: 28,
              child: PopupMenuButton<String>(
                key: Key('waiting-menu-${action.id}'),
                padding: EdgeInsets.zero,
                iconSize: 14,
                tooltip: 'Waiting options',
                icon: Icon(FontAwesomeIcons.ellipsisVertical, color: t.textFaint),
                onSelected: (v) {
                  if (v == 'done') onComplete();
                  if (v == 'edit') onEdit();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'done', child: Text('Mark done')),
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

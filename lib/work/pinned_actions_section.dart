import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/shared/link_text.dart';
import 'package:taskr/shared/shared.dart';
import 'package:taskr/work/work_actions.dart';
import 'package:taskr/work/work_logic.dart';

/// The pinned actions list at the top of the Work page: every open pinned
/// action across all priorities, oldest pin first, on violet cards so the
/// day's chosen actions stand apart from the board. Rows carry their own keys
/// ('pinned-*') because the same action is simultaneously visible on its
/// source card.
class PinnedActionsSection extends StatelessWidget {
  final List<WorkItem> items;
  final WorkActions actions;

  const PinnedActionsSection({super.key, required this.items, required this.actions});

  @override
  Widget build(BuildContext context) {
    final pairs = WorkLogic.pinnedActions(items);
    if (pairs.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final t = theme.appTokens;
    final pin = t.pinned;
    return Padding(
      key: const Key('pinned-section'),
      padding: const EdgeInsets.fromLTRB(Insets.md, Insets.sm, Insets.md, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: Insets.xs, bottom: Insets.xs),
            child: Row(
              children: [
                Icon(FontAwesomeIcons.thumbtack, size: 11, color: pin.accent),
                const SizedBox(width: Insets.sm),
                Text('Pinned', style: theme.textTheme.labelMedium?.copyWith(color: pin.accent)),
              ],
            ),
          ),
          for (final (item, action) in pairs)
            Padding(
              padding: const EdgeInsets.only(bottom: Insets.xs),
              child: _PinnedRow(item: item, action: action, actions: actions, color: pin),
            ),
        ],
      ),
    );
  }
}

class _PinnedRow extends StatelessWidget {
  final WorkItem item;
  final NextAction action;
  final WorkActions actions;
  final PriorityColor color;

  const _PinnedRow({required this.item, required this.action, required this.actions, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.appTokens;
    final waiting = action.isWaiting;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Insets.sm, vertical: Insets.xs),
      decoration: BoxDecoration(
        color: color.fill,
        border: Border.all(color: color.border),
        borderRadius: BorderRadius.circular(Corners.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (waiting)
            Padding(
              padding: const EdgeInsets.only(top: 2, right: Insets.sm, left: 2),
              child: Icon(FontAwesomeIcons.hourglassHalf,
                  key: Key('pinned-waiting-${action.id}'), size: 16, color: t.textMuted),
            )
          else
            SizedBox(
              width: 28,
              height: 24,
              child: Checkbox(
                key: Key('pinned-complete-${action.id}'),
                value: false,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (_) => actions.complete(context, item.id!, action),
              ),
            ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => actions.editNextAction(context, item.id!, action),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinkText(action.text, style: theme.textTheme.bodyMedium?.copyWith(color: color.ink)),
                  if (waiting)
                    Text(
                      'Waiting on ${action.waitingOn}',
                      style: theme.textTheme.bodySmall?.copyWith(color: t.textFaint, fontStyle: FontStyle.italic),
                    ),
                  Text(
                    item.title,
                    style: theme.textTheme.bodySmall?.copyWith(color: color.ink.withValues(alpha: 0.7)),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 28,
            height: 28,
            child: IconButton(
              key: Key('pinned-pin-${action.id}'),
              padding: EdgeInsets.zero,
              iconSize: 14,
              tooltip: 'Unpin',
              icon: Icon(FontAwesomeIcons.thumbtack, color: color.accent),
              onPressed: () => actions.togglePin(item.id!, action),
            ),
          ),
          if (waiting)
            SizedBox(
              width: 28,
              height: 28,
              child: PopupMenuButton<String>(
                key: Key('pinned-menu-${action.id}'),
                padding: EdgeInsets.zero,
                iconSize: 14,
                tooltip: 'Waiting options',
                icon: Icon(FontAwesomeIcons.ellipsisVertical, color: t.textFaint),
                onSelected: (v) {
                  if (v == 'done') actions.complete(context, item.id!, action);
                  if (v == 'edit') actions.editNextAction(context, item.id!, action);
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

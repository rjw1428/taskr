import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/shared/link_text.dart';
import 'package:taskr/shared/shared.dart';
import 'package:taskr/work/next_action_row.dart';
import 'package:taskr/work/work_actions.dart';
import 'package:taskr/work/work_detail_page.dart';
import 'package:taskr/work/work_item_form.dart';

/// One work item on the board: title, notes preview, open next actions, and
/// the controls that keep a priority moving.
class WorkItemCard extends StatelessWidget {
  final WorkItem item;
  final int index;
  final WorkActions actions;
  final VoidCallback onSendToBottom;

  const WorkItemCard({
    super.key,
    required this.item,
    required this.index,
    required this.actions,
    required this.onSendToBottom,
  });

  Future<void> _openEdit(BuildContext context) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => WorkItemForm(item: item, service: actions.service),
      );

  void _openDetail(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => WorkDetailPage(itemId: item.id!, archived: false, service: actions.service)),
      );

  Future<void> _onMenu(BuildContext context, String value) async {
    switch (value) {
      case 'edit':
        await _openEdit(context);
      case 'update':
        await actions.addUpdate(context, item.id!);
      case 'bottom':
        onSendToBottom();
      case 'archive':
        await actions.archive(item.id!);
      case 'delete':
        if (await actions.confirmDelete(context, item.title)) await actions.delete(item.id!, archived: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.appTokens;
    final open = item.openActions;
    final notes = item.notes.trim();
    return AppCard(
      padding: const EdgeInsets.fromLTRB(Insets.md, Insets.sm, Insets.xs, Insets.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _openDetail(context),
                  child: Padding(
                    padding: const EdgeInsets.only(top: Insets.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: LinkText(item.title, style: theme.textTheme.titleMedium)),
                            if (open.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(left: Insets.sm),
                                child: _NoNextActionBadge(key: Key('no-next-action-${item.id}')),
                              ),
                          ],
                        ),
                        if (notes.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: LinkText(
                              notes,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(color: t.textMuted),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 28,
                height: 28,
                child: PopupMenuButton<String>(
                  key: Key('item-menu-${item.id}'),
                  padding: EdgeInsets.zero,
                  iconSize: 16,
                  tooltip: 'Work item options',
                  icon: Icon(FontAwesomeIcons.ellipsisVertical, color: t.textFaint),
                  onSelected: (v) => _onMenu(context, v),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'update', child: Text('Add update')),
                    PopupMenuItem(value: 'bottom', child: Text('Send to bottom')),
                    PopupMenuItem(value: 'archive', child: Text('Archive')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ),
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Insets.sm, vertical: 6),
                  child: Icon(FontAwesomeIcons.gripLines, key: Key('drag-${item.id}'), size: 16, color: t.textFaint),
                ),
              ),
            ],
          ),
          if (open.isNotEmpty) ...[
            const SizedBox(height: Insets.xs),
            for (final a in open)
              NextActionRow(
                key: Key('action-${a.id}'),
                action: a,
                onComplete: () => actions.complete(context, item.id!, a),
                onEdit: () => actions.editNextAction(context, item.id!, a),
              ),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: Key('add-action-${item.id}'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: Insets.xs)),
              onPressed: () => actions.addNextAction(context, item.id!),
              icon: const Icon(FontAwesomeIcons.plus, size: 12),
              label: const Text('Next action'),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoNextActionBadge extends StatelessWidget {
  const _NoNextActionBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warn = theme.appTokens.priority[Effort.high]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Insets.sm, vertical: 2),
      decoration: BoxDecoration(
        color: warn.fill,
        border: Border.all(color: warn.border),
        borderRadius: BorderRadius.circular(Corners.sm),
      ),
      child: Text('No next action', style: theme.textTheme.labelSmall?.copyWith(color: warn.ink)),
    );
  }
}

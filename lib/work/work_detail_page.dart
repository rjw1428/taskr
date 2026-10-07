import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/work.service.dart';
import 'package:taskr/shared/link_text.dart';
import 'package:taskr/shared/shared.dart';
import 'package:taskr/work/next_action_row.dart';
import 'package:taskr/work/work_actions.dart';
import 'package:taskr/work/work_item_form.dart';
import 'package:taskr/work/work_logic.dart';

/// A work item's full picture: notes, open next actions, and the timeline of
/// everything that has happened to it. Archived items open read-mostly.
class WorkDetailPage extends StatefulWidget {
  final String itemId;
  final bool archived;
  final WorkService? service;

  const WorkDetailPage({super.key, required this.itemId, required this.archived, this.service});

  @override
  State<WorkDetailPage> createState() => _WorkDetailPageState();
}

class _WorkDetailPageState extends State<WorkDetailPage> {
  late final WorkService _service = widget.service ?? WorkService();
  late final WorkActions _actions = WorkActions(_service);
  late final Stream<WorkItem?> _stream = _service.streamOne(widget.itemId, archived: widget.archived);
  bool _popped = false;

  static final _stamp = DateFormat('MMM d, yyyy · h:mm a');

  Future<void> _onMenu(BuildContext context, WorkItem item, String value) async {
    switch (value) {
      case 'copy':
        await _actions.copyItem(context, item);
      case 'edit':
        await showAppSheet(
          context,
          builder: (_) => WorkItemForm(item: item, service: _service),
        );
      case 'update':
        await _actions.addUpdate(context, item.id!);
      case 'archive':
        await _actions.archive(item.id!);
        if (mounted) Navigator.of(this.context).pop();
      case 'restore':
        await _actions.restore(item.id!);
        if (mounted) Navigator.of(this.context).pop();
      case 'delete':
        if (await _actions.confirmDelete(context, item.title)) {
          await _actions.delete(item.id!, archived: widget.archived);
          if (mounted) Navigator.of(this.context).pop();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.appTokens;
    return StreamBuilder<WorkItem?>(
      stream: _stream,
      builder: (context, snapshot) {
        final item = snapshot.data;
        if (snapshot.connectionState == ConnectionState.waiting && item == null) {
          return const Scaffold(body: LoadingScreen());
        }
        if (item == null) {
          // Moved or deleted underneath us (e.g. archived from another device).
          if (!_popped) {
            _popped = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
            });
          }
          return const Scaffold(body: SizedBox.shrink());
        }
        final open = item.openActions;
        final timeline = WorkLogic.buildTimeline(item);
        return ContentColumn(child: Scaffold(
          appBar: AppBar(
            title: Text(widget.archived ? 'Archived work' : 'Work item'),
            actions: [
              if (widget.archived)
                TextButton(
                  key: const Key('detail-restore'),
                  onPressed: () => _onMenu(context, item, 'restore'),
                  child: const Text('Restore'),
                ),
              PopupMenuButton<String>(
                key: const Key('detail-menu'),
                onSelected: (v) => _onMenu(context, item, v),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'copy', child: Text('Copy as Markdown')),
                  if (!widget.archived) ...const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'update', child: Text('Add update')),
                    PopupMenuItem(value: 'archive', child: Text('Archive')),
                  ],
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(Insets.lg),
            children: [
              LinkText(item.title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: Insets.xs),
              Text(
                widget.archived && item.archivedAt != null
                    ? 'Archived ${_stamp.format(DateTime.fromMillisecondsSinceEpoch(item.archivedAt!))}'
                    : 'Created ${_stamp.format(DateTime.fromMillisecondsSinceEpoch(item.createdAt))}',
                style: theme.textTheme.bodySmall?.copyWith(color: t.textMuted),
              ),
              if (item.notes.trim().isNotEmpty) ...[
                const SectionHeader('Notes'),
                LinkText(item.notes.trim(), style: theme.textTheme.bodyMedium),
              ],
              SectionHeader(
                'Next actions',
                trailing: widget.archived
                    ? null
                    : IconButton(
                        key: const Key('detail-add-action'),
                        tooltip: 'Add next action',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(FontAwesomeIcons.plus, size: 14),
                        onPressed: () => _actions.addNextAction(context, item.id!),
                      ),
              ),
              if (open.isEmpty)
                Text(widget.archived ? 'None open' : 'No next action yet', style: theme.textTheme.bodySmall?.copyWith(color: t.textFaint))
              else if (widget.archived)
                for (final a in open)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Insets.xs),
                    child: LinkText(a.isWaiting ? '${a.text} (waiting on ${a.waitingOn})' : a.text, style: theme.textTheme.bodyMedium),
                  )
              else
                for (final a in open)
                  NextActionRow(
                    key: Key('detail-action-${a.id}'),
                    action: a,
                    onComplete: () => _actions.complete(context, item.id!, a),
                    onEdit: () => _actions.editNextAction(context, item.id!, a),
                    onTogglePin: () => _actions.togglePin(item.id!, a),
                  ),
              const SectionHeader('Timeline'),
              for (final e in timeline) _TimelineRow(event: e, stamp: _stamp),
              const SizedBox(height: Insets.xxl),
            ],
          ),
        ));
      },
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final WorkEvent event;
  final DateFormat stamp;
  const _TimelineRow({required this.event, required this.stamp});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.appTokens;
    final (icon, label, color) = switch (event.kind) {
      WorkEventKind.created => (FontAwesomeIcons.flag, 'Created', t.textMuted),
      WorkEventKind.actionAdded => (FontAwesomeIcons.plus, 'Next action added', t.textFaint),
      WorkEventKind.actionCompleted => (FontAwesomeIcons.check, 'Done', theme.colorScheme.primary),
      WorkEventKind.updateAdded => (FontAwesomeIcons.penToSquare, 'Update', theme.colorScheme.onSurface),
      WorkEventKind.archived => (FontAwesomeIcons.boxArchive, 'Archived', t.textMuted),
      WorkEventKind.restored => (FontAwesomeIcons.rotateLeft, 'Restored', t.textMuted),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 24, child: Icon(icon, size: 14, color: color)),
          const SizedBox(width: Insets.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$label · ${stamp.format(DateTime.fromMillisecondsSinceEpoch(event.at))}',
                  style: theme.textTheme.labelSmall?.copyWith(color: t.textMuted),
                ),
                if (event.text.isNotEmpty) LinkText(event.text, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

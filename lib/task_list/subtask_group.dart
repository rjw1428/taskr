import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/shared.dart';
import 'package:taskr/task_list/add_task.dart';

/// Backlog view of a parent task: a container card showing the parent's title,
/// an n/m progress indicator, and its subtasks nested beneath — including
/// children already scheduled to a date (shown with a date chip). Provides
/// add-subtask, assign-date (cascade), and delete-parent affordances.
class SubtaskGroupCard extends StatefulWidget {
  final Task parent;
  final List<Task> childTasks;
  final int index; // position in the reorderable list, for the drag handle
  final TaskService taskService;

  const SubtaskGroupCard({
    super.key,
    required this.parent,
    required this.childTasks,
    required this.index,
    required this.taskService,
  });

  @override
  State<SubtaskGroupCard> createState() => _SubtaskGroupCardState();
}

class _SubtaskGroupCardState extends State<SubtaskGroupCard> {
  bool _expanded = true;

  List<Task> get _sortedChildren {
    final list = [...widget.childTasks];
    // Incomplete first, then by due date (undated last), then title.
    list.sort((a, b) {
      if (a.completed != b.completed) return a.completed ? 1 : -1;
      final ad = a.dueDate, bd = b.dueDate;
      if (ad != bd) {
        if (ad == null) return 1;
        if (bd == null) return -1;
        return ad.compareTo(bd);
      }
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.appTokens;
    final p = t.of(widget.parent.priority);
    final children = _sortedChildren;
    final total = children.length;
    final done = children.where((c) => c.completed).length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: t.hairline),
        borderRadius: BorderRadius.circular(Corners.md),
        boxShadow: t.raisedShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Parent header
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: p.accent),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                      child: Row(
                        children: [
                          Icon(_expanded ? FontAwesomeIcons.chevronDown : FontAwesomeIcons.chevronRight,
                              size: 11, color: t.textFaint),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(widget.parent.title,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      decoration: widget.parent.completed ? TextDecoration.lineThrough : null,
                                    )),
                                const SizedBox(height: 3),
                                _ProgressPips(done: done, total: total, color: p.accent),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(FontAwesomeIcons.plus, size: 14),
                            tooltip: 'Add subtask',
                            visualDensity: VisualDensity.compact,
                            color: theme.colorScheme.primary,
                            onPressed: _addSubtask,
                          ),
                          _menu(context),
                          ReorderableDragStartListener(
                            index: widget.index,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              child: Icon(FontAwesomeIcons.gripLines, size: 16, color: t.textFaint),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_expanded && total > 0)
            Padding(
              padding: const EdgeInsets.only(left: 26, right: 8, bottom: 6),
              child: Column(children: children.map(_childRow).toList()),
            ),
          if (_expanded && total == 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(30, 0, 12, 12),
              child: Text('No steps yet — add one.', style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }

  Widget _childRow(Task child) {
    final theme = Theme.of(context);
    final t = theme.appTokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Checkbox(
              value: child.completed,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (v) => widget.taskService.toggleSubtaskComplete(child, v ?? false),
            ),
          ),
          Expanded(
            child: Text(
              child.title,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: child.completed ? t.textFaint : theme.colorScheme.onSurface,
                decoration: child.completed ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          if (child.dueDate != null)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withAlpha(30),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(_shortDate(child.dueDate!),
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary)),
            ),
          SizedBox(
            width: 32,
            child: PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              iconSize: 15,
              icon: Icon(FontAwesomeIcons.ellipsisVertical, color: t.textFaint),
              onSelected: (v) {
                if (v == 'schedule') {
                  _scheduleChild(child);
                } else if (v == 'unschedule') {
                  widget.taskService.scheduleSubtask(child, null);
                } else if (v == 'delete') {
                  widget.taskService.deleteSubtask(child);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'schedule', child: Text('Set date')),
                if (child.dueDate != null)
                  const PopupMenuItem(value: 'unschedule', child: Text('Move to backlog')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _menu(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Icon(FontAwesomeIcons.ellipsisVertical, size: 15, color: Theme.of(context).appTokens.textFaint),
      onSelected: (v) {
        if (v == 'edit') {
          showModalBottomSheet(
            useSafeArea: true,
            isScrollControlled: true,
            context: context,
            builder: (_) => AddTaskScreen(task: widget.parent, isBacklog: true),
          );
        } else if (v == 'assign') {
          _assignParentDate();
        } else if (v == 'delete') {
          _confirmDeleteParent();
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'edit', child: Text('Edit')),
        const PopupMenuItem(value: 'assign', child: Text('Schedule all steps…')),
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
  }

  Future<void> _addSubtask() async {
    final controller = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add subtask'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Subtask'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Add')),
        ],
      ),
    );
    if (title == null || title.trim().isEmpty) return;
    try {
      await widget.taskService.addSubtask(widget.parent, title.trim());
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not add subtask: $e')));
    }
  }

  Future<void> _scheduleChild(Task child) async {
    final picked = await _pickDate(child.dueDate);
    if (picked == null) return;
    await widget.taskService.scheduleSubtask(child, DateService().getString(picked));
  }

  Future<void> _assignParentDate() async {
    final picked = await _pickDate(null);
    if (picked == null) return;
    await widget.taskService.assignParentDate(widget.parent, DateService().getString(picked));
  }

  Future<DateTime?> _pickDate(String? current) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: current != null ? DateService().getDate(current) : now,
      firstDate: DateTime(now.year - 1),
      lastDate: now.add(const Duration(days: 365)),
    );
  }

  Future<void> _confirmDeleteParent() async {
    final messenger = ScaffoldMessenger.of(context);
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${widget.parent.title}"?'),
        content: const Text('Delete its steps too, or keep them as standalone tasks?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'keep'), child: const Text('Keep steps')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'delete'),
            child: Text('Delete steps', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (choice == null) return;
    try {
      await widget.taskService.deleteParent(widget.parent, keepChildren: choice == 'keep');
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not delete: $e')));
    }
  }

  String _shortDate(String iso) {
    try {
      return DateFormat('MMM d').format(DateService().getDate(iso));
    } catch (_) {
      return iso;
    }
  }
}

/// A compact "n/m done" indicator: filled pips for completed steps.
class _ProgressPips extends StatelessWidget {
  final int done;
  final int total;
  final Color color;
  const _ProgressPips({required this.done, required this.total, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.appTokens;
    return Row(
      children: [
        Text('$done/$total',
            style: theme.textTheme.labelSmall?.copyWith(
                color: t.textMuted, fontFeatures: const [FontFeature.tabularFigures()])),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: 4,
              backgroundColor: t.surfaceRaised,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
      ],
    );
  }
}

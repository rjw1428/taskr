import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/work.service.dart';
import 'package:taskr/shared/shared.dart';
import 'package:taskr/task_list/task_list_logic.dart';
import 'package:taskr/work/pinned_actions_section.dart';
import 'package:taskr/work/work_actions.dart';
import 'package:taskr/work/work_archive_page.dart';
import 'package:taskr/work/work_item_card.dart';

/// The Work tab: priorities in a user-controlled order, each with its next
/// actions visible. Lives inside the home shell's Scaffold, so its own header
/// row carries the Archived and Copy actions.
class WorkPage extends StatefulWidget {
  final WorkService? service;
  const WorkPage({super.key, this.service});

  @override
  State<WorkPage> createState() => _WorkPageState();
}

class _WorkPageState extends State<WorkPage> {
  late final WorkService _service = widget.service ?? WorkService();
  late final WorkActions _actions = WorkActions(_service);
  late final Stream<List<WorkItem>> _stream = _service.streamActive();

  /// Order applied locally the moment a drag ends, so the list does not snap
  /// back while the batch is in flight. The next stream emission wins.
  List<String>? _optimisticIds;

  List<WorkItem> _ordered(List<WorkItem> items) {
    final ids = _optimisticIds;
    if (ids == null) return items;
    final byId = {for (final i in items) i.id!: i};
    final out = [for (final id in ids) if (byId.containsKey(id)) byId[id]!];
    for (final i in items) {
      if (!ids.contains(i.id)) out.add(i);
    }
    return out;
  }

  Future<void> _persist(List<String> ids) async {
    setState(() => _optimisticIds = ids);
    await WorkActions.guard(() => _service.reorder(ids), 'Reorder');
  }

  void _onReorder(List<WorkItem> items, int oldIndex, int newIndex) {
    final ids = items.map((i) => i.id!).toList();
    _persist(TaskListLogic.reorder(ids, oldIndex, newIndex));
  }

  void _sendToBottom(List<WorkItem> items, String id) {
    final ids = items.map((i) => i.id!).toList()..remove(id);
    _persist([...ids, id]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<List<WorkItem>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: ErrorMessage(message: describeError(snapshot.error!)));
        if (!snapshot.hasData) return const LoadingScreen();
        final items = _ordered(snapshot.data!);
        // Once the server order matches, drop the optimistic overlay.
        if (_optimisticIds != null && _sameOrder(snapshot.data!, _optimisticIds!)) _optimisticIds = null;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.sm, Insets.sm, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      items.isEmpty ? '' : '${items.length} ${items.length == 1 ? 'priority' : 'priorities'}',
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('work-archived'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => WorkArchivePage(service: _service)),
                    ),
                    icon: const Icon(FontAwesomeIcons.boxArchive, size: 14),
                    label: const Text('Archived'),
                  ),
                  IconButton(
                    key: const Key('work-copy-all'),
                    tooltip: 'Copy all as Markdown',
                    icon: const Icon(FontAwesomeIcons.copy, size: 16),
                    onPressed: () => _actions.copyBoard(items),
                  ),
                ],
              ),
            ),
            PinnedActionsSection(items: items, actions: _actions),
            Expanded(
              child: items.isEmpty
                  ? const EmptyState(
                      icon: Icons.corporate_fare,
                      title: 'Nothing in flight',
                      message: 'Add a work item to keep a priority and its next action in view.',
                    )
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(Insets.md, Insets.sm, Insets.md, 96),
                      buildDefaultDragHandles: false,
                      itemCount: items.length,
                      onReorder: (o, n) => _onReorder(items, o, n),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return Padding(
                          key: ValueKey(item.id),
                          padding: const EdgeInsets.only(bottom: Insets.sm),
                          child: WorkItemCard(
                            item: item,
                            index: index,
                            actions: _actions,
                            onSendToBottom: () => _sendToBottom(items, item.id!),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  static bool _sameOrder(List<WorkItem> items, List<String> ids) {
    if (items.length != ids.length) return false;
    for (var i = 0; i < ids.length; i++) {
      if (items[i].id != ids[i]) return false;
    }
    return true;
  }
}

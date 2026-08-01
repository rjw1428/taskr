import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/services/tag.provider.dart';
import 'package:taskr/shared/progress_bar.dart';
import 'package:taskr/task_list/divider_item.dart';
import 'package:taskr/task_list/health_page.dart';
import 'package:taskr/task_list/journal_modal.dart';
import 'package:taskr/task_list/task_item.dart';
import 'package:taskr/task_list/subtask_group.dart';
import '../shared/shared.dart';

class TaskListScreen extends StatefulWidget {
  final bool isBacklog;
  const TaskListScreen({super.key, this.isBacklog = false});

  @override
  TaskListState createState() => TaskListState();
}

class TaskListState extends State<TaskListScreen> {
  List<Task>? _tasks;
  int _completedCount = 0;
  int _totalCount = 0;
  String today = DateService().getString(DateTime.now());
  String selectedDate = DateService().getString(DateTime.now());
  late String userId;
  final TaskService _taskService = TaskService();

  // Memoized streams so rebuilds don't tear down and re-subscribe Firestore
  // listeners (which caused sluggish backlog updates). Recreated only when the
  // day, backlog flag, or tag set actually changes.
  String? _streamKey;
  Stream<List<Task>>? _taskStream;
  Stream<List<Task>>? _subtaskStream;
  Stream<List<Habit>>? _habitStream;

  void _ensureStreams(List<Tag> tags) {
    _habitStream ??= HabitService().streamHabits();
    final key = "${widget.isBacklog}|$selectedDate|${tags.map((t) => t.id).join(',')}";
    if (key == _streamKey) return;
    _streamKey = key;
    _taskStream = _taskService.streamTasks(userId, widget.isBacklog ? null : selectedDate, tags);
    _subtaskStream = widget.isBacklog ? _taskService.streamSubtasks(userId, tags) : null;
  }

  bool _isSearching = false;
  List<Task>? _searchResults;
  bool _searchLoading = false;
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    userId = AuthService().user!.uid;
    setFcmToken();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        _searchResults = null;
      }
    });
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.length < 2) {
      setState(() => _searchResults = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() => _searchLoading = true);
      final results = await _taskService.searchTasks(query);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _searchLoading = false;
        });
      }
    });
  }

  setFcmToken() async {
    debugPrint('[Update FCM] checking FCM');
    final user = await AuthService().getUserProfile(userId);
    if (user == null) {
      debugPrint('[Update FCM] no profile');
      return;
    }
    if (kIsWeb) {
      return;
    }
    await FirebaseMessaging.instance.requestPermission();
    final fcmToken = await FirebaseMessaging.instance.getToken();
    if (fcmToken != null && fcmToken != user['fcmToken']) {
      debugPrint('[Update FCM] Updating token');
      await AuthService().updateFcmToken(userId, fcmToken);
    } else {
      debugPrint('[Update FCM] No update required');
    }
  }

  @override
  Widget build(BuildContext context) {
    var tagProvider = Provider.of<TagProvider>(context);
    var tags = tagProvider.tags;
    _ensureStreams(tags);
    // Stream habits so their instances can show a live streak on the card.
    return StreamBuilder<List<Habit>>(
      stream: _habitStream,
      builder: (context, habitSnap) {
        final habitStreaks = <String, int>{
          for (final h in (habitSnap.data ?? const <Habit>[]))
            if (h.id != null) h.id!: h.currentStreak,
        };
        // The backlog also streams subtasks (across date partitions) so it can
        // nest a parent's children beneath it, including ones scheduled elsewhere.
        if (widget.isBacklog) {
          return StreamBuilder<List<Task>>(
            stream: _subtaskStream,
            builder: (context, subSnap) {
              final childrenByParent = <String, List<Task>>{};
              for (final s in (subSnap.data ?? const <Task>[])) {
                if (s.parentId != null) (childrenByParent[s.parentId!] ??= []).add(s);
              }
              return _buildTaskList(context, childrenByParent, habitStreaks);
            },
          );
        }
        return _buildTaskList(context, const {}, habitStreaks);
      },
    );
  }

  Widget _buildTaskList(
      BuildContext context, Map<String, List<Task>> childrenByParent, Map<String, int> habitStreaks) {
    return StreamBuilder<List<Task>>(
        stream: _taskStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && _tasks == null) {
            return const LoadingScreen(message: 'Loading Tasks...');
          }
          if (snapshot.hasError) {
            debugPrint("LIST ERROR: ${snapshot.error}");
            return const ErrorMessage(message: 'Oh Shit');
          }
          debugPrint("FETCHING NEW TASK DATA");
          if (snapshot.hasError || !snapshot.hasData) {
            _tasks = [];
          }

          _tasks = snapshot.data!;
          _completedCount = 0;
          _totalCount = 0;

          // Rows actually rendered at the top level: hide container parents on a
          // day (they live only in the backlog), and hide subtasks in the
          // backlog (they're shown nested under their parent).
          final visible = <Task>[];
          for (final task in _tasks!) {
            if (!widget.isBacklog && task.isParent) continue;
            if (widget.isBacklog && task.isSubtask) continue;
            visible.add(task);
          }

          // Reorder/complete operate on the visible subset, then merge back into
          // the full partition order so hidden ids keep their positions.
          void persistVisibleOrder(List<String> newVisibleIds) {
            final fullIds = _tasks!.map((t) => t.id!).toList();
            final visibleIds = visible.map((t) => t.id!).toSet();
            final positions = <int>[];
            for (int k = 0; k < fullIds.length; k++) {
              if (visibleIds.contains(fullIds[k])) positions.add(k);
            }
            for (int k = 0; k < positions.length && k < newVisibleIds.length; k++) {
              fullIds[positions[k]] = newVisibleIds[k];
            }
            _taskService.updateTaskOrder(userId, fullIds, widget.isBacklog ? null : selectedDate);
          }

          onComplete(int vIndex) {
            setState(() {
              final ids = visible.map((t) => t.id!).toList();
              final moved = ids.removeAt(vIndex);
              ids.add(moved);
              persistVisibleOrder(ids);
            });
          }

          List<Widget> children = [];
          for (int i = 0; i < visible.length; i++) {
            final task = visible[i];
            if (task.isDivider) {
              children.add(AppReveal(
                key: ValueKey(task.id!),
                delay: staggerDelay(i),
                child: DividerItem(
                  divider: task,
                  index: i,
                  onDelete: deleteTaskWithUndo,
                ),
              ));
            } else if (widget.isBacklog && task.isParent) {
              children.add(AppReveal(
                key: ValueKey(task.id!),
                delay: staggerDelay(i),
                child: SubtaskGroupCard(
                  parent: task,
                  childTasks: childrenByParent[task.id!] ?? const <Task>[],
                  index: i,
                  taskService: _taskService,
                ),
              ));
            } else {
              children.add(AppReveal(
                key: ValueKey(task.id!),
                delay: staggerDelay(i),
                child: displayTask(
                    task, i, onComplete, widget.isBacklog, _taskService, deleteTaskWithUndo, habitStreaks),
              ));
            }
          }

          if (_isSearching) {
            children = [];
            if (_searchLoading) {
              children.add(const Padding(
                key: ValueKey('search-loading'),
                padding: EdgeInsets.only(top: 80.0),
                child: Center(child: CircularProgressIndicator()),
              ));
            } else if (_searchResults != null && _searchResults!.isEmpty) {
              children.add(Padding(
                key: const ValueKey('search-empty'),
                padding: const EdgeInsets.only(top: 80.0),
                child: Text(
                  "No results found",
                  style: TextStyle(color: Theme.of(context).appTokens.textMuted),
                  textAlign: TextAlign.center,
                ),
              ));
            } else if (_searchResults != null) {
              for (int i = 0; i < _searchResults!.length; i++) {
                final task = _searchResults![i];
                children.add(_buildSearchResult(context, task, i));
              }
            }
          }

          if (children.isEmpty && !_isSearching) {
            children.add(Padding(
              key: const ValueKey(0),
              padding: const EdgeInsets.only(top: 80.0),
              child: Text(
                "You have nothing scheduled 🎉",
                style: TextStyle(color: Theme.of(context).appTokens.textMuted),
                textAlign: TextAlign.center,
              ),
            ));
          }
          double? dragStart;
          return GestureDetector(
              onHorizontalDragStart: (details) => dragStart = details.globalPosition.dx,
              onHorizontalDragEnd: (details) {
                final dragEnd = details.globalPosition.dx;
                final dragDelta = dragEnd - dragStart!;
                if (dragDelta > 10) {
                  setState(() {
                    selectedDate = DateService().decrementDate(DateService().getDate(selectedDate));
                    DateService().setSelectedDate(DateService().getDate(selectedDate));
                  });
                } else if (dragDelta < -10) {
                  setState(() {
                    selectedDate = DateService().incrementDate(DateService().getDate(selectedDate));
                    DateService().setSelectedDate(DateService().getDate(selectedDate));
                  });
                }
              },
              child: ReorderableListView(
                  footer: !widget.isBacklog && AuthService().isOwner
                      ? StreamBuilder<JournalEntry?>(
                          stream: JournalService().streamEntry(selectedDate),
                          builder: (context, journalSnapshot) {
                            final hasJournal = journalSnapshot.data != null && journalSnapshot.data!.hasData;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () {
                                        Navigator.of(context, rootNavigator: true).push(
                                          MaterialPageRoute(
                                            fullscreenDialog: true,
                                            builder: (_) => JournalModal(date: selectedDate),
                                          ),
                                        );
                                      },
                                      icon: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          const Icon(FontAwesomeIcons.book, size: 16),
                                          if (hasJournal)
                                            Positioned(
                                              right: -4,
                                              top: -4,
                                              child: Container(
                                                width: 8,
                                                height: 8,
                                                decoration: BoxDecoration(
                                                  color: Theme.of(context).colorScheme.primary,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      label: const Text('Journal'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Theme.of(context).colorScheme.onSurface,
                                        side: BorderSide(color: Theme.of(context).appTokens.hairline),
                                      ),
                                    ),
                                  ),
                                  StreamBuilder<HealthEntry?>(
                                    stream: HealthService().streamEntry(selectedDate),
                                    builder: (context, healthSnapshot) {
                                      final hasHealth =
                                          healthSnapshot.data != null && healthSnapshot.data!.hasData;
                                      if (!hasHealth) return const SizedBox.shrink();
                                      return Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.only(left: 12),
                                          child: OutlinedButton.icon(
                                            onPressed: () {
                                              Navigator.of(context, rootNavigator: true).push(
                                                MaterialPageRoute(
                                                  fullscreenDialog: true,
                                                  builder: (_) => HealthPage(date: selectedDate),
                                                ),
                                              );
                                            },
                                            icon: const Icon(FontAwesomeIcons.heartPulse, size: 16),
                                            label: const Text('Health'),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: Theme.of(context).colorScheme.onSurface,
                                              side: BorderSide(color: Theme.of(context).appTokens.hairline),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        )
                      : null,
                  header: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (!widget.isBacklog) DailyProgress(numerator: _completedCount, denominator: _totalCount),
                    if (!widget.isBacklog)
                      StreamBuilder<List<Map<String, dynamic>>>(
                        stream: _taskService.streamCountdowns(userId),
                        builder: (context, cdSnapshot) {
                          if (!cdSnapshot.hasData) return const SizedBox.shrink();
                          final viewed = DateService().getDate(selectedDate);
                          final chips = cdSnapshot.data!.where((cd) {
                            final due = cd['dueDate'] as String?;
                            if (due == null) return false;
                            final dueDate = DateService().getDate(due);
                            return dueDate.isAfter(viewed);
                          }).toList()
                            ..sort((a, b) => (a['dueDate'] as String).compareTo(b['dueDate'] as String));
                          if (chips.isEmpty) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                            child: Wrap(
                              alignment: WrapAlignment.start,
                              spacing: 6,
                              runSpacing: 4,
                              children: chips.map((cd) {
                                final dueDate = DateService().getDate(cd['dueDate'] as String);
                                final days = dueDate.difference(viewed).inDays;
                                return ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 100),
                                  child: ActionChip(
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                    side: BorderSide.none,
                                    label: Text(
                                      '${cd['title']} · ${days}d',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                    onPressed: () {
                                      final due = cd['dueDate'] as String;
                                      setState(() => selectedDate = due);
                                      DateService().setSelectedDate(DateService().getDate(due));
                                    },
                                  ),
                                );
                              }).toList(),
                            ),
                          );
                        },
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (!widget.isBacklog)
                          IconButton(
                            icon: Icon(_isSearching ? FontAwesomeIcons.xmark : FontAwesomeIcons.magnifyingGlass, size: 18),
                            onPressed: _toggleSearch,
                          ),
                        if (_isSearching)
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              autofocus: true,
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                              decoration: InputDecoration(
                                hintText: 'Search tasks...',
                                hintStyle: TextStyle(color: Theme.of(context).appTokens.textFaint),
                                border: InputBorder.none,
                              ),
                              onChanged: _onSearchChanged,
                            ),
                          )
                        else ...[
                          Expanded(
                              child: Center(
                                  child: Text(widget.isBacklog
                                      ? "Backlog"
                                      : DateService().getDayOfWeek(DateService().getDate(selectedDate))))),
                          if (!widget.isBacklog)
                            Row(
                              children: [
                                if (DateService().isDateLessThan(today, selectedDate))
                                  IconButton(
                                      onPressed: () => setState(() {
                                            debugPrint("BACK TO TODAY");
                                            selectedDate = today;
                                            DateService().setSelectedDate(DateService().getDate(selectedDate));
                                          }),
                                      icon: const Icon(FontAwesomeIcons.backwardStep)),
                                IconButton(
                                    onPressed: () => setState(() {
                                          debugPrint("LEFT");
                                          selectedDate = DateService().decrementDate(DateService().getDate(selectedDate));
                                          DateService().setSelectedDate(DateService().getDate(selectedDate));
                                        }),
                                    icon: const Icon(FontAwesomeIcons.caretLeft)),
                                Text(selectedDate),
                                IconButton(
                                    onPressed: () => setState(() {
                                          debugPrint("RIGHT");
                                          selectedDate = DateService().incrementDate(DateService().getDate(selectedDate));
                                          DateService().setSelectedDate(DateService().getDate(selectedDate));
                                        }),
                                    icon: const Icon(FontAwesomeIcons.caretRight)),
                                if (DateService().isDateLessThan(selectedDate, today))
                                  IconButton(
                                      onPressed: () => setState(() {
                                            debugPrint("FORWARD TO TODAY");
                                            selectedDate = today;
                                            DateService().setSelectedDate(DateService().getDate(selectedDate));
                                          }),
                                      icon: const Icon(FontAwesomeIcons.forwardStep)),
                              ],
                            ),
                        ],
                      ],
                    ),
                  ]),
                  buildDefaultDragHandles: false,
                  onReorder: (int oldIndex, int newIndex) {
                    if (_isSearching) return;
                    setState(() {
                      final ids = visible.map((t) => t.id!).toList();
                      final delta = newIndex > oldIndex ? -1 : 0;
                      if (newIndex >= ids.length) {
                        final m = ids.removeAt(oldIndex);
                        ids.add(m);
                      } else {
                        final m = ids.removeAt(oldIndex);
                        ids.insert(newIndex + delta, m);
                      }
                      persistVisibleOrder(ids);
                    });
                  },
                  children: children));
        });
  }

  Widget _buildSearchResult(BuildContext context, Task task, int index) {
    final theme = Theme.of(context);
    final t = theme.appTokens;
    final pc = t.of(task.priority);
    final ink = task.completed ? pc.ink.withAlpha(160) : pc.ink;
    return GestureDetector(
      key: ValueKey('search-$index'),
      onTap: () {
        if (task.dueDate == null) return;
        setState(() {
          selectedDate = task.dueDate!;
          DateService().setSelectedDate(DateService().getDate(selectedDate));
          _isSearching = false;
          _searchController.clear();
          _searchResults = null;
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: pc.fill.withAlpha(task.completed ? 128 : 255),
          border: Border.all(color: pc.border),
          borderRadius: BorderRadius.circular(Corners.md),
          boxShadow: t.raisedShadow,
        ),
        margin: const EdgeInsets.all(Insets.xs),
        padding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: Insets.sm),
        child: Row(
          children: [
            if (task.completed)
              Padding(
                padding: const EdgeInsets.only(right: Insets.sm),
                child: Icon(FontAwesomeIcons.check, size: 14, color: ink),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(task.title, style: theme.textTheme.titleSmall?.copyWith(color: ink)),
                  if (task.dueDate != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(task.dueDate!,
                          style: theme.textTheme.bodySmall?.copyWith(color: ink.withAlpha(180))),
                    ),
                ],
              ),
            ),
            Icon(FontAwesomeIcons.arrowRight, size: 14, color: ink.withAlpha(160)),
          ],
        ),
      ),
    );
  }

  void deleteTaskWithUndo(Task task) async {
    final messenger = ScaffoldMessenger.of(context);
    if (task.reminderTaskName != null) {
      ReminderService().cancelReminder(task);
    }
    // Await the delete so we only report success when it actually happened.
    // Previously this was fire-and-forget, so a failed delete still showed a
    // "removed" snackbar while the task stayed on the list.
    try {
      await _taskService.deleteTask(task);
    } catch (e, st) {
      debugPrint('DELETE FAILED: $e\n$st');
      messenger.showSnackBar(
        SnackBar(content: Text('Could not remove task: $e')),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(days: 365),
        content: Text(task.isDivider ? 'Divider removed' : 'Task removed'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            _taskService.restoreTask(task);
            if (task.reminderTime != null) {
              ReminderService().scheduleReminder(task);
            }
          },
        ),
      ),
    );
    Timer(const Duration(seconds: 3), () {
      messenger.hideCurrentSnackBar();
    });
  }

  displayTask(Task task, int i, Function onComplete, bool isBacklog, TaskService taskService,
      Function(Task) onDelete, Map<String, int> habitStreaks) {
    if (!task.isDivider) {
      _totalCount += PerformanceService().getScore(task.priority);
      if (task.completed) {
        _completedCount += PerformanceService().getScore(task.priority);
      }
    }
    return TaskItem(
        task: task,
        index: i,
        key: ValueKey(task.id!),
        onComplete: onComplete,
        isBacklog: isBacklog,
        taskService: taskService,
        onDelete: onDelete,
        habitStreaks: habitStreaks);
  }
}

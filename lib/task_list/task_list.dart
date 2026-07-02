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
import 'package:taskr/task_list/journal_modal.dart';
import 'package:taskr/task_list/task_item.dart';
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
    return StreamBuilder<List<Task>>(
        stream: _taskService.streamTasks(userId, widget.isBacklog ? null : selectedDate, tags),
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
          onComplete(int taskIndex) {
            setState(() {
              var list = _tasks!.map((task) => task.id!).toList();
              var taskId = list.removeAt(taskIndex);
              list.add(taskId);
              _taskService.updateTaskOrder(userId, list, widget.isBacklog ? null : selectedDate);
            });
          }

          List<Widget> children = [];
          for (int i = 0; i < _tasks!.length; i++) {
            final task = _tasks![i];
            if (task.isDivider) {
              children.add(DividerItem(
                key: ValueKey(task.id!),
                divider: task,
                index: i,
                onDelete: deleteTaskWithUndo,
              ));
            } else {
              children.add(displayTask(task, i, onComplete, widget.isBacklog, _taskService, deleteTaskWithUndo));
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
              children.add(const Padding(
                key: ValueKey('search-empty'),
                padding: EdgeInsets.only(top: 80.0),
                child: Text(
                  "No results found",
                  style: TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ));
            } else if (_searchResults != null) {
              for (int i = 0; i < _searchResults!.length; i++) {
                final task = _searchResults![i];
                children.add(_buildSearchResult(task, i));
              }
            }
          }

          if (children.isEmpty && !_isSearching) {
            children.add(const Padding(
              key: ValueKey(0),
              padding: EdgeInsets.only(top: 80.0),
              child: Text(
                "You have nothing scheduled 🎉",
                style: TextStyle(color: Colors.white70),
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
                  footer: !widget.isBacklog
                      ? StreamBuilder<JournalEntry?>(
                          stream: JournalService().streamEntry(selectedDate),
                          builder: (context, journalSnapshot) {
                            final hasJournal = journalSnapshot.data != null && journalSnapshot.data!.hasData;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
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
                                          decoration: const BoxDecoration(
                                            color: Colors.orange,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                label: const Text('Journal'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white70,
                                  side: const BorderSide(color: Colors.white24),
                                ),
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
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                hintText: 'Search tasks...',
                                hintStyle: TextStyle(color: Colors.white54),
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
                    setState(() {
                      final delta = newIndex > oldIndex ? -1 : 0;
                      var list = _tasks!.map((task) => task.id!).toList();
                      if (newIndex == list.length) {
                        var swapId = list.removeAt(oldIndex);
                        list.add(swapId);

                        var swapItem = _tasks!.removeAt(oldIndex);
                        _tasks!.add(swapItem);
                      } else {
                        var item = list.removeAt(oldIndex);
                        list.insert(newIndex + delta, item);

                        var swapItem = _tasks!.removeAt(oldIndex);
                        _tasks!.insert(newIndex + delta, swapItem);
                      }

                      _taskService.updateTaskOrder(userId, list, widget.isBacklog ? null : selectedDate);
                    });
                  },
                  children: children));
        });
  }

  Widget _buildSearchResult(Task task, int index) {
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
          color: priorityColors[task.priority]!.withAlpha(task.completed ? 128 : 255),
          border: Border.all(color: Colors.black45),
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [BoxShadow(color: Colors.black45, offset: Offset(2.0, 4.0), blurRadius: 5.0)],
        ),
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            if (task.completed)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(FontAwesomeIcons.check, size: 14, color: Colors.white70),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(task.title, style: const TextStyle(fontSize: 16, color: Colors.white)),
                  if (task.dueDate != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(task.dueDate!, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                    ),
                ],
              ),
            ),
            const Icon(FontAwesomeIcons.arrowRight, size: 14, color: Colors.white54),
          ],
        ),
      ),
    );
  }

  void deleteTaskWithUndo(Task task) {
    if (task.reminderTaskName != null) {
      ReminderService().cancelReminder(task);
    }
    _taskService.deleteTask(task);
    final messenger = ScaffoldMessenger.of(context);
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

  displayTask(Task task, int i, Function onComplete, bool isBacklog, TaskService taskService, Function(Task) onDelete) {
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
        onDelete: onDelete);
  }
}

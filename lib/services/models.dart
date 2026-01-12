import 'package:json_annotation/json_annotation.dart';
import 'package:taskr/shared/constants.dart';
part 'models.g.dart';

enum Difficulty {
  low,
  medium,
  high,
}

@JsonSerializable()
class Accomplishment {
  String? id;
  String title;
  String? description;
  String date;
  Difficulty difficulty;

  Accomplishment({
    this.id,
    required this.title,
    this.description,
    required this.date,
    this.difficulty = Difficulty.low,
  });

  factory Accomplishment.fromJson(Map<String, dynamic> json) => _$AccomplishmentFromJson(json);
  Map<String, dynamic> toJson() => _$AccomplishmentToJson(this);
}

@JsonSerializable()
class Task {
  String? id;
  int? added;
  String modified;
  String title;
  String? description;
  bool completed;
  List<Tag> tags;
  String? dueDate;
  String? startTime;
  String? endTime;
  String? completedTime;
  String? recurringTemplateId;
  List<String> subtasks;
  Effort priority;
  int pushCount;
  Task(
      {this.id,
      required this.added,
      this.modified = '',
      required this.title,
      this.description,
      this.completed = false,
      this.tags = const [],
      this.priority = Effort.low,
      this.dueDate,
      this.startTime,
      this.endTime,
      this.recurringTemplateId,
      this.pushCount = 0,
      this.subtasks = const []});

  factory Task.fromJson(Map<String, dynamic> json) => _$TaskFromJson(json);
  Map<String, dynamic> toJson() => _$TaskToJson(this);

  Map<String, dynamic> toDbTask() {
    var obj = toJson();
    obj['tags'] = tags.map((tag) => tag.id).toList();
    return (obj);
  }

  Task copyWith({
    String? id,
    int? added,
    String? modified,
    String? title,
    String? description,
    bool? completed,
    List<Tag>? tags,
    String? dueDate,
    String? startTime,
    String? endTime,
    String? completedTime,
    List<String>? subtasks,
    Effort? priority,
    int? pushCount,
    String? recurringTemplateId,
  }) {
    return Task(
        id: id ?? this.id,
        added: added ?? this.added,
        modified: modified ?? this.modified,
        title: title ?? this.title,
        description: description ?? this.description,
        completed: completed ?? this.completed,
        tags: tags ?? this.tags,
        dueDate: dueDate ?? this.dueDate,
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
        subtasks: subtasks ?? this.subtasks,
        priority: priority ?? this.priority,
        pushCount: pushCount ?? this.pushCount,
        recurringTemplateId: recurringTemplateId ?? this.recurringTemplateId);
  }
}

@JsonSerializable()
class Tag {
  String id;
  String label;
  bool deleted;
  bool archived;

  Tag({
    required this.id,
    required this.label,
    this.deleted = false,
    this.archived = false,
  });

  factory Tag.fromJson(Map<String, dynamic> json) => _$TagFromJson(json);
  Map<String, dynamic> toJson() => _$TagToJson(this);
}

@JsonSerializable()
class RecurringTask {
  String? id;
  String recurrenceType;
  int? frequency;
  Map<String, bool>? daysOfWeek;
  DateTime? startDate;
  DateTime? endDate;
  int? dayOfMonth;

  RecurringTask({
    required this.recurrenceType,
    this.frequency = 1,
    this.daysOfWeek,
    this.startDate,
    this.endDate,
    this.dayOfMonth = 1,
  });

  factory RecurringTask.fromJson(Map<String, dynamic> json) => _$RecurringTaskFromJson(json);
  Map<String, dynamic> toJson() => _$RecurringTaskToJson(this);

  RecurringTask copyWith({
    String? id,
    String? recurrenceType,
    int? frequency,
    Map<String, bool>? daysOfWeek,
    DateTime? startDate,
    DateTime? endDate,
    int? dayOfMonth,
  }) {
    final copy = RecurringTask(
      recurrenceType: recurrenceType ?? this.recurrenceType,
      frequency: frequency ?? this.frequency,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      dayOfMonth: dayOfMonth ?? this.dayOfMonth,
    );
    copy.id = id ?? this.id;
    return copy;
  }
}

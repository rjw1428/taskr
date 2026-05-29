import 'package:json_annotation/json_annotation.dart';
import 'package:taskr/shared/constants.dart';
part 'models.g.dart';

enum Difficulty {
  low,
  medium,
  high,
}

@JsonSerializable()
class JournalEntry {
  String? id;
  String date;
  String? thinking;
  String? feeling;
  String? gratitude;

  JournalEntry({
    this.id,
    required this.date,
    this.thinking,
    this.feeling,
    this.gratitude,
  });

  factory JournalEntry.fromJson(Map<String, dynamic> json) => _$JournalEntryFromJson(json);
  Map<String, dynamic> toJson() => _$JournalEntryToJson(this);

  bool get hasData =>
      (thinking != null && thinking!.isNotEmpty) ||
      (feeling != null && feeling!.isNotEmpty) ||
      (gratitude != null && gratitude!.isNotEmpty);
}

enum GoalTimeframe {
  @JsonValue('1_week')
  oneWeek,
  @JsonValue('1_month')
  oneMonth,
  @JsonValue('3_months')
  threeMonths,
  @JsonValue('6_months')
  sixMonths,
  @JsonValue('1_year')
  oneYear,
}

enum GoalFrequency {
  daily,
  @JsonValue('n_times_week')
  nTimesWeek,
  auto,
}

enum GoalStatus {
  active,
  completed,
  deleted,
}

@JsonSerializable()
class Goal {
  String? id;
  String title;
  String? description;
  GoalTimeframe timeframe;
  GoalFrequency frequency;
  int? frequencyCount;
  String startDate;
  String endDate;
  GoalStatus status;
  int createdAt;
  int modifiedAt;

  Goal({
    this.id,
    required this.title,
    this.description,
    required this.timeframe,
    required this.frequency,
    this.frequencyCount,
    required this.startDate,
    required this.endDate,
    this.status = GoalStatus.active,
    required this.createdAt,
    required this.modifiedAt,
  });

  factory Goal.fromJson(Map<String, dynamic> json) => _$GoalFromJson(json);
  Map<String, dynamic> toJson() => _$GoalToJson(this);

  Goal copyWith({
    String? id,
    String? title,
    String? description,
    GoalTimeframe? timeframe,
    GoalFrequency? frequency,
    int? frequencyCount,
    String? startDate,
    String? endDate,
    GoalStatus? status,
    int? createdAt,
    int? modifiedAt,
  }) {
    return Goal(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      timeframe: timeframe ?? this.timeframe,
      frequency: frequency ?? this.frequency,
      frequencyCount: frequencyCount ?? this.frequencyCount,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
    );
  }

  static String computeEndDate(String startDate, GoalTimeframe timeframe) {
    final start = DateTime.parse(startDate);
    late DateTime end;
    switch (timeframe) {
      case GoalTimeframe.oneWeek:
        end = start.add(const Duration(days: 7));
      case GoalTimeframe.oneMonth:
        end = DateTime(start.year, start.month + 1, start.day);
      case GoalTimeframe.threeMonths:
        end = DateTime(start.year, start.month + 3, start.day);
      case GoalTimeframe.sixMonths:
        end = DateTime(start.year, start.month + 6, start.day);
      case GoalTimeframe.oneYear:
        end = DateTime(start.year + 1, start.month, start.day);
    }
    return end.toIso8601String().split('T')[0];
  }

  String get timeframeLabel {
    switch (timeframe) {
      case GoalTimeframe.oneWeek:
        return '1 Week';
      case GoalTimeframe.oneMonth:
        return '1 Month';
      case GoalTimeframe.threeMonths:
        return '3 Months';
      case GoalTimeframe.sixMonths:
        return '6 Months';
      case GoalTimeframe.oneYear:
        return '1 Year';
    }
  }

  String get frequencyLabel {
    switch (frequency) {
      case GoalFrequency.daily:
        return 'Daily';
      case GoalFrequency.nTimesWeek:
        return '${frequencyCount}x / week';
      case GoalFrequency.auto:
        return 'Auto';
    }
  }
}

@JsonSerializable()
class Generation {
  String? id;
  int generatedAt;
  String weekStart;
  String weekEnd;
  List<String> taskIds;
  String prompt;
  String response;
  List<String> completedTaskIds;
  List<String> skippedTaskIds;
  Map<String, String> taskFeedback;

  Generation({
    this.id,
    required this.generatedAt,
    required this.weekStart,
    required this.weekEnd,
    this.taskIds = const [],
    required this.prompt,
    required this.response,
    this.completedTaskIds = const [],
    this.skippedTaskIds = const [],
    this.taskFeedback = const {},
  });

  factory Generation.fromJson(Map<String, dynamic> json) => _$GenerationFromJson(json);
  Map<String, dynamic> toJson() => _$GenerationToJson(this);
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
  String type;
  List<Tag> tags;
  String? dueDate;
  String? startTime;
  String? endTime;
  String? completedTime;
  String? recurringTemplateId;
  String? goalId;
  String? calendarEventId;
  String? feedback;
  String? multiDayGroupId;
  String? multiDayPosition;
  List<String> subtasks;
  Effort priority;
  int pushCount;

  bool get isDivider => type == 'divider';
  bool get isMultiDay => multiDayGroupId != null;
  bool get isMultiDayStart => multiDayPosition == 'start';
  bool get isMultiDayEnd => multiDayPosition == 'end';
  bool get isMultiDayMiddle => multiDayPosition == 'middle';

  Task(
      {this.id,
      required this.added,
      this.modified = '',
      required this.title,
      this.description,
      this.completed = false,
      this.type = 'task',
      this.tags = const [],
      this.priority = Effort.low,
      this.dueDate,
      this.startTime,
      this.endTime,
      this.recurringTemplateId,
      this.goalId,
      this.calendarEventId,
      this.feedback,
      this.multiDayGroupId,
      this.multiDayPosition,
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
    String? type,
    List<Tag>? tags,
    String? dueDate,
    String? startTime,
    String? endTime,
    String? completedTime,
    List<String>? subtasks,
    Effort? priority,
    int? pushCount,
    String? recurringTemplateId,
    String? goalId,
    String? calendarEventId,
    String? feedback,
    String? multiDayGroupId,
    String? multiDayPosition,
  }) {
    return Task(
        id: id ?? this.id,
        added: added ?? this.added,
        modified: modified ?? this.modified,
        title: title ?? this.title,
        description: description ?? this.description,
        completed: completed ?? this.completed,
        type: type ?? this.type,
        tags: tags ?? this.tags,
        dueDate: dueDate ?? this.dueDate,
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
        subtasks: subtasks ?? this.subtasks,
        priority: priority ?? this.priority,
        pushCount: pushCount ?? this.pushCount,
        recurringTemplateId: recurringTemplateId ?? this.recurringTemplateId,
        goalId: goalId ?? this.goalId,
        calendarEventId: calendarEventId ?? this.calendarEventId,
        feedback: feedback ?? this.feedback,
        multiDayGroupId: multiDayGroupId ?? this.multiDayGroupId,
        multiDayPosition: multiDayPosition ?? this.multiDayPosition);
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

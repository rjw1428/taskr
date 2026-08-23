import 'package:json_annotation/json_annotation.dart';
import 'package:taskr/shared/constants.dart';
part 'models.g.dart';

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

@JsonSerializable()
class HealthEntry {
  String? id;
  String date;
  int? sleepScore;
  int? sleepSeconds;
  int? deepSeconds;
  int? lightSeconds;
  int? remSeconds;
  int? awakeSeconds;
  int? bodyBatteryHigh;
  int? bodyBatteryLow;
  int? bodyBatteryCharged;
  int? bodyBatteryDrained;
  int? stressAvg;
  int? stressMax;
  int? steps;
  int? floorsClimbed;
  int? activeCalories;
  int? restingHeartRate;

  HealthEntry({
    this.id,
    required this.date,
    this.sleepScore,
    this.sleepSeconds,
    this.deepSeconds,
    this.lightSeconds,
    this.remSeconds,
    this.awakeSeconds,
    this.bodyBatteryHigh,
    this.bodyBatteryLow,
    this.bodyBatteryCharged,
    this.bodyBatteryDrained,
    this.stressAvg,
    this.stressMax,
    this.steps,
    this.floorsClimbed,
    this.activeCalories,
    this.restingHeartRate,
  });

  factory HealthEntry.fromJson(Map<String, dynamic> json) => _$HealthEntryFromJson(json);
  Map<String, dynamic> toJson() => _$HealthEntryToJson(this);

  bool get hasData => sleepSeconds != null || steps != null || stressAvg != null || bodyBatteryHigh != null;
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
  paused,
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
  int difficultyScore;

  Accomplishment({
    this.id,
    required this.title,
    this.description,
    required this.date,
    this.difficultyScore = 1,
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
  String? reminderTime;
  String? reminderTaskName;
  String? parentId;
  String? parentTitle;
  String? userId;
  String? habitId;
  int childCount;
  int childCompletedCount;
  Effort priority;
  int pushCount;
  bool countdown;
  String? countdownLabel;

  bool get isDivider => type == 'divider';
  bool get isMultiDay => multiDayGroupId != null;
  bool get isMultiDayStart => multiDayPosition == 'start';
  bool get isMultiDayEnd => multiDayPosition == 'end';
  bool get isMultiDayMiddle => multiDayPosition == 'middle';
  bool get isSubtask => parentId != null;
  bool get isParent => childCount > 0;

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
      this.reminderTime,
      this.reminderTaskName,
      this.pushCount = 0,
      this.countdown = false,
      this.countdownLabel,
      this.parentId,
      this.parentTitle,
      this.userId,
      this.habitId,
      this.childCount = 0,
      this.childCompletedCount = 0});

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
    String? parentId,
    String? parentTitle,
    String? userId,
    String? habitId,
    int? childCount,
    int? childCompletedCount,
    Effort? priority,
    int? pushCount,
    bool? countdown,
    String? countdownLabel,
    String? recurringTemplateId,
    String? goalId,
    String? calendarEventId,
    String? feedback,
    String? multiDayGroupId,
    String? multiDayPosition,
    String? reminderTime,
    String? reminderTaskName,
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
        parentId: parentId ?? this.parentId,
        habitId: habitId ?? this.habitId,
        parentTitle: parentTitle ?? this.parentTitle,
        userId: userId ?? this.userId,
        childCount: childCount ?? this.childCount,
        childCompletedCount: childCompletedCount ?? this.childCompletedCount,
        priority: priority ?? this.priority,
        pushCount: pushCount ?? this.pushCount,
        countdown: countdown ?? this.countdown,
        countdownLabel: countdownLabel ?? this.countdownLabel,
        recurringTemplateId: recurringTemplateId ?? this.recurringTemplateId,
        goalId: goalId ?? this.goalId,
        calendarEventId: calendarEventId ?? this.calendarEventId,
        feedback: feedback ?? this.feedback,
        multiDayGroupId: multiDayGroupId ?? this.multiDayGroupId,
        multiDayPosition: multiDayPosition ?? this.multiDayPosition,
        reminderTime: reminderTime ?? this.reminderTime,
        reminderTaskName: reminderTaskName ?? this.reminderTaskName);
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

@JsonSerializable()
class Kid {
  String name;
  int age;
  String? birthday;
  String dateAdded;

  Kid({
    required this.name,
    required this.age,
    this.birthday,
    required this.dateAdded,
  });

  factory Kid.fromJson(Map<String, dynamic> json) => _$KidFromJson(json);
  Map<String, dynamic> toJson() => _$KidToJson(this);
}

@JsonSerializable()
class ConversationLog {
  String? id;
  String date;
  String entry;
  int? createdAt;
  int? updatedAt;

  ConversationLog({
    this.id,
    required this.date,
    required this.entry,
    this.createdAt,
    this.updatedAt,
  });

  factory ConversationLog.fromJson(Map<String, dynamic> json) => _$ConversationLogFromJson(json);
  Map<String, dynamic> toJson() => _$ConversationLogToJson(this);
}

// explicitToJson is required because Person contains nested serializable lists
// (kids, logs). Without it the generated toJson emits raw Kid/ConversationLog
// instances, which Firestore cannot serialize ("Invalid argument: Instance of
// 'ConversationLog'").
@JsonSerializable(explicitToJson: true)
class Person {
  String? id;
  String name;
  int? age;
  String? birthday;
  String? job;
  String? spouse;
  List<Kid> kids;
  List<ConversationLog> logs;
  int? createdAt;
  int? lastUpdated;

  Person({
    this.id,
    required this.name,
    this.age,
    this.birthday,
    this.job,
    this.spouse,
    this.kids = const [],
    this.logs = const [],
    this.createdAt,
    this.lastUpdated,
  });

  factory Person.fromJson(Map<String, dynamic> json) => _$PersonFromJson(json);
  Map<String, dynamic> toJson() => _$PersonToJson(this);
}

@JsonSerializable()
class Habit {
  String? id;
  String title;
  Effort effort;
  // Reuse the recurring-task cadence vocabulary: 'Daily' | 'Weekly' | 'Monthly'.
  String recurrenceType;
  int frequency;
  Map<String, bool>? daysOfWeek; // weekly: 'Su'..'Sa' -> selected
  int? dayOfMonth; // monthly
  String startDate; // yyyy-MM-dd
  String? reminderTime; // HH:mm
  String status; // 'active' | 'paused'
  // Denormalized streak state (maintained; recomputed authoritatively).
  int currentStreak;
  int longestStreak;
  String? lastCompletedDate; // scheduled date string of most recent completed occurrence
  String? lastMaterializedDate; // rolling top-up bookkeeping
  int? createdAt;
  int? modifiedAt;

  Habit({
    this.id,
    required this.title,
    this.effort = Effort.low,
    this.recurrenceType = 'Daily',
    this.frequency = 1,
    this.daysOfWeek,
    this.dayOfMonth,
    required this.startDate,
    this.reminderTime,
    this.status = 'active',
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.lastCompletedDate,
    this.lastMaterializedDate,
    this.createdAt,
    this.modifiedAt,
  });

  factory Habit.fromJson(Map<String, dynamic> json) => _$HabitFromJson(json);
  Map<String, dynamic> toJson() => _$HabitToJson(this);
}

@JsonSerializable()
class AppNotification {
  String? id;
  String title;
  String body;
  Map<String, dynamic> data;
  String? type;
  int sentAt; // epoch ms
  bool read;

  AppNotification({
    this.id,
    required this.title,
    required this.body,
    this.data = const {},
    this.type,
    required this.sentAt,
    this.read = false,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) => _$AppNotificationFromJson(json);
  Map<String, dynamic> toJson() => _$AppNotificationToJson(this);
}

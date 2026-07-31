// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

JournalEntry _$JournalEntryFromJson(Map<String, dynamic> json) => JournalEntry(
      id: json['id'] as String?,
      date: json['date'] as String,
      thinking: json['thinking'] as String?,
      feeling: json['feeling'] as String?,
      gratitude: json['gratitude'] as String?,
    );

Map<String, dynamic> _$JournalEntryToJson(JournalEntry instance) =>
    <String, dynamic>{
      'id': instance.id,
      'date': instance.date,
      'thinking': instance.thinking,
      'feeling': instance.feeling,
      'gratitude': instance.gratitude,
    };

HealthEntry _$HealthEntryFromJson(Map<String, dynamic> json) => HealthEntry(
      id: json['id'] as String?,
      date: json['date'] as String,
      sleepScore: (json['sleepScore'] as num?)?.toInt(),
      sleepSeconds: (json['sleepSeconds'] as num?)?.toInt(),
      deepSeconds: (json['deepSeconds'] as num?)?.toInt(),
      lightSeconds: (json['lightSeconds'] as num?)?.toInt(),
      remSeconds: (json['remSeconds'] as num?)?.toInt(),
      awakeSeconds: (json['awakeSeconds'] as num?)?.toInt(),
      bodyBatteryHigh: (json['bodyBatteryHigh'] as num?)?.toInt(),
      bodyBatteryLow: (json['bodyBatteryLow'] as num?)?.toInt(),
      bodyBatteryCharged: (json['bodyBatteryCharged'] as num?)?.toInt(),
      bodyBatteryDrained: (json['bodyBatteryDrained'] as num?)?.toInt(),
      stressAvg: (json['stressAvg'] as num?)?.toInt(),
      stressMax: (json['stressMax'] as num?)?.toInt(),
      steps: (json['steps'] as num?)?.toInt(),
      floorsClimbed: (json['floorsClimbed'] as num?)?.toInt(),
      activeCalories: (json['activeCalories'] as num?)?.toInt(),
      restingHeartRate: (json['restingHeartRate'] as num?)?.toInt(),
    );

Map<String, dynamic> _$HealthEntryToJson(HealthEntry instance) =>
    <String, dynamic>{
      'id': instance.id,
      'date': instance.date,
      'sleepScore': instance.sleepScore,
      'sleepSeconds': instance.sleepSeconds,
      'deepSeconds': instance.deepSeconds,
      'lightSeconds': instance.lightSeconds,
      'remSeconds': instance.remSeconds,
      'awakeSeconds': instance.awakeSeconds,
      'bodyBatteryHigh': instance.bodyBatteryHigh,
      'bodyBatteryLow': instance.bodyBatteryLow,
      'bodyBatteryCharged': instance.bodyBatteryCharged,
      'bodyBatteryDrained': instance.bodyBatteryDrained,
      'stressAvg': instance.stressAvg,
      'stressMax': instance.stressMax,
      'steps': instance.steps,
      'floorsClimbed': instance.floorsClimbed,
      'activeCalories': instance.activeCalories,
      'restingHeartRate': instance.restingHeartRate,
    };

Goal _$GoalFromJson(Map<String, dynamic> json) => Goal(
      id: json['id'] as String?,
      title: json['title'] as String,
      description: json['description'] as String?,
      timeframe: $enumDecode(_$GoalTimeframeEnumMap, json['timeframe']),
      frequency: $enumDecode(_$GoalFrequencyEnumMap, json['frequency']),
      frequencyCount: (json['frequencyCount'] as num?)?.toInt(),
      startDate: json['startDate'] as String,
      endDate: json['endDate'] as String,
      status: $enumDecodeNullable(_$GoalStatusEnumMap, json['status']) ??
          GoalStatus.active,
      createdAt: (json['createdAt'] as num).toInt(),
      modifiedAt: (json['modifiedAt'] as num).toInt(),
    );

Map<String, dynamic> _$GoalToJson(Goal instance) => <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'description': instance.description,
      'timeframe': _$GoalTimeframeEnumMap[instance.timeframe]!,
      'frequency': _$GoalFrequencyEnumMap[instance.frequency]!,
      'frequencyCount': instance.frequencyCount,
      'startDate': instance.startDate,
      'endDate': instance.endDate,
      'status': _$GoalStatusEnumMap[instance.status]!,
      'createdAt': instance.createdAt,
      'modifiedAt': instance.modifiedAt,
    };

const _$GoalTimeframeEnumMap = {
  GoalTimeframe.oneWeek: '1_week',
  GoalTimeframe.oneMonth: '1_month',
  GoalTimeframe.threeMonths: '3_months',
  GoalTimeframe.sixMonths: '6_months',
  GoalTimeframe.oneYear: '1_year',
};

const _$GoalFrequencyEnumMap = {
  GoalFrequency.daily: 'daily',
  GoalFrequency.nTimesWeek: 'n_times_week',
  GoalFrequency.auto: 'auto',
};

const _$GoalStatusEnumMap = {
  GoalStatus.active: 'active',
  GoalStatus.paused: 'paused',
  GoalStatus.completed: 'completed',
  GoalStatus.deleted: 'deleted',
};

Generation _$GenerationFromJson(Map<String, dynamic> json) => Generation(
      id: json['id'] as String?,
      generatedAt: (json['generatedAt'] as num).toInt(),
      weekStart: json['weekStart'] as String,
      weekEnd: json['weekEnd'] as String,
      taskIds: (json['taskIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      prompt: json['prompt'] as String,
      response: json['response'] as String,
      completedTaskIds: (json['completedTaskIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      skippedTaskIds: (json['skippedTaskIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      taskFeedback: (json['taskFeedback'] as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry(k, e as String),
          ) ??
          const {},
    );

Map<String, dynamic> _$GenerationToJson(Generation instance) =>
    <String, dynamic>{
      'id': instance.id,
      'generatedAt': instance.generatedAt,
      'weekStart': instance.weekStart,
      'weekEnd': instance.weekEnd,
      'taskIds': instance.taskIds,
      'prompt': instance.prompt,
      'response': instance.response,
      'completedTaskIds': instance.completedTaskIds,
      'skippedTaskIds': instance.skippedTaskIds,
      'taskFeedback': instance.taskFeedback,
    };

Accomplishment _$AccomplishmentFromJson(Map<String, dynamic> json) =>
    Accomplishment(
      id: json['id'] as String?,
      title: json['title'] as String,
      description: json['description'] as String?,
      date: json['date'] as String,
      difficultyScore: (json['difficultyScore'] as num?)?.toInt() ?? 1,
    );

Map<String, dynamic> _$AccomplishmentToJson(Accomplishment instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'description': instance.description,
      'date': instance.date,
      'difficultyScore': instance.difficultyScore,
    };

Task _$TaskFromJson(Map<String, dynamic> json) => Task(
      id: json['id'] as String?,
      added: (json['added'] as num?)?.toInt(),
      modified: json['modified'] as String? ?? '',
      title: json['title'] as String,
      description: json['description'] as String?,
      completed: json['completed'] as bool? ?? false,
      type: json['type'] as String? ?? 'task',
      tags: (json['tags'] as List<dynamic>?)
              ?.map((e) => Tag.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      priority:
          $enumDecodeNullable(_$EffortEnumMap, json['priority']) ?? Effort.low,
      dueDate: json['dueDate'] as String?,
      startTime: json['startTime'] as String?,
      endTime: json['endTime'] as String?,
      recurringTemplateId: json['recurringTemplateId'] as String?,
      goalId: json['goalId'] as String?,
      calendarEventId: json['calendarEventId'] as String?,
      feedback: json['feedback'] as String?,
      multiDayGroupId: json['multiDayGroupId'] as String?,
      multiDayPosition: json['multiDayPosition'] as String?,
      reminderTime: json['reminderTime'] as String?,
      reminderTaskName: json['reminderTaskName'] as String?,
      pushCount: (json['pushCount'] as num?)?.toInt() ?? 0,
      countdown: json['countdown'] as bool? ?? false,
      parentId: json['parentId'] as String?,
      parentTitle: json['parentTitle'] as String?,
      userId: json['userId'] as String?,
      habitId: json['habitId'] as String?,
      childCount: (json['childCount'] as num?)?.toInt() ?? 0,
      childCompletedCount: (json['childCompletedCount'] as num?)?.toInt() ?? 0,
    )..completedTime = json['completedTime'] as String?;

Map<String, dynamic> _$TaskToJson(Task instance) => <String, dynamic>{
      'id': instance.id,
      'added': instance.added,
      'modified': instance.modified,
      'title': instance.title,
      'description': instance.description,
      'completed': instance.completed,
      'type': instance.type,
      'tags': instance.tags,
      'dueDate': instance.dueDate,
      'startTime': instance.startTime,
      'endTime': instance.endTime,
      'completedTime': instance.completedTime,
      'recurringTemplateId': instance.recurringTemplateId,
      'goalId': instance.goalId,
      'calendarEventId': instance.calendarEventId,
      'feedback': instance.feedback,
      'multiDayGroupId': instance.multiDayGroupId,
      'multiDayPosition': instance.multiDayPosition,
      'reminderTime': instance.reminderTime,
      'reminderTaskName': instance.reminderTaskName,
      'parentId': instance.parentId,
      'parentTitle': instance.parentTitle,
      'userId': instance.userId,
      'habitId': instance.habitId,
      'childCount': instance.childCount,
      'childCompletedCount': instance.childCompletedCount,
      'priority': _$EffortEnumMap[instance.priority]!,
      'pushCount': instance.pushCount,
      'countdown': instance.countdown,
    };

const _$EffortEnumMap = {
  Effort.high: 'high',
  Effort.medium: 'medium',
  Effort.low: 'low',
  Effort.info: 'info',
};

Tag _$TagFromJson(Map<String, dynamic> json) => Tag(
      id: json['id'] as String,
      label: json['label'] as String,
      deleted: json['deleted'] as bool? ?? false,
      archived: json['archived'] as bool? ?? false,
    );

Map<String, dynamic> _$TagToJson(Tag instance) => <String, dynamic>{
      'id': instance.id,
      'label': instance.label,
      'deleted': instance.deleted,
      'archived': instance.archived,
    };

RecurringTask _$RecurringTaskFromJson(Map<String, dynamic> json) =>
    RecurringTask(
      recurrenceType: json['recurrenceType'] as String,
      frequency: (json['frequency'] as num?)?.toInt() ?? 1,
      daysOfWeek: (json['daysOfWeek'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as bool),
      ),
      startDate: json['startDate'] == null
          ? null
          : DateTime.parse(json['startDate'] as String),
      endDate: json['endDate'] == null
          ? null
          : DateTime.parse(json['endDate'] as String),
      dayOfMonth: (json['dayOfMonth'] as num?)?.toInt() ?? 1,
    )..id = json['id'] as String?;

Map<String, dynamic> _$RecurringTaskToJson(RecurringTask instance) =>
    <String, dynamic>{
      'id': instance.id,
      'recurrenceType': instance.recurrenceType,
      'frequency': instance.frequency,
      'daysOfWeek': instance.daysOfWeek,
      'startDate': instance.startDate?.toIso8601String(),
      'endDate': instance.endDate?.toIso8601String(),
      'dayOfMonth': instance.dayOfMonth,
    };

Kid _$KidFromJson(Map<String, dynamic> json) => Kid(
      name: json['name'] as String,
      age: (json['age'] as num).toInt(),
      birthday: json['birthday'] as String?,
      dateAdded: json['dateAdded'] as String,
    );

Map<String, dynamic> _$KidToJson(Kid instance) => <String, dynamic>{
      'name': instance.name,
      'age': instance.age,
      'birthday': instance.birthday,
      'dateAdded': instance.dateAdded,
    };

ConversationLog _$ConversationLogFromJson(Map<String, dynamic> json) =>
    ConversationLog(
      id: json['id'] as String?,
      date: json['date'] as String,
      entry: json['entry'] as String,
      createdAt: (json['createdAt'] as num?)?.toInt(),
      updatedAt: (json['updatedAt'] as num?)?.toInt(),
    );

Map<String, dynamic> _$ConversationLogToJson(ConversationLog instance) =>
    <String, dynamic>{
      'id': instance.id,
      'date': instance.date,
      'entry': instance.entry,
      'createdAt': instance.createdAt,
      'updatedAt': instance.updatedAt,
    };

Person _$PersonFromJson(Map<String, dynamic> json) => Person(
      id: json['id'] as String?,
      name: json['name'] as String,
      age: (json['age'] as num?)?.toInt(),
      birthday: json['birthday'] as String?,
      job: json['job'] as String?,
      spouse: json['spouse'] as String?,
      kids: (json['kids'] as List<dynamic>?)
              ?.map((e) => Kid.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      logs: (json['logs'] as List<dynamic>?)
              ?.map((e) => ConversationLog.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      createdAt: (json['createdAt'] as num?)?.toInt(),
      lastUpdated: (json['lastUpdated'] as num?)?.toInt(),
    );

Map<String, dynamic> _$PersonToJson(Person instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'age': instance.age,
      'birthday': instance.birthday,
      'job': instance.job,
      'spouse': instance.spouse,
      'kids': instance.kids.map((e) => e.toJson()).toList(),
      'logs': instance.logs.map((e) => e.toJson()).toList(),
      'createdAt': instance.createdAt,
      'lastUpdated': instance.lastUpdated,
    };

Habit _$HabitFromJson(Map<String, dynamic> json) => Habit(
      id: json['id'] as String?,
      title: json['title'] as String,
      effort:
          $enumDecodeNullable(_$EffortEnumMap, json['effort']) ?? Effort.low,
      recurrenceType: json['recurrenceType'] as String? ?? 'Daily',
      frequency: (json['frequency'] as num?)?.toInt() ?? 1,
      daysOfWeek: (json['daysOfWeek'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as bool),
      ),
      dayOfMonth: (json['dayOfMonth'] as num?)?.toInt(),
      startDate: json['startDate'] as String,
      reminderTime: json['reminderTime'] as String?,
      status: json['status'] as String? ?? 'active',
      currentStreak: (json['currentStreak'] as num?)?.toInt() ?? 0,
      longestStreak: (json['longestStreak'] as num?)?.toInt() ?? 0,
      lastCompletedDate: json['lastCompletedDate'] as String?,
      lastMaterializedDate: json['lastMaterializedDate'] as String?,
      createdAt: (json['createdAt'] as num?)?.toInt(),
      modifiedAt: (json['modifiedAt'] as num?)?.toInt(),
    );

Map<String, dynamic> _$HabitToJson(Habit instance) => <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'effort': _$EffortEnumMap[instance.effort]!,
      'recurrenceType': instance.recurrenceType,
      'frequency': instance.frequency,
      'daysOfWeek': instance.daysOfWeek,
      'dayOfMonth': instance.dayOfMonth,
      'startDate': instance.startDate,
      'reminderTime': instance.reminderTime,
      'status': instance.status,
      'currentStreak': instance.currentStreak,
      'longestStreak': instance.longestStreak,
      'lastCompletedDate': instance.lastCompletedDate,
      'lastMaterializedDate': instance.lastMaterializedDate,
      'createdAt': instance.createdAt,
      'modifiedAt': instance.modifiedAt,
    };

AppNotification _$AppNotificationFromJson(Map<String, dynamic> json) =>
    AppNotification(
      id: json['id'] as String?,
      title: json['title'] as String,
      body: json['body'] as String,
      data: json['data'] as Map<String, dynamic>? ?? const {},
      type: json['type'] as String?,
      sentAt: (json['sentAt'] as num).toInt(),
      read: json['read'] as bool? ?? false,
    );

Map<String, dynamic> _$AppNotificationToJson(AppNotification instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'body': instance.body,
      'data': instance.data,
      'type': instance.type,
      'sentAt': instance.sentAt,
      'read': instance.read,
    };

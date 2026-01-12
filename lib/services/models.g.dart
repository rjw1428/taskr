// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Accomplishment _$AccomplishmentFromJson(Map<String, dynamic> json) =>
    Accomplishment(
      id: json['id'] as String?,
      title: json['title'] as String,
      description: json['description'] as String?,
      date: json['date'] as String,
      difficulty:
          $enumDecodeNullable(_$DifficultyEnumMap, json['difficulty']) ??
              Difficulty.low,
    );

Map<String, dynamic> _$AccomplishmentToJson(Accomplishment instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'description': instance.description,
      'date': instance.date,
      'difficulty': _$DifficultyEnumMap[instance.difficulty]!,
    };

const _$DifficultyEnumMap = {
  Difficulty.low: 'low',
  Difficulty.medium: 'medium',
  Difficulty.high: 'high',
};

Task _$TaskFromJson(Map<String, dynamic> json) => Task(
      id: json['id'] as String?,
      added: (json['added'] as num?)?.toInt(),
      modified: json['modified'] as String? ?? '',
      title: json['title'] as String,
      description: json['description'] as String?,
      completed: json['completed'] as bool? ?? false,
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
      pushCount: (json['pushCount'] as num?)?.toInt() ?? 0,
      subtasks: (json['subtasks'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    )..completedTime = json['completedTime'] as String?;

Map<String, dynamic> _$TaskToJson(Task instance) => <String, dynamic>{
      'id': instance.id,
      'added': instance.added,
      'modified': instance.modified,
      'title': instance.title,
      'description': instance.description,
      'completed': instance.completed,
      'tags': instance.tags,
      'dueDate': instance.dueDate,
      'startTime': instance.startTime,
      'endTime': instance.endTime,
      'completedTime': instance.completedTime,
      'recurringTemplateId': instance.recurringTemplateId,
      'subtasks': instance.subtasks,
      'priority': _$EffortEnumMap[instance.priority]!,
      'pushCount': instance.pushCount,
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

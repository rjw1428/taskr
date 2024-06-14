// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Task _$TaskFromJson(Map<String, dynamic> json) => Task(
      added: (json['added'] as num?)?.toInt(),
      modified: json['modified'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      completed: json['completed'] as bool? ?? false,
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
      priority: json['priority'] as String? ?? 'low',
      dueDate: json['dueDate'] as String? ?? '',
      startTime: json['startTime'] as String? ?? '',
      endTime: json['endTime'] as String?,
      subtasks: (json['subtasks'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
    )..id = json['id'] as String?;

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
      'subtasks': instance.subtasks,
      'priority': instance.priority,
    };

Tag _$TagFromJson(Map<String, dynamic> json) => Tag(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
    );

Map<String, dynamic> _$TagToJson(Tag instance) => <String, dynamic>{
      'id': instance.id,
      'label': instance.label,
    };

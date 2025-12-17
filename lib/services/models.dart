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

  factory Accomplishment.fromJson(Map<String, dynamic> json) =>
      _$AccomplishmentFromJson(json);
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
  List<String> subtasks;
  Effort priority;
  int pushCount;
  Task(
      {this.added,
      this.modified = '',
      this.title = '',
      this.description,
      this.completed = false,
      this.tags = const [],
      this.priority = Effort.low,
      this.dueDate,
      this.startTime,
      this.endTime,
      this.pushCount = 0,
      this.subtasks = const []});

  factory Task.fromJson(Map<String, dynamic> json) => _$TaskFromJson(json);
  Map<String, dynamic> toJson() => _$TaskToJson(this);

  Map<String, dynamic> toDbTask() {
    var obj = toJson();
    obj['tags'] = tags.map((tag) => tag.id).toList();
    return (obj);
  }
}

@JsonSerializable()
class Tag {
  String id;
  String label;
  bool deleted;
  bool archived;

  Tag(
      {required this.id,
      required this.label,
      this.deleted = false,
      this.archived = false});

  factory Tag.fromJson(Map<String, dynamic> json) => _$TagFromJson(json);
  Map<String, dynamic> toJson() => _$TagToJson(this);
}

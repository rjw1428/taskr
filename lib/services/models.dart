import 'package:json_annotation/json_annotation.dart';
import 'package:taskr/shared/constants.dart';
part 'models.g.dart';

@JsonSerializable()
class Task {
  String? id;
  int? added;
  String modified;
  String title;
  String? description;
  bool completed;
  List<String> tags;
  String? dueDate;
  String? startTime;
  String? endTime;
  String? completedTime;
  List<String> subtasks;
  Priority priority;
  int pushCount;
  Task(
      {this.added,
      this.modified = '',
      this.title = '',
      this.description,
      this.completed = false,
      this.tags = const [],
      this.priority = Priority.low,
      this.dueDate,
      this.startTime,
      this.endTime,
      this.pushCount = 0,
      this.subtasks = const []});

  factory Task.fromJson(Map<String, dynamic> json) => _$TaskFromJson(json);
  Map<String, dynamic> toJson() => _$TaskToJson(this);

  Map<String, dynamic> removeNulls() {
    var obj = toJson();
    obj.removeWhere((key, value) => value == null || value == '');
    return obj;
  }
}

@JsonSerializable()
class Tag {
  String id;
  String label;

  Tag({this.id = '', this.label = ''});

  factory Tag.fromJson(Map<String, dynamic> json) => _$TagFromJson(json);
  Map<String, dynamic> toJson() => _$TagToJson(this);
}

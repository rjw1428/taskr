import 'package:json_annotation/json_annotation.dart';
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
  String dueDate;
  String startTime;
  String? endTime;
  List<String> subtasks;
  int priority;
  Task(
      {this.added,
      this.modified = '',
      this.title = '',
      this.description,
      this.completed = false,
      this.tags = const [],
      this.priority = 1,
      this.dueDate = '',
      this.startTime = '',
      this.endTime,
      this.subtasks = const []});

  factory Task.fromJson(Map<String, dynamic> json) => _$TaskFromJson(json);
  Map<String, dynamic> toJson() => _$TaskToJson(this);

  Map<String, dynamic> removeNulls() {
    var obj = toJson();
    obj.removeWhere((key, value) => value == null || value == '');
    return obj;
  }
}

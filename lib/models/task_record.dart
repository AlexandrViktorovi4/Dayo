// Прогресс по задаче за конкретную дату: 25/100 отжиманий на 2025-10-19
class TaskRecord {
  final String id;
  final String userId;
  final String taskId;
  final DateTime date;
  final int currentValue;
  final DateTime updatedAt;

  TaskRecord({
    required this.id,
    required this.userId,
    required this.taskId,
    required this.date,
    required this.currentValue,
    required this.updatedAt,
  });

  factory TaskRecord.fromJson(Map<String, dynamic> json) {
    return TaskRecord(
      id: json['id'],
      userId: json['user_id'],
      taskId: json['task_id'],
      date: DateTime.parse('${json['date']}T00:00:00Z').toLocal(),
      currentValue: json['current_value'],
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'task_id': taskId,
        'date': '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        'current_value': currentValue,
      };
}
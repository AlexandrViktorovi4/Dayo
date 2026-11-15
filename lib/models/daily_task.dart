class DailyTask {
  final String id;
  final String userId;
  final String title;
  final int targetValue;
  final String? unit;
  final bool isActive;
  final DateTime createdAt;

  DailyTask({
    required this.id,
    required this.userId,
    required this.title,
    required this.targetValue,
    this.unit,
    required this.isActive,
    required this.createdAt,
  });

  factory DailyTask.fromJson(Map<String, dynamic> json) {
    return DailyTask(
      id: json['id'],
      userId: json['user_id'],
      title: json['title'],
      targetValue: json['target_value'],
      unit: json['unit'],
      isActive: json['is_active'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'title': title,
        'target_value': targetValue,
        'unit': unit,
        'is_active': isActive,
      };
}
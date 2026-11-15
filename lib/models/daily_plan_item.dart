class DailyPlanItem {
  final String id;
  final String userId;
  final DateTime date;
  final String title;
  final List<Subtask> subtasks;
  final bool isDone;
  final int order; // ← новое поле
  final DateTime createdAt;
  final String? recurrenceId;

  DailyPlanItem({
    required this.id,
    required this.userId,
    required this.date,
    required this.title,
    required this.subtasks,
    required this.isDone,
    required this.order, // ← добавь в конструктор
    required this.createdAt,
    this.recurrenceId,
  });

  factory DailyPlanItem.fromJson(Map<String, dynamic> json) {
    return DailyPlanItem(
      id: json['id'],
      userId: json['user_id'],
      date: DateTime.parse(json['date'] as String),
      title: json['title'],
      subtasks:
          (json['subtasks'] as List?)
              ?.map((e) => Subtask.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      isDone: json['is_done'] ?? false,
      order: json['order'] ?? 0, // ← загрузка из БД
      createdAt: DateTime.parse(json['created_at']),
      recurrenceId: json['recurrence_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'date':
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
    'title': title,
    'subtasks': subtasks.map((e) => e.toJson()).toList(),
    'is_done': isDone,
    'order': order, // ← сохранение в БД
    'recurrence_id': recurrenceId,
  };
}

class Subtask {
  final String title;
  final bool done;

  Subtask({required this.title, this.done = false});

  factory Subtask.fromJson(Map<String, dynamic> json) =>
      Subtask(title: json['title'], done: json['done'] ?? false);

  Map<String, dynamic> toJson() => {'title': title, 'done': done};
}

// Оценка дня: настроение, продуктивность, заметка
class DayRecord {
  final String id;
  final String userId;
  final DateTime date;
  final int? mood; // 1–5
  final int? productivity; // 1–5
  final String? notes;
  final DateTime updatedAt;

  DayRecord({
    required this.id,
    required this.userId,
    required this.date,
    this.mood,
    this.productivity,
    this.notes,
    required this.updatedAt,
  });

  factory DayRecord.fromJson(Map<String, dynamic> json) {
    return DayRecord(
      id: json['id'],
      userId: json['user_id'],
      date: DateTime.parse('${json['date']}T00:00:00Z').toLocal(),
      mood: json['mood'],
      productivity: json['productivity'],
      notes: json['notes'],
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'date': '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        'mood': mood,
        'productivity': productivity,
        'notes': notes,
      };
}
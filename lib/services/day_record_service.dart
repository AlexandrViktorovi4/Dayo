// lib/services/day_record_service.dart
import 'package:planner/models/day_redord.dart';
import 'package:planner/services/local_database.dart';
import 'package:planner/services/local_session.dart';
import 'package:uuid/uuid.dart';

class DayRecordService {
  final Uuid _uuid = const Uuid();

  String _dateString(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  // Строка БД -> модель
  DayRecord _fromRow(Map<String, dynamic> row) {
    final json = Map<String, dynamic>.from(row);
    json['updated_at'] ??= DateTime.now().toIso8601String();
    return DayRecord.fromJson(json);
  }

  // Получить запись дня
  Future<DayRecord?> getRecordForDate(DateTime date) async {
    final db = await LocalDatabase.instance.database;
    final userId = LocalSession.instance.userId;

    final rows = await db.query(
      'day_records',
      where: 'user_id = ? AND date = ?',
      whereArgs: [userId, _dateString(date)],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  // Сохранить или обновить запись дня
  Future<void> saveRecord({
    required DateTime date,
    int? mood,
    int? productivity,
    String? notes,
  }) async {
    final db = await LocalDatabase.instance.database;
    final userId = LocalSession.instance.userId;
    final dateString = _dateString(date);

    final existing = await db.query(
      'day_records',
      columns: ['id'],
      where: 'user_id = ? AND date = ?',
      whereArgs: [userId, dateString],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      await db.update(
        'day_records',
        {
          'mood': mood,
          'productivity': productivity,
          'notes': notes,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    } else {
      await db.insert('day_records', {
        'id': _uuid.v4(),
        'user_id': userId,
        'date': dateString,
        'mood': mood,
        'productivity': productivity,
        'notes': notes,
        'updated_at': DateTime.now().toIso8601String(),
      });
    }
  }
}

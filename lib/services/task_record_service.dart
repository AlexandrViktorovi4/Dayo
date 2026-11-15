// lib/services/task_record_service.dart
import 'package:planner/models/task_record.dart';
import 'package:planner/services/local_database.dart';
import 'package:planner/services/local_session.dart';
import 'package:uuid/uuid.dart';

class TaskRecordService {
  final Uuid _uuid = const Uuid();

  String _dateString(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  // Строка БД -> модель
  TaskRecord _fromRow(Map<String, dynamic> row) {
    final json = Map<String, dynamic>.from(row);
    json['updated_at'] ??= DateTime.now().toIso8601String();
    return TaskRecord.fromJson(json);
  }

  // Получить прогресс по задачам за дату
  Future<List<TaskRecord>> getRecordsForDate(DateTime date) async {
    final db = await LocalDatabase.instance.database;
    final userId = LocalSession.instance.userId;

    final rows = await db.query(
      'task_records',
      where: 'user_id = ? AND date = ?',
      whereArgs: [userId, _dateString(date)],
    );

    return rows.map(_fromRow).toList();
  }

  // Убедиться, что записи на сегодня существуют (создать, если нет)
  Future<void> ensureRecordsForToday(List<String> taskIds) async {
    final db = await LocalDatabase.instance.database;
    final userId = LocalSession.instance.userId;
    final today = DateTime.now();
    final dateString = _dateString(today);

    for (final taskId in taskIds) {
      final existing = await db.query(
        'task_records',
        columns: ['id'],
        where: 'user_id = ? AND task_id = ? AND date = ?',
        whereArgs: [userId, taskId, dateString],
        limit: 1,
      );

      if (existing.isEmpty) {
        await db.insert('task_records', {
          'id': _uuid.v4(),
          'user_id': userId,
          'task_id': taskId,
          'date': dateString,
          'current_value': 0,
          'updated_at': DateTime.now().toIso8601String(),
        });
      }
    }
  }

  // Обновить прогресс
  Future<void> updateProgress(String recordId, int value) async {
    final db = await LocalDatabase.instance.database;
    await db.update(
      'task_records',
      {
        'current_value': value,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [recordId],
    );
  }
}

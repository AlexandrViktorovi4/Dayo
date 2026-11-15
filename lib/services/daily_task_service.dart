// lib/services/daily_task_service.dart
import 'package:planner/models/daily_task.dart';
import 'package:planner/services/local_database.dart';
import 'package:planner/services/local_session.dart';
import 'package:uuid/uuid.dart';

class DailyTaskService {
  final Uuid _uuid = const Uuid();

  // Модель -> строка БД
  Map<String, dynamic> _toRow(DailyTask task) => {
        'id': task.id,
        'user_id': task.userId,
        'title': task.title,
        'target_value': task.targetValue,
        'unit': task.unit,
        'is_active': task.isActive ? 1 : 0,
        'created_at': task.createdAt.toIso8601String(),
      };

  // Строка БД -> модель
  DailyTask _fromRow(Map<String, dynamic> row) {
    final json = Map<String, dynamic>.from(row);
    json['is_active'] = row['is_active'] == 1;
    json['created_at'] ??= DateTime.now().toIso8601String();
    return DailyTask.fromJson(json);
  }

  // Получить все активные задачи пользователя
  Future<List<DailyTask>> getActiveTasks() async {
    final db = await LocalDatabase.instance.database;
    final userId = LocalSession.instance.userId;

    final rows = await db.query(
      'daily_tasks',
      where: 'user_id = ? AND is_active = 1',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
    );

    return rows.map(_fromRow).toList();
  }

  // Создать новую задачу
  Future<void> createTask({
    required String title,
    required int targetValue,
    String? unit,
  }) async {
    final db = await LocalDatabase.instance.database;
    final userId = LocalSession.instance.userId;

    final task = DailyTask(
      id: _uuid.v4(),
      userId: userId,
      title: title,
      targetValue: targetValue,
      unit: unit ?? 'раз',
      isActive: true,
      createdAt: DateTime.now(),
    );

    await db.insert('daily_tasks', _toRow(task));
  }

  // Обновить статус активности
  Future<void> toggleActive(String taskId, bool isActive) async {
    final db = await LocalDatabase.instance.database;
    await db.update(
      'daily_tasks',
      {'is_active': isActive ? 1 : 0},
      where: 'id = ?',
      whereArgs: [taskId],
    );
  }

  // Удалить задачу
  Future<void> deleteTask(String taskId) async {
    final db = await LocalDatabase.instance.database;
    await db.delete('daily_tasks', where: 'id = ?', whereArgs: [taskId]);
  }
}

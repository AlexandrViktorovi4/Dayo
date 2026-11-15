// lib/services/daily_plan_service.dart
import 'dart:convert';
import 'package:planner/models/daily_plan_item.dart';
import 'package:planner/services/local_database.dart';
import 'package:planner/services/local_session.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class DailyPlanService {
  DailyPlanService({
    Future<Database> Function()? databaseProvider,
    String Function()? userIdProvider,
  }) : _databaseProvider =
           databaseProvider ?? (() => LocalDatabase.instance.database),
       _userIdProvider = userIdProvider ?? (() => LocalSession.instance.userId);

  final Future<Database> Function() _databaseProvider;
  final String Function() _userIdProvider;
  final Uuid _uuid = const Uuid();

  String _dateString(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  // Модель -> строка БД
  Map<String, dynamic> _toRow(DailyPlanItem task) => {
    'id': task.id,
    'user_id': task.userId,
    'date': _dateString(task.date),
    'title': task.title,
    'subtasks': jsonEncode(task.subtasks.map((e) => e.toJson()).toList()),
    'is_done': task.isDone ? 1 : 0,
    'order': task.order,
    'created_at': task.createdAt.toIso8601String(),
    'recurrence_id': task.recurrenceId,
  };

  // Строка БД -> модель
  DailyPlanItem _fromRow(Map<String, dynamic> row) {
    final json = Map<String, dynamic>.from(row);
    json['subtasks'] = jsonDecode((row['subtasks'] as String?) ?? '[]');
    json['is_done'] = row['is_done'] == 1;
    json['created_at'] ??= DateTime.now().toIso8601String();
    json['recurrence_id'] = row['recurrence_id'];
    return DailyPlanItem.fromJson(json);
  }

  Future<List<DailyPlanItem>> getPlanForDate(DateTime date) async {
    final db = await _databaseProvider();
    final userId = _userIdProvider();
    await _ensureRecurringTasksForRange(date, date);

    final rows = await db.query(
      'daily_plan_items',
      where: 'user_id = ? AND date = ?',
      whereArgs: [userId, _dateString(date)],
      orderBy: '"order" ASC',
    );

    return rows.map(_fromRow).toList();
  }

  // Загрузить задачи за диапазон дат в одном запросе
  Future<Map<DateTime, List<DailyPlanItem>>> getPlanForDateRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final db = await _databaseProvider();
    final userId = _userIdProvider();
    await _ensureRecurringTasksForRange(startDate, endDate);

    final rows = await db.query(
      'daily_plan_items',
      where: 'user_id = ? AND date >= ? AND date <= ?',
      whereArgs: [userId, _dateString(startDate), _dateString(endDate)],
      orderBy: 'date ASC, "order" ASC',
    );

    final grouped = <DateTime, List<DailyPlanItem>>{};
    for (final row in rows) {
      final task = _fromRow(row);
      final dateKey = DateTime(task.date.year, task.date.month, task.date.day);
      grouped.update(
        dateKey,
        (value) => [...value, task],
        ifAbsent: () => [task],
      );
    }

    return grouped;
  }

  Future<void> _ensureRecurringTasksForRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final db = await _databaseProvider();
    final userId = _userIdProvider();
    final rangeStart = DateTime.utc(
      startDate.year,
      startDate.month,
      startDate.day,
    );
    final rangeEnd = DateTime.utc(endDate.year, endDate.month, endDate.day);
    if (rangeStart.isAfter(rangeEnd)) return;

    final recurringTasks = await db.query(
      'recurring_tasks',
      where: 'user_id = ? AND is_active = 1 AND start_date <= ?',
      whereArgs: [userId, _dateString(rangeEnd)],
    );
    if (recurringTasks.isEmpty) return;

    await db.transaction((transaction) async {
      for (final recurringTask in recurringTasks) {
        final start = DateTime.parse(
          '${recurringTask['start_date']}T00:00:00Z',
        );
        var date = start.isAfter(rangeStart) ? start : rangeStart;

        while (!date.isAfter(rangeEnd)) {
          final dateString = _dateString(date);
          final existingOccurrence = await transaction.query(
            'daily_plan_items',
            columns: ['id'],
            where: 'recurrence_id = ? AND date = ?',
            whereArgs: [recurringTask['id'], dateString],
            limit: 1,
          );
          if (existingOccurrence.isEmpty) {
            final skippedOccurrence = await transaction.query(
              'recurring_task_skips',
              columns: ['date'],
              where: 'recurring_task_id = ? AND date = ?',
              whereArgs: [recurringTask['id'], dateString],
              limit: 1,
            );

            if (skippedOccurrence.isEmpty) {
              final orderRows = await transaction.rawQuery(
                'SELECT MAX("order") AS max_order FROM daily_plan_items '
                'WHERE user_id = ? AND date = ?',
                [userId, dateString],
              );
              final maxOrder = orderRows.single['max_order'];
              final order = maxOrder is num ? maxOrder.toInt() + 1 : 0;

              await transaction.insert('daily_plan_items', {
                'id': _uuid.v4(),
                'user_id': userId,
                'date': dateString,
                'title': recurringTask['title'],
                'subtasks': recurringTask['subtasks'],
                'is_done': 0,
                'order': order,
                'created_at': DateTime.now().toIso8601String(),
                'recurrence_id': recurringTask['id'],
              });
            }
          }

          date = date.add(const Duration(days: 1));
        }
      }
    });
  }

  // Метод для добавления задачи (используется в home_screen.dart)
  Future<void> addTask(DailyPlanItem task) async {
    final db = await _databaseProvider();
    await db.insert(
      'daily_plan_items',
      _toRow(task),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> createTask({
    required DateTime date,
    required String title,
    List<Subtask>? subtasks,
    int? order,
  }) async {
    final userId = _userIdProvider();

    final task = DailyPlanItem(
      id: _uuid.v4(),
      userId: userId,
      date: date,
      title: title,
      subtasks: subtasks ?? [],
      isDone: false,
      order: order ?? 0,
      createdAt: DateTime.now(),
    );

    await addTask(task);
  }

  Future<void> createRecurringTask({
    required DateTime startDate,
    required String title,
    List<Subtask>? subtasks,
  }) async {
    final db = await _databaseProvider();
    await db.insert('recurring_tasks', {
      'id': _uuid.v4(),
      'user_id': _userIdProvider(),
      'title': title,
      'subtasks': jsonEncode(
        subtasks?.map((subtask) => subtask.toJson()).toList() ?? [],
      ),
      'start_date': _dateString(startDate),
      'is_active': 1,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> stopRecurringTask(String recurringTaskId) async {
    final db = await _databaseProvider();
    final userId = _userIdProvider();
    final today = _dateString(DateTime.now());

    await db.transaction((transaction) async {
      final matches = await transaction.query(
        'recurring_tasks',
        columns: ['id'],
        where: 'id = ? AND user_id = ? AND is_active = 1',
        whereArgs: [recurringTaskId, userId],
        limit: 1,
      );
      if (matches.isEmpty) {
        throw StateError('Повторяющаяся задача не найдена или уже отключена.');
      }

      await transaction.update(
        'recurring_tasks',
        {'is_active': 0},
        where: 'id = ? AND user_id = ?',
        whereArgs: [recurringTaskId, userId],
      );
      await transaction.delete(
        'daily_plan_items',
        where: 'recurrence_id = ? AND date > ?',
        whereArgs: [recurringTaskId, today],
      );
      await transaction.update(
        'daily_plan_items',
        {'recurrence_id': null},
        where: 'recurrence_id = ?',
        whereArgs: [recurringTaskId],
      );
      await transaction.delete(
        'recurring_task_skips',
        where: 'recurring_task_id = ? AND date > ?',
        whereArgs: [recurringTaskId, today],
      );
    });
  }

  Future<void> updateTask(DailyPlanItem task) async {
    final db = await _databaseProvider();
    await db.update(
      'daily_plan_items',
      _toRow(task),
      where: 'id = ?',
      whereArgs: [task.id],
    );
  }

  // Массовое обновление порядка
  Future<void> updateTasksOrder(List<DailyPlanItem> tasks) async {
    final db = await _databaseProvider();
    final batch = db.batch();
    for (final task in tasks) {
      batch.insert(
        'daily_plan_items',
        _toRow(task),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> deleteTask(String taskId) async {
    final db = await _databaseProvider();
    final rows = await db.query(
      'daily_plan_items',
      columns: ['user_id', 'date', 'recurrence_id'],
      where: 'id = ?',
      whereArgs: [taskId],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final row = rows.first;
    final recurrenceId = row['recurrence_id'];
    if (recurrenceId is String) {
      await db.transaction((transaction) async {
        await transaction.insert('recurring_task_skips', {
          'recurring_task_id': recurrenceId,
          'user_id': row['user_id'],
          'date': row['date'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await transaction.delete(
          'daily_plan_items',
          where: 'id = ?',
          whereArgs: [taskId],
        );
      });
    } else {
      await db.delete('daily_plan_items', where: 'id = ?', whereArgs: [taskId]);
    }
  }
}

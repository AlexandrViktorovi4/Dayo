import 'package:flutter_test/flutter_test.dart';
import 'package:planner/models/daily_plan_item.dart';
import 'package:planner/services/daily_plan_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'daily occurrences are independent, skippable, and stop with the rule',
    () async {
      final database = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute('''
            CREATE TABLE daily_plan_items (
              id TEXT PRIMARY KEY,
              user_id TEXT NOT NULL,
              date TEXT NOT NULL,
              title TEXT NOT NULL,
              subtasks TEXT,
              is_done INTEGER NOT NULL DEFAULT 0,
              "order" INTEGER NOT NULL DEFAULT 0,
              created_at TEXT,
              recurrence_id TEXT
            )
          ''');
            await db.execute('''
            CREATE TABLE recurring_tasks (
              id TEXT PRIMARY KEY,
              user_id TEXT NOT NULL,
              title TEXT NOT NULL,
              subtasks TEXT NOT NULL DEFAULT '[]',
              start_date TEXT NOT NULL,
              is_active INTEGER NOT NULL DEFAULT 1,
              created_at TEXT NOT NULL
            )
          ''');
            await db.execute('''
            CREATE TABLE recurring_task_skips (
              recurring_task_id TEXT NOT NULL,
              user_id TEXT NOT NULL,
              date TEXT NOT NULL,
              PRIMARY KEY (recurring_task_id, date)
            )
          ''');
            await db.execute(
              'CREATE UNIQUE INDEX idx_plan_recurring_date '
              'ON daily_plan_items(recurrence_id, date) '
              'WHERE recurrence_id IS NOT NULL',
            );
          },
        ),
      );

      final service = DailyPlanService(
        databaseProvider: () async => database,
        userIdProvider: () => 'user-1',
      );
      final now = DateTime.now();
      final startDate = DateTime(now.year, now.month, now.day);
      final nextDate = startDate.add(const Duration(days: 1));
      final thirdDate = startDate.add(const Duration(days: 2));
      final fourthDate = startDate.add(const Duration(days: 3));

      try {
        await service.createRecurringTask(
          startDate: startDate,
          title: 'Прогулка',
          subtasks: [Subtask(title: 'Взять воду')],
        );

        final firstDay = await service.getPlanForDate(startDate);
        final nextDay = await service.getPlanForDate(nextDate);
        final recurringId = firstDay.single.recurrenceId!;

        expect(nextDay, hasLength(1));
        expect(nextDay.single.recurrenceId, recurringId);
        expect(nextDay.single.id, isNot(firstDay.single.id));
        expect(nextDay.single.subtasks.single.title, 'Взять воду');

        await service.updateTask(
          DailyPlanItem(
            id: firstDay.single.id,
            userId: firstDay.single.userId,
            date: firstDay.single.date,
            title: firstDay.single.title,
            subtasks: firstDay.single.subtasks,
            isDone: true,
            order: firstDay.single.order,
            createdAt: firstDay.single.createdAt,
            recurrenceId: recurringId,
          ),
        );
        expect((await service.getPlanForDate(startDate)).single.isDone, isTrue);
        expect((await service.getPlanForDate(nextDate)).single.isDone, isFalse);

        await service.deleteTask(nextDay.single.id);
        expect(await service.getPlanForDate(nextDate), isEmpty);

        expect(await service.getPlanForDate(thirdDate), hasLength(1));
        await service.stopRecurringTask(recurringId);

        final remainingToday = await service.getPlanForDate(startDate);
        expect(remainingToday, hasLength(1));
        expect(remainingToday.single.recurrenceId, isNull);
        expect(await service.getPlanForDate(thirdDate), isEmpty);
        expect(await service.getPlanForDate(fourthDate), isEmpty);
      } finally {
        await database.close();
      }
    },
  );
}

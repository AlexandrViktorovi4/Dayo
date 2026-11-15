// test/widget_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:planner/models/daily_plan_item.dart';
import 'package:planner/models/streak.dart';

void main() {
  test('DailyPlanItem корректно сохраняется и читается из JSON', () {
    final item = DailyPlanItem(
      id: 'id-1',
      userId: 'user-1',
      date: DateTime(2026, 11, 12),
      title: 'Задача',
      subtasks: [Subtask(title: 'Подзадача', done: true)],
      isDone: false,
      order: 2,
      createdAt: DateTime(2026, 11, 12, 8, 30),
    );

    final json = item.toJson();
    // toJson не включает created_at, сервис БД добавляет его отдельно
    json['created_at'] = item.createdAt.toIso8601String();
    final restored = DailyPlanItem.fromJson(json);

    expect(restored.id, 'id-1');
    expect(restored.title, 'Задача');
    expect(restored.order, 2);
    expect(restored.subtasks.length, 1);
    expect(restored.subtasks.first.done, true);
    expect(restored.date.year, 2026);
    expect(restored.date.month, 11);
    expect(restored.date.day, 12);
    expect(restored.date, DateTime(2026, 11, 12));
  });

  test('Streak.empty создаёт нулевой стрик', () {
    final streak = Streak.empty();
    expect(streak.currentStreak, 0);
    expect(streak.longestStreak, 0);
    expect(streak.activityDates, isEmpty);
    expect(streak.totalTasksCompleted, 0);
  });
}

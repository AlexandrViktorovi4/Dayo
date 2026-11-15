import 'package:flutter_test/flutter_test.dart';
import 'package:planner/models/daily_plan_item.dart';
import 'package:planner/utils/daily_plan_filter.dart';

void main() {
  final tasks = [
    DailyPlanItem(
      id: 'task-1',
      userId: 'user-1',
      date: DateTime(2026, 11, 15),
      title: 'Купить продукты',
      subtasks: [Subtask(title: 'Молоко')],
      isDone: false,
      order: 0,
      createdAt: DateTime(2026, 11, 15),
    ),
    DailyPlanItem(
      id: 'task-2',
      userId: 'user-1',
      date: DateTime(2026, 11, 15),
      title: 'Позвонить врачу',
      subtasks: [],
      isDone: true,
      order: 1,
      createdAt: DateTime(2026, 11, 15),
    ),
  ];

  test('search is case-insensitive and includes subtask titles', () {
    expect(
      filterDailyPlanItems(tasks, query: 'МОЛОКО').map((task) => task.id),
      ['task-1'],
    );
    expect(filterDailyPlanItems(tasks, query: 'врачу').map((task) => task.id), [
      'task-2',
    ]);
  });

  test('completion filter can be combined with search', () {
    expect(
      filterDailyPlanItems(
        tasks,
        query: 'Купить',
        completionFilter: DailyPlanCompletionFilter.incomplete,
      ).map((task) => task.id),
      ['task-1'],
    );
    expect(
      filterDailyPlanItems(
        tasks,
        completionFilter: DailyPlanCompletionFilter.completed,
      ).map((task) => task.id),
      ['task-2'],
    );
  });
}

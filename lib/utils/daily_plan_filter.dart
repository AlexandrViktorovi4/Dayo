import 'package:planner/models/daily_plan_item.dart';

enum DailyPlanCompletionFilter { all, incomplete, completed }

List<DailyPlanItem> filterDailyPlanItems(
  Iterable<DailyPlanItem> tasks, {
  String query = '',
  DailyPlanCompletionFilter completionFilter = DailyPlanCompletionFilter.all,
}) {
  final normalizedQuery = query.trim().toLowerCase();

  return tasks.where((task) {
    final matchesQuery =
        normalizedQuery.isEmpty ||
        task.title.toLowerCase().contains(normalizedQuery) ||
        task.subtasks.any(
          (subtask) => subtask.title.toLowerCase().contains(normalizedQuery),
        );
    final matchesCompletion = switch (completionFilter) {
      DailyPlanCompletionFilter.all => true,
      DailyPlanCompletionFilter.incomplete => !task.isDone,
      DailyPlanCompletionFilter.completed => task.isDone,
    };

    return matchesQuery && matchesCompletion;
  }).toList();
}

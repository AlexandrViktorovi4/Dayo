// lib/models/streak.dart
class Streak {
  final int currentStreak;
  final int longestStreak;
  final DateTime? lastActivityDate;
  final List<DateTime> activityDates;
  final int totalTasksCompleted;

  Streak({
    required this.currentStreak,
    required this.longestStreak,
    required this.lastActivityDate,
    required this.activityDates,
    required this.totalTasksCompleted,
  });

  factory Streak.empty() {
    return Streak(
      currentStreak: 0,
      longestStreak: 0,
      lastActivityDate: null,
      activityDates: [],
      totalTasksCompleted: 0,
    );
  }

  factory Streak.fromJson(Map<String, dynamic> json) {
    return Streak(
      currentStreak: json['current_streak'] ?? 0,
      longestStreak: json['longest_streak'] ?? 0,
      lastActivityDate: json['last_activity_date'] != null
          ? DateTime.parse(json['last_activity_date'])
          : null,
      activityDates: (json['activity_dates'] as List<dynamic>?)
              ?.map((date) => DateTime.parse(date))
              .toList() ??
          [],
      totalTasksCompleted: json['total_tasks_completed'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'current_streak': currentStreak,
      'longest_streak': longestStreak,
      'last_activity_date': lastActivityDate?.toIso8601String(),
      'activity_dates': activityDates.map((date) => date.toIso8601String()).toList(),
      'total_tasks_completed': totalTasksCompleted,
    };
  }
}
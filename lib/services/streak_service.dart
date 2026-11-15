// lib/services/streak_service.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:planner/models/streak.dart';
import 'package:planner/services/local_database.dart';
import 'package:planner/services/local_session.dart';

class StreakService {
  // Строка БД -> модель
  Streak _fromRow(Map<String, dynamic> row) {
    final json = Map<String, dynamic>.from(row);
    json['activity_dates'] = jsonDecode((row['activity_dates'] as String?) ?? '[]');
    return Streak.fromJson(json);
  }

  // Получить текущий стрик пользователя
  Future<Streak> getCurrentStreak() async {
    try {
      final db = await LocalDatabase.instance.database;
      final userId = LocalSession.instance.userId;

      final rows = await db.query(
        'streaks',
        where: 'user_id = ?',
        whereArgs: [userId],
        limit: 1,
      );

      if (rows.isEmpty) {
        // Создаем запись если не существует
        return await _createStreakRecord(userId);
      }

      return _fromRow(rows.first);
    } catch (e) {
      return Streak.empty();
    }
  }

  // Создать запись стрика
  Future<Streak> _createStreakRecord(String userId) async {
    final db = await LocalDatabase.instance.database;
    final streak = Streak.empty();
    final now = DateTime.now().toIso8601String();

    await db.insert('streaks', {
      'user_id': userId,
      'current_streak': streak.currentStreak,
      'longest_streak': streak.longestStreak,
      'last_activity_date': streak.lastActivityDate?.toIso8601String(),
      'activity_dates': jsonEncode(
          streak.activityDates.map((date) => date.toIso8601String()).toList()),
      'total_tasks_completed': streak.totalTasksCompleted,
      'created_at': now,
      'updated_at': now,
    });

    return streak;
  }

  // Обновить стрик при выполнении задачи
  Future<void> updateStreakOnTaskCompletion() async {
    try {
      final db = await LocalDatabase.instance.database;
      final userId = LocalSession.instance.userId;

      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);

      // Получаем текущий стрик
      final currentStreak = await getCurrentStreak();

      // Проверяем, был ли сегодня уже учтен
      final todayAlreadyCounted = currentStreak.activityDates.any((date) {
        final activityDate = DateTime(date.year, date.month, date.day);
        return activityDate.isAtSameMomentAs(todayDate);
      });

      if (todayAlreadyCounted) {
        // Сегодня уже учтено, просто увеличиваем счетчик задач
        await db.update(
          'streaks',
          {
            'total_tasks_completed': currentStreak.totalTasksCompleted + 1,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'user_id = ?',
          whereArgs: [userId],
        );
        return;
      }

      // Проверяем, был ли вчера активность
      final yesterday = today.subtract(const Duration(days: 1));
      final yesterdayDate =
          DateTime(yesterday.year, yesterday.month, yesterday.day);

      final yesterdayWasActive = currentStreak.activityDates.any((date) {
        final activityDate = DateTime(date.year, date.month, date.day);
        return activityDate.isAtSameMomentAs(yesterdayDate);
      });

      int newCurrentStreak;
      if (currentStreak.lastActivityDate == null) {
        // Первая активность
        newCurrentStreak = 1;
      } else if (yesterdayWasActive) {
        // Подряд идут дни
        newCurrentStreak = currentStreak.currentStreak + 1;
      } else {
        // Разрыв в цепи - начинаем с 1
        newCurrentStreak = 1;
      }

      // Обновляем самый длинный стрик
      final newLongestStreak = newCurrentStreak > currentStreak.longestStreak
          ? newCurrentStreak
          : currentStreak.longestStreak;

      // Добавляем сегодняшнюю дату
      final newActivityDates = [...currentStreak.activityDates, today];

      // Обновляем в базе
      await db.update(
        'streaks',
        {
          'current_streak': newCurrentStreak,
          'longest_streak': newLongestStreak,
          'last_activity_date': today.toIso8601String(),
          'activity_dates': jsonEncode(
              newActivityDates.map((date) => date.toIso8601String()).toList()),
          'total_tasks_completed': currentStreak.totalTasksCompleted + 1,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'user_id = ?',
        whereArgs: [userId],
      );
    } catch (e) {
      // Ошибка обновления стрика не должна ломать основной сценарий
    }
  }

  // Получить статистику за неделю
  Future<List<bool>> getWeeklyActivity() async {
    try {
      final currentStreak = await getCurrentStreak();
      final today = DateTime.now();

      // Создаем список из 7 дней (сегодня + 6 предыдущих)
      List<bool> weeklyActivity = [];

      for (int i = 6; i >= 0; i--) {
        final date = today.subtract(Duration(days: i));
        final dateOnly = DateTime(date.year, date.month, date.day);

        final wasActive = currentStreak.activityDates.any((activityDate) {
          final activityDateOnly = DateTime(
              activityDate.year, activityDate.month, activityDate.day);
          return activityDateOnly.isAtSameMomentAs(dateOnly);
        });

        weeklyActivity.add(wasActive);
      }

      return weeklyActivity;
    } catch (e) {
      return List.filled(7, false);
    }
  }

  // Получить активность за месяц
  Future<List<bool>> getMonthlyActivity() async {
    try {
      final currentStreak = await getCurrentStreak();
      final today = DateTime.now();

      // Создаем список из 30 дней
      List<bool> monthlyActivity = [];

      for (int i = 29; i >= 0; i--) {
        final date = today.subtract(Duration(days: i));
        final dateOnly = DateTime(date.year, date.month, date.day);

        final wasActive = currentStreak.activityDates.any((activityDate) {
          final activityDateOnly = DateTime(
              activityDate.year, activityDate.month, activityDate.day);
          return activityDateOnly.isAtSameMomentAs(dateOnly);
        });

        monthlyActivity.add(wasActive);
      }

      return monthlyActivity;
    } catch (e) {
      return List.filled(30, false);
    }
  }

  // Получить достижения
  Future<Map<String, bool>> getAchievements() async {
    try {
      final currentStreak = await getCurrentStreak();

      return {
        'first_day': currentStreak.totalTasksCompleted >= 1,
        'three_days_streak': currentStreak.longestStreak >= 3,
        'seven_days_streak': currentStreak.longestStreak >= 7,
        'thirty_days_streak': currentStreak.longestStreak >= 30,
        'ten_tasks': currentStreak.totalTasksCompleted >= 10,
        'fifty_tasks': currentStreak.totalTasksCompleted >= 50,
        'hundred_tasks': currentStreak.totalTasksCompleted >= 100,
      };
    } catch (e) {
      return {};
    }
  }

  // Получить мотивационное сообщение на основе стрика
  String getMotivationalMessage(Streak streak) {
    if (streak.currentStreak == 0) {
      return 'Начни свой первый стрик сегодня! 🔥';
    } else if (streak.currentStreak == 1) {
      return 'Отличное начало! Продолжай завтра! 💪';
    } else if (streak.currentStreak < 7) {
      return 'Так держать! Уже ${streak.currentStreak} дня подряд! 🚀';
    } else if (streak.currentStreak < 30) {
      return 'Недельный стрик! Ты на огне! 🔥🔥';
    } else {
      return 'Легенда! ${streak.currentStreak} дней подряд! 🏆';
    }
  }

  // Проверить, можно ли обновить стрик сегодня
  Future<bool> canUpdateStreakToday() async {
    try {
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);

      final currentStreak = await getCurrentStreak();

      return !currentStreak.activityDates.any((date) {
        final activityDate = DateTime(date.year, date.month, date.day);
        return activityDate.isAtSameMomentAs(todayDate);
      });
    } catch (e) {
      return true;
    }
  }

  // Сбросить стрик (для отладки)
  Future<void> resetStreak() async {
    try {
      final db = await LocalDatabase.instance.database;
      final userId = LocalSession.instance.userId;

      await db.update(
        'streaks',
        {
          'current_streak': 0,
          'longest_streak': 0,
          'activity_dates': jsonEncode([]),
          'last_activity_date': null,
          'total_tasks_completed': 0,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'user_id = ?',
        whereArgs: [userId],
      );
    } catch (e) {
      // игнорируем ошибку сброса
    }
  }

  // Получить данные для графика прогресса
  Future<Map<String, dynamic>> getProgressData() async {
    try {
      final streak = await getCurrentStreak();
      final weeklyActivity = await getWeeklyActivity();
      final monthlyActivity = await getMonthlyActivity();
      final achievements = await getAchievements();

      return {
        'streak': streak,
        'weekly_activity': weeklyActivity,
        'monthly_activity': monthlyActivity,
        'achievements': achievements,
        'motivational_message': getMotivationalMessage(streak),
        'next_milestone': _getNextMilestone(streak.currentStreak),
      };
    } catch (e) {
      return {};
    }
  }

  // Получить следующий этап
  String _getNextMilestone(int currentStreak) {
    if (currentStreak < 3) return '3 дня';
    if (currentStreak < 7) return '7 дней';
    if (currentStreak < 14) return '2 недели';
    if (currentStreak < 30) return '30 дней';
    if (currentStreak < 60) return '60 дней';
    if (currentStreak < 90) return '90 дней';
    if (currentStreak < 100) return '100 дней';
    return '200 дней';
  }

  // Получить цвет стрика на основе его длины
  static Color getStreakColor(int streak) {
    if (streak == 0) return Colors.grey;
    if (streak < 3) return Colors.orange;
    if (streak < 7) return Colors.red;
    if (streak < 30) return const Color(0xFFFF6B6B);
    if (streak < 60) return const Color(0xFFFF8E53);
    if (streak < 90) return const Color(0xFFFFD700);
    return const Color(0xFF00D4AA);
  }

  // Получить иконку стрика на основе его длины
  static IconData getStreakIcon(int streak) {
    if (streak == 0) return Icons.local_fire_department_outlined;
    if (streak < 7) return Icons.local_fire_department;
    if (streak < 30) return Icons.whatshot;
    return Icons.auto_awesome;
  }

  // Получить уровень стрика
  static String getStreakLevel(int streak) {
    if (streak == 0) return 'Новичок';
    if (streak < 3) return 'Начинающий';
    if (streak < 7) return 'Активный';
    if (streak < 30) return 'Опытный';
    if (streak < 60) return 'Мастер';
    if (streak < 90) return 'Легенда';
    return 'Бог продуктивности';
  }
}

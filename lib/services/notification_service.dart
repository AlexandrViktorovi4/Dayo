// lib/services/notification_service.dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  late FlutterLocalNotificationsPlugin _notificationsPlugin;

  Future<void> init() async {
    tz_data.initializeTimeZones();
    _notificationsPlugin = FlutterLocalNotificationsPlugin();

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    final InitializationSettings settings =
        InitializationSettings(android: androidSettings, iOS: iosSettings);

    await _notificationsPlugin.initialize(settings);

    // Создание каналов уведомлений для Android
    await _createNotificationChannels();
  }

  Future<bool?> areNotificationsEnabled() async {
    final android = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return android.areNotificationsEnabled();
    }

    final ios = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return (await ios.checkPermissions())?.isEnabled;
    }
    return null;
  }

  Future<bool?> requestNotificationPermission() async {
    final android = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return android.requestNotificationsPermission();
    }

    final ios = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return ios.requestPermissions(alert: true, badge: true, sound: true);
    }
    return null;
  }

  Future<void> scheduleDailyPlanReminder() async {
    await _scheduleDailyNotification(
      id: 1,
      hour: 9,
      minute: 0,
      title: 'Планировщик задач',
      body: 'Доброе утро! Не забудьте заполнить план на сегодня 📝',
      channel: 'daily_plan_reminder',
    );
  }

  Future<void> scheduleTaskReminder() async {
    await _scheduleDailyNotification(
      id: 2,
      hour: 18,
      minute: 0,
      title: 'Напоминание о задачах',
      body: 'Не забудьте отметить выполнение задач на сегодня! ✅',
      channel: 'task_reminder',
    );
  }

  Future<void> scheduleRecurringTaskReminders(int intervalHours) async {
    // Отменяем предыдущие повторяющиеся уведомления
    await cancelRecurringReminders();

    if (intervalHours == 0) return; // Если интервал 0, не планируем

    final repeatDuration = Duration(hours: intervalHours);

    await _notificationsPlugin.periodicallyShowWithDuration(
      100, // Уникальный ID для повторяющихся уведомлений
      'Напоминание о задачах',
      'Проверьте свои задачи! 📋',
      repeatDuration,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'recurring_task_reminder',
          'Повторяющиеся напоминания',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<void> cancelRecurringReminders() async {
    await _notificationsPlugin.cancel(100);
  }

  Future<void> scheduleIncompleteTasksReminder() async {
    await _scheduleDailyNotification(
      id: 3,
      hour: 21,
      minute: 0,
      title: 'Невыполненные задачи',
      body: 'У вас остались невыполненные задачи на сегодня! 🕒',
      channel: 'incomplete_tasks_reminder',
    );
  }

  Future<void> _scheduleDailyNotification({
    required int id,
    required int hour,
    required int minute,
    required String title,
    required String body,
    required String channel,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    await _notificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      scheduledDate,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel,
          _formatChannelName(channel),
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      // timeZone НЕ НУЖЕН — дата уже содержит временную зону
    );
  }

  String _formatChannelName(String channel) {
    return channel.split('_').map((word) =>
      '${word[0].toUpperCase()}${word.substring(1)}'
    ).join(' ');
  }

  Future<void> showMotivationalNotification() async {
    await _notificationsPlugin.show(
      4,
      'Отличная работа! 🎉',
      'Поздравляем! Вы выполнили все задачи на сегодня!',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'motivational_channel',
          'Мотивация',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  Future<void> _createNotificationChannels() async {
    const AndroidNotificationChannel dailyPlanChannel = AndroidNotificationChannel(
      'daily_plan_reminder',
      'Напоминания о плане',
      description: 'Ежедневные напоминания о заполнении плана задач',
      importance: Importance.max,
    );

    const AndroidNotificationChannel taskReminderChannel = AndroidNotificationChannel(
      'task_reminder',
      'Напоминания о задачах',
      description: 'Напоминания о выполнении задач',
      importance: Importance.max,
    );

    const AndroidNotificationChannel incompleteTasksChannel = AndroidNotificationChannel(
      'incomplete_tasks_reminder',
      'Невыполненные задачи',
      description: 'Напоминания о невыполненных задачах',
      importance: Importance.max,
    );

    const AndroidNotificationChannel motivationalChannel = AndroidNotificationChannel(
      'motivational_channel',
      'Мотивация',
      description: 'Мотивационные уведомления',
      importance: Importance.max,
    );

    const AndroidNotificationChannel recurringChannel = AndroidNotificationChannel(
      'recurring_task_reminder',
      'Повторяющиеся напоминания',
      description: 'Регулярные напоминания о задачах',
      importance: Importance.defaultImportance,
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(dailyPlanChannel);

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(taskReminderChannel);

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(incompleteTasksChannel);

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(motivationalChannel);

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(recurringChannel);
  }

}
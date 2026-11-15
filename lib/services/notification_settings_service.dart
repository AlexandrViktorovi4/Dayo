// lib/services/notification_settings_service.dart
import 'package:shared_preferences/shared_preferences.dart';

class NotificationSettingsService {
  static const String _reminderIntervalKey = 'reminder_interval_hours';
  static const String _remindersEnabledKey = 'reminders_enabled';

  Future<int> getReminderInterval() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_reminderIntervalKey) ?? 0; // 0 означает отключено
  }

  Future<void> setReminderInterval(int hours) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_reminderIntervalKey, hours);
  }

  Future<bool> areRemindersEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_remindersEnabledKey) ?? false;
  }

  Future<void> setRemindersEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_remindersEnabledKey, enabled);
  }
}
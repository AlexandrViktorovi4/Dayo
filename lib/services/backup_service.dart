import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:planner/services/avatar_service.dart';
import 'package:planner/services/local_database.dart';
import 'package:planner/services/local_session.dart';
import 'package:planner/services/notification_settings_service.dart';
import 'package:planner/services/theme_service.dart';

class BackupSnapshot {
  const BackupSnapshot({
    required this.createdAt,
    required this.userId,
    required this.name,
    required this.themeIndex,
    required this.remindersEnabled,
    required this.reminderIntervalHours,
    required this.tables,
    required this.avatarFileName,
    required this.avatarBytes,
  });

  final DateTime createdAt;
  final String userId;
  final String? name;
  final int themeIndex;
  final bool remindersEnabled;
  final int reminderIntervalHours;
  final Map<String, List<Map<String, Object?>>> tables;
  final String? avatarFileName;
  final Uint8List? avatarBytes;

  int get recordCount =>
      tables.values.fold(0, (total, rows) => total + rows.length);
}

class BackupService {
  static const String _format = 'planner_backup';
  static const int _version = 1;
  static const int _maxBackupBytes = 16 * 1024 * 1024;
  static const int _maxAvatarBytes = 5 * 1024 * 1024;

  Future<Uint8List> createBackup() async {
    final tables = await LocalDatabase.instance.exportAll();
    final userId = LocalSession.instance.userId;
    final theme = await ThemeService().getTheme();
    final notifications = NotificationSettingsService();
    final avatar = await _readAvatar(tables, userId);

    final backup = <String, Object?>{
      'format': _format,
      'version': _version,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'session': {'userId': userId, 'name': LocalSession.instance.name},
      'settings': {
        'themeIndex': theme.index,
        'remindersEnabled': await notifications.areRemindersEnabled(),
        'reminderIntervalHours': await notifications.getReminderInterval(),
      },
      'tables': tables,
      'avatar': avatar,
    };

    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(backup)));
    if (bytes.length > _maxBackupBytes) {
      throw StateError('Размер резервной копии превышает 16 МБ.');
    }
    return bytes;
  }

  BackupSnapshot parseBackup(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > _maxBackupBytes) {
      throw const FormatException('Размер файла резервной копии недопустим.');
    }

    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != _format ||
        decoded['version'] != _version) {
      throw const FormatException(
        'Файл не является резервной копией поддерживаемого формата Dayo.',
      );
    }

    final createdAtValue = decoded['createdAt'];
    if (createdAtValue is! String) {
      throw const FormatException('В копии отсутствует дата создания.');
    }
    final createdAt = DateTime.tryParse(createdAtValue);
    if (createdAt == null) {
      throw const FormatException('Дата создания копии повреждена.');
    }

    final session = decoded['session'];
    if (session is! Map<String, dynamic>) {
      throw const FormatException('В копии отсутствуют данные профиля.');
    }
    final userId = session['userId'];
    final name = session['name'];
    if (userId is! String ||
        !RegExp(r'^[A-Za-z0-9._-]{1,128}$').hasMatch(userId) ||
        (name != null && name is! String)) {
      throw const FormatException('Данные профиля в копии повреждены.');
    }

    final settings = decoded['settings'];
    if (settings is! Map<String, dynamic>) {
      throw const FormatException('В копии отсутствуют настройки приложения.');
    }
    final themeIndex = settings['themeIndex'];
    final remindersEnabled = settings['remindersEnabled'];
    final reminderIntervalHours = settings['reminderIntervalHours'];
    if (themeIndex is! int ||
        themeIndex < 0 ||
        themeIndex >= ThemeMode.values.length ||
        remindersEnabled is! bool ||
        reminderIntervalHours is! int ||
        reminderIntervalHours < 0 ||
        reminderIntervalHours > 8760) {
      throw const FormatException('Настройки приложения в копии повреждены.');
    }

    final rawTables = decoded['tables'];
    const requiredBackupTables = [
      'user_profiles',
      'daily_plan_items',
      'daily_tasks',
      'day_records',
      'task_records',
      'streaks',
    ];
    if (rawTables is! Map<String, dynamic> ||
        rawTables.keys
            .toSet()
            .difference(LocalDatabase.tableNames.toSet())
            .isNotEmpty ||
        requiredBackupTables.any((table) => !rawTables.containsKey(table))) {
      throw const FormatException(
        'Структура данных в копии не поддерживается.',
      );
    }

    final tables = <String, List<Map<String, Object?>>>{};
    for (final table in LocalDatabase.tableNames) {
      final rawRows = rawTables[table] ?? const [];
      if (rawRows is! List) {
        throw FormatException('Таблица "$table" в копии повреждена.');
      }

      final rows = <Map<String, Object?>>[];
      for (final rawRow in rawRows) {
        if (rawRow is! Map<String, dynamic>) {
          throw FormatException('Запись таблицы "$table" повреждена.');
        }
        final row = <String, Object?>{};
        for (final entry in rawRow.entries) {
          final value = entry.value;
          if (value != null && value is! String && value is! num) {
            throw FormatException(
              'Запись таблицы "$table" содержит неверные данные.',
            );
          }
          row[entry.key] = value;
        }
        rows.add(row);
      }
      tables[table] = rows;
    }

    _validateUserRows(tables, userId);
    final avatar = _parseAvatar(decoded['avatar'], tables, userId);

    return BackupSnapshot(
      createdAt: createdAt,
      userId: userId,
      name: name as String?,
      themeIndex: themeIndex,
      remindersEnabled: remindersEnabled,
      reminderIntervalHours: reminderIntervalHours,
      tables: tables,
      avatarFileName: avatar.$1,
      avatarBytes: avatar.$2,
    );
  }

  Future<void> restoreBackup(BackupSnapshot backup) async {
    final tables = {
      for (final entry in backup.tables.entries)
        entry.key: entry.value
            .map((row) => Map<String, Object?>.from(row))
            .toList(),
    };

    final profileRows = tables['user_profiles']!;
    if (backup.avatarBytes != null) {
      final profileIndex = profileRows.indexWhere(
        (row) => row['id'] == backup.userId,
      );
      if (profileIndex < 0) {
        throw const FormatException('В копии не найден профиль для аватара.');
      }
      profileRows[profileIndex]['avatar_url'] = await AvatarService()
          .saveRestoredAvatar(
            backup.avatarBytes!,
            backup.avatarFileName!,
            backup.userId,
          );
    }

    await LocalDatabase.instance.replaceAll(tables);
    await LocalSession.instance.restore(
      userId: backup.userId,
      name: backup.name,
    );
    await ThemeService().saveTheme(ThemeMode.values[backup.themeIndex]);

    final notifications = NotificationSettingsService();
    await notifications.setRemindersEnabled(backup.remindersEnabled);
    await notifications.setReminderInterval(backup.reminderIntervalHours);
  }

  Future<Map<String, Object?>?> _readAvatar(
    Map<String, List<Map<String, Object?>>> tables,
    String userId,
  ) async {
    final profiles = tables['user_profiles']!;
    final matchingProfiles = profiles.where((row) => row['id'] == userId);
    if (matchingProfiles.isEmpty) return null;

    final avatarUrl = matchingProfiles.first['avatar_url'];
    if (avatarUrl == null ||
        avatarUrl is! String ||
        avatarUrl.startsWith('asset_')) {
      return null;
    }
    if (avatarUrl.startsWith('http://') || avatarUrl.startsWith('https://')) {
      return null;
    }

    final avatarFile = File(avatarUrl);
    if (!await avatarFile.exists()) {
      throw StateError('Не удалось найти файл аватара для резервной копии.');
    }
    final size = await avatarFile.length();
    if (size > _maxAvatarBytes) {
      throw StateError('Размер аватара превышает допустимые 5 МБ.');
    }

    return {
      'fileName': avatarFile.uri.pathSegments.last,
      'data': base64Encode(await avatarFile.readAsBytes()),
    };
  }

  (String?, Uint8List?) _parseAvatar(
    Object? rawAvatar,
    Map<String, List<Map<String, Object?>>> tables,
    String userId,
  ) {
    Map<String, Object?>? profile;
    for (final row in tables['user_profiles']!) {
      if (row['id'] == userId) {
        profile = row;
        break;
      }
    }

    if (rawAvatar == null) {
      final avatarUrl = profile?['avatar_url'];
      if (avatarUrl is String &&
          avatarUrl.startsWith('/') &&
          avatarUrl.isNotEmpty) {
        throw const FormatException('В копии отсутствует файл аватара.');
      }
      return (null, null);
    }

    if (rawAvatar is! Map<String, dynamic> ||
        rawAvatar['fileName'] is! String ||
        rawAvatar['data'] is! String) {
      throw const FormatException('Данные аватара в копии повреждены.');
    }

    final fileName = rawAvatar['fileName'] as String;
    if (fileName.isEmpty || fileName.contains('/') || fileName.contains(r'\')) {
      throw const FormatException('Имя файла аватара в копии недопустимо.');
    }

    final Uint8List avatarBytes;
    try {
      avatarBytes = base64Decode(rawAvatar['data'] as String);
    } on FormatException {
      throw const FormatException('Файл аватара в копии повреждён.');
    }
    if (avatarBytes.isEmpty || avatarBytes.length > _maxAvatarBytes) {
      throw const FormatException('Размер файла аватара в копии недопустим.');
    }

    return (fileName, avatarBytes);
  }

  void _validateUserRows(
    Map<String, List<Map<String, Object?>>> tables,
    String userId,
  ) {
    for (final row in tables['user_profiles']!) {
      if (row['id'] != userId) {
        throw const FormatException('В копии найден чужой профиль.');
      }
    }

    for (final table in [
      'daily_plan_items',
      'recurring_tasks',
      'recurring_task_skips',
      'daily_tasks',
      'day_records',
      'task_records',
    ]) {
      for (final row in tables[table]!) {
        if (row['user_id'] != userId) {
          throw FormatException(
            'В таблице "$table" найден пользователь вне копии.',
          );
        }
      }
    }
    for (final row in tables['streaks']!) {
      if (row['user_id'] != userId) {
        throw const FormatException('В копии найден чужой прогресс.');
      }
    }
  }
}

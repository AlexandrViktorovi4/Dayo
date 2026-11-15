import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:planner/services/backup_service.dart';
import 'package:planner/services/local_database.dart';

void main() {
  final service = BackupService();

  Map<String, Object?> createBackup({
    int version = 1,
    Map<String, Object?>? tables,
  }) {
    return {
      'format': 'planner_backup',
      'version': version,
      'createdAt': '2026-11-15T00:00:00.000Z',
      'session': {'userId': 'user-1', 'name': 'Пользователь'},
      'settings': {
        'themeIndex': 0,
        'remindersEnabled': false,
        'reminderIntervalHours': 0,
      },
      'tables':
          tables ??
          {for (final table in LocalDatabase.tableNames) table: <Object?>[]},
      'avatar': null,
    };
  }

  Uint8List encode(Map<String, Object?> backup) =>
      Uint8List.fromList(utf8.encode(jsonEncode(backup)));

  test('parses a valid backup and counts its records', () {
    final backup = createBackup(
      tables: {
        for (final table in LocalDatabase.tableNames)
          table: table == 'daily_tasks'
              ? [
                  {'id': 'task-1', 'user_id': 'user-1', 'title': 'Задача'},
                ]
              : <Object?>[],
      },
    );

    final snapshot = service.parseBackup(encode(backup));

    expect(snapshot.userId, 'user-1');
    expect(snapshot.name, 'Пользователь');
    expect(snapshot.recordCount, 1);
  });

  test('rejects unsupported backup versions', () {
    expect(
      () => service.parseBackup(encode(createBackup(version: 2))),
      throwsFormatException,
    );
  });

  test('restores legacy backups without recurring-task tables', () {
    final oldTables = {
      for (final table in LocalDatabase.tableNames)
        if (table != 'recurring_tasks' && table != 'recurring_task_skips')
          table: <Object?>[],
    };

    final snapshot = service.parseBackup(
      encode(createBackup(tables: oldTables)),
    );

    expect(snapshot.tables['recurring_tasks'], isEmpty);
    expect(snapshot.tables['recurring_task_skips'], isEmpty);
  });

  test('rejects rows belonging to a different local user', () {
    final backup = createBackup(
      tables: {
        for (final table in LocalDatabase.tableNames)
          table: table == 'daily_tasks'
              ? [
                  {
                    'id': 'task-1',
                    'user_id': 'another-user',
                    'title': 'Задача',
                  },
                ]
              : <Object?>[],
      },
    );

    expect(() => service.parseBackup(encode(backup)), throwsFormatException);
  });
}

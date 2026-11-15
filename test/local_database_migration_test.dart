import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:planner/services/local_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'upgrading version 1 preserves task records and adds the date index',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'planner-database-migration-',
      );
      final path = '${directory.path}/planner.db';
      Database? database;

      try {
        database = await databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 1,
            onCreate: (db, _) async {
              await db.execute('''
              CREATE TABLE task_records (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                task_id TEXT NOT NULL,
                date TEXT NOT NULL,
                current_value INTEGER NOT NULL DEFAULT 0,
                updated_at TEXT
              )
            ''');
              await db.execute(
                'CREATE INDEX idx_taskrec_user_task_date '
                'ON task_records(user_id, task_id, date)',
              );
              await db.insert('task_records', {
                'id': 'record-1',
                'user_id': 'user-1',
                'task_id': 'task-1',
                'date': '2026-11-15',
                'current_value': 3,
              });
            },
          ),
        );
        await database.close();
        database = null;

        database = await databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 2,
            onUpgrade: LocalDatabase.onUpgrade,
          ),
        );

        final records = await database.query('task_records');
        final indexes = await database.rawQuery(
          "PRAGMA index_list('task_records')",
        );

        expect(records, hasLength(1));
        expect(records.single, containsPair('id', 'record-1'));
        expect(records.single, containsPair('current_value', 3));
        expect(
          indexes.map((index) => index['name']),
          contains('idx_taskrec_user_date'),
        );
      } finally {
        await database?.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'upgrading version 2 preserves plan items and adds recurrence storage',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'planner-recurrence-migration-',
      );
      final path = '${directory.path}/planner.db';
      Database? database;

      try {
        database = await databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 2,
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
                created_at TEXT
              )
            ''');
              await db.insert('daily_plan_items', {
                'id': 'plan-1',
                'user_id': 'user-1',
                'date': '2026-11-15',
                'title': 'Существующая задача',
                'is_done': 1,
                'order': 2,
              });
            },
          ),
        );
        await database.close();
        database = null;

        database = await databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: LocalDatabase.schemaVersion,
            onUpgrade: LocalDatabase.onUpgrade,
          ),
        );

        final items = await database.query('daily_plan_items');
        final recurringTables = await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name IN ('recurring_tasks', 'recurring_task_skips')",
        );
        final columns = await database.rawQuery(
          "PRAGMA table_info('daily_plan_items')",
        );

        expect(items, hasLength(1));
        expect(items.single, containsPair('id', 'plan-1'));
        expect(items.single, containsPair('is_done', 1));
        expect(items.single['recurrence_id'], isNull);
        expect(
          recurringTables.map((row) => row['name']),
          containsAll(['recurring_tasks', 'recurring_task_skips']),
        );
        expect(
          columns.map((column) => column['name']),
          contains('recurrence_id'),
        );
      } finally {
        await database?.close();
        await directory.delete(recursive: true);
      }
    },
  );
}

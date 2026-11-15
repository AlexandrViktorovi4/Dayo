// lib/services/local_database.dart
import 'package:sqflite/sqflite.dart';

/// Локальная база данных SQLite — замена облачным таблицам Supabase.
///
/// Все таблицы повторяют структуру прежних моделей, поэтому сервисы работают
/// практически с теми же полями.
class LocalDatabase {
  LocalDatabase._();

  static final LocalDatabase instance = LocalDatabase._();

  static const String _dbName = 'planner.db';
  static const int schemaVersion = 3;
  static const int _dbVersion = schemaVersion;
  static const List<String> tableNames = [
    'user_profiles',
    'daily_plan_items',
    'recurring_tasks',
    'recurring_task_skips',
    'daily_tasks',
    'day_records',
    'task_records',
    'streaks',
  ];

  Database? _db;

  /// Единственный экземпляр подключения к базе.
  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = '$dir/$_dbName';
    return openDatabase(
      path,
      version: _dbVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
      onUpgrade: onUpgrade,
    );
  }

  static Future<void> onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2 && newVersion >= 2) {
      await db.execute(
        'CREATE INDEX idx_taskrec_user_date ON task_records(user_id, date)',
      );
    }
    if (oldVersion < 3 && newVersion >= 3) {
      await db.execute(
        'ALTER TABLE daily_plan_items ADD COLUMN recurrence_id TEXT',
      );
      await db.execute('''
        CREATE TABLE recurring_tasks (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          title TEXT NOT NULL,
          subtasks TEXT NOT NULL DEFAULT '[]',
          start_date TEXT NOT NULL,
          is_active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE recurring_task_skips (
          recurring_task_id TEXT NOT NULL,
          user_id TEXT NOT NULL,
          date TEXT NOT NULL,
          PRIMARY KEY (recurring_task_id, date)
        )
      ''');
      await db.execute(
        'CREATE UNIQUE INDEX idx_plan_recurring_date '
        'ON daily_plan_items(recurrence_id, date) '
        'WHERE recurrence_id IS NOT NULL',
      );
      await db.execute(
        'CREATE INDEX idx_recurring_user_active '
        'ON recurring_tasks(user_id, is_active)',
      );
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE user_profiles (
        id TEXT PRIMARY KEY,
        full_name TEXT,
        avatar_url TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE daily_plan_items (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        date TEXT NOT NULL,
        title TEXT NOT NULL,
        subtasks TEXT,
        is_done INTEGER NOT NULL DEFAULT 0,
        "order" INTEGER NOT NULL DEFAULT 0,
        created_at TEXT,
        recurrence_id TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE recurring_tasks (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        title TEXT NOT NULL,
        subtasks TEXT NOT NULL DEFAULT '[]',
        start_date TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE recurring_task_skips (
        recurring_task_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        date TEXT NOT NULL,
        PRIMARY KEY (recurring_task_id, date)
      )
    ''');

    await db.execute('''
      CREATE TABLE daily_tasks (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        title TEXT NOT NULL,
        target_value INTEGER NOT NULL DEFAULT 0,
        unit TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE day_records (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        date TEXT NOT NULL,
        mood INTEGER,
        productivity INTEGER,
        notes TEXT,
        updated_at TEXT
      )
    ''');

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

    await db.execute('''
      CREATE TABLE streaks (
        user_id TEXT PRIMARY KEY,
        current_streak INTEGER NOT NULL DEFAULT 0,
        longest_streak INTEGER NOT NULL DEFAULT 0,
        last_activity_date TEXT,
        activity_dates TEXT,
        total_tasks_completed INTEGER NOT NULL DEFAULT 0,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    // Индексы для частых выборок.
    await db.execute(
      'CREATE INDEX idx_plan_user_date ON daily_plan_items(user_id, date)',
    );
    await db.execute(
      'CREATE INDEX idx_tasks_user_active ON daily_tasks(user_id, is_active)',
    );
    await db.execute(
      'CREATE INDEX idx_dayrec_user_date ON day_records(user_id, date)',
    );
    await db.execute(
      'CREATE INDEX idx_taskrec_user_task_date ON task_records(user_id, task_id, date)',
    );
    await db.execute(
      'CREATE INDEX idx_taskrec_user_date ON task_records(user_id, date)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX idx_plan_recurring_date '
      'ON daily_plan_items(recurrence_id, date) '
      'WHERE recurrence_id IS NOT NULL',
    );
    await db.execute(
      'CREATE INDEX idx_recurring_user_active '
      'ON recurring_tasks(user_id, is_active)',
    );
  }

  /// Полная очистка всех данных (сброс профиля).
  Future<void> clearAll() async {
    final db = await database;
    for (final table in tableNames) {
      await db.delete(table);
    }
  }

  Future<Map<String, List<Map<String, Object?>>>> exportAll() async {
    final db = await database;
    return db.transaction((transaction) async {
      final tables = <String, List<Map<String, Object?>>>{};
      for (final table in tableNames) {
        tables[table] = await transaction.query(table);
      }
      return tables;
    });
  }

  Future<void> replaceAll(
    Map<String, List<Map<String, Object?>>> tables,
  ) async {
    if (tables.keys.toSet().difference(tableNames.toSet()).isNotEmpty ||
        tableNames.any((table) => !tables.containsKey(table))) {
      throw ArgumentError.value(tables.keys, 'tables', 'Unexpected table set');
    }

    final db = await database;
    await db.transaction((transaction) async {
      for (final table in tableNames.reversed) {
        await transaction.delete(table);
      }
      for (final table in tableNames) {
        for (final row in tables[table]!) {
          await transaction.insert(table, row);
        }
      }
    });
  }
}

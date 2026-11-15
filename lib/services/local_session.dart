// lib/services/local_session.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Локальная "сессия" пользователя.
///
/// В offline-режиме аккаунтов и облачной авторизации нет, поэтому используется
/// один стабильный идентификатор, который генерируется при первом запуске и
/// сохраняется на устройстве. Он подставляется туда, где раньше использовался
/// `Supabase.instance.client.auth.currentUser!.id`.
class LocalSession {
  LocalSession._();

  static final LocalSession instance = LocalSession._();

  static const String _keyUserId = 'local_user_id';
  static const String _keyName = 'local_user_name';

  String _userId = 'local-user';
  String? _name;

  /// Стабильный идентификатор локального пользователя.
  String get userId => _userId;

  /// Email в локальном режиме отсутствует.
  String? get email => null;

  /// Имя профиля (если было сохранено).
  String? get name => _name;

  /// Инициализация: читает или создаёт идентификатор пользователя.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_keyUserId);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await prefs.setString(_keyUserId, id);
    }
    _userId = id;
    _name = prefs.getString(_keyName);
  }

  /// Сохраняет имя профиля.
  Future<void> setName(String name) async {
    _name = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyName, name);
  }

  Future<void> restore({required String userId, required String? name}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserId, userId);
    if (name == null) {
      await prefs.remove(_keyName);
    } else {
      await prefs.setString(_keyName, name);
    }
    _userId = userId;
    _name = name;
  }

  /// Очищает сохранённые данные сессии (используется при сбросе данных).
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyName);
    _name = null;
  }
}

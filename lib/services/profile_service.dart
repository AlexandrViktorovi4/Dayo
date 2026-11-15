// lib/services/profile_service.dart
import 'package:planner/models/user_profile.dart';
import 'package:planner/services/local_database.dart';
import 'package:planner/services/local_session.dart';

class ProfileService {
  Future<UserProfile?> getProfile() async {
    final db = await LocalDatabase.instance.database;
    final userId = LocalSession.instance.userId;

    final rows = await db.query(
      'user_profiles',
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return UserProfile.fromJson(rows.first);
  }

  // При сохранении профиля
  Future<void> saveProfile(String fullName, {String? avatarUrl}) async {
    final db = await LocalDatabase.instance.database;
    final userId = LocalSession.instance.userId;

    final data = <String, dynamic>{
      'id': userId,
      'full_name': fullName,
      'avatar_url': avatarUrl,
    };

    final existing = await db.query(
      'user_profiles',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      await db.update('user_profiles', data, where: 'id = ?', whereArgs: [userId]);
    } else {
      await db.insert('user_profiles', data);
    }

    await LocalSession.instance.setName(fullName);
  }
}

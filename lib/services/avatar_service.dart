// lib/services/avatar_service.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:planner/services/local_session.dart';

/// Хранение аватара локально, в папке документов приложения.
/// Возвращаемый "URL" — это абсолютный путь к файлу на устройстве.
class AvatarService {
  static const int _maxBytes = 5 * 1024 * 1024; // 5MB лимит

  Future<Directory> _avatarsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/avatars');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  // Загрузка аватара из bytes (для WEB платформы)
  Future<String> uploadAvatarFromBytes(Uint8List bytes, String fileName) async {
    if (bytes.isEmpty) {
      throw Exception('Файл аватара пустой');
    }

    if (bytes.length > _maxBytes) {
      throw Exception('Файл слишком большой. Максимум 5MB');
    }

    final ext = _getFileExtension(fileName);
    final dir = await _avatarsDir();
    final userId = LocalSession.instance.userId;

    await _clearOldAvatars(dir, userId);

    final destPath = '${dir.path}/$userId.$ext';
    await File(destPath).writeAsBytes(bytes);
    return destPath;
  }

  Future<String> saveRestoredAvatar(
    Uint8List bytes,
    String fileName,
    String userId,
  ) async {
    if (bytes.isEmpty) {
      throw Exception('Файл аватара пустой');
    }
    if (bytes.length > _maxBytes) {
      throw Exception('Файл слишком большой. Максимум 5MB');
    }

    final ext = _getFileExtension(fileName);
    final dir = await _avatarsDir();
    final destPath =
        '${dir.path}/$userId.backup-${DateTime.now().microsecondsSinceEpoch}.$ext';
    await File(destPath).writeAsBytes(bytes, flush: true);
    return destPath;
  }

  Future<void> _clearOldAvatars(Directory dir, String userId) async {
    await for (final entity in dir.list()) {
      if (entity is File &&
          entity.uri.pathSegments.last.startsWith('$userId.')) {
        await entity.delete();
      }
    }
  }

  // Определение расширения файла
  String _getFileExtension(String filePath) {
    final extension = filePath.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'heic', 'webp', 'gif'].contains(extension)) {
      return extension;
    }
    return 'png'; // Значение по умолчанию
  }

  // Получение пути к аватару пользователя
  String getAvatarUrl(String userId) {
    return '$userId.png';
  }

  // Удаление аватара
  Future<void> deleteAvatar() async {
    final dir = await _avatarsDir();
    final userId = LocalSession.instance.userId;
    await _clearOldAvatars(dir, userId);
  }
}

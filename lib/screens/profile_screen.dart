// lib/screens/profile_screen.dart
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:planner/services/avatar_service.dart';
import 'package:planner/services/backup_service.dart';
import 'package:planner/services/theme_service.dart';
import 'package:planner/services/local_session.dart';
import 'package:planner/services/profile_service.dart';
import 'package:planner/services/notification_service.dart';
import 'package:planner/services/notification_settings_service.dart';

class ProfileScreen extends StatefulWidget {
  final void Function(ThemeMode) toggleTheme;
  final bool isDesktop;

  const ProfileScreen({
    super.key,
    required this.toggleTheme,
    this.isDesktop = false,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _imagePicker = ImagePicker();
  late TextEditingController _nameController;
  late ProfileService _profileService;
  late ThemeMode _currentTheme;
  late ThemeService _themeService;
  bool _isLoading = true;
  bool _planReminder = true;
  bool _taskReminder = true;
  bool _incompleteReminder = true;
  bool _recurringRemindersEnabled = false;
  int _recurringInterval = 0;
  String? _avatarUrl;
  late AvatarService _avatarService;
  bool _isUploading = false;
  final BackupService _backupService = BackupService();
  bool _isBackupBusy = false;
  bool? _notificationsEnabled;
  bool _isCheckingNotificationStatus = true;
  bool _isRequestingNotificationPermission = false;
  bool _isRefreshingNotificationStatus = false;
  String? _notificationStatusError;
  late AnimationController _animationController;
  bool _showContent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _profileService = ProfileService();
    _avatarService = AvatarService();
    _themeService = ThemeService();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _loadTheme();
    _loadProfile();
    _loadNotificationSettings();
    _refreshNotificationStatus(showProgress: false);

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _showContent = true);
        _animationController.forward();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animationController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshNotificationStatus();
    }
  }

  Future<void> _loadTheme() async {
    final savedTheme = await _themeService.getTheme();
    if (mounted) {
      setState(() {
        _currentTheme = savedTheme;
      });
    }
  }

  void _selectTheme(ThemeMode mode) async {
    await _themeService.saveTheme(mode);

    if (mounted) {
      setState(() {
        _currentTheme = mode;
      });
      widget.toggleTheme(mode);
    }
  }

  Future<void> _loadNotificationSettings() async {
    final settings = NotificationSettingsService();
    final enabled = await settings.areRemindersEnabled();
    final interval = await settings.getReminderInterval();

    if (mounted) {
      setState(() {
        _recurringRemindersEnabled = enabled;
        _recurringInterval = interval;
      });
    }
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _profileService.getProfile();
      final name = profile?.fullName ?? 'Друг';
      // Используем только avatarUrl если он явно сохранен в БД
      final avatar = profile?.avatarUrl;

      if (mounted) {
        setState(() {
          _nameController = TextEditingController(text: name);
          _avatarUrl = avatar;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки профиля: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _selectAvatar() async {
    final action = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(32),
              topRight: Radius.circular(32),
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Индикатор захвата
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Theme.of(context).dividerColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Выберите аватар',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Галерея стандартных аватаров
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.emoji_emotions_outlined,
                              color: Theme.of(context).colorScheme.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Стандартные аватары',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 3,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          children: List.generate(6, (index) {
                            final avatarIndex = index + 1;

                            return GestureDetector(
                              onTap: () {
                                Navigator.pop(context, 'asset_$avatarIndex');
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.2,
                                      ),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Image.asset(
                                    'assets/avatars/$avatarIndex.png',
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Кнопки
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        _buildAvatarActionButton(
                          Icons.photo_library,
                          'Выбрать из галереи',
                          () => Navigator.pop(context, 'gallery'),
                        ),
                        const SizedBox(height: 12),
                        _buildAvatarActionButton(
                          Icons.camera_alt,
                          'Сделать фото',
                          () => Navigator.pop(context, 'camera'),
                          isOutlined: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (action != null) {
      if (action.startsWith('asset_')) {
        final avatarIndex = action.split('_')[1];
        await _selectDefaultAvatar(avatarIndex);
      } else if (action == 'gallery') {
        await _pickImageFromGallery();
      } else if (action == 'camera') {
        await _pickImageFromCamera();
      }
    }
  }

  Widget _buildAvatarActionButton(
    IconData icon,
    String text,
    VoidCallback onTap, {
    bool isOutlined = false,
  }) {
    if (isOutlined) {
      return OutlinedButton.icon(
        icon: Icon(icon),
        onPressed: onTap,
        label: Text(text),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          side: BorderSide(color: Theme.of(context).colorScheme.primary),
        ),
      );
    }

    return FilledButton.icon(
      icon: Icon(icon),
      onPressed: onTap,
      label: Text(text),
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  BoxDecoration _sectionDecoration(
    ColorScheme colorScheme, {
    double radius = 24,
  }) {
    return BoxDecoration(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: colorScheme.outlineVariant.withValues(alpha: 0.55),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.045),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  Future<void> _selectDefaultAvatar(String avatarIndex) async {
    try {
      setState(() => _isUploading = true);

      final newAvatarUrl = 'asset_$avatarIndex';

      await _profileService.saveProfile(
        _nameController.text.trim(),
        avatarUrl: newAvatarUrl,
      );

      if (mounted) {
        setState(() {
          _avatarUrl = newAvatarUrl;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Аватар обновлен!'),
            backgroundColor: Theme.of(context).colorScheme.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка обновления аватара: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 80,
      );

      if (image != null) {
        await _uploadAvatarFromXFile(image);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка выбора фото: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  Future<void> _pickImageFromCamera() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 80,
      );

      if (image != null) {
        await _uploadAvatarFromXFile(image);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка съемки фото: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  Future<void> _uploadAvatarFromXFile(XFile image) async {
    try {
      setState(() => _isUploading = true);

      final bytes = await image.readAsBytes();
      final newAvatarUrl = await _avatarService.uploadAvatarFromBytes(
        bytes,
        image.name,
      );

      await _profileService.saveProfile(
        _nameController.text.trim(),
        avatarUrl: newAvatarUrl,
      );

      if (mounted) {
        setState(() {
          _avatarUrl = newAvatarUrl;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Аватар обновлен!'),
            backgroundColor: Theme.of(context).colorScheme.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки аватара: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _deleteAvatar() async {
    try {
      setState(() => _isUploading = true);

      await _avatarService.deleteAvatar();
      await _profileService.saveProfile(
        _nameController.text.trim(),
        avatarUrl: null,
      );

      if (mounted) {
        setState(() {
          _avatarUrl = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Аватар удален!'),
            backgroundColor: Theme.of(context).colorScheme.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка удаления аватара: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  ImageProvider? get _avatarImageProvider {
    if (_avatarUrl == null) {
      return null;
    } else if (_avatarUrl!.startsWith('asset_')) {
      // Преобразуем asset_1 в assets/avatars/1.png
      final avatarIndex = _avatarUrl!.split('_')[1];
      return AssetImage('assets/avatars/$avatarIndex.png');
    } else if (_avatarUrl!.startsWith('/')) {
      // Локальный файл аватара
      return FileImage(File(_avatarUrl!));
    } else {
      return NetworkImage(_avatarUrl!);
    }
  }

  Widget get _avatarIcon {
    if (_avatarUrl == null) {
      return Icon(Icons.person, size: 40, color: Colors.white);
    } else if (_avatarUrl!.startsWith('asset_')) {
      // Иконка уже отображается через ImageProvider
      return const SizedBox();
    } else {
      return const SizedBox();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    _currentTheme = brightness == Brightness.dark
        ? ThemeMode.dark
        : ThemeMode.light;
  }

  Future<void> _saveName() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    await _profileService.saveProfile(name, avatarUrl: _avatarUrl);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Имя сохранено!'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  Future<void> _exportBackup() async {
    if (_isBackupBusy) return;
    setState(() => _isBackupBusy = true);

    try {
      final bytes = await _backupService.createBackup();
      final now = DateTime.now();
      String twoDigits(int value) => value.toString().padLeft(2, '0');
      final fileName =
          'planner_backup_${now.year}${twoDigits(now.month)}${twoDigits(now.day)}'
          '_${twoDigits(now.hour)}${twoDigits(now.minute)}.json';
      final savedPath = await FilePicker.saveFile(
        dialogTitle: 'Сохранить резервную копию',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: bytes,
      );

      if (savedPath != null) {
        _showBackupMessage('Резервная копия сохранена.');
      }
    } catch (error) {
      _showBackupMessage(
        'Не удалось создать резервную копию: $error',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isBackupBusy = false);
      }
    }
  }

  Future<void> _importBackup() async {
    if (_isBackupBusy) return;
    setState(() => _isBackupBusy = true);

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (result == null) return;

      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        throw StateError('Не удалось прочитать выбранный файл.');
      }

      final backup = _backupService.parseBackup(bytes);
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Восстановить резервную копию?'),
          content: Text(
            'Копия от ${backup.createdAt.toLocal().toString().substring(0, 16)} '
            'содержит ${backup.recordCount} записей. Все текущие данные '
            'и настройки будут заменены. Это действие нельзя отменить.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Восстановить'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      await _backupService.restoreBackup(backup);
      final restoredProfile = await _profileService.getProfile();
      final restoredTheme = await _themeService.getTheme();

      if (mounted) {
        setState(() {
          _nameController.text =
              restoredProfile?.fullName ?? LocalSession.instance.name ?? 'Друг';
          _avatarUrl = restoredProfile?.avatarUrl;
          _currentTheme = restoredTheme;
          _recurringRemindersEnabled = backup.remindersEnabled;
          _recurringInterval = backup.reminderIntervalHours;
        });
        widget.toggleTheme(restoredTheme);
      }

      String? reminderError;
      try {
        if (backup.remindersEnabled && backup.reminderIntervalHours > 0) {
          await NotificationService().scheduleRecurringTaskReminders(
            backup.reminderIntervalHours,
          );
        } else {
          await NotificationService().cancelRecurringReminders();
        }
      } catch (error) {
        reminderError = error.toString();
      }

      if (reminderError == null) {
        _showBackupMessage('Резервная копия восстановлена.');
      } else {
        _showBackupMessage(
          'Данные восстановлены, но не удалось настроить напоминания: '
          '$reminderError',
          isError: true,
        );
      }
    } catch (error) {
      _showBackupMessage(
        'Не удалось восстановить резервную копию: $error',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isBackupBusy = false);
      }
    }
  }

  void _showBackupMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _goBack() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 60,
                height: 60,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Загружаем профиль...',
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final user = LocalSession.instance;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Более точное определение платформы
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isDesktop =
        widget.isDesktop || screenWidth > 768 || screenHeight < screenWidth;
    final isLargeScreen = screenWidth > 1024; // Большие экраны

    return AnimatedOpacity(
      opacity: _showContent ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: !isDesktop
            ? AppBar(
                backgroundColor: colorScheme.surface,
                elevation: 0,
                scrolledUnderElevation: 0,
                leading: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    icon: Icon(Icons.arrow_back, color: colorScheme.primary),
                    onPressed: _goBack,
                  ),
                ),
                title: Text(
                  'Профиль',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
                centerTitle: false,
              )
            : AppBar(
                backgroundColor: colorScheme.surface,
                elevation: 0,
                scrolledUnderElevation: 0,
                leading: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    icon: Icon(Icons.arrow_back, color: colorScheme.primary),
                    onPressed: _goBack,
                  ),
                ),
                title: Text(
                  'Настройки профиля',
                  style: TextStyle(
                    fontSize: isLargeScreen ? 24 : 22,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
                centerTitle: false,
              ),
        body: SafeArea(
          child: isDesktop
              ? _buildDesktopBody(
                  context,
                  user,
                  colorScheme,
                  isLargeScreen,
                  _isBackupBusy,
                  _exportBackup,
                  _importBackup,
                )
              : _buildMobileBody(
                  context,
                  user,
                  colorScheme,
                  isDark,
                  _isBackupBusy,
                  _exportBackup,
                  _importBackup,
                ),
        ),
      ),
    );
  }

  Future<void> _refreshNotificationStatus({bool showProgress = true}) async {
    if (_isRefreshingNotificationStatus) return;
    _isRefreshingNotificationStatus = true;
    if (showProgress && mounted) {
      setState(() {
        _isCheckingNotificationStatus = true;
        _notificationStatusError = null;
      });
    }

    try {
      final enabled = await NotificationService().areNotificationsEnabled();
      if (mounted) {
        setState(() {
          _notificationsEnabled = enabled;
          _notificationStatusError = null;
          _isCheckingNotificationStatus = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _notificationsEnabled = null;
          _notificationStatusError = error.toString();
          _isCheckingNotificationStatus = false;
        });
      }
    } finally {
      _isRefreshingNotificationStatus = false;
    }
  }

  Future<void> _requestNotificationPermission() async {
    if (_isRequestingNotificationPermission) return;
    setState(() {
      _isRequestingNotificationPermission = true;
      _notificationStatusError = null;
    });

    String? requestError;
    try {
      await NotificationService().requestNotificationPermission();
    } catch (error) {
      requestError = error.toString();
    }

    await _refreshNotificationStatus(showProgress: false);
    if (mounted) {
      setState(() {
        _isRequestingNotificationPermission = false;
        if (requestError != null) {
          _notificationStatusError =
              'Не удалось запросить разрешение: $requestError';
        }
      });
    }
  }

  Widget _buildNotificationPermissionCard({
    required ColorScheme colorScheme,
    required bool isCompact,
  }) {
    final enabled = _notificationsEnabled == true;
    final statusColor = enabled ? colorScheme.primary : colorScheme.error;
    final settingsPath = defaultTargetPlatform == TargetPlatform.android
        ? 'Настройки устройства → Приложения → Dayo → Уведомления.'
        : 'Настройки устройства → Уведомления → Dayo.';
    final title = _isCheckingNotificationStatus
        ? 'Проверяем разрешение…'
        : enabled
        ? 'Уведомления разрешены'
        : _notificationsEnabled == false
        ? 'Уведомления отключены'
        : 'Статус уведомлений неизвестен';
    final message =
        _notificationStatusError ??
        (enabled
            ? 'Общее разрешение включено. Приложению не нужно отдельное '
                  'разрешение на точные будильники. Энергосбережение Android '
                  'может задержать уведомление. Если '
                  'не приходит конкретное напоминание, проверьте его канал в настройках.'
            : _notificationsEnabled == false
            ? 'Разрешите уведомления. Если запрос уже отклоняли, включите '
                  'их вручную: $settingsPath'
            : 'Проверьте разрешение в настройках устройства.');

    if (enabled && _notificationStatusError == null) {
      return Container(
        margin: EdgeInsets.only(bottom: isCompact ? 8 : 12),
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 12 : 16,
          vertical: isCompact ? 8 : 10,
        ),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(isCompact ? 14 : 16),
          border: Border.all(color: statusColor.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(Icons.notifications_active_outlined, color: statusColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Уведомления разрешены',
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                  fontSize: isCompact ? 13 : 14,
                ),
              ),
            ),
            if (_isCheckingNotificationStatus ||
                _isRequestingNotificationPermission)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              IconButton(
                tooltip: 'Проверить разрешение',
                visualDensity: VisualDensity.compact,
                onPressed: _refreshNotificationStatus,
                icon: const Icon(Icons.refresh_rounded),
                color: statusColor,
              ),
          ],
        ),
      );
    }

    return Container(
      margin: EdgeInsets.only(bottom: isCompact ? 12 : 16),
      padding: EdgeInsets.all(isCompact ? 12 : 16),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(isCompact ? 12 : 16),
        border: Border.all(color: statusColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                enabled
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined,
                color: statusColor,
                size: isCompact ? 20 : 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                    fontSize: isCompact ? 13 : 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.75),
              fontSize: isCompact ? 12 : 13,
            ),
          ),
          if (_isCheckingNotificationStatus ||
              _isRequestingNotificationPermission) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: enabled
                ? TextButton.icon(
                    onPressed: _isCheckingNotificationStatus
                        ? null
                        : () => _refreshNotificationStatus(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Проверить снова'),
                  )
                : FilledButton.icon(
                    onPressed:
                        _isRequestingNotificationPermission ||
                            _isCheckingNotificationStatus
                        ? null
                        : _requestNotificationPermission,
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('Разрешить уведомления'),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackupCard({
    required ColorScheme colorScheme,
    required bool isCompact,
    required bool isBusy,
    required VoidCallback onExport,
    required VoidCallback onImport,
  }) {
    final exportButton = FilledButton.icon(
      onPressed: isBusy ? null : onExport,
      icon: const Icon(Icons.file_download_outlined),
      label: Text(isCompact ? 'Экспорт' : 'Создать копию'),
    );
    final importButton = OutlinedButton.icon(
      onPressed: isBusy ? null : onImport,
      icon: const Icon(Icons.upload_file_outlined),
      label: const Text('Восстановить'),
    );

    return Container(
      margin: EdgeInsets.only(bottom: isCompact ? 12 : 20),
      padding: EdgeInsets.all(isCompact ? 14 : 24),
      decoration: _sectionDecoration(colorScheme, radius: isCompact ? 20 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.backup_outlined, color: colorScheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Резервная копия',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: isCompact ? 16 : 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Экспортируйте профиль, задачи и настройки. '
            'Восстановление заменит текущие данные; файл содержит личную информацию.',
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.7),
              fontSize: isCompact ? 12 : 14,
            ),
          ),
          SizedBox(height: isCompact ? 12 : 16),
          if (isCompact)
            Row(
              children: [
                Expanded(child: exportButton),
                const SizedBox(width: 8),
                Expanded(child: importButton),
              ],
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [exportButton, importButton],
            ),
          if (isBusy) ...[
            const SizedBox(height: 14),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }

  Widget _buildMobileBody(
    BuildContext context,
    LocalSession user,
    ColorScheme colorScheme,
    bool isDark,
    bool isBackupBusy,
    VoidCallback onExportBackup,
    VoidCallback onImportBackup,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmallScreen = constraints.maxHeight < 600;

        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: isSmallScreen ? 8 : 16,
            ),
            child: Column(
              children: _buildMobileSections(
                context,
                user,
                colorScheme,
                isDark,
                isSmallScreen,
                isBackupBusy,
                onExportBackup,
                onImportBackup,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDesktopBody(
    BuildContext context,
    LocalSession user,
    ColorScheme colorScheme,
    bool isLargeScreen,
    bool isBackupBusy,
    VoidCallback onExportBackup,
    VoidCallback onImportBackup,
  ) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isLargeScreen ? 48 : 24,
        vertical: 24,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Левая колонка - профиль и имя
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(right: 24),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // Карточка профиля
                    Container(
                      padding: const EdgeInsets.all(32),
                      decoration: _sectionDecoration(colorScheme, radius: 28),
                      child: Column(
                        children: [
                          // Аватар
                          Stack(
                            children: [
                              Container(
                                width: isLargeScreen ? 160 : 140,
                                height: isLargeScreen ? 160 : 140,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF7C3AED),
                                      Color(0xFFEC4899),
                                    ],
                                  ),
                                  border: Border.all(
                                    color: colorScheme.primary.withValues(
                                      alpha: 0.2,
                                    ),
                                    width: 4,
                                  ),
                                ),
                                child: ClipOval(
                                  child: _avatarImageProvider != null
                                      ? Image(
                                          image: _avatarImageProvider!,
                                          fit: BoxFit.cover,
                                          loadingBuilder: (context, child, loadingProgress) {
                                            if (loadingProgress == null) {
                                              return child;
                                            }
                                            return Center(
                                              child: CircularProgressIndicator(
                                                value:
                                                    loadingProgress
                                                            .expectedTotalBytes !=
                                                        null
                                                    ? loadingProgress
                                                              .cumulativeBytesLoaded /
                                                          loadingProgress
                                                              .expectedTotalBytes!
                                                    : null,
                                              ),
                                            );
                                          },
                                          errorBuilder:
                                              (context, error, stackTrace) {
                                                debugPrint(
                                                  '[DEBUG] Ошибка загрузки аватара: $error',
                                                );
                                                return Center(
                                                  child: Column(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Icon(
                                                        Icons
                                                            .image_not_supported,
                                                        color: colorScheme.error
                                                            .withValues(
                                                              alpha: 0.5,
                                                            ),
                                                        size: 32,
                                                      ),
                                                      const SizedBox(height: 8),
                                                      Text(
                                                        'Не удалось\nзагрузить',
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: colorScheme
                                                              .error
                                                              .withValues(
                                                                alpha: 0.5,
                                                              ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              },
                                        )
                                      : Center(child: _avatarIcon),
                                ),
                              ),
                              if (_isUploading)
                                Positioned.fill(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(
                                        isLargeScreen ? 80 : 70,
                                      ),
                                    ),
                                    child: const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  ),
                                ),
                              Positioned(
                                bottom: 8,
                                right: 8,
                                child: GestureDetector(
                                  onTap: _isUploading ? null : _selectAvatar,
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: colorScheme.primary,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          blurRadius: 8,
                                          color: Colors.black.withValues(
                                            alpha: 0.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      Icons.edit,
                                      color: colorScheme.onPrimary,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Email
                          Text(
                            user.email ?? 'Локальный профиль',
                            style: TextStyle(
                              fontSize: isLargeScreen ? 20 : 18,
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),

                          // Удалить аватар
                          if (_avatarUrl != null &&
                              !_avatarUrl!.startsWith('asset_'))
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: TextButton(
                                onPressed: _isUploading ? null : _deleteAvatar,
                                child: Text(
                                  'Удалить аватар',
                                  style: TextStyle(
                                    color: colorScheme.error,
                                    fontWeight: FontWeight.w500,
                                    fontSize: isLargeScreen ? 18 : 16,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Имя
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: _sectionDecoration(colorScheme, radius: 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Имя для приветствия',
                            style: TextStyle(
                              fontSize: isLargeScreen ? 20 : 18,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Form(
                            key: _formKey,
                            child: TextFormField(
                              controller: _nameController,
                              decoration: InputDecoration(
                                hintText: 'Как вас называть?',
                                filled: true,
                                fillColor: colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.55),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 18,
                                ),
                              ),
                              style: TextStyle(
                                fontSize: isLargeScreen ? 20 : 18,
                                color: colorScheme.onSurface,
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Введите имя';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _saveName,
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 18,
                                ),
                              ),
                              child: Text(
                                'Сохранить имя',
                                style: TextStyle(
                                  fontSize: isLargeScreen ? 20 : 18,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Правая колонка - настройки (тема и уведомления)
          Expanded(
            flex: 3,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Тема
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: _sectionDecoration(colorScheme, radius: 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Тема',
                          style: TextStyle(
                            fontSize: isLargeScreen ? 24 : 22,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 20),
                        RadioGroup<ThemeMode>(
                          groupValue: _currentTheme,
                          onChanged: (value) {
                            if (value != null) _selectTheme(value);
                          },
                          child: Column(
                            children: [
                              _buildDesktopThemeOption(
                                'Светлая',
                                ThemeMode.light,
                                Icons.light_mode_outlined,
                                isLargeScreen: isLargeScreen,
                              ),
                              _buildDesktopThemeOption(
                                'Тёмная',
                                ThemeMode.dark,
                                Icons.dark_mode_outlined,
                                isLargeScreen: isLargeScreen,
                              ),
                              _buildDesktopThemeOption(
                                'Как в системе',
                                ThemeMode.system,
                                Icons.phone_iphone_outlined,
                                isLargeScreen: isLargeScreen,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Уведомления
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: _sectionDecoration(colorScheme, radius: 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Уведомления',
                          style: TextStyle(
                            fontSize: isLargeScreen ? 24 : 22,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 20),
                        _buildNotificationPermissionCard(
                          colorScheme: colorScheme,
                          isCompact: !isLargeScreen,
                        ),
                        _buildDesktopNotificationOption(
                          'Напоминание о плане (09:00)',
                          _planReminder,
                          (value) {
                            setState(() => _planReminder = value);
                            if (value) {
                              NotificationService().scheduleDailyPlanReminder();
                            }
                          },
                          isLargeScreen: isLargeScreen,
                        ),
                        _buildDesktopNotificationOption(
                          'Напоминание о задачах (18:00)',
                          _taskReminder,
                          (value) {
                            setState(() => _taskReminder = value);
                            if (value) {
                              NotificationService().scheduleTaskReminder();
                            }
                          },
                          isLargeScreen: isLargeScreen,
                        ),
                        _buildDesktopNotificationOption(
                          'Напоминание о невыполненных (21:00)',
                          _incompleteReminder,
                          (value) {
                            setState(() => _incompleteReminder = value);
                            if (value) {
                              NotificationService()
                                  .scheduleIncompleteTasksReminder();
                            }
                          },
                          isLargeScreen: isLargeScreen,
                        ),
                        const SizedBox(height: 16),
                        // Повторяющиеся напоминания
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: colorScheme.surface.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Повторяющиеся напоминания',
                                    style: TextStyle(
                                      fontSize: isLargeScreen ? 16 : 14,
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                  const Spacer(),
                                  Switch(
                                    value: _recurringRemindersEnabled,
                                    onChanged: (value) async {
                                      setState(
                                        () =>
                                            _recurringRemindersEnabled = value,
                                      );
                                      final settings =
                                          NotificationSettingsService();
                                      await settings.setRemindersEnabled(value);

                                      if (value && _recurringInterval > 0) {
                                        await NotificationService()
                                            .scheduleRecurringTaskReminders(
                                              _recurringInterval,
                                            );
                                      } else {
                                        await NotificationService()
                                            .cancelRecurringReminders();
                                      }
                                    },
                                  ),
                                ],
                              ),
                              if (_recurringRemindersEnabled) ...[
                                const SizedBox(height: 12),
                                Text(
                                  'Интервал:',
                                  style: TextStyle(
                                    fontSize: isLargeScreen ? 14 : 12,
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.7,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    _buildIntervalButton(1, isLargeScreen),
                                    _buildIntervalButton(2, isLargeScreen),
                                    _buildIntervalButton(3, isLargeScreen),
                                    _buildIntervalButton(6, isLargeScreen),
                                    _buildIntervalButton(12, isLargeScreen),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildBackupCard(
                    colorScheme: colorScheme,
                    isCompact: !isLargeScreen,
                    isBusy: isBackupBusy,
                    onExport: onExportBackup,
                    onImport: onImportBackup,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildMobileSections(
    BuildContext context,
    LocalSession user,
    ColorScheme colorScheme,
    bool isDark,
    bool isSmallScreen,
    bool isBackupBusy,
    VoidCallback onExportBackup,
    VoidCallback onImportBackup,
  ) {
    final avatarSize = isSmallScreen ? 70.0 : 84.0;
    final padding = isSmallScreen ? 12.0 : 16.0;
    final fontSize = isSmallScreen ? 13.0 : 15.0;
    final iconSize = isSmallScreen ? 16.0 : 18.0;

    return [
      // Карточка профиля
      Container(
        margin: EdgeInsets.only(bottom: isSmallScreen ? 8 : 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? const [
                    Color(0xFF282254),
                    Color(0xFF413A91),
                    Color(0xFF273F73),
                  ]
                : const [
                    Color(0xFF5148C8),
                    Color(0xFF7166E8),
                    Color(0xFF4F70D8),
                  ],
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: const Color(
                0xFF5148C8,
              ).withValues(alpha: isDark ? 0.22 : 0.2),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(
            children: [
              Positioned(
                top: -56,
                right: -34,
                child: Container(
                  width: 156,
                  height: 156,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Positioned(
                bottom: -74,
                right: 82,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Stack(
                          children: [
                            Container(
                              width: avatarSize,
                              height: avatarSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.4),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    blurRadius: 10,
                                    color: Colors.black.withValues(alpha: 0.16),
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: _avatarImageProvider != null
                                    ? Image(
                                        image: _avatarImageProvider!,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                              return Center(child: _avatarIcon);
                                            },
                                      )
                                    : Center(child: _avatarIcon),
                              ),
                            ),
                            if (_isUploading)
                              Positioned.fill(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(
                                      avatarSize / 2,
                                    ),
                                  ),
                                  child: const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                              ),
                            Positioned(
                              bottom: -3,
                              right: -3,
                              child: Tooltip(
                                message: 'Изменить фото',
                                child: Semantics(
                                  button: true,
                                  label: 'Изменить фото профиля',
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: _isUploading ? null : _selectAvatar,
                                    child: SizedBox(
                                      width: 40,
                                      height: 40,
                                      child: Align(
                                        alignment: Alignment.bottomRight,
                                        child: Container(
                                          width: 28,
                                          height: 28,
                                          decoration: BoxDecoration(
                                            color: colorScheme.secondary,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 2,
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.edit_rounded,
                                            color: colorScheme.onSecondary,
                                            size: 14,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(width: isSmallScreen ? 14 : 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ВАШ ПРОФИЛЬ',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.76),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.1,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _nameController.text.trim().isEmpty
                                    ? 'Друг'
                                    : _nameController.text.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: isSmallScreen ? 20 : 23,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                user.email ?? 'Локальный профиль',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: isSmallScreen ? 11 : 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_avatarUrl != null && !_avatarUrl!.startsWith('asset_'))
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _isUploading ? null : _deleteAvatar,
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Удалить фото'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),

      // Имя для приветствия
      Container(
        margin: EdgeInsets.only(bottom: isSmallScreen ? 8 : 12),
        padding: EdgeInsets.all(padding),
        decoration: _sectionDecoration(
          colorScheme,
          radius: isSmallScreen ? 20 : 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(isSmallScreen ? 5 : 6),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(isSmallScreen ? 8 : 10),
                  ),
                  child: Icon(
                    Icons.person_outline,
                    color: colorScheme.primary,
                    size: iconSize,
                  ),
                ),
                SizedBox(width: isSmallScreen ? 8 : 10),
                Text(
                  'Имя для приветствия',
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            SizedBox(height: isSmallScreen ? 10 : 12),
            Form(
              key: _formKey,
              child: TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  hintText: 'Как вас называть?',
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.55,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      isSmallScreen ? 12 : 14,
                    ),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: isSmallScreen ? 12 : 14,
                    vertical: isSmallScreen ? 10 : 12,
                  ),
                ),
                style: TextStyle(
                  fontSize: fontSize,
                  color: colorScheme.onSurface,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Введите имя';
                  }
                  return null;
                },
              ),
            ),
            SizedBox(height: isSmallScreen ? 10 : 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saveName,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      isSmallScreen ? 12 : 14,
                    ),
                  ),
                  padding: EdgeInsets.symmetric(
                    vertical: isSmallScreen ? 12 : 14,
                  ),
                ),
                child: Text(
                  'Сохранить имя',
                  style: TextStyle(fontSize: fontSize),
                ),
              ),
            ),
          ],
        ),
      ),

      // Настройки темы
      Container(
        margin: EdgeInsets.only(bottom: isSmallScreen ? 8 : 12),
        padding: EdgeInsets.all(padding),
        decoration: _sectionDecoration(
          colorScheme,
          radius: isSmallScreen ? 20 : 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(isSmallScreen ? 5 : 6),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(isSmallScreen ? 8 : 10),
                  ),
                  child: Icon(
                    Icons.palette_outlined,
                    color: colorScheme.primary,
                    size: iconSize,
                  ),
                ),
                SizedBox(width: isSmallScreen ? 8 : 10),
                Text(
                  'Тема',
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            SizedBox(height: isSmallScreen ? 8 : 10),
            SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_outlined),
                  label: Text('Светлая'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_outlined),
                  label: Text('Тёмная'),
                ),
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.phone_iphone_outlined),
                  label: Text('Авто'),
                ),
              ],
              selected: {_currentTheme},
              onSelectionChanged: (selection) => _selectTheme(selection.first),
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                ),
                textStyle: WidgetStatePropertyAll(
                  TextStyle(fontSize: isSmallScreen ? 11 : 12),
                ),
              ),
            ),
          ],
        ),
      ),

      // Уведомления
      Container(
        margin: EdgeInsets.only(bottom: isSmallScreen ? 8 : 12),
        padding: EdgeInsets.all(padding),
        decoration: _sectionDecoration(
          colorScheme,
          radius: isSmallScreen ? 20 : 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(isSmallScreen ? 5 : 6),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(isSmallScreen ? 8 : 10),
                  ),
                  child: Icon(
                    Icons.notifications_outlined,
                    color: colorScheme.primary,
                    size: iconSize,
                  ),
                ),
                SizedBox(width: isSmallScreen ? 8 : 10),
                Text(
                  'Уведомления',
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            SizedBox(height: isSmallScreen ? 6 : 8),
            _buildNotificationPermissionCard(
              colorScheme: colorScheme,
              isCompact: true,
            ),
            _buildMobileNotificationOption(
              'Напоминание о плане (09:00)',
              _planReminder,
              (value) {
                setState(() => _planReminder = value);
                if (value) {
                  NotificationService().scheduleDailyPlanReminder();
                }
              },
              isSmallScreen: isSmallScreen,
            ),
            _buildMobileNotificationOption(
              'Напоминание о задачах (18:00)',
              _taskReminder,
              (value) {
                setState(() => _taskReminder = value);
                if (value) {
                  NotificationService().scheduleTaskReminder();
                }
              },
              isSmallScreen: isSmallScreen,
            ),
            _buildMobileNotificationOption(
              'Напоминание о невыполненных (21:00)',
              _incompleteReminder,
              (value) {
                setState(() => _incompleteReminder = value);
                if (value) {
                  NotificationService().scheduleIncompleteTasksReminder();
                }
              },
              isSmallScreen: isSmallScreen,
            ),
            const SizedBox(height: 12),
            // Повторяющиеся напоминания
            Container(
              padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(isSmallScreen ? 12 : 16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Повторяющиеся напоминания',
                        style: TextStyle(
                          fontSize: fontSize - 1,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const Spacer(),
                      Switch(
                        value: _recurringRemindersEnabled,
                        onChanged: (value) async {
                          setState(() => _recurringRemindersEnabled = value);
                          final settings = NotificationSettingsService();
                          await settings.setRemindersEnabled(value);

                          if (value && _recurringInterval > 0) {
                            await NotificationService()
                                .scheduleRecurringTaskReminders(
                                  _recurringInterval,
                                );
                          } else {
                            await NotificationService()
                                .cancelRecurringReminders();
                          }
                        },
                      ),
                    ],
                  ),
                  if (_recurringRemindersEnabled) ...[
                    SizedBox(height: isSmallScreen ? 8 : 12),
                    Text(
                      'Интервал:',
                      style: TextStyle(
                        fontSize: fontSize - 2,
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    SizedBox(height: isSmallScreen ? 6 : 8),
                    Wrap(
                      spacing: isSmallScreen ? 6 : 8,
                      children: [
                        _buildIntervalButton(1, !isSmallScreen),
                        _buildIntervalButton(2, !isSmallScreen),
                        _buildIntervalButton(3, !isSmallScreen),
                        _buildIntervalButton(6, !isSmallScreen),
                        _buildIntervalButton(12, !isSmallScreen),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      _buildBackupCard(
        colorScheme: colorScheme,
        isCompact: true,
        isBusy: isBackupBusy,
        onExport: onExportBackup,
        onImport: onImportBackup,
      ),
    ];
  }

  Widget _buildDesktopThemeOption(
    String title,
    ThemeMode mode,
    IconData icon, {
    required bool isLargeScreen,
  }) {
    final platformBrightness = MediaQuery.platformBrightnessOf(context);
    final isSystemDark = platformBrightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: Theme.of(context).colorScheme.primary,
            size: isLargeScreen ? 26 : 24,
          ),
        ),
        title: mode == ThemeMode.system
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: isLargeScreen ? 20 : 18,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isSystemDark
                        ? 'Сейчас на устройстве: Тёмная'
                        : 'Сейчас на устройстве: Светлая',
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                      fontSize: isLargeScreen ? 15 : 14,
                    ),
                  ),
                ],
              )
            : Text(
                title,
                style: TextStyle(
                  fontSize: isLargeScreen ? 20 : 18,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
        trailing: Radio<ThemeMode>(value: mode),
        onTap: () => _selectTheme(mode),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Widget _buildDesktopNotificationOption(
    String title,
    bool value,
    Function(bool) onChanged, {
    required bool isLargeScreen,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
        ),
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        title: Text(
          title,
          style: TextStyle(
            fontSize: isLargeScreen ? 20 : 18,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        value: value,
        onChanged: onChanged,
        activeThumbColor: Theme.of(context).colorScheme.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Widget _buildMobileNotificationOption(
    String title,
    bool value,
    Function(bool) onChanged, {
    required bool isSmallScreen,
  }) {
    return SwitchListTile(
      dense: isSmallScreen,
      visualDensity: isSmallScreen
          ? VisualDensity.compact
          : VisualDensity.standard,
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: TextStyle(
          fontSize: isSmallScreen ? 13 : 14,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      value: value,
      onChanged: onChanged,
      activeThumbColor: Theme.of(context).colorScheme.primary,
    );
  }

  Widget _buildIntervalButton(int hours, bool isLargeScreen) {
    final isSelected = _recurringInterval == hours;
    return ElevatedButton(
      onPressed: () async {
        setState(() => _recurringInterval = hours);
        final settings = NotificationSettingsService();
        await settings.setReminderInterval(hours);

        if (_recurringRemindersEnabled) {
          await NotificationService().scheduleRecurringTaskReminders(hours);
        }
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.surface,
        foregroundColor: isSelected
            ? Colors.white
            : Theme.of(context).colorScheme.onSurface,
        padding: EdgeInsets.symmetric(
          horizontal: isLargeScreen ? 16 : 12,
          vertical: isLargeScreen ? 12 : 8,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(
        '$hours ч',
        style: TextStyle(
          fontSize: isLargeScreen ? 14 : 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}

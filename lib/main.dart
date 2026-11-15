// lib/main.dart
import 'package:flutter/material.dart';
import 'package:planner/services/notification_service.dart';
import 'package:planner/services/theme_service.dart';
import 'package:planner/services/local_database.dart';
import 'package:planner/services/local_session.dart';
import 'screens/auth/auth_gate.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'services/notification_settings_service.dart';

ThemeData _buildPlannerTheme(Brightness brightness) {
  const lightPrimary = Color(0xFF5752C9);
  const darkPrimary = Color(0xFFA6A3FF);
  const lightBackground = Color(0xFFF6F7FB);
  const darkBackground = Color(0xFF111217);
  const lightSurface = Color(0xFFFFFFFF);
  const darkSurface = Color(0xFF1B1C24);
  const lightSecondary = Color(0xFF258B80);
  const darkSecondary = Color(0xFF79C9BE);

  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: lightPrimary,
    brightness: brightness,
    primary: isDark ? darkPrimary : lightPrimary,
    secondary: isDark ? darkSecondary : lightSecondary,
    surface: isDark ? darkSurface : lightSurface,
  );
  final outline = scheme.outlineVariant.withValues(alpha: 0.65);
  final roundedShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: isDark ? darkBackground : lightBackground,
    appBarTheme: AppBarTheme(
      backgroundColor: isDark ? darkBackground : lightBackground,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: 64,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: outline),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.error, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: roundedShape,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: roundedShape,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: roundedShape,
        side: BorderSide(color: outline),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primary.withValues(alpha: 0.12),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide(color: outline),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    ),
    dividerTheme: DividerThemeData(color: outline, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Инициализация timezone
    tz.initializeTimeZones();

    // Инициализация локальной сессии и базы данных
    await LocalSession.instance.init();
    await LocalDatabase.instance.database;

    // Инициализация уведомлений
    await NotificationService().init();

    // Загружаем настройки уведомлений и планируем их
    final notificationSettings = NotificationSettingsService();
    final remindersEnabled = await notificationSettings.areRemindersEnabled();
    if (remindersEnabled) {
      final interval = await notificationSettings.getReminderInterval();
      if (interval > 0) {
        await NotificationService().scheduleRecurringTaskReminders(interval);
      }
    }

    // Запуск уведомлений по умолчанию (с небольшой задержкой)
    Future.delayed(const Duration(seconds: 2), () {
      NotificationService().scheduleDailyPlanReminder();
      NotificationService().scheduleTaskReminder();
      NotificationService().scheduleIncompleteTasksReminder();
    });

    // Загружаем сохранённую тему
    final themeService = ThemeService();
    final savedTheme = await themeService.getTheme();

    runApp(PlannerApp(initialTheme: savedTheme));
  } catch (e, stack) {
    // Показываем реальный текст ошибки и стек — это помогает быстро
    // понять причину сбоя при запуске.
    runApp(ErrorApp(error: e.toString(), stackTrace: stack.toString()));
  }
}

class PlannerApp extends StatefulWidget {
  final ThemeMode initialTheme;

  const PlannerApp({super.key, this.initialTheme = ThemeMode.system});

  @override
  State<PlannerApp> createState() => _PlannerAppState();
}

class _PlannerAppState extends State<PlannerApp> {
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.initialTheme;
  }

  void _toggleTheme(ThemeMode mode) {
    setState(() {
      _themeMode = mode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dayo',
      debugShowCheckedModeBanner: false,
      theme: _buildPlannerTheme(Brightness.light),
      darkTheme: _buildPlannerTheme(Brightness.dark),
      themeMode: _themeMode,
      home: AuthGate(toggleTheme: _toggleTheme),
    );
  }
}

class ErrorApp extends StatelessWidget {
  final String error;
  final String? stackTrace;

  const ErrorApp({super.key, this.error = '', this.stackTrace});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF4F46E5),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 64),
                const SizedBox(height: 24),
                const Text(
                  'Ошибка запуска',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Не удалось запустить приложение. Подробности ниже:',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(
                    error.isEmpty ? 'нет данных' : error,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () {
                    // Попытка перезапуска
                    main();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF4F46E5),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Попробовать снова'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

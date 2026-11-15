// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:planner/models/daily_plan_item.dart';
import 'package:planner/screens/add_task_screen.dart';
import 'package:planner/screens/calendar_screen.dart';
import 'package:planner/services/daily_plan_service.dart';
import 'package:planner/services/day_record_service.dart';
import 'package:planner/services/notification_service.dart';
import 'package:planner/services/streak_service.dart';
import 'package:planner/screens/profile_screen.dart';
import 'package:planner/widgets/notes_input_widget.dart';
import 'package:planner/services/local_session.dart';
import 'package:planner/services/profile_service.dart';
import 'package:planner/utils/daily_plan_filter.dart';

class HomeScreen extends StatefulWidget {
  final DateTime? initialDate;
  final void Function(ThemeMode) toggleTheme;
  final bool isDesktop;

  const HomeScreen({
    super.key,
    this.initialDate,
    required this.toggleTheme,
    this.isDesktop = false,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  static const _taskPreviewLimit = 5;

  final DailyPlanService _planService = DailyPlanService();
  final DayRecordService _dayService = DayRecordService();
  final StreakService _streakService = StreakService();

  late DateTime _currentDate;
  List<DailyPlanItem> _tasks = [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearchExpanded = false;
  bool _showAllTasks = false;
  DailyPlanCompletionFilter _completionFilter = DailyPlanCompletionFilter.all;
  final Set<String> _expandedTasks = {}; // Отслеживание раскрытых задач
  int? _mood;
  int? _productivity;
  String? _notes;
  bool _isLoading = true;
  String? _displayName;
  String? _avatarUrl;
  int _currentStreak = 0;
  int _longestStreak = 0;
  bool _isStreakLoading = true;
  late AnimationController _animationController;
  String? _completedTaskId;
  bool _showContent = false;

  List<DailyPlanItem> get _visibleTasks => filterDailyPlanItems(
    _tasks,
    query: _searchQuery,
    completionFilter: _completionFilter,
  );

  bool get _hasTaskFilters =>
      _searchQuery.trim().isNotEmpty ||
      _completionFilter != DailyPlanCompletionFilter.all;

  List<DailyPlanItem> get _displayedTasks => _showAllTasks
      ? _visibleTasks
      : _visibleTasks.take(_taskPreviewLimit).toList();

  @override
  void initState() {
    super.initState();
    _currentDate = widget.initialDate ?? DateTime.now();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _loadData();
    _loadStreakData();

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _showContent = true);
        _animationController.forward();
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildTaskFilters(ColorScheme colorScheme) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildCompletionChip(
                      label: 'Все',
                      filter: DailyPlanCompletionFilter.all,
                      colorScheme: colorScheme,
                    ),
                    const SizedBox(width: 6),
                    _buildCompletionChip(
                      label: 'Активные',
                      filter: DailyPlanCompletionFilter.incomplete,
                      colorScheme: colorScheme,
                    ),
                    const SizedBox(width: 6),
                    _buildCompletionChip(
                      label: 'Готово',
                      filter: DailyPlanCompletionFilter.completed,
                      colorScheme: colorScheme,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: _isSearchExpanded ? 'Скрыть поиск' : 'Поиск по задачам',
              onPressed: () {
                if (_isSearchExpanded) {
                  FocusScope.of(context).unfocus();
                }
                setState(() => _isSearchExpanded = !_isSearchExpanded);
              },
              style: IconButton.styleFrom(
                foregroundColor: colorScheme.primary,
                backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: Icon(
                _isSearchExpanded ? Icons.close_rounded : Icons.search_rounded,
              ),
            ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: _isSearchExpanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextField(
                    autofocus: true,
                    controller: _searchController,
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                        _showAllTasks = false;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Поиск по задачам',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchQuery.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Очистить поиск',
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                  _showAllTasks = false;
                                });
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                      isDense: true,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildCompletionChip({
    required String label,
    required DailyPlanCompletionFilter filter,
    required ColorScheme colorScheme,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: _completionFilter == filter,
      selectedColor: colorScheme.primary.withValues(alpha: 0.12),
      checkmarkColor: colorScheme.primary,
      visualDensity: VisualDensity.compact,
      labelPadding: const EdgeInsets.symmetric(horizontal: 2),
      onSelected: (_) {
        setState(() {
          _completionFilter = filter;
          _showAllTasks = false;
        });
      },
    );
  }

  Widget _buildNoTaskMatches(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off,
            size: 40,
            color: colorScheme.onSurface.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 8),
          Text(
            'Задачи не найдены',
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          TextButton(
            onPressed: () {
              _searchController.clear();
              setState(() {
                _searchQuery = '';
                _completionFilter = DailyPlanCompletionFilter.all;
              });
            },
            child: const Text('Сбросить фильтры'),
          ),
        ],
      ),
    );
  }

  ImageProvider? get _avatarImageProvider {
    if (_avatarUrl == null) {
      return null;
    } else if (_avatarUrl!.startsWith('asset_')) {
      // Преобразуем asset_1 в assets/avatars/1.png
      final avatarIndex = _avatarUrl!.split('_')[1];
      return AssetImage('assets/avatars/$avatarIndex.png');
    } else {
      return NetworkImage(_avatarUrl!);
    }
  }

  Future<void> _loadData() async {
    try {
      final tasks = await _planService.getPlanForDate(_currentDate);
      tasks.sort((a, b) => a.order.compareTo(b.order));

      final dayRecord = await _dayService.getRecordForDate(_currentDate);
      final profileService = ProfileService();
      final profile = await profileService.getProfile();
      final name = profile?.fullName ?? 'Друг';

      if (mounted) {
        setState(() {
          _tasks = tasks;
          _mood = dayRecord?.mood;
          _productivity = dayRecord?.productivity;
          _notes = dayRecord?.notes;
          _displayName = name;
          _avatarUrl = profile?.avatarUrl;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadStreakData() async {
    try {
      final streak = await _streakService.getCurrentStreak();
      if (mounted) {
        setState(() {
          _currentStreak = streak.currentStreak;
          _longestStreak = streak.longestStreak;
          _isStreakLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Ошибка загрузки стрика: $e');
      if (mounted) {
        setState(() => _isStreakLoading = false);
      }
    }
  }

  Future<void> _addTaskForFutureDate(BuildContext context) async {
    final DateTime? selectedDate = await showDatePicker(
      context: context,
      initialDate: _currentDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (!context.mounted || selectedDate == null) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => EditPlanScreen(date: selectedDate),
      ),
    );
    if (mounted) await _loadData();
  }

  Future<void> _toggleTaskOrSubtask(
    DailyPlanItem task, [
    int? subtaskIndex,
  ]) async {
    try {
      debugPrint(
        '[_toggleTaskOrSubtask] START - Task: ${task.title}, SubtaskIndex: $subtaskIndex',
      );

      bool wasCompletedBefore = false;

      // Если это задача с подзадачами и нажата сама задача (не подзадача)
      if (task.subtasks.isNotEmpty && subtaskIndex == null) {
        // Раскрыть/скрыть задачу вместо её выполнения
        debugPrint('[_toggleTaskOrSubtask] Toggling expand state');
        setState(() {
          if (_expandedTasks.contains(task.id)) {
            _expandedTasks.remove(task.id);
          } else {
            _expandedTasks.add(task.id);
          }
        });
        return;
      }

      if (subtaskIndex != null) {
        wasCompletedBefore = task.subtasks[subtaskIndex].done;
      } else {
        wasCompletedBefore = task.isDone;
      }

      if (subtaskIndex != null) {
        // Выполнение подзадачи
        debugPrint('[_toggleTaskOrSubtask] Toggling subtask $subtaskIndex');
        final updatedSubtasks = List<Subtask>.from(task.subtasks);
        updatedSubtasks[subtaskIndex] = Subtask(
          title: updatedSubtasks[subtaskIndex].title,
          done: !updatedSubtasks[subtaskIndex].done,
        );

        // Проверяем, все ли подзадачи выполнены
        final allSubtasksDone = updatedSubtasks.every((s) => s.done);
        debugPrint(
          '[_toggleTaskOrSubtask] All subtasks done: $allSubtasksDone',
        );

        final updatedTask = DailyPlanItem(
          id: task.id,
          userId: task.userId,
          date: task.date,
          title: task.title,
          subtasks: updatedSubtasks,
          isDone: allSubtasksDone,
          order: task.order,
          createdAt: task.createdAt,
          recurrenceId: task.recurrenceId,
        );

        debugPrint('[_toggleTaskOrSubtask] Updating task in DB...');
        await _planService.updateTask(updatedTask);
        debugPrint('[_toggleTaskOrSubtask] Task updated successfully');
      } else {
        // Выполнение обычной задачи (без подзадач)
        debugPrint('[_toggleTaskOrSubtask] Toggling main task completion');
        final updatedTask = DailyPlanItem(
          id: task.id,
          userId: task.userId,
          date: task.date,
          title: task.title,
          subtasks: task.subtasks,
          isDone: !task.isDone,
          order: task.order,
          createdAt: task.createdAt,
          recurrenceId: task.recurrenceId,
        );

        await _planService.updateTask(updatedTask);

        if (!wasCompletedBefore && _isToday(_currentDate)) {
          _animateTaskCompletion(task.id);
        }
      }

      // Авто-обновление страницы при изменении статуса задачи
      if (!wasCompletedBefore && _isToday(_currentDate)) {
        debugPrint('[_toggleTaskOrSubtask] Updating streak...');
        await _streakService.updateStreakOnTaskCompletion();
        debugPrint('[_toggleTaskOrSubtask] Streak updated');
        // Задержка для анимации
        await Future.delayed(const Duration(milliseconds: 600));
      } else {
        // Меньшая задержка при отмене
        await Future.delayed(const Duration(milliseconds: 300));
      }

      // Обновляем данные для всех случаев
      if (mounted) {
        debugPrint('[_toggleTaskOrSubtask] Loading data...');
        await _loadData();
        debugPrint('[_toggleTaskOrSubtask] Data loaded');

        debugPrint('[_toggleTaskOrSubtask] Loading streak data...');
        await _loadStreakData();
        debugPrint('[_toggleTaskOrSubtask] Streak data loaded');
      }

      debugPrint('[_toggleTaskOrSubtask] Checking if all tasks completed...');
      if (_isAllTasksCompleted()) {
        debugPrint(
          '[_toggleTaskOrSubtask] All tasks completed! Showing notification',
        );
        NotificationService().showMotivationalNotification();
      }

      debugPrint('[_toggleTaskOrSubtask] FINISH');
    } catch (e) {
      debugPrint('[_toggleTaskOrSubtask] ERROR: $e');
      rethrow;
    }
  }

  void _animateTaskCompletion(String taskId) {
    setState(() {
      _completedTaskId = taskId;
    });

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _completedTaskId = null);
      }
    });
  }

  bool _isAllTasksCompleted() {
    if (_tasks.isEmpty) return false;

    for (final task in _tasks) {
      if (task.subtasks.isEmpty) {
        if (!task.isDone) return false;
      } else {
        if (task.subtasks.any((s) => !s.done)) return false;
      }
    }
    return true;
  }

  Future<void> _deleteTask(String taskId) async {
    await _planService.deleteTask(taskId);
    await _loadData();
  }

  void _onMoodChanged(int? value) {
    setState(() => _mood = value);
    _saveDayRecord();
  }

  void _onProductivityChanged(int? value) {
    setState(() => _productivity = value);
    _saveDayRecord();
  }

  void _onNotesChanged(String? value) {
    setState(() => _notes = value);
    _saveDayRecord();
  }

  Future<void> _saveDayRecord() async {
    await _dayService.saveRecord(
      date: _currentDate,
      mood: _mood,
      productivity: _productivity,
      notes: _notes,
    );
  }

  String _getGreeting() {
    if (!_isToday(_currentDate)) return '';
    final hour = DateTime.now().hour;
    if (hour < 6) return 'Доброй ночи';
    if (hour < 12) return 'Доброе утро';
    if (hour < 18) return 'Добрый день';
    return 'Добрый вечер';
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  bool _isFutureDate(DateTime date) {
    final now = DateTime.now();
    return DateTime(
      date.year,
      date.month,
      date.day,
    ).isAfter(DateTime(now.year, now.month, now.day));
  }

  String _getUserName() {
    return _displayName ?? 'Друг';
  }

  String _getMonthName(int month) {
    const months = [
      'января',
      'февраля',
      'марта',
      'апреля',
      'мая',
      'июня',
      'июля',
      'августа',
      'сентября',
      'октября',
      'ноября',
      'декабря',
    ];
    return months[month - 1];
  }

  String _getWeekdayName(int weekday) {
    const weekdays = [
      'Понедельник',
      'Вторник',
      'Среда',
      'Четверг',
      'Пятница',
      'Суббота',
      'Воскресенье',
    ];
    return weekdays[weekday - 1];
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    final reorderedTasks = List<DailyPlanItem>.from(_tasks);
    final task = reorderedTasks.removeAt(oldIndex);
    reorderedTasks.insert(newIndex, task);

    final updatedTasks = <DailyPlanItem>[];
    for (int i = 0; i < reorderedTasks.length; i++) {
      updatedTasks.add(
        DailyPlanItem(
          id: reorderedTasks[i].id,
          userId: reorderedTasks[i].userId,
          date: reorderedTasks[i].date, // ← DateTime
          title: reorderedTasks[i].title,
          subtasks: reorderedTasks[i].subtasks,
          isDone: reorderedTasks[i].isDone,
          order: i,
          createdAt: reorderedTasks[i].createdAt,
          recurrenceId: reorderedTasks[i].recurrenceId,
        ),
      );
    }

    setState(() {
      _tasks = updatedTasks;
    });

    await _planService.updateTasksOrder(updatedTasks);
  }

  void _changeDate(int days) {
    setState(() {
      _currentDate = _currentDate.add(Duration(days: days));
    });
    _loadData();
    _loadStreakData();
  }

  void _goToToday() {
    final now = DateTime.now();
    if (_isToday(_currentDate)) return;

    setState(() {
      _currentDate = DateTime(now.year, now.month, now.day);
    });
    _loadData();
  }

  void _showTaskContextMenu(BuildContext context, DailyPlanItem task) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    task.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(
                    Icons.edit,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(
                    'Редактировать',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context)
                        .push(
                          MaterialPageRoute(
                            builder: (context) => EditPlanScreen(
                              date: _currentDate,
                              taskToEdit: task,
                            ),
                          ),
                        )
                        .then((_) => _loadData());
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.copy,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(
                    'Дублировать',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _duplicateTask(task);
                  },
                ),
                if (task.recurrenceId != null)
                  ListTile(
                    leading: Icon(
                      Icons.repeat,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(
                      'Отключить повторение',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _confirmStopRecurringTask(task);
                    },
                  ),
                ListTile(
                  leading: Icon(
                    Icons.delete,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    task.recurrenceId == null
                        ? 'Удалить'
                        : 'Удалить только этот день',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _deleteTask(task.id);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmStopRecurringTask(DailyPlanItem task) async {
    final recurrenceId = task.recurrenceId;
    if (recurrenceId == null) return;

    final shouldStop = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отключить повторение?'),
        content: const Text(
          'Новые задачи перестанут создаваться. Уже запланированные '
          'на будущие даты будут удалены.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Отключить'),
          ),
        ],
      ),
    );
    if (shouldStop != true) return;

    try {
      await _planService.stopRecurringTask(recurrenceId);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Повторение отключено')));
        await _loadData();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось отключить повторение: $error')),
        );
      }
    }
  }

  Future<void> _duplicateTask(DailyPlanItem task) async {
    final newTaskId =
        'task_${DateTime.now().millisecondsSinceEpoch}_${LocalSession.instance.userId.substring(0, 8)}';

    final newTask = DailyPlanItem(
      id: newTaskId,
      userId: task.userId,
      date: _currentDate, // ← Передаем DateTime напрямую
      title: '${task.title} (копия)',
      subtasks: task.subtasks,
      isDone: false,
      order: _tasks.length,
      createdAt: DateTime.now(),
    );

    await _planService.addTask(newTask);
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final isToday = _isToday(_currentDate);
    final hasTasks = _tasks.isNotEmpty;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final isDesktop =
        widget.isDesktop || MediaQuery.of(context).size.width > 768;

    return AnimatedOpacity(
      opacity: _showContent ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: isDesktop
            ? _buildDesktopAppBar(context, colorScheme, isToday)
            : _buildMobileAppBar(context, colorScheme, isToday),
        body: _isLoading
            ? _buildLoadingState()
            : isDesktop
            ? _buildDesktopBody(context, isToday, colorScheme, isDark)
            : RefreshIndicator(
                onRefresh: () async {
                  await _loadData();
                  await _loadStreakData();
                },
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: _buildMobileSlivers(
                    context,
                    isToday,
                    hasTasks,
                    colorScheme,
                    isDark,
                  ),
                ),
              ),
        floatingActionButton: isDesktop
            ? null
            : isToday
            ? _buildMobileFAB(context, colorScheme)
            : _isFutureDate(_currentDate)
            ? _buildFutureDateActions(context, colorScheme)
            : _buildTodayFAB(context, colorScheme),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
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
            'Загружаем ваш день...',
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  AppBar _buildMobileAppBar(
    BuildContext context,
    ColorScheme colorScheme,
    bool isToday,
  ) {
    return AppBar(
      backgroundColor: colorScheme.surface,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: _buildAppBarButton(context, Icons.calendar_today, () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => CalendarScreen(
              initialDate: _currentDate,
              toggleTheme: widget.toggleTheme,
            ),
          ),
        );
      }),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_currentDate.day} ${_getMonthName(_currentDate.month)}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
          if (isToday)
            Text(
              _getWeekdayName(_currentDate.weekday),
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
        ],
      ),
      actions: [
        _buildAppBarButton(
          context,
          Icons.add,
          () => _addTaskForFutureDate(context),
        ),
        _buildAppBarButton(
          context,
          Icons.notifications,
          () => NotificationService().showMotivationalNotification(),
        ),
        _buildAppBarButton(context, Icons.person, () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) =>
                  ProfileScreen(toggleTheme: widget.toggleTheme),
            ),
          );
        }),
      ],
    );
  }

  AppBar _buildDesktopAppBar(
    BuildContext context,
    ColorScheme colorScheme,
    bool isToday,
  ) {
    return AppBar(
      backgroundColor: colorScheme.surface,
      elevation: 0,
      scrolledUnderElevation: 0,
      title: Row(
        children: [
          // Логотип
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.task_alt, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Text(
            'Dayo',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const Spacer(),

          // Навигация по дням
          Row(
            children: [
              _buildAppBarButton(
                context,
                Icons.chevron_left,
                () => _changeDate(-1),
                small: true,
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      '${_currentDate.day} ${_getMonthName(_currentDate.month)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      _getWeekdayName(_currentDate.weekday),
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              _buildAppBarButton(
                context,
                Icons.chevron_right,
                () => _changeDate(1),
                small: true,
              ),
              if (!isToday)
                _buildAppBarButton(
                  context,
                  Icons.today_rounded,
                  _goToToday,
                  small: true,
                  tooltip: 'Вернуться к сегодня',
                ),
            ],
          ),
          const Spacer(),

          // Кнопки действий
          _buildAppBarButton(
            context,
            Icons.add,
            () => _addTaskForFutureDate(context),
          ),
          const SizedBox(width: 8),
          _buildAppBarButton(context, Icons.calendar_today, () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => CalendarScreen(
                  initialDate: _currentDate,
                  toggleTheme: widget.toggleTheme,
                ),
              ),
            );
          }),
          const SizedBox(width: 8),
          _buildAppBarButton(context, Icons.person, () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) =>
                    ProfileScreen(toggleTheme: widget.toggleTheme),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildDesktopBody(
    BuildContext context,
    bool isToday,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: MediaQuery.of(context).size.width > 1200 ? 48 : 24,
        vertical: 24,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Левая колонка - задачи
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.only(right: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Приветствие
                  _buildDesktopWelcomeWidget(isToday, isDark),
                  const SizedBox(height: 32),

                  // Заголовок задач
                  Row(
                    children: [
                      Text(
                        'Задачи',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const Spacer(),
                      if (_tasks.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            '${_tasks.where((t) => t.isDone).length}/${_tasks.length}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Список задач
                  Expanded(
                    child: _tasks.isEmpty
                        ? _buildEmptyState(
                            context,
                            isToday,
                            colorScheme,
                            isDark,
                            isDesktop: true,
                          )
                        : Column(
                            children: [
                              _buildTaskFilters(colorScheme),
                              const SizedBox(height: 16),
                              Expanded(
                                child: _visibleTasks.isEmpty
                                    ? _buildNoTaskMatches(colorScheme)
                                    : _hasTaskFilters
                                    ? ListView.builder(
                                        itemCount: _visibleTasks.length,
                                        itemBuilder: (context, index) =>
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 12,
                                              ),
                                              child: _buildModernTaskItem(
                                                _visibleTasks[index],
                                                context,
                                                isDesktop: true,
                                              ),
                                            ),
                                      )
                                    : ReorderableListView.builder(
                                        onReorder: _onReorder,
                                        itemCount: _visibleTasks.length,
                                        itemBuilder: (context, index) {
                                          final task = _visibleTasks[index];
                                          return ReorderableDelayedDragStartListener(
                                            key: Key('task-${task.id}'),
                                            index: index,
                                            child: Container(
                                              margin: const EdgeInsets.only(
                                                bottom: 12,
                                              ),
                                              child: _buildModernTaskItem(
                                                task,
                                                context,
                                                isDesktop: true,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),

          // Правая колонка - статистика и итоги
          Expanded(
            flex: 2,
            child: _buildDesktopSidePanel(
              context,
              colorScheme,
              isDark,
              _isFutureDate(_currentDate),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopSidePanel(
    BuildContext context,
    ColorScheme colorScheme,
    bool isDark,
    bool isFutureDate,
  ) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1B4B) : Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Статистика
          Text(
            'Статистика',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),

          _buildDesktopStatCard(
            context,
            Icons.task_alt,
            'Прогресс задач',
            '${_tasks.where((t) => t.isDone).length} из ${_tasks.length}',
            _tasks.isNotEmpty
                ? '${((_tasks.where((t) => t.isDone).length / _tasks.length) * 100).toStringAsFixed(0)}% выполнено'
                : 'Добавьте задачи',
            colorScheme.primary,
          ),

          const SizedBox(height: 32),

          if (isFutureDate)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.event_available_rounded,
                      size: 40,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Запланируйте дела на этот день',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _addTaskForCurrentDate,
                      icon: const Icon(Icons.add_task_rounded),
                      label: const Text('Добавить задачу'),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Text(
              'Итоги дня',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildModernMoodRating(colorScheme),
                    const SizedBox(height: 24),
                    _buildModernProductivityRating(colorScheme),
                    const SizedBox(height: 24),
                    NotesInputWidget(
                      value: _notes,
                      onNotesChanged: _onNotesChanged,
                      maxLines: 6,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDesktopStatCard(
    BuildContext context,
    IconData icon,
    String title,
    String value,
    String subtitle,
    Color color, {
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildMobileSlivers(
    BuildContext context,
    bool isToday,
    bool hasTasks,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    return [
      // Приветствие
      SliverToBoxAdapter(child: _buildMobileWelcomeWidget(isToday, isDark)),

      // Быстрая статистика
      if (isToday)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    context,
                    Icons.pending_actions_rounded,
                    'Осталось',
                    '${_tasks.where((task) => !task.isDone).length}',
                    colorScheme.secondary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    context,
                    Icons.local_fire_department_rounded,
                    'Серия',
                    _isStreakLoading ? '…' : '$_currentStreak дн.',
                    const Color(0xFFF07852),
                    onTap: _currentStreak > 0
                        ? () => _showStreakDetails(context)
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),

      // Задачи
      if (_tasks.isNotEmpty) ...[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
          sliver: SliverToBoxAdapter(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Мой план',
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isToday
                            ? 'Задачи на сегодня'
                            : 'План на ${_getWeekdayName(_currentDate.weekday)}',
                        style: TextStyle(
                          color: colorScheme.onSurface.withValues(alpha: 0.62),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '${_visibleTasks.length}',
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          sliver: SliverToBoxAdapter(child: _buildTaskFilters(colorScheme)),
        ),
        if (_visibleTasks.isEmpty)
          SliverToBoxAdapter(
            child: SizedBox(
              height: 180,
              child: _buildNoTaskMatches(colorScheme),
            ),
          )
        else if (_hasTaskFilters)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: _buildModernTaskItem(_displayedTasks[index], context),
                ),
                childCount: _displayedTasks.length,
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            sliver: SliverReorderableList(
              itemCount: _displayedTasks.length,
              onReorder: _onReorder,
              itemBuilder: (context, index) {
                final task = _displayedTasks[index];
                return ReorderableDelayedDragStartListener(
                  key: Key('task-${task.id}'),
                  index: index,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: _buildModernTaskItem(task, context),
                  ),
                );
              },
            ),
          ),
        if (_visibleTasks.length > _taskPreviewLimit)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Center(
                child: TextButton.icon(
                  onPressed: () {
                    setState(() => _showAllTasks = !_showAllTasks);
                  },
                  icon: Icon(
                    _showAllTasks
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                  ),
                  label: Text(
                    _showAllTasks
                        ? 'Свернуть список'
                        : 'Показать ещё ${_visibleTasks.length - _displayedTasks.length}',
                  ),
                ),
              ),
            ),
          ),
      ] else
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _buildEmptyState(context, isToday, colorScheme, isDark),
          ),
        ),

      // Итоги дня
      if (!_isFutureDate(_currentDate))
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _buildDaySummary(colorScheme),
          ),
        ),

      const SliverToBoxAdapter(child: SizedBox(height: 80)),
    ];
  }

  Widget _buildMobileWelcomeWidget(bool isToday, bool isDark) {
    final completedTasks = _tasks.where((task) => task.isDone).length;
    final progress = _tasks.isEmpty ? 0.0 : completedTasks / _tasks.length;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? const [Color(0xFF282254), Color(0xFF413A91), Color(0xFF273F73)]
              : const [Color(0xFF5148C8), Color(0xFF7166E8), Color(0xFF4F70D8)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(
              0xFF5148C8,
            ).withValues(alpha: isDark ? 0.22 : 0.2),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            Positioned(
              top: -54,
              right: -34,
              child: Container(
                width: 164,
                height: 164,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              bottom: -66,
              right: 68,
              child: Container(
                width: 132,
                height: 132,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundImage: _avatarImageProvider,
                        backgroundColor: Colors.white.withValues(alpha: 0.18),
                        child: _avatarImageProvider == null
                            ? Text(
                                _getUserName().substring(0, 1).toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _getGreeting(),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.76),
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              _getUserName(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Text(
                          '${_currentDate.day} ${_getMonthName(_currentDate.month)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 16,
                        color: Colors.white.withValues(alpha: 0.84),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isToday ? 'ПЛАН НА СЕГОДНЯ' : 'ПЛАН НА ДЕНЬ',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.84),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${(progress * 100).round()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    _tasks.isEmpty
                        ? 'Добавьте задачу, чтобы начать день'
                        : '$completedTasks из ${_tasks.length} задач выполнено',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopWelcomeWidget(bool isToday, bool isDark) {
    final completedTasks = _tasks.where((task) => task.isDone).length;
    final progress = _tasks.isEmpty ? 0.0 : completedTasks / _tasks.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? const [Color(0xFF282254), Color(0xFF413A91), Color(0xFF273F73)]
              : const [Color(0xFF5148C8), Color(0xFF7166E8), Color(0xFF4F70D8)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(
              0xFF5148C8,
            ).withValues(alpha: isDark ? 0.22 : 0.2),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -72,
            right: 110,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getGreeting(),
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withValues(alpha: 0.76),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _getUserName(),
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isToday
                          ? 'Соберём день в понятный план'
                          : 'План на ${_getWeekdayName(_currentDate.weekday)}',
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.white.withValues(alpha: 0.82),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 7,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.2,
                              ),
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Text(
                          '${(progress * 100).round()}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _tasks.isEmpty
                          ? 'Добавьте задачу, чтобы начать день'
                          : '$completedTasks из ${_tasks.length} задач выполнено',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.76),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 32),
              CircleAvatar(
                radius: 40,
                backgroundImage: _avatarImageProvider,
                backgroundColor: Colors.white.withValues(alpha: 0.18),
                child: _avatarImageProvider == null
                    ? Text(
                        _getUserName().substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  LinearGradient _getStreakGradient(int streak) {
    if (streak >= 30) {
      return const LinearGradient(
        colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
      );
    } else if (streak >= 7) {
      return const LinearGradient(
        colors: [Color(0xFFFF6B6B), Color(0xFFFF8E53)],
      );
    } else {
      return const LinearGradient(
        colors: [Color(0xFF7C3AED), Color(0xFF6366F1)],
      );
    }
  }

  Widget _buildStatCard(
    BuildContext context,
    IconData icon,
    String title,
    String value,
    Color color, {
    VoidCallback? onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.55),
          ),
          boxShadow: [
            BoxShadow(
              blurRadius: 14,
              color: Colors.black.withValues(alpha: 0.045),
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernTaskItem(
    DailyPlanItem task,
    BuildContext context, {
    bool isDesktop = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isCompleted = task.id == _completedTaskId;

    return RepaintBoundary(
      child: AnimatedScale(
        scale: isCompleted ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 300),
        child: GestureDetector(
          onLongPress: () => _showTaskContextMenu(context, task),
          child: Container(
            decoration: BoxDecoration(
              gradient: _getTaskGradient(task.isDone, isDark),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: task.isDone
                      ? colorScheme.primary.withValues(alpha: 0.2)
                      : Colors.black.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(
                color: task.isDone
                    ? colorScheme.primary.withValues(alpha: 0.3)
                    : Colors.transparent,
                width: 1,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(24),
              child: InkWell(
                onTap: () => _toggleTaskOrSubtask(task),
                borderRadius: BorderRadius.circular(24),
                child: Padding(
                  padding: EdgeInsets.all(isDesktop ? 20 : 16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          // Кастомный чекбокс
                          _buildModernCheckbox(task, colorScheme),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  task.title,
                                  style: TextStyle(
                                    fontSize: isDesktop ? 18 : 16,
                                    fontWeight: FontWeight.w600,
                                    color: task.isDone
                                        ? colorScheme.onSurface.withValues(
                                            alpha: 0.6,
                                          )
                                        : colorScheme.onSurface,
                                    decoration: task.isDone
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                if (task.recurrenceId != null)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Tooltip(
                                      message: 'Повторяется каждый день',
                                      child: Icon(
                                        Icons.repeat,
                                        color: colorScheme.primary,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                if (task.subtasks.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: _buildSubtasksProgress(
                                      task,
                                      colorScheme,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (task.subtasks.isNotEmpty)
                            Icon(
                              _expandedTasks.contains(task.id)
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              color: colorScheme.primary,
                            ),
                          _buildTaskActions(task, context),
                        ],
                      ),
                      // Раскрытые подзадачи
                      if (task.subtasks.isNotEmpty &&
                          _expandedTasks.contains(task.id))
                        Column(
                          children: [
                            const SizedBox(height: 16),
                            Divider(
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.1,
                              ),
                              height: 1,
                            ),
                            const SizedBox(height: 12),
                            ...List.generate(task.subtasks.length, (index) {
                              final subtask = task.subtasks[index];
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: GestureDetector(
                                  onTap: () =>
                                      _toggleTaskOrSubtask(task, index),
                                  child: Row(
                                    children: [
                                      const SizedBox(width: 8),
                                      AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 200,
                                        ),
                                        width: 20,
                                        height: 20,
                                        decoration: BoxDecoration(
                                          color: subtask.done
                                              ? colorScheme.primary
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          border: Border.all(
                                            color: subtask.done
                                                ? colorScheme.primary
                                                : colorScheme.onSurface
                                                      .withValues(alpha: 0.3),
                                            width: 2,
                                          ),
                                        ),
                                        child: subtask.done
                                            ? const Icon(
                                                Icons.check,
                                                size: 14,
                                                color: Colors.white,
                                              )
                                            : null,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          subtask.title,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: subtask.done
                                                ? colorScheme.onSurface
                                                      .withValues(alpha: 0.5)
                                                : colorScheme.onSurface,
                                            decoration: subtask.done
                                                ? TextDecoration.lineThrough
                                                : null,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubtasksProgress(DailyPlanItem task, ColorScheme colorScheme) {
    final completedCount = task.subtasks.where((s) => s.done).length;
    final total = task.subtasks.length;
    final progress = total > 0 ? completedCount / total : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$completedCount/$total выполнено',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            Text(
              '${(progress * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: 4,
          decoration: BoxDecoration(
            color: colorScheme.onSurface.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(2),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: progress,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colorScheme.primary,
                    colorScheme.primary.withValues(alpha: 0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTaskActions(DailyPlanItem task, BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            Icons.edit,
            color: colorScheme.primary.withValues(alpha: 0.7),
            size: 20,
          ),
          onPressed: () {
            Navigator.of(context)
                .push(
                  MaterialPageRoute(
                    builder: (context) =>
                        EditPlanScreen(date: _currentDate, taskToEdit: task),
                  ),
                )
                .then((_) => _loadData());
          },
        ),
      ],
    );
  }

  LinearGradient _getTaskGradient(bool isDone, bool isDark) {
    if (isDone) {
      return LinearGradient(
        colors: isDark
            ? [
                const Color(0xFF10B981).withValues(alpha: 0.2),
                const Color(0xFF059669).withValues(alpha: 0.2),
              ]
            : [
                const Color(0xFF10B981).withValues(alpha: 0.1),
                const Color(0xFF059669).withValues(alpha: 0.1),
              ],
      );
    } else {
      return LinearGradient(
        colors: isDark
            ? [const Color(0xFF334155), const Color(0xFF475569)]
            : [Colors.white, const Color(0xFFF8FAFC)],
      );
    }
  }

  Widget _buildModernCheckbox(DailyPlanItem task, ColorScheme colorScheme) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: task.isDone ? colorScheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: task.isDone
              ? colorScheme.primary
              : colorScheme.onSurface.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: task.isDone
          ? const Icon(Icons.check, size: 16, color: Colors.white)
          : null,
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    bool isToday,
    ColorScheme colorScheme,
    bool isDark, {
    bool isDesktop = false,
  }) {
    return Container(
      padding: EdgeInsets.all(isDesktop ? 48 : 40),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1B4B) : Colors.white,
        borderRadius: BorderRadius.circular(isDesktop ? 32 : 24),
        boxShadow: [
          BoxShadow(
            blurRadius: 20,
            color: Colors.black.withValues(alpha: 0.1),
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            Icons.task_alt,
            size: isDesktop ? 80 : 64,
            color: colorScheme.primary.withValues(alpha: 0.3),
          ),
          SizedBox(height: isDesktop ? 24 : 16),
          Text(
            isToday
                ? 'Пока нет задач\nДобавьте первую задачу!'
                : 'Нет задач на этот день',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isDesktop ? 18 : 16,
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          if (isToday)
            Column(
              children: [
                Padding(
                  padding: EdgeInsets.only(top: isDesktop ? 32 : 24),
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: Text(
                      'Добавить задачу',
                      style: TextStyle(fontSize: isDesktop ? 16 : 14),
                    ),
                    onPressed: () {
                      Navigator.of(context)
                          .push(
                            MaterialPageRoute(
                              builder: (context) =>
                                  EditPlanScreen(date: _currentDate),
                            ),
                          )
                          .then((_) => _loadData());
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        horizontal: isDesktop ? 32 : 24,
                        vertical: isDesktop ? 16 : 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.calendar_today),
                  label: Text(
                    'Добавить на другой день',
                    style: TextStyle(fontSize: isDesktop ? 16 : 14),
                  ),
                  onPressed: () => _addTaskForFutureDate(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.secondary,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                      horizontal: isDesktop ? 32 : 24,
                      vertical: isDesktop ? 16 : 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildDaySummary(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
        boxShadow: [
          BoxShadow(
            blurRadius: 16,
            color: Colors.black.withValues(alpha: 0.045),
            offset: const Offset(0, 6),
          ),
        ],
      ),
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
                child: Icon(Icons.insights, color: colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Text(
                'Итоги дня',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _buildModernMoodRating(colorScheme),
          const SizedBox(height: 16),
          Divider(
            height: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 16),
          _buildModernProductivityRating(colorScheme),
          const SizedBox(height: 18),
          NotesInputWidget(value: _notes, onNotesChanged: _onNotesChanged),
        ],
      ),
    );
  }

  Widget _buildModernMoodRating(ColorScheme colorScheme) {
    final moods = [
      _MoodItem('😭', 'Ужасно', const Color(0xFFEF4444)),
      _MoodItem('😢', 'Плохо', const Color(0xFFF97316)),
      _MoodItem('😐', 'Нормально', const Color(0xFFFBBF24)),
      _MoodItem('😊', 'Хорошо', const Color(0xFF10B981)),
      _MoodItem('🤩', 'Отлично', const Color(0xFF3B82F6)),
    ];
    final selectedIndex = _mood != null && _mood! >= 1 && _mood! <= moods.length
        ? _mood! - 1
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.emoji_emotions_outlined,
              color: colorScheme.primary,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'Настроение',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            if (selectedIndex != null)
              Text(
                moods[selectedIndex].label,
                style: TextStyle(
                  color: moods[selectedIndex].color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: List.generate(moods.length, (index) {
            final mood = moods[index];
            final isSelected = _mood == index + 1;

            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: index == moods.length - 1 ? 0 : 6,
                ),
                child: Tooltip(
                  message: mood.label,
                  child: Semantics(
                    button: true,
                    selected: isSelected,
                    label: 'Настроение: ${mood.label}',
                    child: GestureDetector(
                      onTap: () =>
                          _onMoodChanged(isSelected ? null : index + 1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        height: 48,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? mood.color.withValues(alpha: 0.14)
                              : colorScheme.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? mood.color
                                : colorScheme.outlineVariant.withValues(
                                    alpha: 0.7,
                                  ),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            mood.emoji,
                            style: const TextStyle(fontSize: 22),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildModernProductivityRating(ColorScheme colorScheme) {
    final levels = [
      _ProductivityItem('😴', 'Низкая', const Color(0xFFEF4444)),
      _ProductivityItem('😐', 'Средняя', const Color(0xFFFBBF24)),
      _ProductivityItem('⚡', 'Высокая', const Color(0xFF10B981)),
    ];
    final selectedIndex =
        _productivity != null &&
            _productivity! >= 1 &&
            _productivity! <= levels.length
        ? _productivity! - 1
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.trending_up, color: colorScheme.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              'Продуктивность',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            if (selectedIndex != null)
              Text(
                levels[selectedIndex].label,
                style: TextStyle(
                  color: levels[selectedIndex].color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: List.generate(levels.length, (index) {
            final level = levels[index];
            final isSelected = _productivity == index + 1;

            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: index == levels.length - 1 ? 0 : 8,
                ),
                child: Semantics(
                  button: true,
                  selected: isSelected,
                  label: 'Продуктивность: ${level.label}',
                  child: GestureDetector(
                    onTap: () =>
                        _onProductivityChanged(isSelected ? null : index + 1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 58,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? level.color.withValues(alpha: 0.14)
                            : colorScheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected
                              ? level.color
                              : colorScheme.outlineVariant.withValues(
                                  alpha: 0.7,
                                ),
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            level.emoji,
                            style: const TextStyle(fontSize: 19),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            level.label,
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontSize: 11,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildAppBarButton(
    BuildContext context,
    IconData icon,
    VoidCallback onPressed, {
    bool small = false,
    String? tooltip,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(small ? 8 : 12),
      ),
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, color: colorScheme.primary, size: small ? 20 : 24),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildMobileFAB(BuildContext context, ColorScheme colorScheme) {
    return FloatingActionButton.extended(
      heroTag: 'add-task-fab',
      backgroundColor: colorScheme.primary,
      foregroundColor: Colors.white,
      elevation: 8,
      icon: const Icon(Icons.add),
      label: const Text('Добавить задачу'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      onPressed: _addTaskForCurrentDate,
    );
  }

  Future<void> _addTaskForCurrentDate() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => EditPlanScreen(date: _currentDate),
      ),
    );
    if (!mounted) return;
    await _loadData();
    await _loadStreakData();
  }

  Widget _buildTodayFAB(BuildContext context, ColorScheme colorScheme) {
    return FloatingActionButton.extended(
      heroTag: 'today-fab',
      backgroundColor: colorScheme.primary,
      foregroundColor: Colors.white,
      elevation: 8,
      icon: const Icon(Icons.today_rounded),
      label: const Text('Сегодня'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      onPressed: _goToToday,
    );
  }

  Widget _buildFutureDateActions(
    BuildContext context,
    ColorScheme colorScheme,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FloatingActionButton.extended(
          heroTag: 'future-add-task-fab',
          backgroundColor: colorScheme.secondaryContainer,
          foregroundColor: colorScheme.onSecondaryContainer,
          elevation: 4,
          icon: const Icon(Icons.add_task_rounded),
          label: const Text('Добавить задачу'),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          onPressed: _addTaskForCurrentDate,
        ),
        const SizedBox(height: 12),
        _buildTodayFAB(context, colorScheme),
      ],
    );
  }

  void _showStreakDetails(BuildContext context) {
    showModalBottomSheet(
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
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).dividerColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Заголовок
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: _getStreakGradient(_currentStreak),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.local_fire_department,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Ваш стрик',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Статистика
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildStreakStatItem('🔥', 'Текущий', '$_currentStreak'),
                      _buildStreakStatItem('🏆', 'Рекорд', '$_longestStreak'),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Прогресс бар следующего уровня
                  if (_currentStreak > 0)
                    Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'До следующего уровня:',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.8),
                              ),
                            ),
                            Text(
                              _getNextLevelText(),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 8,
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: _getProgressToNextLevel(),
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: _getStreakGradient(_currentStreak),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),

                  // Советы
                  Text(
                    '💡 Совет: Выполняйте хотя бы одну задачу в день для поддержания стрика',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Кнопка закрытия
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        foregroundColor: Theme.of(
                          context,
                        ).colorScheme.onSurface,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text('Закрыть'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStreakStatItem(String icon, String label, String value) {
    return Column(
      children: [
        Text(icon, style: const TextStyle(fontSize: 28)),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  String _getNextLevelText() {
    if (_currentStreak < 7) return '${7 - _currentStreak} до 7 дней';
    if (_currentStreak < 30) return '${30 - _currentStreak} до 30 дней';
    return 'Достигнут максимум!';
  }

  double _getProgressToNextLevel() {
    if (_currentStreak < 7) return _currentStreak / 7;
    if (_currentStreak < 30) return (_currentStreak - 7) / (30 - 7);
    return 1.0;
  }
}

class _MoodItem {
  final String emoji;
  final String label;
  final Color color;

  _MoodItem(this.emoji, this.label, this.color);
}

class _ProductivityItem {
  final String emoji;
  final String label;
  final Color color;

  _ProductivityItem(this.emoji, this.label, this.color);
}

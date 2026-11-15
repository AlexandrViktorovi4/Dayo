// lib/screens/calendar_screen.dart
import 'package:flutter/material.dart';
import 'package:planner/screens/home_screen.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:planner/services/daily_plan_service.dart';
import 'package:planner/models/daily_plan_item.dart';
import 'package:fl_chart/fl_chart.dart'; // Добавляем пакет для графиков
import 'package:planner/services/streak_service.dart'; // Для стриков

class CalendarScreen extends StatefulWidget {
  final DateTime? initialDate;
  final void Function(ThemeMode) toggleTheme;

  const CalendarScreen({
    super.key,
    this.initialDate,
    required this.toggleTheme,
  });

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final DailyPlanService _planService = DailyPlanService();
  final StreakService _streakService =
      StreakService(); // Добавляем сервис стриков
  late DateTime _focusedDay;
  DateTime? _selectedDay;
  Map<DateTime, List<DailyPlanItem>> _tasksByDate = {};
  bool _isLoading = true;

  // Новые поля для графиков
  List<double> _weeklyProgress = [];
  List<double> _monthlyProgress = [];
  List<double> _yearlyProgress = [];
  int _currentStreak = 0;
  int _longestStreak = 0;
  String _chartType = 'week'; // 'week', 'month', 'year'

  @override
  void initState() {
    super.initState();
    _focusedDay = widget.initialDate ?? DateTime.now();
    _selectedDay = _focusedDay;
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);

    try {
      // Загружаем всё параллельно вместо последовательной загрузки
      await Future.wait([
        _loadTasksForMonth(_focusedDay),
        _loadChartData(),
        _loadStreakData(),
      ]);
    } catch (e) {
      debugPrint('Ошибка загрузки данных календаря: $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadTasksForMonth(DateTime date) async {
    final start = DateTime(date.year, date.month, 1);
    final end = DateTime(date.year, date.month + 1, 0);

    try {
      final grouped = await _planService.getPlanForDateRange(start, end);
      if (mounted) {
        setState(() {
          _tasksByDate = grouped;
        });
      }
    } catch (e) {
      debugPrint('Ошибка загрузки задач месяца: $e');
    }
  }

  Future<void> _loadChartData() async {
    final now = DateTime.now();

    try {
      // Загружаем параллельно вместо последовательно
      final results = await Future.wait([
        _getProgressForPeriod(7),
        _getProgressForPeriod(30),
        _getMonthlyProgressForYear(now.year),
      ]);

      if (mounted) {
        setState(() {
          _weeklyProgress = results[0];
          _monthlyProgress = results[1];
          _yearlyProgress = results[2];
        });
      }
    } catch (e) {
      debugPrint('Ошибка загрузки данных графиков: $e');
    }
  }

  Future<void> _loadStreakData() async {
    try {
      final streak = await _streakService.getCurrentStreak();
      setState(() {
        _currentStreak = streak.currentStreak;
        _longestStreak = streak.longestStreak;
      });
    } catch (e) {
      debugPrint('Ошибка загрузки стрика: $e');
    }
  }

  Future<List<double>> _getProgressForPeriod(int days) async {
    final now = DateTime.now();
    final startDate = now.subtract(Duration(days: days - 1));
    final endDate = now;

    // Загружаем все задачи за период одним запросом
    final tasksByDate = await _planService.getPlanForDateRange(
      startDate,
      endDate,
    );

    List<double> progress = [];

    // Заполняем прогресс для каждого дня
    for (int i = 0; i < days; i++) {
      final date = startDate.add(Duration(days: i));
      final dateKey = DateTime(date.year, date.month, date.day);
      final tasks = tasksByDate[dateKey] ?? [];
      final dayProgress = _calculateProgress(tasks);
      progress.add(dayProgress);
    }

    return progress;
  }

  Future<List<double>> _getMonthlyProgressForYear(int year) async {
    List<double> monthlyProgress = [];

    // Загружаем все задачи за год одним запросом
    final startDate = DateTime(year, 1, 1);
    final endDate = DateTime(year, 12, 31);
    final allTasksByDate = await _planService.getPlanForDateRange(
      startDate,
      endDate,
    );

    for (int month = 1; month <= 12; month++) {
      double monthProgress = 0.0;
      int daysWithTasks = 0;

      // Получаем первый и последний день месяца
      final firstDay = DateTime(year, month, 1);
      final lastDay = DateTime(year, month + 1, 0);

      // Проверяем все дни месяца в già загруженных данных
      for (int day = firstDay.day; day <= lastDay.day; day++) {
        final dateKey = DateTime(year, month, day);
        final tasks = allTasksByDate[dateKey];

        if (tasks != null && tasks.isNotEmpty) {
          final dayProgress = _calculateProgress(tasks);
          monthProgress += dayProgress;
          daysWithTasks++;
        }
      }

      // Средний прогресс за месяц
      monthlyProgress.add(
        daysWithTasks > 0 ? monthProgress / daysWithTasks : 0.0,
      );
    }

    return monthlyProgress;
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    if (!isSameDay(_selectedDay, selectedDay)) {
      setState(() {
        _selectedDay = selectedDay;
        _focusedDay = focusedDay;
      });
    }

    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => HomeScreen(
            initialDate: selectedDay,
            toggleTheme: widget.toggleTheme,
          ),
        ),
      );
    });
  }

  void _goToToday() {
    final today = DateTime.now();
    final monthChanged =
        _focusedDay.year != today.year || _focusedDay.month != today.month;

    setState(() {
      _selectedDay = today;
      _focusedDay = today;
    });

    if (monthChanged) {
      _loadTasksForMonth(today);
    }
  }

  BoxDecoration _cardDecoration(ColorScheme colorScheme, {double radius = 24}) {
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
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
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (context) =>
                      HomeScreen(toggleTheme: widget.toggleTheme),
                ),
              );
            },
          ),
        ),
        title: Text(
          'Календарь и аналитика',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        centerTitle: false,
        actions: [
          if (!isSameDay(_focusedDay, DateTime.now()))
            IconButton(
              tooltip: 'Перейти к сегодняшнему дню',
              onPressed: _goToToday,
              icon: Icon(Icons.today_rounded, color: colorScheme.primary),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAllData,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // Статистика месяца и стрик
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(20),
                      decoration: _cardDecoration(colorScheme),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(9),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withValues(
                                    alpha: 0.1,
                                  ),
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: Icon(
                                  Icons.insights_rounded,
                                  color: colorScheme.primary,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Обзор месяца',
                                      style: TextStyle(
                                        color: colorScheme.onSurface,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Ваша активность и прогресс',
                                      style: TextStyle(
                                        color: colorScheme.onSurface.withValues(
                                          alpha: 0.62,
                                        ),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          // Первая строка: общая статистика
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatItem(
                                  'Дни с задачами',
                                  '${_tasksByDate.length}',
                                  Icons.calendar_today_rounded,
                                  colorScheme.primary,
                                ),
                              ),
                              Expanded(
                                child: _buildStatItem(
                                  'Всего задач',
                                  '${_getTotalTasksCount()}',
                                  Icons.task_alt_rounded,
                                  colorScheme.secondary,
                                ),
                              ),
                              Expanded(
                                child: _buildStatItem(
                                  'Прогресс',
                                  '${_getCompletionRate()}%',
                                  Icons.trending_up_rounded,
                                  const Color(0xFFF07852),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 18),

                          // Вторая строка: стрик
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(
                                alpha: 0.07,
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                Flexible(
                                  child: _buildStreakStat(
                                    '🔥 Текущая серия',
                                    '$_currentStreak дн',
                                    colorScheme.primary,
                                  ),
                                ),
                                Flexible(
                                  child: _buildStreakStat(
                                    '🏆 Лучший результат',
                                    '$_longestStreak дн',
                                    colorScheme.secondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Переключение графиков
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.all(5),
                      decoration: _cardDecoration(colorScheme, radius: 18),
                      child: SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: 'week',
                            label: Text('Неделя'),
                            icon: Icon(Icons.show_chart_rounded),
                          ),
                          ButtonSegment(
                            value: 'month',
                            label: Text('Месяц'),
                            icon: Icon(Icons.timeline_rounded),
                          ),
                          ButtonSegment(
                            value: 'year',
                            label: Text('Год'),
                            icon: Icon(Icons.bar_chart_rounded),
                          ),
                        ],
                        selected: {_chartType},
                        onSelectionChanged: (selection) {
                          setState(() => _chartType = selection.first);
                        },
                      ),
                    ),

                    const SizedBox(height: 16),

                    // График прогресса
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.all(20),
                      decoration: _cardDecoration(colorScheme),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _chartType == 'week'
                                    ? Icons.show_chart
                                    : _chartType == 'month'
                                    ? Icons.timeline
                                    : Icons.bar_chart,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _chartType == 'week'
                                      ? 'Прогресс за неделю'
                                      : _chartType == 'month'
                                      ? 'Прогресс за 30 дней'
                                      : 'Прогресс за год',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (_chartType == 'week')
                                Container(
                                  margin: const EdgeInsets.only(left: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary.withValues(
                                      alpha: 0.09,
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    'Среднее ${_getAverageProgress(_weeklyProgress)}%',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 200,
                            child: _chartType == 'week'
                                ? _buildWeeklyChart()
                                : _chartType == 'month'
                                ? _buildMonthlyChart()
                                : _buildYearlyChart(),
                          ),
                        ],
                      ),
                    ),

                    // Календарь
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(20),
                      decoration: _cardDecoration(colorScheme),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(9),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withValues(
                                    alpha: 0.1,
                                  ),
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: Icon(
                                  Icons.calendar_month_rounded,
                                  color: colorScheme.primary,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Календарь',
                                      style: TextStyle(
                                        color: colorScheme.onSurface,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Нажмите на день, чтобы открыть план',
                                      style: TextStyle(
                                        color: colorScheme.onSurface.withValues(
                                          alpha: 0.62,
                                        ),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TableCalendar(
                            firstDay: DateTime(DateTime.now().year - 1),
                            lastDay: DateTime(DateTime.now().year + 1),
                            focusedDay: _focusedDay,
                            startingDayOfWeek: StartingDayOfWeek.monday,
                            selectedDayPredicate: (day) {
                              return isSameDay(_selectedDay, day);
                            },
                            onPageChanged: (focusedDay) {
                              setState(() {
                                _focusedDay = focusedDay;
                              });
                              _loadTasksForMonth(focusedDay);
                            },
                            calendarFormat: CalendarFormat.month,
                            onFormatChanged: null,
                            onDaySelected: _onDaySelected,
                            headerStyle: HeaderStyle(
                              formatButtonVisible: false,
                              titleCentered: true,
                              titleTextStyle: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface,
                              ),
                              leftChevronIcon: Icon(
                                Icons.chevron_left,
                                color: colorScheme.primary,
                                size: 24,
                              ),
                              rightChevronIcon: Icon(
                                Icons.chevron_right,
                                color: colorScheme.primary,
                                size: 24,
                              ),
                              headerPadding: const EdgeInsets.symmetric(
                                vertical: 16,
                              ),
                              formatButtonShowsNext: false,
                            ),
                            daysOfWeekStyle: DaysOfWeekStyle(
                              weekdayStyle: TextStyle(
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.7,
                                ),
                                fontWeight: FontWeight.w500,
                              ),
                              weekendStyle: TextStyle(
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.7,
                                ),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            calendarStyle: CalendarStyle(
                              todayDecoration: BoxDecoration(
                                color: colorScheme.primary.withValues(
                                  alpha: 0.2,
                                ),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: colorScheme.primary,
                                  width: 2,
                                ),
                              ),
                              todayTextStyle: TextStyle(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              selectedDecoration: BoxDecoration(
                                color: colorScheme.primary,
                                shape: BoxShape.circle,
                              ),
                              selectedTextStyle: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              defaultTextStyle: TextStyle(
                                color: colorScheme.onSurface,
                                fontSize: 14,
                              ),
                              weekendTextStyle: TextStyle(
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.7,
                                ),
                                fontSize: 14,
                              ),
                              outsideTextStyle: TextStyle(
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.3,
                                ),
                                fontSize: 14,
                              ),
                              cellPadding: const EdgeInsets.all(6),
                              cellMargin: const EdgeInsets.all(2),
                            ),
                            calendarBuilders: CalendarBuilders(
                              defaultBuilder: (context, day, focusedDay) {
                                final isSelected = isSameDay(_selectedDay, day);
                                final isToday = isSameDay(day, DateTime.now());
                                final isOtherMonth =
                                    day.month != _focusedDay.month;

                                if (isOtherMonth) {
                                  return Container(
                                    margin: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? Colors.grey[700]!.withValues(
                                              alpha: 0.3,
                                            )
                                          : Colors.grey[100]!.withValues(
                                              alpha: 0.5,
                                            ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${day.day}',
                                        style: TextStyle(
                                          color: colorScheme.onSurface
                                              .withValues(alpha: 0.3),
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  );
                                }

                                final tasks = _tasksByDate[day];
                                final progress = _calculateProgress(tasks);

                                return Container(
                                  margin: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: isToday && !isSelected
                                        ? Border.all(
                                            color: colorScheme.primary,
                                            width: 2,
                                          )
                                        : null,
                                  ),
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      if (tasks != null &&
                                          tasks.isNotEmpty &&
                                          !isSelected)
                                        CircularProgressIndicator(
                                          value: progress,
                                          backgroundColor: isDark
                                              ? Colors.grey[700]
                                              : Colors.grey[200],
                                          color: _getProgressColor(progress),
                                          strokeWidth: 2,
                                        ),

                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isSelected
                                              ? colorScheme.primary
                                              : (tasks != null &&
                                                        tasks.isNotEmpty
                                                    ? _getProgressColor(
                                                        progress,
                                                      ).withValues(alpha: 0.1)
                                                    : Colors.transparent),
                                        ),
                                        child: Center(
                                          child: Text(
                                            '${day.day}',
                                            style: TextStyle(
                                              color: isSelected
                                                  ? Colors.white
                                                  : _getTextColor(
                                                      day,
                                                      tasks,
                                                      progress,
                                                      colorScheme,
                                                    ),
                                              fontSize: 14,
                                              fontWeight: isToday || isSelected
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                        ),
                                      ),

                                      if (tasks != null &&
                                          tasks.isNotEmpty &&
                                          !isSelected)
                                        Positioned(
                                          top: 2,
                                          right: 2,
                                          child: Container(
                                            width: 6,
                                            height: 6,
                                            decoration: BoxDecoration(
                                              color: _getProgressColor(
                                                progress,
                                              ),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Цвет отметки показывает выполнение задач',
                            style: TextStyle(
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.62,
                              ),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 14,
                            runSpacing: 8,
                            children: [
                              _buildProgressLegend(
                                '0–54%',
                                Colors.red,
                                colorScheme,
                              ),
                              _buildProgressLegend(
                                '55–95%',
                                Colors.orange,
                                colorScheme,
                              ),
                              _buildProgressLegend(
                                '96–100%',
                                Colors.green,
                                colorScheme,
                              ),
                            ],
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
  }

  // График за неделю (областной)
  Widget _buildWeeklyChart() {
    final colorScheme = Theme.of(context).colorScheme;
    final days = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

    return LineChart(
      LineChartData(
        gridData: FlGridData(show: false),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value >= 0 && value < days.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      days[value.toInt()],
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  );
                }
                return const SizedBox();
              },
              reservedSize: 32,
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                return Text(
                  '${(value * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 10,
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                );
              },
              reservedSize: 40,
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(
            bottom: BorderSide(
              color: colorScheme.onSurface.withValues(alpha: 0.1),
              width: 1,
            ),
            left: BorderSide(
              color: colorScheme.onSurface.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: _weeklyProgress.asMap().entries.map((entry) {
              return FlSpot(entry.key.toDouble(), entry.value);
            }).toList(),
            isCurved: true,
            color: colorScheme.primary,
            barWidth: 3,
            isStrokeCapRound: true,
            belowBarData: BarAreaData(
              show: true,
              color: colorScheme.primary.withValues(alpha: 0.2),
            ),
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                return FlDotCirclePainter(
                  radius: 4,
                  color: colorScheme.primary,
                  strokeWidth: 2,
                  strokeColor: Colors.white,
                );
              },
            ),
          ),
        ],
        minY: 0,
        maxY: 1.0,
      ),
    );
  }

  // График за месяц (линейный)
  Widget _buildMonthlyChart() {
    final colorScheme = Theme.of(context).colorScheme;

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          horizontalInterval: 0.25,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: colorScheme.onSurface.withValues(alpha: 0.1),
              strokeWidth: 1,
            );
          },
          getDrawingVerticalLine: (value) {
            return FlLine(
              color: colorScheme.onSurface.withValues(alpha: 0.1),
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value % 5 == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      'День ${value.toInt() + 1}',
                      style: TextStyle(
                        fontSize: 10,
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  );
                }
                return const SizedBox();
              },
              reservedSize: 32,
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value == 0 || value == 0.5 || value == 1.0) {
                  return Text(
                    '${(value * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: 10,
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  );
                }
                return const SizedBox();
              },
              reservedSize: 40,
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(
            color: colorScheme.onSurface.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: _monthlyProgress.asMap().entries.map((entry) {
              return FlSpot(entry.key.toDouble(), entry.value);
            }).toList(),
            isCurved: true,
            color: Colors.orange,
            barWidth: 3,
            isStrokeCapRound: true,
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  Colors.orange.withValues(alpha: 0.3),
                  Colors.orange.withValues(alpha: 0.1),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            dotData: FlDotData(show: false),
          ),
        ],
        minY: 0,
        maxY: 1.0,
      ),
    );
  }

  // График за год (столбчатый)
  Widget _buildYearlyChart() {
    final colorScheme = Theme.of(context).colorScheme;
    final months = [
      'Янв',
      'Фев',
      'Мар',
      'Апр',
      'Май',
      'Июн',
      'Июл',
      'Авг',
      'Сен',
      'Окт',
      'Ноя',
      'Дек',
    ];

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: 1.0,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            tooltipBgColor: colorScheme.surface,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                '${months[group.x.toInt()]}: ${(rod.toY * 100).toStringAsFixed(1)}%',
                TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value >= 0 && value < months.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      months[value.toInt()],
                      style: TextStyle(
                        fontSize: 10,
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  );
                }
                return const SizedBox();
              },
              reservedSize: 32,
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value == 0 || value == 0.5 || value == 1.0) {
                  return Text(
                    '${(value * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: 10,
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  );
                }
                return const SizedBox();
              },
              reservedSize: 40,
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 0.25,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: colorScheme.onSurface.withValues(alpha: 0.1),
              strokeWidth: 1,
            );
          },
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(
            color: colorScheme.onSurface.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        barGroups: _yearlyProgress.asMap().entries.map((entry) {
          final value = entry.value;
          final color = value >= 0.7
              ? Colors.green
              : value >= 0.4
              ? Colors.orange
              : Colors.red;

          return BarChartGroupData(
            x: entry.key,
            barRods: [
              BarChartRodData(
                toY: value,
                width: 16,
                color: color,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  // Дополнительные методы
  Widget _buildStatItem(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildStreakStat(String title, String value, Color color) {
    return Column(
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.9)),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildProgressLegend(
    String label,
    Color color,
    ColorScheme colorScheme,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: colorScheme.onSurface.withValues(alpha: 0.72),
          ),
        ),
      ],
    );
  }

  String _getAverageProgress(List<double> progress) {
    if (progress.isEmpty) return '0';
    final average = progress.reduce((a, b) => a + b) / progress.length;
    return (average * 100).toStringAsFixed(1);
  }

  Color _getProgressColor(double progress) {
    if (progress == 0.0) return Colors.grey;
    if (progress > 0.95) return Colors.green;
    if (progress >= 0.55) return Colors.orange;
    return Colors.red;
  }

  Color _getTextColor(
    DateTime day,
    List<DailyPlanItem>? tasks,
    double progress,
    ColorScheme colorScheme,
  ) {
    if (day.month != _focusedDay.month) {
      return colorScheme.onSurface.withValues(alpha: 0.3);
    }

    if (tasks == null || tasks.isEmpty) {
      return colorScheme.onSurface.withValues(alpha: 0.5);
    }

    return _getProgressColor(progress);
  }

  int _getTotalTasksCount() {
    int total = 0;
    for (final tasks in _tasksByDate.values) {
      for (final task in tasks) {
        if (task.subtasks.isEmpty) {
          total++;
        } else {
          total += task.subtasks.length;
        }
      }
    }
    return total;
  }

  int _getCompletionRate() {
    if (_tasksByDate.isEmpty) return 0;

    int totalDays = _tasksByDate.length;
    int completedDays = 0;

    for (final tasks in _tasksByDate.values) {
      final progress = _calculateProgress(tasks);
      if (progress >= 1.0) {
        completedDays++;
      }
    }

    return ((completedDays / totalDays) * 100).round();
  }

  double _calculateProgress(List<DailyPlanItem>? tasks) {
    if (tasks == null || tasks.isEmpty) return 0.0;

    int totalElements = 0;
    int completedElements = 0;

    for (final task in tasks) {
      if (task.subtasks.isEmpty) {
        totalElements++;
        if (task.isDone) completedElements++;
      } else {
        totalElements += task.subtasks.length;
        completedElements += task.subtasks.where((s) => s.done).length;
      }
    }

    return totalElements == 0 ? 0.0 : completedElements / totalElements;
  }
}

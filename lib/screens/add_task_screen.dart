// lib/screens/edit_plan_screen.dart
import 'package:flutter/material.dart';
import 'package:planner/models/daily_plan_item.dart';
import 'package:planner/services/daily_plan_service.dart';

class EditPlanScreen extends StatefulWidget {
  final DateTime date;
  final DailyPlanItem? taskToEdit;

  const EditPlanScreen({super.key, required this.date, this.taskToEdit});

  @override
  State<EditPlanScreen> createState() => _EditPlanScreenState();
}

class _EditPlanScreenState extends State<EditPlanScreen> {
  final DailyPlanService _service = DailyPlanService();
  List<TaskInput> _tasks = [];
  final List<FocusNode> _taskFocusNodes = [];
  final List<List<FocusNode>> _subtaskFocusNodes = [];
  List<DailyPlanItem> _existingTasks = [];

  @override
  void initState() {
    super.initState();
    _loadExistingTasks();
  }

  Future<void> _loadExistingTasks() async {
    try {
      final existingTasks = await _service.getPlanForDate(widget.date);
      existingTasks.sort((a, b) => a.order.compareTo(b.order));

      setState(() {
        _existingTasks = existingTasks;
        if (widget.taskToEdit != null) {
          // Если редактируем конкретную задачу, показываем только её
          _tasks = [TaskInput.fromTask(widget.taskToEdit!)];
        } else {
          // Иначе показываем все существующие + одну пустую для новой
          _tasks = existingTasks
              .map((task) => TaskInput.fromTask(task))
              .toList();
          _tasks.add(TaskInput(isNew: true)); // Пустая для новой задачи
        }

        // Создаем FocusNodes
        _taskFocusNodes.clear();
        _subtaskFocusNodes.clear();
        for (var task in _tasks) {
          _taskFocusNodes.add(FocusNode());
          _subtaskFocusNodes.add([]);
          for (var _ in task.subtaskControllers) {
            _subtaskFocusNodes.last.add(FocusNode());
          }
        }

        // Автофокус на последнюю пустую задачу, если добавляем новую
        if (widget.taskToEdit == null && _tasks.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _taskFocusNodes.last.requestFocus();
          });
        }
      });
    } catch (e) {
      debugPrint('Ошибка загрузки существующих задач: $e');
      // Fallback к пустой задаче
      setState(() {
        _existingTasks = [];
        _tasks = [TaskInput()];
        _taskFocusNodes.add(FocusNode());
        _subtaskFocusNodes.add([]);
      });
    }
  }

  @override
  void dispose() {
    for (var node in _taskFocusNodes) {
      node.dispose();
    }
    for (var list in _subtaskFocusNodes) {
      for (var node in list) {
        node.dispose();
      }
    }
    super.dispose();
  }

  void _addTask({bool focus = false}) {
    setState(() {
      _tasks.add(TaskInput());
      _taskFocusNodes.add(FocusNode());
      _subtaskFocusNodes.add([]);

      // Фокус только если явно запрошено
      if (focus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_taskFocusNodes.isNotEmpty) {
            _taskFocusNodes.last.requestFocus();
          }
        });
      }
    });
  }

  void _removeTask(int index) {
    // Не удаляем последнюю пустую задачу
    if (_tasks.length <= 1 ||
        (index == _tasks.length - 1 &&
            _tasks[index].mainController.text.isEmpty)) {
      return;
    }

    setState(() {
      _tasks.removeAt(index);
      _taskFocusNodes[index].dispose();
      _taskFocusNodes.removeAt(index);
      for (var node in _subtaskFocusNodes[index]) {
        node.dispose();
      }
      _subtaskFocusNodes.removeAt(index);
    });
  }

  void _addSubtask(int taskIndex, {bool focus = false}) {
    setState(() {
      _tasks[taskIndex].subtaskControllers.add(TextEditingController());
      _subtaskFocusNodes[taskIndex].add(FocusNode());

      if (focus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_subtaskFocusNodes[taskIndex].isNotEmpty) {
            _subtaskFocusNodes[taskIndex].last.requestFocus();
          }
        });
      }
    });
  }

  void _removeSubtask(int taskIndex, int subIndex) {
    setState(() {
      _tasks[taskIndex].subtaskControllers.removeAt(subIndex);
      _subtaskFocusNodes[taskIndex][subIndex].dispose();
      _subtaskFocusNodes[taskIndex].removeAt(subIndex);
    });
  }

  void _moveToNextTask(int currentIndex) {
    // Добавляем новую задачу если текущая последняя и не пустая
    if (currentIndex == _tasks.length - 1 &&
        _tasks[currentIndex].mainController.text.trim().isNotEmpty) {
      _addTask(focus: true);
    }
    // Или просто переходим к следующей существующей
    else if (currentIndex < _tasks.length - 1) {
      _taskFocusNodes[currentIndex + 1].requestFocus();
    }
  }

  Future<void> _saveTasks() async {
    // Фильтруем только заполненные задачи
    final validTasks = <TaskInput>[];
    for (final task in _tasks) {
      if (task.mainController.text.trim().isNotEmpty) {
        validTasks.add(task);
      }
    }

    if (validTasks.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    try {
      if (widget.taskToEdit != null) {
        final task = validTasks.first;
        final subtasks = <Subtask>[];
        for (final controller in task.subtaskControllers) {
          final text = controller.text.trim();
          if (text.isNotEmpty) {
            subtasks.add(Subtask(title: text));
          }
        }

        final updatedTask = DailyPlanItem(
          id: widget.taskToEdit!.id,
          userId: widget.taskToEdit!.userId,
          date: widget.date,
          title: task.mainController.text.trim(),
          subtasks: subtasks,
          isDone: widget.taskToEdit!.isDone,
          order: widget.taskToEdit!.order,
          createdAt: widget.taskToEdit!.createdAt,
          recurrenceId: widget.taskToEdit!.recurrenceId,
        );

        await _service.updateTask(updatedTask);
      } else {
        // Обрабатываем каждую задачу: новые создаем, существующие обновляем
        int newTaskOrder = _existingTasks.length;
        for (final taskInput in validTasks) {
          final subtasks = <Subtask>[];
          for (final controller in taskInput.subtaskControllers) {
            final text = controller.text.trim();
            if (text.isNotEmpty) {
              subtasks.add(Subtask(title: text));
            }
          }

          if (taskInput.isNew) {
            final title = taskInput.mainController.text.trim();
            if (taskInput.repeatsDaily) {
              await _service.createRecurringTask(
                startDate: widget.date,
                title: title,
                subtasks: subtasks,
              );
            } else {
              await _service.createTask(
                date: widget.date,
                title: title,
                subtasks: subtasks.isEmpty ? null : subtasks,
                order: newTaskOrder++,
              );
            }
          } else {
            // Обновляем существующую задачу
            final existingTask = _existingTasks.firstWhere(
              (t) => t.id == taskInput.id,
            );
            final updatedTask = DailyPlanItem(
              id: existingTask.id,
              userId: existingTask.userId,
              date: widget.date,
              title: taskInput.mainController.text.trim(),
              subtasks: subtasks,
              isDone: existingTask.isDone,
              order: existingTask.order,
              createdAt: existingTask.createdAt,
              recurrenceId: existingTask.recurrenceId,
            );
            await _service.updateTask(updatedTask);
          }
        }
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEditingSingleTask = widget.taskToEdit != null;
    final enteredTaskCount = _tasks
        .where((task) => task.mainController.text.trim().isNotEmpty)
        .length;
    final formattedDate =
        '${widget.date.day.toString().padLeft(2, '0')}.'
        '${widget.date.month.toString().padLeft(2, '0')}.${widget.date.year}';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          isEditingSingleTask ? 'Редактировать задачу' : 'Новые задачи',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.all(8),
            child: FilledButton(
              onPressed: _saveTasks,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                backgroundColor: colorScheme.primary,
              ),
              child: const Text(
                'Сохранить',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.14),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    Icons.calendar_today_rounded,
                    color: colorScheme.primary,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'План на день',
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isEditingSingleTask
                            ? formattedDate
                            : '$formattedDate · Enter — следующая задача',
                        style: TextStyle(
                          color: colorScheme.onSurface.withValues(alpha: 0.65),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isEditingSingleTask) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$enteredTaskCount',
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Список задач
          Expanded(
            child: _tasks.isEmpty
                ? Center(
                    child: CircularProgressIndicator(
                      color: colorScheme.primary,
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    itemCount: _tasks.length,
                    itemBuilder: (context, taskIndex) {
                      final task = _tasks[taskIndex];
                      return _buildTaskCard(task, taskIndex, colorScheme);
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: !isEditingSingleTask
          ? FloatingActionButton(
              backgroundColor: colorScheme.primary,
              foregroundColor: Colors.white,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              onPressed: () => _addTask(focus: true),
              tooltip: 'Добавить новую задачу',
              child: const Icon(Icons.add, size: 28),
            )
          : null,
    );
  }

  Widget _buildTaskCard(
    TaskInput task,
    int taskIndex,
    ColorScheme colorScheme,
  ) {
    final isSingleTask = _tasks.length == 1 && widget.taskToEdit != null;
    final isLastTask = taskIndex == _tasks.length - 1;
    final isEmptyTask = task.mainController.text.trim().isEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
        children: [
          // Заголовок карточки
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.55),
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      '${taskIndex + 1}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isEmptyTask ? 'Новая задача' : 'Задача ${taskIndex + 1}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                if (!isSingleTask && !isEmptyTask && _tasks.length > 1)
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      color: Colors.red.withValues(alpha: 0.7),
                      size: 20,
                    ),
                    onPressed: () => _removeTask(taskIndex),
                    tooltip: 'Удалить задачу',
                  ),
              ],
            ),
          ),

          // Поле основной задачи
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: task.mainController,
              focusNode: _taskFocusNodes[taskIndex],
              decoration: InputDecoration(
                hintText: 'Что нужно сделать?',
                hintStyle: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                prefixIcon: const Icon(Icons.edit_note_rounded),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.45,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: colorScheme.primary,
                    width: 1.5,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 15,
                ),
              ),
              style: TextStyle(fontSize: 16, color: colorScheme.onSurface),
              maxLines: 2,
              onChanged: (value) {
                setState(() {
                  if (value.trim().isNotEmpty && !task.showSubtasks) {
                    task.showSubtasks = true;
                  }
                });
              },
              // Только по Enter добавляем новую задачу
              textInputAction: isLastTask
                  ? TextInputAction.done
                  : TextInputAction.next,
              onSubmitted: (value) {
                if (value.trim().isNotEmpty) {
                  _moveToNextTask(taskIndex);
                }
              },
            ),
          ),

          if (task.isNew)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.secondary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.repeat_rounded,
                      color: colorScheme.secondary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Повторять каждый день',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Создавать задачу на новые даты',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: task.repeatsDaily,
                      onChanged: (value) {
                        setState(() => task.repeatsDaily = value);
                      },
                    ),
                  ],
                ),
              ),
            ),

          // Подзадачи
          if (task.showSubtasks || task.subtaskControllers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Заголовок подзадач
                  Row(
                    children: [
                      Icon(
                        Icons.list_alt_outlined,
                        color: colorScheme.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Подзадачи',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                      const Spacer(),
                      if (task.subtaskControllers.isNotEmpty)
                        Text(
                          '${task.subtaskControllers.length}',
                          style: TextStyle(
                            fontSize: 14,
                            color: colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Список подзадач
                  ...List.generate(
                    task.subtaskControllers.length,
                    (subIndex) => _buildSubtaskField(
                      task,
                      taskIndex,
                      subIndex,
                      colorScheme,
                    ),
                  ),

                  // Кнопка добавления подзадачи
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: Icon(Icons.add, color: colorScheme.primary, size: 18),
                    onPressed: () => _addSubtask(taskIndex, focus: true),
                    label: Text(
                      'Добавить подзадачу',
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(
                        color: colorScheme.primary.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSubtaskField(
    TaskInput task,
    int taskIndex,
    int subIndex,
    ColorScheme colorScheme,
  ) {
    final isLastSubtask = subIndex == task.subtaskControllers.length - 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: task.subtaskControllers[subIndex],
              focusNode: _subtaskFocusNodes[taskIndex].length > subIndex
                  ? _subtaskFocusNodes[taskIndex][subIndex]
                  : null,
              decoration: InputDecoration(
                hintText: 'Подзадача ${subIndex + 1}',
                hintStyle: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.45,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: colorScheme.primary,
                    width: 1.5,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
              textInputAction: isLastSubtask
                  ? TextInputAction.done
                  : TextInputAction.next,
              onSubmitted: (value) {
                if (value.trim().isNotEmpty && isLastSubtask) {
                  _addSubtask(taskIndex, focus: true);
                } else if (!isLastSubtask) {
                  _subtaskFocusNodes[taskIndex][subIndex + 1].requestFocus();
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              Icons.close,
              color: Colors.red.withValues(alpha: 0.7),
              size: 18,
            ),
            onPressed: () => _removeSubtask(taskIndex, subIndex),
          ),
        ],
      ),
    );
  }
}

class TaskInput {
  final TextEditingController mainController;
  final List<TextEditingController> subtaskControllers;
  bool showSubtasks;
  final String? id;
  final bool isNew;
  bool repeatsDaily;

  TaskInput({
    TextEditingController? mainController,
    List<TextEditingController>? subtaskControllers,
    this.id,
    this.isNew = true,
    this.repeatsDaily = false,
  }) : mainController = mainController ?? TextEditingController(),
       subtaskControllers = subtaskControllers ?? [],
       showSubtasks = false;

  factory TaskInput.fromTask(DailyPlanItem task) {
    final subControllers = task.subtasks
        .map((sub) => TextEditingController(text: sub.title))
        .toList();
    final input = TaskInput(
      mainController: TextEditingController(text: task.title),
      subtaskControllers: subControllers,
      id: task.id,
      isNew: false,
    );
    input.showSubtasks = subControllers.isNotEmpty;
    return input;
  }
}

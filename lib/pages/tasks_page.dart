import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/task_model.dart';
import '../models/employer_model.dart';
import '../services/firebase_service.dart';
import '../services/hotel_provider.dart';
import '../services/auth_provider.dart';
import '../utils/stayora_colors.dart';
import '../widgets/app_notification.dart';
import '../widgets/loading_empty_states.dart';

class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  final FirebaseService _firebaseService = FirebaseService();
  List<TaskModel> _tasks = [];
  List<EmployerModel> _employees = [];
  bool _loading = true;
  String? _error;
  String? _subscribedUserId;
  String? _subscribedHotelId;
  dynamic _tasksSubscription;

  /// Filter: 'all' | 'pending' | 'done'
  String _filterStatus = 'all';
  /// Optional assignee id to filter by employee
  String? _filterAssigneeId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final userId = AuthScopeData.of(context).uid;
    final hotelId = HotelProvider.of(context).hotelId;
    if (userId == null || hotelId == null) return;
    if (userId == _subscribedUserId && hotelId == _subscribedHotelId) return;
    _subscribedUserId = userId;
    _subscribedHotelId = hotelId;
    _tasksSubscription?.cancel();
    setState(() { _loading = true; _error = null; });
    _loadEmployees(userId, hotelId);
    _tasksSubscription = _firebaseService
        .tasksStream(userId, hotelId)
        .listen(
      (tasks) {
        if (mounted) setState(() { _tasks = tasks; _loading = false; _error = null; });
      },
      onError: (e) {
        if (mounted) setState(() { _loading = false; _error = e.toString(); });
      },
    );
  }

  Future<void> _loadEmployees(String userId, String hotelId) async {
    try {
      final list = await _firebaseService.getEmployers(userId, hotelId);
      if (mounted) setState(() => _employees = list);
    } catch (_) {
      if (mounted) setState(() => _employees = []);
    }
  }

  @override
  void dispose() {
    _tasksSubscription?.cancel();
    super.dispose();
  }

  List<TaskModel> get _filteredTasks {
    return _tasks.where((t) {
      if (_filterStatus == 'pending' && t.isCompleted) return false;
      if (_filterStatus == 'done' && !t.isCompleted) return false;
      if (_filterAssigneeId != null && t.assigneeId != _filterAssigneeId) return false;
      return true;
    }).toList();
  }

  String _assigneeName(String assigneeId) {
    if (assigneeId.isEmpty) return '—';
    try {
      return _employees.firstWhere((e) => e.id == assigneeId).name;
    } catch (_) {
      return '—';
    }
  }

  Future<void> _markComplete(TaskModel task) async {
    final userId = _subscribedUserId;
    final hotelId = _subscribedHotelId;
    if (userId == null || hotelId == null || task.id == null) return;
    try {
      if (task.recurrence == TaskModel.recurrenceOnce) {
        await _firebaseService.updateTask(
          userId,
          hotelId,
          task.copyWith(completedAt: DateTime.now()),
        );
      } else {
        await _firebaseService.updateTask(
          userId,
          hotelId,
          task.copyWith(dueDate: task.nextDueDate, completedAt: null),
        );
      }
      if (mounted) {
        showAppNotification(
          context,
          task.recurrence == TaskModel.recurrenceOnce
              ? 'Task completed'
              : 'Marked done; next due ${DateFormat('MMM d').format(task.nextDueDate)}',
          type: AppNotificationType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        showAppNotification(context, 'Failed to update: $e', type: AppNotificationType.error);
      }
    }
  }

  Future<void> _markIncomplete(TaskModel task) async {
    final userId = _subscribedUserId;
    final hotelId = _subscribedHotelId;
    if (userId == null || hotelId == null || task.id == null) return;
    try {
      await _firebaseService.updateTask(
        userId,
        hotelId,
        task.copyWith(completedAt: null),
      );
      if (mounted) showAppNotification(context, 'Marked as pending', type: AppNotificationType.success);
    } catch (e) {
      if (mounted) showAppNotification(context, 'Failed to update: $e', type: AppNotificationType.error);
    }
  }

  Future<void> _deleteTask(TaskModel task) async {
    final userId = _subscribedUserId;
    final hotelId = _subscribedHotelId;
    if (userId == null || hotelId == null || task.id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete task?'),
        content: Text(
          'Delete "${task.title}"? This cannot be undone.',
          style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: StayoraColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _firebaseService.deleteTask(userId, hotelId, task.id!);
      if (mounted) showAppNotification(context, 'Task deleted', type: AppNotificationType.success);
    } catch (e) {
      if (mounted) showAppNotification(context, 'Failed to delete: $e', type: AppNotificationType.error);
    }
  }

  Future<void> _openTaskSheet({TaskModel? existing}) async {
    final userId = AuthScopeData.of(context).uid;
    final hotelId = HotelProvider.of(context).hotelId;
    if (userId == null || hotelId == null) return;
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TaskEditSheet(
        task: existing,
        employees: _employees,
        onSave: (title, description, assigneeId, recurrence, dueDate) {
          Navigator.pop(ctx, {
            'title': title,
            'description': description,
            'assigneeId': assigneeId,
            'recurrence': recurrence,
            'dueDate': dueDate,
          });
        },
        onCancel: () => Navigator.pop(ctx),
      ),
    );
    if (result == null || !mounted) return;
    try {
      if (existing != null) {
        await _firebaseService.updateTask(
          userId,
          hotelId,
          existing.copyWith(
            title: result['title'] as String,
            description: result['description'] as String,
            assigneeId: result['assigneeId'] as String,
            recurrence: result['recurrence'] as String,
            dueDate: result['dueDate'] as DateTime,
          ),
        );
        showAppNotification(context, 'Task updated', type: AppNotificationType.success);
      } else {
        await _firebaseService.createTask(
          userId,
          hotelId,
          TaskModel(
            title: result['title'] as String,
            description: result['description'] as String,
            assigneeId: result['assigneeId'] as String,
            recurrence: result['recurrence'] as String,
            dueDate: result['dueDate'] as DateTime,
          ),
        );
        showAppNotification(context, 'Task added', type: AppNotificationType.success);
      }
    } catch (e) {
      if (mounted) showAppNotification(context, 'Failed to save: $e', type: AppNotificationType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            _subscribedUserId = null;
            _subscribedHotelId = null;
            didChangeDependencies();
          },
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Text(
                        'Tasks',
                        style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 34,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Assign and track tasks for employees',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          _FilterChip(
                            label: 'All',
                            isSelected: _filterStatus == 'all',
                            onTap: () => setState(() { _filterStatus = 'all'; _filterAssigneeId = null; }),
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: 'Pending',
                            isSelected: _filterStatus == 'pending',
                            onTap: () => setState(() { _filterStatus = 'pending'; _filterAssigneeId = null; }),
                            color: StayoraColors.warning,
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: 'Done',
                            isSelected: _filterStatus == 'done',
                            onTap: () => setState(() { _filterStatus = 'done'; _filterAssigneeId = null; }),
                            color: StayoraColors.success,
                          ),
                        ],
                      ),
                      if (_employees.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _FilterChip(
                                label: 'All staff',
                                isSelected: _filterAssigneeId == null,
                                onTap: () => setState(() => _filterAssigneeId = null),
                                color: colorScheme.secondary,
                              ),
                              ..._employees.map((e) {
                                final isSelected = _filterAssigneeId == e.id;
                                return Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: _FilterChip(
                                    label: e.name,
                                    isSelected: isSelected,
                                    onTap: () => setState(() => _filterAssigneeId = isSelected ? null : e.id),
                                    color: StayoraColors.blue,
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              if (_loading)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SkeletonListLoader(
                      itemCount: 5,
                      itemHeight: 88,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                )
              else if (_error != null)
                SliverFillRemaining(
                  child: ErrorStateWidget(
                    message: _error!,
                    onRetry: () {
                      _subscribedUserId = null;
                      _subscribedHotelId = null;
                      didChangeDependencies();
                    },
                  ),
                )
              else if (_filteredTasks.isEmpty)
                SliverFillRemaining(
                  child: EmptyStateWidget(
                    icon: Icons.task_alt_rounded,
                    title: _filterStatus != 'all' || _filterAssigneeId != null
                        ? 'No tasks match filter'
                        : 'No tasks yet',
                    subtitle: _filterStatus == 'all' && _filterAssigneeId == null
                        ? 'Tap + to add a task for an employee'
                        : 'Try changing the filter',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final task = _filteredTasks[index];
                        return _TaskCard(
                          task: task,
                          assigneeName: _assigneeName(task.assigneeId),
                          onTap: () => _openTaskSheet(existing: task),
                          onComplete: () => _markComplete(task),
                          onIncomplete: () => _markIncomplete(task),
                          onDelete: () => _deleteTask(task),
                        );
                      },
                      childCount: _filteredTasks.length,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openTaskSheet(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add task'),
        backgroundColor: StayoraColors.blue,
        foregroundColor: Colors.white,
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.color,
  });
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.15) : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : colorScheme.outline.withOpacity(0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? color : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.assigneeName,
    required this.onTap,
    required this.onComplete,
    required this.onIncomplete,
    required this.onDelete,
  });
  final TaskModel task;
  final String assigneeName;
  final VoidCallback onTap;
  final VoidCallback onComplete;
  final VoidCallback onIncomplete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDone = task.isCompleted;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Checkbox(
                value: isDone,
                onChanged: (_) => isDone ? onIncomplete() : onComplete(),
                activeColor: StayoraColors.success,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                        decoration: isDone ? TextDecoration.lineThrough : null,
                        decorationColor: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (task.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        task.description,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant,
                          decoration: isDone ? TextDecoration.lineThrough : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.person_outline_rounded, size: 14, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          assigneeName,
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(width: 12),
                        Icon(Icons.repeat_rounded, size: 14, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          TaskModel.recurrenceLabels[task.recurrence] ?? task.recurrence,
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          DateFormat('MMM d').format(task.dueDate),
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline_rounded, color: colorScheme.onSurfaceVariant),
                onPressed: onDelete,
                tooltip: 'Delete task',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskEditSheet extends StatefulWidget {
  const _TaskEditSheet({
    this.task,
    required this.employees,
    required this.onSave,
    required this.onCancel,
  });
  final TaskModel? task;
  final List<EmployerModel> employees;
  final void Function(String title, String description, String assigneeId, String recurrence, DateTime dueDate) onSave;
  final VoidCallback onCancel;

  @override
  State<_TaskEditSheet> createState() => _TaskEditSheetState();
}

class _TaskEditSheetState extends State<_TaskEditSheet> {
  late TextEditingController _titleController;
  late TextEditingController _descController;
  late String _assigneeId;
  late String _recurrence;
  late DateTime _dueDate;

  List<EmployerModel> get _validEmployees =>
      widget.employees.where((e) => e.id != null && e.id!.isNotEmpty).toList();

  String? get _firstEmployeeId =>
      _validEmployees.isNotEmpty ? _validEmployees.first.id! : null;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task?.title ?? '');
    _descController = TextEditingController(text: widget.task?.description ?? '');
    _assigneeId = widget.task?.assigneeId ?? _firstEmployeeId ?? '';
    _recurrence = widget.task?.recurrence ?? TaskModel.recurrenceOnce;
    _dueDate = widget.task?.dueDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                widget.task == null ? 'New task' : 'Edit task',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'Title',
                  hintText: 'e.g. Check minibar',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Description (optional)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 12),
              if (_validEmployees.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: StayoraColors.warning.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: StayoraColors.warning.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: StayoraColors.warning, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Add at least one employee in More → Employees before assigning tasks.',
                          style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
                        ),
                      ),
                    ],
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  value: _assigneeId.isNotEmpty ? _assigneeId : _firstEmployeeId,
                  decoration: InputDecoration(
                    labelText: 'Assign to',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest,
                  ),
                  items: _validEmployees
                      .map((e) => DropdownMenuItem(value: e.id!, child: Text(e.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _assigneeId = v ?? ''),
                ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _recurrence,
                decoration: InputDecoration(
                  labelText: 'Repeat',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest,
                ),
                items: TaskModel.recurrenceOptions
                    .map((r) => DropdownMenuItem(
                          value: r,
                          child: Text(TaskModel.recurrenceLabels[r] ?? r),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _recurrence = v ?? TaskModel.recurrenceOnce),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Due date'),
                subtitle: Text(DateFormat('EEEE, MMM d, yyyy').format(_dueDate)),
                trailing: const Icon(Icons.calendar_today_rounded),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _dueDate,
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                  );
                  if (date != null) setState(() => _dueDate = date);
                },
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: widget.onCancel,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _validEmployees.isEmpty
                          ? null
                          : () {
                              final title = _titleController.text.trim();
                              if (title.isEmpty) {
                                showAppNotification(context, 'Enter a title', type: AppNotificationType.error);
                                return;
                              }
                              final assignee = _assigneeId.isNotEmpty ? _assigneeId : _firstEmployeeId;
                              if (assignee == null || assignee.isEmpty) {
                                showAppNotification(context, 'Select an employee', type: AppNotificationType.error);
                                return;
                              }
                              widget.onSave(
                                title,
                                _descController.text.trim(),
                                assignee,
                                _recurrence,
                                _dueDate,
                              );
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: StayoraColors.blue,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(widget.task == null ? 'Add task' : 'Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

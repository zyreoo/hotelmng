/// A task assigned to an employee. Can be one-off or recurring (daily, weekly, monthly).
class TaskModel {
  final String? id;
  final String title;
  final String description;
  /// Firestore document ID of the assigned employee (employers collection).
  final String assigneeId;
  /// daily | weekly | monthly | once
  final String recurrence;
  /// When this occurrence is due. For recurring tasks, advanced when marked complete.
  final DateTime dueDate;
  /// When the task was completed (null = pending).
  final DateTime? completedAt;
  final DateTime createdAt;

  static const String recurrenceDaily = 'daily';
  static const String recurrenceWeekly = 'weekly';
  static const String recurrenceMonthly = 'monthly';
  static const String recurrenceOnce = 'once';

  static const List<String> recurrenceOptions = [
    recurrenceOnce,
    recurrenceDaily,
    recurrenceWeekly,
    recurrenceMonthly,
  ];

  static const Map<String, String> recurrenceLabels = {
    recurrenceOnce: 'Once',
    recurrenceDaily: 'Daily',
    recurrenceWeekly: 'Weekly',
    recurrenceMonthly: 'Monthly',
  };

  TaskModel({
    this.id,
    required this.title,
    this.description = '',
    required this.assigneeId,
    required this.recurrence,
    required this.dueDate,
    this.completedAt,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isCompleted => completedAt != null;
  bool get isRecurring => recurrence != recurrenceOnce;

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'description': description,
      'assigneeId': assigneeId,
      'recurrence': recurrence,
      'dueDate': dueDate.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory TaskModel.fromFirestore(Map<String, dynamic> data, String id) {
    return TaskModel(
      id: id,
      title: data['title']?.toString() ?? '',
      description: data['description']?.toString() ?? '',
      assigneeId: data['assigneeId']?.toString() ?? '',
      recurrence: data['recurrence']?.toString() ?? recurrenceOnce,
      dueDate: data['dueDate'] != null
          ? DateTime.parse(data['dueDate'] as String)
          : DateTime.now(),
      completedAt: data['completedAt'] != null
          ? DateTime.parse(data['completedAt'] as String)
          : null,
      createdAt: data['createdAt'] != null
          ? DateTime.parse(data['createdAt'] as String)
          : DateTime.now(),
    );
  }

  TaskModel copyWith({
    String? id,
    String? title,
    String? description,
    String? assigneeId,
    String? recurrence,
    DateTime? dueDate,
    DateTime? completedAt,
    DateTime? createdAt,
  }) {
    return TaskModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      assigneeId: assigneeId ?? this.assigneeId,
      recurrence: recurrence ?? this.recurrence,
      dueDate: dueDate ?? this.dueDate,
      completedAt: completedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Next due date after completing this occurrence (for recurring tasks).
  DateTime get nextDueDate {
    switch (recurrence) {
      case recurrenceDaily:
        return DateTime(dueDate.year, dueDate.month, dueDate.day + 1);
      case recurrenceWeekly:
        return DateTime(dueDate.year, dueDate.month, dueDate.day + 7);
      case recurrenceMonthly:
        return DateTime(dueDate.year, dueDate.month + 1, dueDate.day);
      default:
        return dueDate;
    }
  }
}

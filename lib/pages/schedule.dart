import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/employer_model.dart';

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  static const double _headerHeight = 50.0;
  static const double _employeeLabelWidth = 150.0;

  final double _dayColumnWidth = 120.0;
  final double _employeeRowHeight = 50.0;

  // Days of the week
  final List<String> _daysOfWeek = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  // Real-time Firestore synchronization
  StreamSubscription<QuerySnapshot>? _employeesSubscription;
  Timer? _debounceTimer;
  static const Duration _debounceDuration = Duration(milliseconds: 100);

  // Employees loaded from Firestore
  List<EmployerModel> _employees = [];

  // Schedule: Map of employee ID -> Map of day -> shift info
  // Key: employeeId, Value: Map<dayOfWeek (0-6), ShiftInfo>
  final Map<String, Map<int, ShiftInfo>> _schedule = {};

  /// Full shift models by document ID
  final Map<String, ShiftModel> _shiftModelsById = {};

  // Selection state for drag-and-drop shift assignment
  bool _isSelecting = false;
  String? _selectionStartEmployee;
  int? _selectionStartDay;
  String? _selectionEndEmployee;
  int? _selectionEndDay;

  final GlobalKey _gridKey = GlobalKey();
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _employeeHeadersScrollController = ScrollController();
  final ScrollController _stickyDayLabelsScrollController = ScrollController();

  // Current week offset (0 = current week, 1 = next week, -1 = previous week)
  int _weekOffset = 0;
  DateTime get _currentWeekStart {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return DateTime(monday.year, monday.month, monday.day)
        .add(Duration(days: 7 * _weekOffset));
  }

  Future<void> _deleteShift(String shiftId) async {
    await FirebaseFirestore.instance
        .collection('shifts')
        .doc(shiftId)
        .delete();
  }

  Future<void> _updateShift(ShiftModel shift) async {
    if (shift.id == null || shift.id!.isEmpty) return;
    await FirebaseFirestore.instance
        .collection('shifts')
        .doc(shift.id)
        .update(shift.toFirestore());
  }

  @override
  void initState() {
    super.initState();

    // Sync employee headers scroll with horizontal scroll
    _horizontalScrollController.addListener(() {
      if (_employeeHeadersScrollController.hasClients &&
          _horizontalScrollController.hasClients) {
        final mainOffset = _horizontalScrollController.offset;
        final headerOffset = _employeeHeadersScrollController.offset;
        if ((mainOffset - headerOffset).abs() > 0.1) {
          _employeeHeadersScrollController.jumpTo(mainOffset);
        }
      }
    });

    // Sync sticky day labels scroll with main vertical scroll
    _verticalScrollController.addListener(() {
      if (_stickyDayLabelsScrollController.hasClients &&
          _verticalScrollController.hasClients) {
        final mainOffset = _verticalScrollController.offset;
        final stickyOffset = _stickyDayLabelsScrollController.offset;
        if ((mainOffset - stickyOffset).abs() > 0.1) {
          _stickyDayLabelsScrollController.jumpTo(mainOffset);
        }
      }
    });

    _subscribeToEmployees();
    _subscribeToShifts();
  }

  @override
  void dispose() {
    _employeesSubscription?.cancel();
    _debounceTimer?.cancel();
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    _employeeHeadersScrollController.dispose();
    _stickyDayLabelsScrollController.dispose();
    super.dispose();
  }

  void _subscribeToEmployees() {
    _employeesSubscription = FirebaseFirestore.instance
        .collection('employers')
        .where('status', isEqualTo: 'Active')
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _employees = snapshot.docs
            .map((doc) => EmployerModel.fromFirestore(doc.data(), doc.id))
            .toList();
      });
    });
  }

  void _subscribeToShifts() {
    final weekStart = _currentWeekStart;
    final weekEnd = weekStart.add(const Duration(days: 7));

    FirebaseFirestore.instance
        .collection('shifts')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart))
        .where('date', isLessThan: Timestamp.fromDate(weekEnd))
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      _processShiftChanges(snapshot.docs);
    });
  }

  void _processShiftChanges(List<QueryDocumentSnapshot> docs) {
    _schedule.clear();
    _shiftModelsById.clear();

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final shift = ShiftModel.fromFirestore(data, doc.id);
      _shiftModelsById[doc.id] = shift;

      final employeeId = shift.employeeId;
      final date = shift.date;
      final dayOfWeek = date.weekday - 1; // 0 = Monday, 6 = Sunday

      _schedule.putIfAbsent(employeeId, () => {});
      _schedule[employeeId]![dayOfWeek] = ShiftInfo(
        shiftId: doc.id,
        startTime: shift.startTime,
        endTime: shift.endTime,
        role: shift.role,
      );
    }

    _debouncedSetState();
  }

  void _debouncedSetState() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () {
      if (mounted) {
        setState(() {});
      }
    });
  }

  ShiftInfo? _getShift(String employeeId, int dayOfWeek) {
    return _schedule[employeeId]?[dayOfWeek];
  }

  bool _isCellSelected(String employeeId, int dayOfWeek) {
    if (!_isSelecting ||
        _selectionStartEmployee == null ||
        _selectionStartDay == null) {
      return false;
    }

    final startEmpIndex = _employees
        .indexWhere((e) => e.id == _selectionStartEmployee);
    final endEmpIndex = _selectionEndEmployee != null
        ? _employees.indexWhere((e) => e.id == _selectionEndEmployee)
        : startEmpIndex;
    final currentEmpIndex = _employees.indexWhere((e) => e.id == employeeId);

    final minEmpIndex = startEmpIndex < endEmpIndex ? startEmpIndex : endEmpIndex;
    final maxEmpIndex = startEmpIndex > endEmpIndex ? startEmpIndex : endEmpIndex;

    final startDay = _selectionStartDay!;
    final endDay = _selectionEndDay ?? startDay;
    final minDay = startDay < endDay ? startDay : endDay;
    final maxDay = startDay > endDay ? startDay : endDay;

    final empInRange =
        currentEmpIndex >= minEmpIndex && currentEmpIndex <= maxEmpIndex;
    final dayInRange = dayOfWeek >= minDay && dayOfWeek <= maxDay;

    return empInRange && dayInRange;
  }

  void _startSelection(String employeeId, int dayOfWeek) {
    setState(() {
      _isSelecting = true;
      _selectionStartEmployee = employeeId;
      _selectionStartDay = dayOfWeek;
      _selectionEndEmployee = employeeId;
      _selectionEndDay = dayOfWeek;
    });
  }

  void _updateSelection(String employeeId, int dayOfWeek) {
    if (_isSelecting) {
      setState(() {
        _selectionEndEmployee = employeeId;
        _selectionEndDay = dayOfWeek;
      });
    }
  }

  void _endSelection() {
    if (_isSelecting &&
        _selectionStartEmployee != null &&
        _selectionStartDay != null) {
      final selectedEmployees = _getSelectedEmployees();
      final selectedDays = _getSelectedDays();

      if (selectedEmployees.isNotEmpty && selectedDays.isNotEmpty) {
        _showShiftDialog(selectedEmployees, selectedDays);
      }

      setState(() {
        _isSelecting = false;
        _selectionStartEmployee = null;
        _selectionStartDay = null;
        _selectionEndEmployee = null;
        _selectionEndDay = null;
      });
    }
  }

  List<String> _getSelectedEmployees() {
    if (_selectionStartEmployee == null) return [];

    final startIndex = _employees
        .indexWhere((e) => e.id == _selectionStartEmployee);
    final endIndex = _selectionEndEmployee != null
        ? _employees.indexWhere((e) => e.id == _selectionEndEmployee)
        : startIndex;

    if (startIndex == -1) return [];

    final minIndex = startIndex < endIndex ? startIndex : endIndex;
    final maxIndex = startIndex > endIndex ? startIndex : endIndex;

    return _employees
        .sublist(minIndex, maxIndex + 1)
        .map((e) => e.id ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
  }

  List<int> _getSelectedDays() {
    if (_selectionStartDay == null) return [];

    final startDay = _selectionStartDay!;
    final endDay = _selectionEndDay ?? startDay;
    final minDay = startDay < endDay ? startDay : endDay;
    final maxDay = startDay > endDay ? startDay : endDay;

    return List.generate(maxDay - minDay + 1, (i) => minDay + i);
  }

  Map<String, dynamic>? _getCellFromPosition(Offset position) {
    final employeeIndex =
        (position.dy / _employeeRowHeight).floor();
    final dayIndex = (position.dx / _dayColumnWidth).floor();

    if (employeeIndex >= 0 &&
        employeeIndex < _employees.length &&
        dayIndex >= 0 &&
        dayIndex < 7) {
      return {
        'employeeId': _employees[employeeIndex].id,
        'dayOfWeek': dayIndex,
      };
    }
    return null;
  }

  void _showShiftDialog(List<String> employeeIds, List<int> days) {
    TimeOfDay startTime = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay endTime = const TimeOfDay(hour: 17, minute: 0);
    String role = 'Regular Shift';

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 340),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: StatefulBuilder(
            builder: (context, setModalState) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 24),
                Text(
                  'Add Shift',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 20,
                        color: Colors.black,
                      ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      // Start Time
                      InkWell(
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: startTime,
                          );
                          if (picked != null) {
                            setModalState(() => startTime = picked);
                          }
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.access_time_rounded,
                                size: 20,
                                color: Colors.grey.shade600,
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Start Time',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black87,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                startTime.format(context),
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 22,
                                color: Colors.grey.shade400,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // End Time
                      InkWell(
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: endTime,
                          );
                          if (picked != null) {
                            setModalState(() => endTime = picked);
                          }
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.access_time_filled_rounded,
                                size: 20,
                                color: Colors.grey.shade600,
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'End Time',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black87,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                endTime.format(context),
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 22,
                                color: Colors.grey.shade400,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Role
                      TextFormField(
                        initialValue: role,
                        decoration: InputDecoration(
                          labelText: 'Role',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onChanged: (value) => role = value,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await _createShifts(
                              employeeIds,
                              days,
                              startTime,
                              endTime,
                              role,
                            );
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF34C759),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                          child: const Text('Create Shifts'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF007AFF),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _createShifts(
    List<String> employeeIds,
    List<int> days,
    TimeOfDay startTime,
    TimeOfDay endTime,
    String role,
  ) async {
    final batch = FirebaseFirestore.instance.batch();

    for (final employeeId in employeeIds) {
      for (final day in days) {
        final date = _currentWeekStart.add(Duration(days: day));
        final shift = ShiftModel(
          employeeId: employeeId,
          date: date,
          startTime: '${startTime.hour}:${startTime.minute.toString().padLeft(2, '0')}',
          endTime: '${endTime.hour}:${endTime.minute.toString().padLeft(2, '0')}',
          role: role,
        );

        final docRef =
            FirebaseFirestore.instance.collection('shifts').doc();
        batch.set(docRef, shift.toFirestore());
      }
    }

    try {
      await batch.commit();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Shifts created successfully'),
          backgroundColor: Color(0xFF34C759),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error creating shifts: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showShiftDetails(BuildContext context, String employeeId,
      int dayOfWeek, ShiftInfo shift) {
    final employee = _employees.firstWhere((e) => e.id == employeeId);
    final shiftModel = _shiftModelsById[shift.shiftId];
    if (shiftModel == null) return;

    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 340),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 24),
              Text(
                'Shift Details',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 20,
                      color: Colors.black,
                    ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _buildDetailRow(
                      Icons.person_rounded,
                      'Employee',
                      employee.name,
                    ),
                    const SizedBox(height: 12),
                    _buildDetailRow(
                      Icons.calendar_today_rounded,
                      'Day',
                      _daysOfWeek[dayOfWeek],
                    ),
                    const SizedBox(height: 12),
                    _buildDetailRow(
                      Icons.access_time_rounded,
                      'Time',
                      '${shift.startTime} - ${shift.endTime}',
                    ),
                    const SizedBox(height: 12),
                    _buildDetailRow(
                      Icons.work_outline_rounded,
                      'Role',
                      shift.role,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final confirm = await _showDeleteConfirmation(dialogContext);
                          if (confirm != true) return;
                          Navigator.pop(dialogContext);
                          await _deleteShift(shift.shiftId);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Shift deleted'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        },
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        label: const Text('Delete Shift'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF007AFF),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('Close'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF007AFF).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: const Color(0xFF007AFF)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showDeleteConfirmation(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_rounded,
                  color: Colors.red,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Delete Shift?',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 17,
                      color: Colors.black,
                    ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'This will permanently delete the shift. This action cannot be undone.',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                        child: const Text('Delete'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF007AFF),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmployeeRow(EmployerModel employee) {
    final employeeId = employee.id ?? '';
    return SizedBox(
      height: _employeeRowHeight,
      child: Row(
        children: List.generate(7, (dayIndex) {
          final shift = _getShift(employeeId, dayIndex);
          final isSelected = _isCellSelected(employeeId, dayIndex);

          return GestureDetector(
            onTap: shift != null
                ? () => _showShiftDetails(context, employeeId, dayIndex, shift)
                : null,
            child: Container(
              width: _dayColumnWidth,
              height: _employeeRowHeight,
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF007AFF).withOpacity(0.2)
                    : shift != null
                        ? const Color(0xFF34C759).withOpacity(0.15)
                        : Colors.white,
                border: Border.all(
                  color: Colors.grey.shade300,
                  width: 0.5,
                ),
              ),
              child: shift != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${shift.startTime} - ${shift.endTime}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF34C759),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            shift.role,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    )
                  : null,
            ),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Text(
                        'Schedule',
                        style: Theme.of(context)
                            .textTheme
                            .headlineLarge
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 34,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left_rounded),
                            onPressed: () {
                              setState(() {
                                _weekOffset--;
                                _subscribeToShifts();
                              });
                            },
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF007AFF),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Week of ${DateFormat('MMM d, yyyy').format(_currentWeekStart)}',
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(color: Colors.grey.shade600),
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            icon: const Icon(Icons.chevron_right_rounded),
                            onPressed: () {
                              setState(() {
                                _weekOffset++;
                                _subscribeToShifts();
                              });
                            },
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF007AFF),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF007AFF).withOpacity(0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.today_rounded),
                      onPressed: () {
                        setState(() {
                          _weekOffset = 0;
                          _subscribeToShifts();
                        });
                      },
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF007AFF),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Schedule Grid
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    children: [
                      // Main scrollable grid
                      Positioned.fill(
                        child: Padding(
                          padding: EdgeInsets.only(top: _headerHeight),
                          child: GestureDetector(
                            key: _gridKey,
                            onPanStart: (details) {
                              final cell =
                                  _getCellFromPosition(details.localPosition);
                              if (cell != null) {
                                final shift = _getShift(
                                  cell['employeeId']!,
                                  cell['dayOfWeek']!,
                                );
                                if (shift == null) {
                                  _startSelection(
                                    cell['employeeId']!,
                                    cell['dayOfWeek']!,
                                  );
                                }
                              }
                            },
                            onPanUpdate: (details) {
                              if (_isSelecting) {
                                final cell = _getCellFromPosition(
                                  details.localPosition,
                                );
                                if (cell != null) {
                                  _updateSelection(
                                    cell['employeeId']!,
                                    cell['dayOfWeek']!,
                                  );
                                }
                              }
                            },
                            onPanEnd: (details) {
                              if (_isSelecting) {
                                _endSelection();
                              }
                            },
                            onPanCancel: () {
                              if (_isSelecting) {
                                setState(() {
                                  _isSelecting = false;
                                  _selectionStartEmployee = null;
                                  _selectionStartDay = null;
                                  _selectionEndEmployee = null;
                                  _selectionEndDay = null;
                                });
                              }
                            },
                            child: SingleChildScrollView(
                              controller: _verticalScrollController,
                              scrollDirection: Axis.vertical,
                              padding: EdgeInsets.zero,
                              child: SingleChildScrollView(
                                controller: _horizontalScrollController,
                                scrollDirection: Axis.horizontal,
                                padding: EdgeInsets.zero,
                                child: Column(
                                  children: _employees
                                      .map((employee) =>
                                          _buildEmployeeRow(employee))
                                      .toList(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Sticky day headers at the top
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: _headerHeight,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF9F9F9),
                            border: Border(
                              bottom: BorderSide(
                                color: Colors.grey.shade300,
                                width: 1,
                              ),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              // Empty corner cell (fixed)
                              Container(
                                width: _employeeLabelWidth,
                                height: _headerHeight,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFEFF4),
                                  border: Border(
                                    right: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                ),
                                child: Center(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.people_rounded,
                                        size: 14,
                                        color: Color(0xFF007AFF),
                                      ),
                                      const SizedBox(width: 4),
                                      const Text(
                                        'Employees',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                          color: Color(0xFF007AFF),
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // Day headers (scrollable horizontally)
                              Expanded(
                                child: SingleChildScrollView(
                                  controller: _employeeHeadersScrollController,
                                  scrollDirection: Axis.horizontal,
                                  physics: const NeverScrollableScrollPhysics(),
                                  child: Row(
                                    children: _daysOfWeek.map((day) {
                                      return Container(
                                        width: _dayColumnWidth,
                                        height: 50,
                                        decoration: BoxDecoration(
                                          border: Border(
                                            right: BorderSide(
                                              color: Colors.white,
                                              width: 1,
                                            ),
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            day,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                              color: Colors.black87,
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Sticky employee labels on the left
                      Positioned(
                        top: _headerHeight,
                        left: 0,
                        bottom: 0,
                        width: _employeeLabelWidth,
                        child: Container(
                          color: Colors.white,
                          child: SingleChildScrollView(
                            controller: _stickyDayLabelsScrollController,
                            physics: const NeverScrollableScrollPhysics(),
                            child: Column(
                              children: _employees.map((employee) {
                                return Container(
                                  width: _employeeLabelWidth,
                                  height: _employeeRowHeight,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF9F9F9),
                                    border: Border(
                                      bottom: BorderSide(
                                        color: Colors.grey.shade300,
                                        width: 0.5,
                                      ),
                                      right: BorderSide(
                                        color: Colors.grey.shade300,
                                        width: 1,
                                      ),
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          employee.name,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black87,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          employee.role,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class ShiftInfo {
  final String shiftId;
  final String startTime;
  final String endTime;
  final String role;

  ShiftInfo({
    required this.shiftId,
    required this.startTime,
    required this.endTime,
    required this.role,
  });
}

class ShiftModel {
  final String? id;
  final String employeeId;
  final DateTime date;
  final String startTime;
  final String endTime;
  final String role;

  ShiftModel({
    this.id,
    required this.employeeId,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.role,
  });

  factory ShiftModel.fromFirestore(Map<String, dynamic> data, String id) {
    return ShiftModel(
      id: id,
      employeeId: data['employeeId'] ?? '',
      date: (data['date'] as Timestamp).toDate(),
      startTime: data['startTime'] ?? '',
      endTime: data['endTime'] ?? '',
      role: data['role'] ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'employeeId': employeeId,
      'date': Timestamp.fromDate(date),
      'startTime': startTime,
      'endTime': endTime,
      'role': role,
    };
  }
}

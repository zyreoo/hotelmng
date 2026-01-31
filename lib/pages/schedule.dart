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
  /// Header needs two lines: weekday name + date
  static const double _headerHeight = 56.0;
  double get _employeeLabelWidth => MediaQuery.of(context).size.width >= 768 ? 150.0 : 100.0;
  double get _dayColumnWidth => MediaQuery.of(context).size.width >= 768 ? 120.0 : 80.0;
  double get _employeeRowHeight => MediaQuery.of(context).size.width >= 768 ? 50.0 : 45.0;

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

  /// Dates for the current week (Mon..Sun), same order as _daysOfWeek.
  List<DateTime> get _currentWeekDates => List.generate(
    7,
    (i) => _currentWeekStart.add(Duration(days: i)),
  );

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
    // Grid has left padding of _employeeLabelWidth so day columns align with header
    final dayColumnX = position.dx - _employeeLabelWidth;
    if (dayColumnX < 0) return null;

    final employeeIndex = (position.dy / _employeeRowHeight).floor();
    final dayIndex = (dayColumnX / _dayColumnWidth).floor();

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

  Future<List<ShiftPreset>> _loadShiftPresets() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('shift_presets')
          .get();
      final fromFirestore = snapshot.docs.map((doc) {
        final d = doc.data();
        return ShiftPreset(
          id: doc.id,
          name: d['name'] ?? '',
          startTime: d['startTime'] ?? '09:00',
          endTime: d['endTime'] ?? '17:00',
          role: d['role'] ?? 'Regular Shift',
        );
      }).toList();
      fromFirestore.sort((a, b) => a.name.compareTo(b.name));
      return fromFirestore;
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveShiftPreset(ShiftPreset preset) async {
    await FirebaseFirestore.instance.collection('shift_presets').add({
      'name': preset.name,
      'startTime': preset.startTime,
      'endTime': preset.endTime,
      'role': preset.role,
    });
  }

  Future<void> _updateShiftPreset(ShiftPreset preset) async {
    if (preset.id == null || preset.id!.isEmpty) return;
    await FirebaseFirestore.instance.collection('shift_presets').doc(preset.id).update({
      'name': preset.name,
      'startTime': preset.startTime,
      'endTime': preset.endTime,
      'role': preset.role,
    });
  }

  Future<void> _deleteShiftPreset(String presetId) async {
    await FirebaseFirestore.instance.collection('shift_presets').doc(presetId).delete();
  }

  void _showShiftDialog(List<String> employeeIds, List<int> days) {
    showDialog(
      context: context,
      builder: (ctx) => _AddShiftDialog(
        employeeIds: employeeIds,
        days: days,
        loadPresets: _loadShiftPresets,
        savePreset: _saveShiftPreset,
        updatePreset: _updateShiftPreset,
        deletePreset: _deleteShiftPreset,
        isValidTime: _isValidTimeString,
        normalizeTime: _normalizeTimeString,
        onCreateShifts: _createShifts,
      ),
    );
  }

  /// Validates time string in HH:mm or H:mm format (24h).
  bool _isValidTimeString(String s) {
    final parts = s.split(':');
    if (parts.length != 2) return false;
    final h = int.tryParse(parts[0].trim());
    final m = int.tryParse(parts[1].trim());
    if (h == null || m == null) return false;
    return h >= 0 && h <= 23 && m >= 0 && m <= 59;
  }

  /// Normalizes time string to HH:mm.
  String _normalizeTimeString(String s) {
    final parts = s.split(':');
    if (parts.length != 2) return s;
    final h = int.tryParse(parts[0].trim());
    final m = int.tryParse(parts[1].trim());
    if (h == null || m == null) return s;
    return '${h.clamp(0, 23).toString().padLeft(2, '0')}:${m.clamp(0, 59).toString().padLeft(2, '0')}';
  }

  Future<void> _createShifts(
    List<String> employeeIds,
    List<int> days,
    String startTimeStr,
    String endTimeStr,
    String role,
  ) async {
    final startTime = _normalizeTimeString(startTimeStr);
    final endTime = _normalizeTimeString(endTimeStr);
    final batch = FirebaseFirestore.instance.batch();

    for (final employeeId in employeeIds) {
      for (final day in days) {
        final date = _currentWeekStart.add(Duration(days: day));
        final shift = ShiftModel(
          employeeId: employeeId,
          date: date,
          startTime: startTime,
          endTime: endTime,
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
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Left spacer so grid columns align with day headers
                                    SizedBox(width: _employeeLabelWidth),
                                    Column(
                                      children: _employees
                                          .map((employee) =>
                                              _buildEmployeeRow(employee))
                                          .toList(),
                                    ),
                                  ],
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
                              // Day headers (scrollable horizontally) – weekday + date
                              Expanded(
                                child: SingleChildScrollView(
                                  controller: _employeeHeadersScrollController,
                                  scrollDirection: Axis.horizontal,
                                  physics: const NeverScrollableScrollPhysics(),
                                  child: Row(
                                    children: List.generate(7, (i) {
                                      final dayName = _daysOfWeek[i];
                                      final date = _currentWeekDates[i];
                                      return Container(
                                        width: _dayColumnWidth,
                                        height: _headerHeight,
                                        decoration: BoxDecoration(
                                          border: Border(
                                            right: BorderSide(
                                              color: Colors.grey.shade200,
                                              width: 1,
                                            ),
                                          ),
                                        ),
                                        child: Center(
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                dayName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 12,
                                                  color: Colors.black87,
                                                  letterSpacing: 0.2,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                DateFormat('MMM d').format(date),
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey.shade600,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }),
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

/// Preset for quick shift selection (Morning, Night shift, Midnight, or custom saved).
class ShiftPreset {
  final String? id;
  final String name;
  final String startTime;
  final String endTime;
  final String role;

  ShiftPreset({
    this.id,
    required this.name,
    required this.startTime,
    required this.endTime,
    required this.role,
  });
}

/// Apple-style dialog: preset name only (Save as preset).
class _PresetNameDialog extends StatefulWidget {
  final String title;
  final String hint;
  final String submitLabel;

  const _PresetNameDialog({
    required this.title,
    required this.hint,
    required this.submitLabel,
  });

  @override
  State<_PresetNameDialog> createState() => _PresetNameDialogState();
}

class _PresetNameDialogState extends State<_PresetNameDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 28),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextFormField(
                  controller: _controller,
                  decoration: InputDecoration(
                    labelText: 'Preset name',
                    hintText: widget.hint,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                  onFieldSubmitted: (v) {
                    if (_formKey.currentState!.validate()) {
                      Navigator.pop(context, v.trim());
                    }
                  },
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            if (_formKey.currentState!.validate()) {
                              Navigator.pop(context, _controller.text.trim());
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF34C759),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Text(
                                widget.submitLabel,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => Navigator.pop(context),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: const Center(
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF007AFF),
                                ),
                              ),
                            ),
                          ),
                        ),
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
}

/// Apple-style dialog: edit preset (name, start, end, role) with Save, Delete, Cancel.
class _EditPresetDialog extends StatefulWidget {
  final ShiftPreset preset;
  final bool Function(String) isValidTime;
  final String Function(String) normalizeTime;
  final Future<void> Function() onDelete;

  const _EditPresetDialog({
    required this.preset,
    required this.isValidTime,
    required this.normalizeTime,
    required this.onDelete,
  });

  @override
  State<_EditPresetDialog> createState() => _EditPresetDialogState();
}

class _EditPresetDialogState extends State<_EditPresetDialog> {
  late TextEditingController _nameController;
  late TextEditingController _startController;
  late TextEditingController _endController;
  late TextEditingController _roleController;
  final _formKey = GlobalKey<FormState>();
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.preset.name);
    _startController = TextEditingController(text: widget.preset.startTime);
    _endController = TextEditingController(text: widget.preset.endTime);
    _roleController = TextEditingController(text: widget.preset.role);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _startController.dispose();
    _endController.dispose();
    _roleController.dispose();
    super.dispose();
  }

  Future<void> _handleDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
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
                'Delete Preset?',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'This preset will be removed. This action cannot be undone.',
                  style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
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
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => Navigator.pop(ctx, true),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF3B30),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Center(
                              child: Text(
                                'Delete',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => Navigator.pop(ctx, false),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: const Center(
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF007AFF),
                                ),
                              ),
                            ),
                          ),
                        ),
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
    if (confirm != true || !mounted) return;
    setState(() => _deleting = true);
    await widget.onDelete();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 28),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'Edit Preset',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: 'Preset name',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _startController,
                        decoration: InputDecoration(
                          labelText: 'Start time',
                          hintText: 'e.g. 09:00',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Enter start time';
                          if (!widget.isValidTime(v.trim())) return 'Use HH:mm';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _endController,
                        decoration: InputDecoration(
                          labelText: 'End time',
                          hintText: 'e.g. 17:00',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Enter end time';
                          if (!widget.isValidTime(v.trim())) return 'Use HH:mm';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _roleController,
                        decoration: InputDecoration(
                          labelText: 'Role',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
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
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _deleting
                                ? null
                                : () async {
                                    if (!_formKey.currentState!.validate()) return;
                                    final updated = ShiftPreset(
                                      id: widget.preset.id,
                                      name: _nameController.text.trim(),
                                      startTime: widget.normalizeTime(
                                          _startController.text.trim()),
                                      endTime: widget.normalizeTime(
                                          _endController.text.trim()),
                                      role: _roleController.text.trim().isEmpty
                                          ? 'Regular Shift'
                                          : _roleController.text.trim(),
                                    );
                                    Navigator.pop(context, updated);
                                  },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF34C759),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Center(
                                child: Text(
                                  'Save',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _deleting ? null : _handleDelete,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFFF3B30)),
                              ),
                              child: const Center(
                                child: Text(
                                  'Delete Preset',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFFF3B30),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.pop(context),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: const Center(
                                child: Text(
                                  'Cancel',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF007AFF),
                                  ),
                                ),
                              ),
                            ),
                          ),
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
}

/// Add Shift dialog: choose preset or custom times, optionally save as preset.
class _AddShiftDialog extends StatefulWidget {
  final List<String> employeeIds;
  final List<int> days;
  final Future<List<ShiftPreset>> Function() loadPresets;
  final Future<void> Function(ShiftPreset) savePreset;
  final Future<void> Function(ShiftPreset) updatePreset;
  final Future<void> Function(String presetId) deletePreset;
  final bool Function(String) isValidTime;
  final String Function(String) normalizeTime;
  final Future<void> Function(
    List<String> employeeIds,
    List<int> days,
    String startTime,
    String endTime,
    String role,
  ) onCreateShifts;

  const _AddShiftDialog({
    required this.employeeIds,
    required this.days,
    required this.loadPresets,
    required this.savePreset,
    required this.updatePreset,
    required this.deletePreset,
    required this.isValidTime,
    required this.normalizeTime,
    required this.onCreateShifts,
  });

  @override
  State<_AddShiftDialog> createState() => _AddShiftDialogState();
}

class _AddShiftDialogState extends State<_AddShiftDialog> {
  late TextEditingController _startController;
  late TextEditingController _endController;
  late TextEditingController _roleController;
  final _formKey = GlobalKey<FormState>();
  List<ShiftPreset> _presets = [];
  bool _presetsLoading = true;
  ShiftPreset? _selectedPreset;

  @override
  void initState() {
    super.initState();
    _startController = TextEditingController(text: '09:00');
    _endController = TextEditingController(text: '17:00');
    _roleController = TextEditingController(text: 'Regular Shift');
    _loadPresets();
  }

  Future<void> _loadPresets() async {
    final list = await widget.loadPresets();
    if (mounted) setState(() {
      _presets = list;
      _presetsLoading = false;
    });
  }

  void _applyPreset(ShiftPreset preset) {
    setState(() {
      _selectedPreset = preset;
      _startController.text = preset.startTime;
      _endController.text = preset.endTime;
      _roleController.text = preset.role;
    });
  }

  Future<void> _saveAsPreset() async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _PresetNameDialog(
        title: 'Save as Preset',
        hint: 'e.g. Evening shift',
        submitLabel: 'Save',
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final start = widget.normalizeTime(_startController.text.trim());
    final end = widget.normalizeTime(_endController.text.trim());
    final role = _roleController.text.trim().isEmpty ? 'Regular Shift' : _roleController.text.trim();
    await widget.savePreset(ShiftPreset(name: name, startTime: start, endTime: end, role: role));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Preset saved'),
        backgroundColor: Color(0xFF34C759),
        behavior: SnackBarBehavior.floating,
      ),
    );
    _loadPresets();
  }

  Future<void> _editPreset(ShiftPreset preset) async {
    if (preset.id == null) return;
    final result = await showDialog<ShiftPreset?>(
      context: context,
      builder: (ctx) => _EditPresetDialog(
        preset: preset,
        isValidTime: widget.isValidTime,
        normalizeTime: widget.normalizeTime,
        onDelete: () async {
          await widget.deletePreset(preset.id!);
          if (!mounted) return;
          Navigator.pop(ctx, null);
        },
      ),
    );
    if (result != null && mounted) {
      await widget.updatePreset(result);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preset updated'),
          backgroundColor: Color(0xFF34C759),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _loadPresets();
      _applyPreset(result);
    } else if (result == null && mounted) {
      _loadPresets();
    }
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    _roleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
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
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Add Shift',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 20,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Presets section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Presets',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_presetsLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: Center(child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )),
                    )
                  else if (_presets.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: Text(
                        'No presets yet. Enter times below and tap "Save as preset" to add one.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                          height: 1.35,
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      height: 64,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: _presets.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final p = _presets[index];
                          final isSelected = _selectedPreset != null &&
                              _selectedPreset!.name == p.name &&
                              _selectedPreset!.startTime == p.startTime &&
                              _selectedPreset!.endTime == p.endTime;
                          final isSavedPreset = p.id != null && p.id!.isNotEmpty;
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => _applyPreset(p),
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? const Color(0xFF007AFF).withOpacity(0.15)
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isSelected
                                            ? const Color(0xFF007AFF)
                                            : Colors.grey.shade300,
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          p.name,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                            color: isSelected ? const Color(0xFF007AFF) : Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${p.startTime} – ${p.endTime}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              if (isSavedPreset) ...[
                                const SizedBox(width: 4),
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () => _editPreset(p),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        Icons.edit_outlined,
                                        size: 18,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 16),
                  // Times and role
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _startController,
                          decoration: InputDecoration(
                            labelText: 'Start time',
                            hintText: 'e.g. 09:00',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Enter start time';
                            if (!widget.isValidTime(v.trim())) return 'Use HH:mm (e.g. 09:00)';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _endController,
                          decoration: InputDecoration(
                            labelText: 'End time',
                            hintText: 'e.g. 17:00',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Enter end time';
                            if (!widget.isValidTime(v.trim())) return 'Use HH:mm (e.g. 17:00)';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _roleController,
                          decoration: InputDecoration(
                            labelText: 'Role',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () async {
                              if (!_formKey.currentState!.validate()) return;
                              Navigator.pop(context);
                              await widget.onCreateShifts(
                                widget.employeeIds,
                                widget.days,
                                widget.normalizeTime(_startController.text.trim()),
                                widget.normalizeTime(_endController.text.trim()),
                                _roleController.text.trim().isEmpty
                                    ? 'Regular Shift'
                                    : _roleController.text.trim(),
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
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton.icon(
                            onPressed: _saveAsPreset,
                            icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                            label: const Text('Save as preset'),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF007AFF),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
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

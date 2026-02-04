import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:table_calendar/table_calendar.dart';
import '../models/employer_model.dart';
import '../services/auth_provider.dart';
import '../services/hotel_provider.dart';
import 'add_employee_page.dart';

class UserPage extends StatefulWidget {
  final EmployerModel employee;

  const UserPage({super.key, required this.employee});

  @override
  State<UserPage> createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  List<_ShiftData> _upcomingShifts = [];
  bool _loading = true;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  late EmployerModel _employee;

  @override
  void initState() {
    super.initState();
    _employee = widget.employee;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final hotelId = HotelProvider.of(context).hotelId;
    final userId = AuthScopeData.of(context).uid;
    if (hotelId != null && userId != null) _loadShifts(userId, hotelId);
  }

  Future<void> _loadShifts(String userId, String hotelId) async {
    if (_employee.id == null || _employee.id!.isEmpty) {
      setState(() => _loading = false);
      return;
    }

    try {
      final now = DateTime.now();
      final twoWeeksAgo = now.subtract(const Duration(days: 14));
      final twoMonthsAhead = now.add(const Duration(days: 60));

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('hotels')
          .doc(hotelId)
          .collection('shifts')
          .where('employeeId', isEqualTo: _employee.id)
          .where(
            'date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(twoWeeksAgo),
          )
          .where('date', isLessThan: Timestamp.fromDate(twoMonthsAhead))
          .get();

      final shifts = snapshot.docs.map((doc) {
        final d = doc.data();
        return _ShiftData(
          date: (d['date'] as Timestamp).toDate(),
          startTime: d['startTime'] ?? '',
          endTime: d['endTime'] ?? '',
          role: d['role'] ?? '',
        );
      }).toList();

      shifts.sort((a, b) => a.date.compareTo(b.date));

      if (mounted) {
        setState(() {
          _upcomingShifts = shifts;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _calculateHoursWorked(List<_ShiftData> shifts) {
    double totalHours = 0;
    for (final shift in shifts) {
      totalHours += _parseShiftHours(shift.startTime, shift.endTime);
    }
    return totalHours;
  }

  double _parseShiftHours(String startTime, String endTime) {
    try {
      final startParts = startTime.split(':');
      final endParts = endTime.split(':');
      if (startParts.length != 2 || endParts.length != 2) return 0;

      final startH = int.parse(startParts[0]);
      final startM = int.parse(startParts[1]);
      final endH = int.parse(endParts[0]);
      final endM = int.parse(endParts[1]);

      double startDecimal = startH + startM / 60.0;
      double endDecimal = endH + endM / 60.0;

      // Handle overnight shifts (e.g. 22:00 - 06:00)
      if (endDecimal < startDecimal) {
        endDecimal += 24;
      }

      return endDecimal - startDecimal;
    } catch (_) {
      return 0;
    }
  }

  List<_ShiftData> _getShiftsThisWeek() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final mondayMidnight = DateTime(monday.year, monday.month, monday.day);
    final sundayEnd = mondayMidnight.add(const Duration(days: 7));

    return _upcomingShifts.where((s) {
      return s.date.isAfter(
            mondayMidnight.subtract(const Duration(seconds: 1)),
          ) &&
          s.date.isBefore(sundayEnd);
    }).toList();
  }

  List<_ShiftData> _getShiftsLastMonth() {
    final now = DateTime.now();
    final firstDayThisMonth = DateTime(now.year, now.month, 1);
    final firstDayLastMonth = DateTime(now.year, now.month - 1, 1);

    return _upcomingShifts.where((s) {
      return s.date.isAfter(
            firstDayLastMonth.subtract(const Duration(seconds: 1)),
          ) &&
          s.date.isBefore(firstDayThisMonth);
    }).toList();
  }

  List<_ShiftData> _getUpcomingShifts() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _upcomingShifts
        .where(
          (s) => s.date.isAfter(today.subtract(const Duration(seconds: 1))),
        )
        .toList();
  }

  List<_ShiftData> _getShiftsForDay(DateTime day) {
    return _upcomingShifts
        .where((shift) => _isSameDay(shift.date, day))
        .toList();
  }

  bool _hasShiftOnDay(DateTime day) {
    return _upcomingShifts.any((shift) => _isSameDay(shift.date, day));
  }

  @override
  Widget build(BuildContext context) {
    final hoursThisWeek = _calculateHoursWorked(_getShiftsThisWeek());
    final hoursLastMonth = _calculateHoursWorked(_getShiftsLastMonth());
    final daysThisWeek = _getShiftsThisWeek().length;
    final upcomingShifts = _getUpcomingShifts();
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth >= 768 ? 24.0 : 16.0;
    final isNarrow = screenWidth < 400;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                // Header like Add Booking: back + title + subtitle + Edit
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(horizontalPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (Navigator.canPop(context))
                              IconButton(
                                icon: const Icon(Icons.arrow_back_ios_rounded),
                                onPressed: () => Navigator.pop(context),
                                color: const Color(0xFF007AFF),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            if (Navigator.canPop(context))
                              const SizedBox(width: 8),
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: const Color(0xFF007AFF).withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  _employee.name.isNotEmpty
                                      ? _employee.name[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF007AFF),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _employee.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineLarge
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 34,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _employee.role,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.copyWith(
                                          color: Colors.grey.shade600,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () async {
                                final updated =
                                    await Navigator.push<EmployerModel>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        AddEmployeePage(employee: _employee),
                                  ),
                                );
                                if (updated != null && mounted) {
                                  setState(() => _employee = updated);
                                }
                              },
                              icon: const Icon(
                                Icons.edit_outlined,
                                size: 18,
                                color: Color(0xFF007AFF),
                              ),
                              label: const Text(
                                'Edit',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF007AFF),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),

                // Employee details card
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(horizontalPadding),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _InfoRow(
                              icon: Icons.phone_rounded,
                              label: 'Phone',
                              value: _employee.phone,
                            ),
                            const SizedBox(height: 16),
                            _InfoRow(
                              icon: Icons.email_rounded,
                              label: 'Email',
                              value: _employee.email.isEmpty
                                  ? 'Not provided'
                                  : _employee.email,
                            ),
                            const SizedBox(height: 16),
                            _InfoRow(
                              icon: Icons.work_outline_rounded,
                              label: 'Department',
                              value: _employee.department,
                            ),
                            const SizedBox(height: 16),
                            _InfoRow(
                              icon: Icons.info_outline_rounded,
                              label: 'Status',
                              value: _employee.status,
                              valueColor: _employee.status == 'Active'
                                  ? const Color(0xFF34C759)
                                  : Colors.grey.shade600,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Stats cards
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Statistics',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                fontSize: 20,
                              ),
                        ),
                        const SizedBox(height: 12),
                        isNarrow
                            ? Column(
                                children: [
                                  _StatCard(
                                    title: 'Hours This Week',
                                    value: hoursThisWeek.toStringAsFixed(1),
                                    icon: Icons.schedule_rounded,
                                    color: const Color(0xFF007AFF),
                                  ),
                                  const SizedBox(height: 12),
                                  _StatCard(
                                    title: 'Days This Week',
                                    value: daysThisWeek.toString(),
                                    icon: Icons.calendar_today_rounded,
                                    color: const Color(0xFF34C759),
                                  ),
                                ],
                              )
                            : Row(
                                children: [
                                  Expanded(
                                    child: _StatCard(
                                      title: 'Hours This Week',
                                      value: hoursThisWeek.toStringAsFixed(1),
                                      icon: Icons.schedule_rounded,
                                      color: const Color(0xFF007AFF),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _StatCard(
                                      title: 'Days This Week',
                                      value: daysThisWeek.toString(),
                                      icon: Icons.calendar_today_rounded,
                                      color: const Color(0xFF34C759),
                                    ),
                                  ),
                                ],
                              ),
                        const SizedBox(height: 12),
                        _StatCard(
                          title: 'Hours Last Month',
                          value: hoursLastMonth.toStringAsFixed(1),
                          icon: Icons.access_time_rounded,
                          color: const Color(0xFFFF9500),
                        ),
                      ],
                    ),
                  ),
                ),

                // Upcoming schedule
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      24,
                      horizontalPadding,
                      12,
                    ),
                    child: Text(
                      'Upcoming Schedule',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 20,
                      ),
                    ),
                  ),
                ),

                // Calendar
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                    ),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: TableCalendar(
                          firstDay: DateTime.now().subtract(
                            const Duration(days: 14),
                          ),
                          lastDay: DateTime.now().add(const Duration(days: 90)),
                          focusedDay: _focusedDay,
                          selectedDayPredicate: (day) =>
                              _selectedDay != null &&
                              _isSameDay(_selectedDay!, day),
                          onDaySelected: (selectedDay, focusedDay) {
                            setState(() {
                              _selectedDay = selectedDay;
                              _focusedDay = focusedDay;
                            });
                          },
                          calendarFormat: CalendarFormat.month,
                          startingDayOfWeek: StartingDayOfWeek.monday,
                          calendarStyle: CalendarStyle(
                            todayDecoration: BoxDecoration(
                              color: const Color(0xFF007AFF).withOpacity(0.3),
                              shape: BoxShape.circle,
                            ),
                            selectedDecoration: const BoxDecoration(
                              color: Color(0xFF007AFF),
                              shape: BoxShape.circle,
                            ),
                            markerDecoration: const BoxDecoration(
                              color: Color(0xFF34C759),
                              shape: BoxShape.circle,
                            ),
                            markersMaxCount: 1,
                          ),
                          headerStyle: HeaderStyle(
                            formatButtonVisible: false,
                            titleCentered: true,
                            titleTextStyle: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                            leftChevronIcon: const Icon(
                              Icons.chevron_left,
                              color: Color(0xFF007AFF),
                            ),
                            rightChevronIcon: const Icon(
                              Icons.chevron_right,
                              color: Color(0xFF007AFF),
                            ),
                          ),
                          eventLoader: (day) {
                            return _hasShiftOnDay(day) ? ['shift'] : [];
                          },
                        ),
                      ),
                    ),
                  ),
                ),

                // Selected day shifts
                if (_selectedDay != null &&
                    _getShiftsForDay(_selectedDay!).isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        16,
                        horizontalPadding,
                        0,
                      ),
                      child: Text(
                        DateFormat('EEEE, MMMM d').format(_selectedDay!),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                      ),
                    ),
                  ),

                if (_selectedDay != null &&
                    _getShiftsForDay(_selectedDay!).isNotEmpty)
                  SliverPadding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final shifts = _getShiftsForDay(_selectedDay!);
                        final shift = shifts[index];
                        return Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: _ShiftCard(
                            shift: shift,
                            isToday: _isSameDay(_selectedDay!, DateTime.now()),
                          ),
                        );
                      }, childCount: _getShiftsForDay(_selectedDay!).length),
                    ),
                  ),

                // Show message if no shifts
                if (upcomingShifts.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                        vertical: 16,
                      ),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            children: [
                              Icon(
                                Icons.calendar_today_outlined,
                                size: 48,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No upcoming shifts',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Go to the Schedule page to assign shifts to this employee',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
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
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: valueColor ?? Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShiftCard extends StatelessWidget {
  final _ShiftData shift;
  final bool isToday;

  const _ShiftCard({required this.shift, required this.isToday});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Date circle
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: isToday
                    ? const Color(0xFF007AFF).withOpacity(0.1)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat('MMM').format(shift.date).toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isToday
                          ? const Color(0xFF007AFF)
                          : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('d').format(shift.date),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isToday ? const Color(0xFF007AFF) : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('EEEE').format(shift.date),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${shift.startTime} – ${shift.endTime}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    shift.role,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShiftData {
  final DateTime date;
  final String startTime;
  final String endTime;
  final String role;

  _ShiftData({
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.role,
  });
}

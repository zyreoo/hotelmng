import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/employer_model.dart';
import '../services/firebase_service.dart';
import '../services/hotel_provider.dart';
import '../services/auth_provider.dart';
import '../widgets/employeer_search_widget.dart';
import 'add_employee_page.dart';
import 'user_page.dart';

class EmployeesPage extends StatefulWidget {
  const EmployeesPage({super.key});

  @override
  State<EmployeesPage> createState() => _EmployeesPageState();
}

class _EmployeesPageState extends State<EmployeesPage> {
  String _selectedFilter = 'All';
  List<String> _filters = ['All', 'Reception', 'Housekeeping', 'Management'];

  /// When set, list shows only this employee (from search widget).
  String? _searchSelectedEmployerId;

  static const List<String> _defaultDepartments = [
    'Reception',
    'Housekeeping',
    'Management',
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final hotelId = HotelProvider.of(context).hotelId;
    final userId = AuthScopeData.of(context).uid;
    if (hotelId != null && userId != null) _loadFilters(userId, hotelId);
  }

  Future<void> _loadFilters(String userId, String hotelId) async {
    try {
      final fromDb = await FirebaseService().getDepartments(userId, hotelId);
      if (!mounted) return;
      setState(() {
        final seen = _defaultDepartments.toSet();
        final list = List<String>.from(_defaultDepartments);
        for (final name in fromDb) {
          if (name.trim().isEmpty) continue;
          if (seen.add(name.trim())) list.add(name.trim());
        }
        _filters = ['All', ...list];
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _filters = ['All', ..._defaultDepartments];
      });
    }
  }

  Stream<List<EmployerModel>> _employerstream(String? userId, String? hotelId) {
    if (userId == null || hotelId == null) return Stream.value([]);
    return FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('hotels')
        .doc(hotelId)
        .collection('employers')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => EmployerModel.fromFirestore(doc.data(), doc.id))
              .toList(),
        );
  }

  Future<void> _deleteEmployee(
      String userId, String hotelId, String employeeId) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('hotels')
        .doc(hotelId)
        .collection('employers')
        .doc(employeeId)
        .delete();
  }

  static const List<Color> _avatarColors = [
    Color(0xFF007AFF),
    Color(0xFF34C759),
    Color(0xFFFF9500),
    Color(0xFFFF3B30),
    Color(0xFFAF52DE),
  ];

  static Employee _employerToEmployee(EmployerModel employer, int index) {
    final initials = employer.name.isNotEmpty
        ? employer.name
              .trim()
              .split(RegExp(r'\s+'))
              .map((w) => w.isNotEmpty ? w[0] : '')
              .take(2)
              .join()
              .toUpperCase()
        : '?';
    return Employee(
      id: employer.id ?? '',
      name: employer.name,
      role: employer.role,
      department: employer.department,
      status: employer.status,
      avatar: initials.length >= 2
          ? initials
          : (employer.name.isNotEmpty ? employer.name[0].toUpperCase() : '?'),
      color: _avatarColors[index % _avatarColors.length],
    );
  }

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = MediaQuery.of(context).size.width >= 768
        ? 24.0
        : 16.0;
    final hotelId = HotelProvider.of(context).hotelId;
    final userId = AuthScopeData.of(context).uid;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: StreamBuilder<List<EmployerModel>>(
          stream: _employerstream(userId, hotelId),
          builder: (context, snapshot) {
            final all = snapshot.data ?? [];
            var filtered = _selectedFilter == 'All'
                ? all
                : all.where((e) => e.department == _selectedFilter).toList();
            if (_searchSelectedEmployerId != null &&
                _searchSelectedEmployerId!.isNotEmpty) {
              filtered = filtered
                  .where((e) => e.id == _searchSelectedEmployerId)
                  .toList();
            }
            final employees = List.generate(
              filtered.length,
              (i) => _employerToEmployee(filtered[i], i),
            );

            return Column(
              children: [
                Padding(
                  padding: EdgeInsets.all(horizontalPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Text(
                        'Employees',
                        style: Theme.of(context).textTheme.headlineLarge
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 34,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${employees.length} members',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: EmployeeSearchWidget(
                    hotelId: hotelId,
                    onEmployeeSelected: (employer) {
                      setState(() {
                        _searchSelectedEmployerId = employer.name.isEmpty
                            ? null
                            : employer.id;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // Filter chips
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _filters.map((filter) {
                        final isSelected = _selectedFilter == filter;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(filter),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                _selectedFilter = filter;
                              });
                            },
                            backgroundColor: Theme.of(context).colorScheme.surface,
                            selectedColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurfaceVariant,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: isSelected
                                    ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
                                    : Theme.of(context).colorScheme.outline.withOpacity(0.3),
                              ),
                            ),
                            showCheckmark: false,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Employee list
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                    ),
                    itemCount: employees.length,
                    itemBuilder: (context, index) {
                      final employee = employees[index];
                      final employerModel = filtered[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _EmployeeCard(
                          employee: employee,
                          employerModel: employerModel,
                          onDelete: (hotelId != null && userId != null)
                              ? (id) => _deleteEmployee(userId, hotelId, id)
                              : null,
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddEmployeePage()),
          );
        },
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: Icon(Icons.person_add, color: Theme.of(context).colorScheme.onPrimary),
      ),
    );
  }
}

class Employee {
  final String id;
  final String name;
  final String role;
  final String department;
  final String status;
  final String avatar;
  final Color color;

  Employee({
    required this.id,
    required this.name,
    required this.role,
    required this.department,
    required this.status,
    required this.avatar,
    required this.color,
  });
}

class _EmployeeCard extends StatelessWidget {
  final Employee employee;
  final EmployerModel employerModel;
  final Future<void> Function(String id)? onDelete;

  const _EmployeeCard({
    required this.employee,
    required this.employerModel,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => UserPage(employee: employerModel),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: employee.color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    employee.avatar,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: employee.color,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Employee info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employee.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      employee.role,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _StatusBadge(
                          status: employee.status,
                          isActive: employee.status == 'Active',
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            employee.department,
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Action button
              IconButton(
                icon: Icon(Icons.more_vert, color: Theme.of(context).colorScheme.onSurfaceVariant),
                onPressed: () {
                  _showEmployeeOptions(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEmployeeOptions(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            _BottomSheetOption(
              icon: Icons.edit_rounded,
              label: 'Edit Employee',
              color: const Color(0xFF007AFF),
            ),
            _BottomSheetOption(
              icon: Icons.schedule_rounded,
              label: 'View Schedule',
              color: const Color(0xFF34C759),
            ),
            _BottomSheetOption(
              icon: Icons.delete_rounded,
              label: 'Remove Employee',
              color: const Color(0xFFFF3B30),
              onPressed: () async {
                Navigator.pop(context);
                await onDelete?.call(employee.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${employee.name} removed'),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: const Color(0xFF34C759),
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  final bool isActive;

  const _StatusBadge({required this.status, required this.isActive});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isActive
            ? const Color(0xFF34C759).withOpacity(0.1)
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFF34C759) : colorScheme.onSurfaceVariant,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            status,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isActive ? const Color(0xFF34C759) : colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomSheetOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  const _BottomSheetOption({
    required this.icon,
    required this.label,
    required this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        if (onPressed != null) {
          onPressed!();
        } else {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$label functionality'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

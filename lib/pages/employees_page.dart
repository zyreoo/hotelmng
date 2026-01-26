import 'package:flutter/material.dart';

class EmployeesPage extends StatefulWidget {
  const EmployeesPage({super.key});

  @override
  State<EmployeesPage> createState() => _EmployeesPageState();
}

class _EmployeesPageState extends State<EmployeesPage> {
  String _selectedFilter = 'All';
  final List<String> _filters = ['All', 'Reception', 'Housekeeping', 'Management'];

  final List<Employee> _employees = [
    Employee(
      name: 'Sarah Johnson',
      role: 'Front Desk Manager',
      department: 'Reception',
      status: 'Active',
      avatar: 'SJ',
      color: const Color(0xFF007AFF),
    ),
    Employee(
      name: 'Michael Chen',
      role: 'Receptionist',
      department: 'Reception',
      status: 'Active',
      avatar: 'MC',
      color: const Color(0xFF34C759),
    ),
    Employee(
      name: 'Emily Davis',
      role: 'Housekeeping Supervisor',
      department: 'Housekeeping',
      status: 'Active',
      avatar: 'ED',
      color: const Color(0xFFFF9500),
    ),
    Employee(
      name: 'James Wilson',
      role: 'Housekeeper',
      department: 'Housekeeping',
      status: 'Off Duty',
      avatar: 'JW',
      color: const Color(0xFF5856D6),
    ),
    Employee(
      name: 'Lisa Anderson',
      role: 'General Manager',
      department: 'Management',
      status: 'Active',
      avatar: 'LA',
      color: const Color(0xFFFF2D55),
    ),
    Employee(
      name: 'David Martinez',
      role: 'Housekeeper',
      department: 'Housekeeping',
      status: 'Active',
      avatar: 'DM',
      color: const Color(0xFF5AC8FA),
    ),
    Employee(
      name: 'Jessica Brown',
      role: 'Receptionist',
      department: 'Reception',
      status: 'Active',
      avatar: 'JB',
      color: const Color(0xFFFFCC00),
    ),
    Employee(
      name: 'Robert Taylor',
      role: 'Night Auditor',
      department: 'Reception',
      status: 'Off Duty',
      avatar: 'RT',
      color: const Color(0xFF32ADE6),
    ),
  ];

  List<Employee> get _filteredEmployees {
    if (_selectedFilter == 'All') {
      return _employees;
    }
    return _employees
        .where((emp) => emp.department == _selectedFilter)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Text(
                    'Employees',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 34,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_filteredEmployees.length} members',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                  ),
                ],
              ),
            ),

            // Filter chips
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
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
                        backgroundColor: Colors.white,
                        selectedColor: const Color(0xFF007AFF).withOpacity(0.1),
                        labelStyle: TextStyle(
                          color: isSelected
                              ? const Color(0xFF007AFF)
                              : Colors.grey.shade700,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w500,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isSelected
                                ? const Color(0xFF007AFF).withOpacity(0.3)
                                : Colors.grey.shade200,
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
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: _filteredEmployees.length,
                itemBuilder: (context, index) {
                  final employee = _filteredEmployees[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _EmployeeCard(employee: employee),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Add employee logic
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Add employee functionality'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        backgroundColor: const Color(0xFF007AFF),
        child: const Icon(Icons.person_add, color: Colors.white),
      ),
    );
  }
}

class Employee {
  final String name;
  final String role;
  final String department;
  final String status;
  final String avatar;
  final Color color;

  Employee({
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

  const _EmployeeCard({required this.employee});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: () {
          // Navigate to employee details
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
                        color: Colors.grey.shade600,
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
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            employee.department,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade700,
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
                icon: Icon(
                  Icons.more_vert,
                  color: Colors.grey.shade400,
                ),
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
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
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
                color: Colors.grey.shade300,
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
              icon: Icons.email_rounded,
              label: 'Send Message',
              color: const Color(0xFFFF9500),
            ),
            _BottomSheetOption(
              icon: Icons.delete_rounded,
              label: 'Remove Employee',
              color: const Color(0xFFFF3B30),
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

  const _StatusBadge({
    required this.status,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isActive
            ? const Color(0xFF34C759).withOpacity(0.1)
            : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFF34C759) : Colors.grey.shade500,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            status,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color:
                  isActive ? const Color(0xFF34C759) : Colors.grey.shade700,
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

  const _BottomSheetOption({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$label functionality'),
            behavior: SnackBarBehavior.floating,
          ),
        );
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

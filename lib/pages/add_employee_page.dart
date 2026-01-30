import 'package:flutter/material.dart';

import '../models/employer_model.dart';
import '../services/firebase_service.dart';

class AddEmployeePage extends StatefulWidget {
  const AddEmployeePage({super.key});

  @override
  State<AddEmployeePage> createState() => _AddEmployeePageState();
}

class _AddEmployeePageState extends State<AddEmployeePage> {
  final _formKey = GlobalKey<FormState>();
  final _firebaseService = FirebaseService();

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _roleController = TextEditingController();
  final _departmentController = TextEditingController();

  String _role = 'Receptionist';
  String _department = 'Reception';
  String _status = 'Active';

  List<String> _roleOptions = [
    'Receptionist',
    'Front Desk Manager',
    'Housekeeper',
    'Manager',
    'Supervisor',
    'Other',
  ];

  List<String> _departmentOptions = [
    'Reception',
    'Housekeeping',
    'Management',
    'Other',
  ];

  static const List<String> _statusOptions = ['Active', 'Inactive'];

  static const List<String> _defaultRoleOptions = [
    'Receptionist',
    'Front Desk Manager',
    'Housekeeper',
    'Manager',
    'Supervisor',
    'Other',
  ];

  static const List<String> _defaultDepartmentOptions = [
    'Reception',
    'Housekeeping',
    'Management',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _loadRolesAndDepartments();
  }

  Future<void> _loadRolesAndDepartments() async {
    try {
      final roles = await _firebaseService.getRoles();
      final departments = await _firebaseService.getDepartments();
      if (!mounted) return;
      setState(() {
        _roleOptions = _mergeOptions(_defaultRoleOptions, roles);
        _departmentOptions = _mergeOptions(
          _defaultDepartmentOptions,
          departments,
        );
      });
    } catch (_) {
      // Permission denied or network error: use defaults only until rules are deployed
      if (!mounted) return;
      setState(() {
        _roleOptions = List<String>.from(_defaultRoleOptions);
        _departmentOptions = List<String>.from(_defaultDepartmentOptions);
      });
    }
  }

  static List<String> _mergeOptions(
    List<String> defaults,
    List<String> fromDb,
  ) {
    final Set<String> set = {};

    for (final d in defaults) {
      if (d.trim().toLowerCase() != 'other') {
        set.add(d.trim());
      }
    }

    for (final name in fromDb) {
      final clean = name.trim();
      if (clean.isEmpty) continue;
      if (clean.toLowerCase() != 'other') set.add(clean);
    }

    final list = set.toList()..sort();
    list.add('Other');
    return list;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _roleController.dispose();
    _departmentController.dispose();
    super.dispose();
  }

  Future<void> _submitEmployee() async {
    if (!_formKey.currentState!.validate()) return;

    if (_nameController.text.trim().isEmpty ||
        _phoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in name and phone'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_role == 'Other' && _roleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter the role when "Other" is selected'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_department == 'Other' && _departmentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter the department when "Other" is selected'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final roleValue = _role == 'Other' ? _roleController.text.trim() : _role;
      final departmentValue = _department == 'Other'
          ? _departmentController.text.trim()
          : _department;
      final employer = EmployerModel(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim().isEmpty
            ? ''
            : _emailController.text.trim(),
        role: roleValue.isEmpty ? _role : roleValue,
        department: departmentValue.isEmpty ? _department : departmentValue,
        status: _status,
      );

      await _firebaseService.createEmployer(employer);

      // Save custom "Other" role/department to DB so they appear in dropdowns next time
      if (_role == 'Other' && roleValue.isNotEmpty) {
        await _firebaseService.addRole(roleValue);
      }
      if (_department == 'Other' && departmentValue.isNotEmpty) {
        await _firebaseService.addDepartment(departmentValue);
      }

      if (mounted) Navigator.pop(context);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Employee ${employer.name} added'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF34C759),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding employee: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'New Employee',
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
                                  'Add a new team member',
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Employee Information',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 22,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildTextField(
                                controller: _nameController,
                                label: 'Full name',
                                hint: 'e.g. Sarah Johnson',
                                icon: Icons.person_rounded,
                                isRequired: true,
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                    ? 'Name is required'
                                    : null,
                              ),
                              const SizedBox(height: 16),
                              _buildTextField(
                                controller: _phoneController,
                                label: 'Phone',
                                hint: 'e.g. +40 722 123 456',
                                icon: Icons.phone_rounded,
                                keyboardType: TextInputType.phone,
                                isRequired: true,
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                    ? 'Phone is required'
                                    : null,
                              ),
                              const SizedBox(height: 16),
                              _buildTextField(
                                controller: _emailController,
                                label: 'Email',
                                hint: 'e.g. sarah@hotel.com',
                                icon: Icons.email_rounded,
                                keyboardType: TextInputType.emailAddress,
                              ),
                              const SizedBox(height: 16),
                              _buildDropdown(
                                label: 'Role',
                                value: _role,
                                items: _roleOptions,
                                icon: Icons.badge_rounded,
                                onChanged: (v) =>
                                    setState(() => _role = v ?? _role),
                              ),
                              if (_role == 'Other') ...[
                                const SizedBox(height: 16),
                                _buildTextField(
                                  controller: _roleController,
                                  label: 'Other role',
                                  hint: 'e.g. Concierge',
                                  icon: Icons.badge_rounded,
                                  keyboardType: TextInputType.text,
                                  isRequired: true,
                                  validator: (v) =>
                                      (v == null || v.trim().isEmpty)
                                      ? 'Role is required'
                                      : null,
                                ),
                              ],
                              const SizedBox(height: 16),
                              _buildDropdown(
                                label: 'Department',
                                value: _department,
                                items: _departmentOptions,
                                icon: Icons.business_rounded,
                                onChanged: (v) => setState(
                                  () => _department = v ?? _department,
                                ),
                              ),
                              if (_department == 'Other') ...[
                                const SizedBox(height: 16),
                                _buildTextField(
                                  controller: _departmentController,
                                  label: 'Other department',
                                  hint: 'e.g. Maintenance',
                                  icon: Icons.business_rounded,
                                  keyboardType: TextInputType.text,
                                  isRequired: true,
                                  validator: (v) =>
                                      (v == null || v.trim().isEmpty)
                                      ? 'Department is required'
                                      : null,
                                ),
                              ],
                              const SizedBox(height: 16),
                              _buildDropdown(
                                label: 'Status',
                                value: _status,
                                items: _statusOptions,
                                icon: Icons.check_circle_rounded,
                                onChanged: (v) =>
                                    setState(() => _status = v ?? _status),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _submitEmployee,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF007AFF),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Save Employee',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool isRequired = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: isRequired ? '$label *' : label,
        hintText: hint,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF007AFF), width: 2),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
        prefixIcon: Icon(icon, color: Colors.grey.shade600),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      style: const TextStyle(fontSize: 16),
      keyboardType: keyboardType,
      validator: validator,
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    required IconData icon,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF007AFF), width: 2),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
        prefixIcon: Icon(icon, color: Colors.grey.shade600),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      items: items
          .map(
            (e) => DropdownMenuItem<String>(
              value: e,
              child: Text(e, style: const TextStyle(color: Colors.black)),
            ),
          )
          .toList(),
      onChanged: onChanged,
      style: const TextStyle(fontSize: 16, color: Colors.black),
    );
  }
}

import 'package:flutter/material.dart';

import '../models/employer_model.dart';
import '../services/firebase_service.dart';
import '../services/hotel_provider.dart';

class AddEmployeePage extends StatefulWidget {
  /// When provided, the form is in edit mode for this employee.
  final EmployerModel? employee;

  const AddEmployeePage({super.key, this.employee});

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

  bool get _isEditMode => widget.employee != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final hotelId = HotelProvider.of(context).hotelId;
    if (hotelId != null) _loadRolesAndDepartments(hotelId);
  }

  @override
  void initState() {
    super.initState();
    if (_isEditMode) {
      final e = widget.employee!;
      _nameController.text = e.name;
      _phoneController.text = e.phone;
      _emailController.text = e.email;
      _status = e.status;
      _role = _defaultRoleOptions.contains(e.role) ? e.role : 'Other';
      if (_role == 'Other') _roleController.text = e.role;
      _department = _defaultDepartmentOptions.contains(e.department)
          ? e.department
          : 'Other';
      if (_department == 'Other') _departmentController.text = e.department;
    }
  }

  Future<void> _loadRolesAndDepartments(String hotelId) async {
    try {
      final roles = await _firebaseService.getRoles(hotelId);
      final departments = await _firebaseService.getDepartments(hotelId);
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
      final name = _nameController.text.trim();
      final phone = _phoneController.text.trim();
      final email = _emailController.text.trim().isEmpty
          ? ''
          : _emailController.text.trim();
      final roleFinal = roleValue.isEmpty ? _role : roleValue;
      final departmentFinal =
          departmentValue.isEmpty ? _department : departmentValue;

      if (_isEditMode) {
        final employer = widget.employee!.copyWith(
          name: name,
          phone: phone,
          email: email,
          role: roleFinal,
          department: departmentFinal,
          status: _status,
          updatedAt: DateTime.now(),
        );
        final hotelId = HotelProvider.of(context).hotelId;
        if (hotelId == null) return;
        await _firebaseService.updateEmployer(hotelId, employer);
        if (_role == 'Other' && roleValue.isNotEmpty) {
          await _firebaseService.addRole(hotelId, roleValue);
        }
        if (_department == 'Other' && departmentValue.isNotEmpty) {
          await _firebaseService.addDepartment(hotelId, departmentValue);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${employer.name} updated'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFF34C759),
            ),
          );
          Navigator.pop(context, employer);
        }
      } else {
        final employer = EmployerModel(
          name: name,
          phone: phone,
          email: email,
          role: roleFinal,
          department: departmentFinal,
          status: _status,
        );
        final hotelId = HotelProvider.of(context).hotelId;
        if (hotelId == null) return;
        await _firebaseService.createEmployer(hotelId, employer);
        if (_role == 'Other' && roleValue.isNotEmpty) {
          await _firebaseService.addRole(hotelId, roleValue);
        }
        if (_department == 'Other' && departmentValue.isNotEmpty) {
          await _firebaseService.addDepartment(hotelId, departmentValue);
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
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                _isEditMode ? 'Error updating employee: $e' : 'Error adding employee: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = MediaQuery.of(context).size.width >= 768 ? 24.0 : 16.0;
    
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(horizontalPadding),
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
                                  _isEditMode ? 'Edit Employee' : 'New Employee',
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
                                  _isEditMode
                                      ? 'Update employee information'
                                      : 'Add a new team member',
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
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
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

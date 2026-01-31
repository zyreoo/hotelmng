import 'package:flutter/material.dart';
import '../models/employer_model.dart';
import '../services/firebase_service.dart';

class EmployeeSearchWidget extends StatefulWidget {
  final Function(EmployerModel) onEmployeeSelected;
  final EmployerModel? initialEmployee;

  const EmployeeSearchWidget({
    super.key,
    required this.onEmployeeSelected,
    this.initialEmployee,
  });

  @override
  State<EmployeeSearchWidget> createState() => _EmployeeSearchWidgetState();
}

class _EmployeeSearchWidgetState extends State<EmployeeSearchWidget> {
  final FirebaseService _firebaseService = FirebaseService();
  final TextEditingController _searchController = TextEditingController();

  List<EmployerModel> _searchResults = [];
  bool _isSearching = false;
  EmployerModel? _selectedEmployee;

  @override
  void initState() {
    super.initState();
    _selectedEmployee = widget.initialEmployee;
    if (_selectedEmployee != null) {
      _searchController.text = _selectedEmployee!.name;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchEmployees(String query) async {
    if (query.trim().length < 2) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    try {
      final results = await _firebaseService.searchEmployers(query.trim());
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSearching = false);
    }
  }

  void _selectEmployee(EmployerModel employee) {
    setState(() {
      _selectedEmployee = employee;
      _searchController.text = employee.name;
      _searchResults = [];
    });
    widget.onEmployeeSelected(employee);
  }

  void _clearSelection() {
    setState(() {
      _selectedEmployee = null;
      _searchController.clear();
      _searchResults = [];
    });
    widget.onEmployeeSelected(
      EmployerModel(
        name: '',
        phone: '',
        email: '',
        role: '',
        department: '',
        status: '',
      ),
    );
  }

  Future<void> _showCreateEmployeeDialog() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final roleController = TextEditingController();
    final departmentController = TextEditingController(text: 'Reception');
    final statusController = TextEditingController(text: 'Active');
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<EmployerModel>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('Create New Employee'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty)
                          ? 'Name is required'
                          : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Phone *',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (value) =>
                      (value == null || value.trim().isEmpty)
                          ? 'Phone is required'
                          : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email (optional)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: roleController,
                  decoration: const InputDecoration(
                    labelText: 'Role *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty)
                          ? 'Role is required'
                          : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: departmentController,
                  decoration: const InputDecoration(
                    labelText: 'Department',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: statusController,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                final newEmployee = EmployerModel(
                  name: nameController.text.trim(),
                  phone: phoneController.text.trim(),
                  email: emailController.text.trim().isEmpty
                      ? ''
                      : emailController.text.trim(),
                  role: roleController.text.trim(),
                  department: departmentController.text.trim().isEmpty
                      ? 'Reception'
                      : departmentController.text.trim(),
                  status: statusController.text.trim().isEmpty
                      ? 'Active'
                      : statusController.text.trim(),
                );
                Navigator.pop(context, newEmployee);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (result != null) {
      try {
        final employerId = await _firebaseService.createEmployer(result);
        final created = result.copyWith(id: employerId);
        _selectEmployee(created);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Employee created'),
            backgroundColor: Color(0xFF34C759),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating employee: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _searchController,
          decoration: InputDecoration(
            labelText: 'Search Employee',
            hintText: 'Type name, phone, or role...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
            suffixIcon: _selectedEmployee != null
                ? IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: _clearSelection,
                    color: Colors.grey.shade600,
                  )
                : _isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.person_add_rounded),
                        onPressed: _showCreateEmployeeDialog,
                        color: const Color(0xFF007AFF),
                        tooltip: 'Create new employee',
                      ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
          style: const TextStyle(fontSize: 16),
          onChanged: _searchEmployees,
        ),

        if (_searchResults.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                final employee = _searchResults[index];
                return InkWell(
                  onTap: () => _selectEmployee(employee),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFF007AFF).withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              employee.name.isNotEmpty
                                  ? employee.name[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                color: Color(0xFF007AFF),
                                fontWeight: FontWeight.w600,
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
                                employee.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                employee.phone,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              if (employee.role.isNotEmpty)
                                Text(
                                  employee.role,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              if (employee.email.isNotEmpty)
                                Text(
                                  employee.email,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

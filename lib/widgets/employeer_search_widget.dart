import 'package:flutter/material.dart';
import '../models/employer_model.dart';
import '../services/firebase_service.dart';
import '../services/auth_provider.dart';
class EmployeeSearchWidget extends StatefulWidget {
  final String? hotelId;
  final Function(EmployerModel) onEmployeeSelected;
  final EmployerModel? initialEmployee;

  const EmployeeSearchWidget({
    super.key,
    required this.onEmployeeSelected,
    this.initialEmployee,
    this.hotelId,
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
    if (query.trim().length < 2 || widget.hotelId == null) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    final userId = AuthScopeData.of(context).uid;
    if (userId == null) return;

    setState(() => _isSearching = true);

    try {
      final results = await _firebaseService.searchEmployers(
        userId,
        widget.hotelId!,
        query.trim(),
      );
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _searchController,
          decoration: InputDecoration(
            labelText: 'Search Employee',
            hintText: 'Type name, phone, or role...',
            prefixIcon: Icon(
              Icons.search_rounded,
              color: Colors.grey.shade600,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            filled: true,
            fillColor: isDark ? const Color(0xFF1C1C1E) : Colors.grey.shade50,
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
                    : null,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
          style: const TextStyle(fontSize: 16),
          onChanged: _searchEmployees,
        ),
        
        // Search results dropdown (fixed height so ListView gets bounded constraints)
        if (_searchResults.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 300,
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _searchResults.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
              ),
              itemBuilder: (context, index) {
                final employee = _searchResults[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF007AFF).withValues(alpha: 0.1),
                    child: Text(
                      employee.name.isNotEmpty
                          ? employee.name[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Color(0xFF007AFF),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    employee.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '${employee.role}${employee.department.isNotEmpty ? ' • ${employee.department}' : ''}',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                  ),
                  onTap: () => _selectEmployee(employee),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                );
              },
              ),
            ),
          ),
        ],
      ],  
    );
  }
}

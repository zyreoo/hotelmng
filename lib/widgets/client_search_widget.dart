import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/firebase_service.dart';

class ClientSearchWidget extends StatefulWidget {
  final String? hotelId;
  final Function(UserModel) onClientSelected;
  final UserModel? initialClient;

  const ClientSearchWidget({
    super.key,
    required this.onClientSelected,
    this.initialClient,
    this.hotelId,
  });

  @override
  State<ClientSearchWidget> createState() => _ClientSearchWidgetState();
}

class _ClientSearchWidgetState extends State<ClientSearchWidget> {
  final FirebaseService _firebaseService = FirebaseService();
  final TextEditingController _searchController = TextEditingController();
  List<UserModel> _searchResults = [];
  bool _isSearching = false;
  UserModel? _selectedClient;

  @override
  void initState() {
    super.initState();
    _selectedClient = widget.initialClient;
    if (_selectedClient != null) {
      _searchController.text = _selectedClient!.name;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchClients(String query) async {
    if (query.length < 2 || widget.hotelId == null) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final results = await _firebaseService.searchUsers(widget.hotelId!, query);
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
      });
    }
  }

  void _selectClient(UserModel client) {
    setState(() {
      _selectedClient = client;
      _searchController.text = client.name;
      _searchResults = [];
    });
    widget.onClientSelected(client);
  }

  void _clearSelection() {
    setState(() {
      _selectedClient = null;
      _searchController.clear();
      _searchResults = [];
    });
    widget.onClientSelected(UserModel(name: '', phone: ''));
  }

  Future<void> _showCreateClientDialog() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<UserModel>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('Create New Client'),
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
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Name is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Phone *',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Phone is required';
                    }
                    return null;
                  },
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
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                final newClient = UserModel(
                  name: nameController.text,
                  phone: phoneController.text,
                  email: emailController.text.isEmpty
                      ? null
                      : emailController.text,
                );
                Navigator.pop(context, newClient);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (result != null && widget.hotelId != null) {
      try {
        // Create client in Firebase
        final userId =
            await _firebaseService.createUser(widget.hotelId!, result);
        final createdClient = result.copyWith(id: userId);
        _selectClient(createdClient);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error creating client: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
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
            labelText: 'Search Client',
            hintText: 'Type name or phone number...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
            suffixIcon: _selectedClient != null
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
                        onPressed: _showCreateClientDialog,
                        color: const Color(0xFF007AFF),
                        tooltip: 'Create new client',
                      ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
          style: const TextStyle(fontSize: 16),
          onChanged: _searchClients,
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
                final client = _searchResults[index];
                return InkWell(
                  onTap: () => _selectClient(client),
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
                              client.name.isNotEmpty
                                  ? client.name[0].toUpperCase()
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
                                client.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                client.phone,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              if (client.email != null &&
                                  client.email!.isNotEmpty)
                                Text(
                                  client.email!,
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
        if (_selectedClient != null)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF007AFF).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF007AFF),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Selected: ${_selectedClient!.name}',
                    style: const TextStyle(
                      color: Color(0xFF007AFF),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/user_model.dart';
import '../models/booking_model.dart';
import '../services/firebase_service.dart';
import '../widgets/client_search_widget.dart';

class AddBookingPage extends StatefulWidget {
  final String? preselectedRoom;
  final DateTime? preselectedStartDate;
  final DateTime? preselectedEndDate;

  const AddBookingPage({
    super.key,
    this.preselectedRoom,
    this.preselectedStartDate,
    this.preselectedEndDate,
  });

  @override
  State<AddBookingPage> createState() => _AddBookingPageState();
}

class _AddBookingPageState extends State<AddBookingPage> {
  final _formKey = GlobalKey<FormState>();
  final _firebaseService = FirebaseService();
  final _notesController = TextEditingController();

  // Client form controllers
  final _clientNameController = TextEditingController();
  final _clientPhoneController = TextEditingController();
  final _clientEmailController = TextEditingController();

  UserModel? _selectedClient;
  bool _showCreateClientForm = false;
  List<String> _selectedRooms = [];
  DateTime? _checkInDate;
  DateTime? _checkOutDate;
  int _numberOfGuests = 1;
  int _numberOfRooms = 1;
  String _bookingStatus = 'Confirmed';
  bool _wantsSpecificRoom = false;
  bool _roomsNextToEachOther = false;

  // Sample rooms
  final List<String> _rooms = [
    '101',
    '102',
    '103',
    '104',
    '105',
    '201',
    '202',
    '203',
    '204',
    '205',
    '301',
    '302',
    '303',
    '304',
    '305',
    'none',
  ];

  final List<String> _statusOptions = ['Confirmed', 'Pending', 'Cancelled'];

  @override
  void initState() {
    super.initState();
    if (widget.preselectedRoom != null) {
      _selectedRooms = [widget.preselectedRoom!];
      _wantsSpecificRoom = true;
      _numberOfRooms = 1;
    }
    _checkInDate = widget.preselectedStartDate;
    _checkOutDate = widget.preselectedEndDate;
  }

  @override
  void dispose() {
    _notesController.dispose();
    _clientNameController.dispose();
    _clientPhoneController.dispose();
    _clientEmailController.dispose();
    super.dispose();
  }

  Future<void> _selectCheckInDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _checkInDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF007AFF),
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _checkInDate = picked;
        if (_checkOutDate != null && _checkOutDate!.isBefore(picked)) {
          _checkOutDate = picked.add(const Duration(days: 1));
        }
      });
    }
  }

  Future<void> _selectCheckOutDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate:
          _checkOutDate ??
          _checkInDate?.add(const Duration(days: 1)) ??
          DateTime.now().add(const Duration(days: 1)),
      firstDate:
          _checkInDate?.add(const Duration(days: 1)) ??
          DateTime.now().add(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF007AFF),
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _checkOutDate = picked;
      });
    }
  }

  int get _numberOfNights {
    if (_checkInDate == null || _checkOutDate == null) return 0;
    return _checkOutDate!.difference(_checkInDate!).inDays;
  }

  Future<void> _submitBooking() async {
    if (_formKey.currentState!.validate()) {
      // Validate client selection or new client form
      UserModel? clientToUse;

      if (_showCreateClientForm) {
        // Validate new client form
        if (_clientNameController.text.isEmpty ||
            _clientPhoneController.text.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please fill in client name and phone number'),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
        // Create client model from form
        clientToUse = UserModel(
          name: _clientNameController.text.trim(),
          phone: _clientPhoneController.text.trim(),
          email: _clientEmailController.text.trim().isEmpty
              ? null
              : _clientEmailController.text.trim(),
        );
      } else {
        // Validate selected client
        if (_selectedClient == null ||
            _selectedClient!.name.isEmpty ||
            _selectedClient!.phone.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Please search and select a client, or create a new one',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
        clientToUse = _selectedClient;
      }

      if (_wantsSpecificRoom) {
        final selectedCount = _selectedRooms
            .where((room) => room.isNotEmpty)
            .length;
        if (selectedCount != _numberOfRooms) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Please select all $_numberOfRooms ${_numberOfRooms == 1 ? 'room' : 'rooms'}',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
      }

      if (_checkInDate == null || _checkOutDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select check-in and check-out dates'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      try {
        // Step 1: Create or get user in Firebase
        String userId;
        UserModel userToUse;

        // Check if user already has an ID (from search or previous creation)
        if (clientToUse!.id != null && clientToUse.id!.isNotEmpty) {
          // User already exists in Firebase
          userId = clientToUse.id!;
          userToUse = clientToUse;
        } else {
          // User doesn't have an ID, check if they exist by phone
          final existingUser = await _firebaseService.getUserByPhone(
            clientToUse.phone,
          );

          if (existingUser != null) {
            // User exists in Firebase, use existing user
            userId = existingUser.id!;
            userToUse = existingUser;
            // Update selected client for future use
            setState(() {
              _selectedClient = existingUser;
              _showCreateClientForm = false;
            });
          } else {
            // User doesn't exist, create new user in Firebase
            userId = await _firebaseService.createUser(clientToUse);
            // Create user object with the new ID
            userToUse = clientToUse.copyWith(id: userId);
            // Update selected client for future use
            setState(() {
              _selectedClient = userToUse;
              _showCreateClientForm = false;
            });
          }
        }

        // Step 2: Create booking with user information
        final selectedRoomNumbers = _wantsSpecificRoom
            ? _selectedRooms.where((room) => room.isNotEmpty).toList()
            : null;

        final booking = BookingModel(
          userId: userId,
          userName: userToUse.name,
          userPhone: userToUse.phone,
          userEmail: userToUse.email,
          checkIn: _checkInDate!,
          checkOut: _checkOutDate!,
          numberOfRooms: _numberOfRooms,
          nextToEachOther: _numberOfRooms >= 2 ? _roomsNextToEachOther : false,
          selectedRooms: selectedRoomNumbers,
          numberOfGuests: _numberOfGuests,
          status: _bookingStatus,
          notes: _notesController.text.isEmpty ? null : _notesController.text,
        );

        // Step 3: Save booking to Firebase
        await _firebaseService.createBooking(booking);

        // Close loading dialog
        if (mounted) Navigator.pop(context);

        // Show success
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Booking created for ${userToUse.name}'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFF34C759),
            ),
          );
        }

        // Navigate back only if there's a previous route
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context, true);
        }
      } catch (e) {
        // Close loading dialog
        if (mounted) Navigator.pop(context);

        // Show error
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error creating booking: $e'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.red,
            ),
          );
        }
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
              // Page Title
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
                                  'New Booking',
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
                                  'Create a new reservation',
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
                      // Client Information Section
                      Text(
                        'Client Information',
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
                              // Toggle between search and create
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            _showCreateClientForm = false;
                                            _selectedClient = null;
                                          });
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: !_showCreateClientForm
                                                ? Colors.white
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            boxShadow: !_showCreateClientForm
                                                ? [
                                                    BoxShadow(
                                                      color: Colors.black
                                                          .withOpacity(0.05),
                                                      blurRadius: 8,
                                                      offset: const Offset(
                                                        0,
                                                        2,
                                                      ),
                                                    ),
                                                  ]
                                                : null,
                                          ),
                                          child: Center(
                                            child: Text(
                                              'Search Client',
                                              style: TextStyle(
                                                color: !_showCreateClientForm
                                                    ? Colors.black87
                                                    : Colors.grey.shade600,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 15,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            _showCreateClientForm = true;
                                            _selectedClient = null;
                                          });
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _showCreateClientForm
                                                ? Colors.white
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            boxShadow: _showCreateClientForm
                                                ? [
                                                    BoxShadow(
                                                      color: Colors.black
                                                          .withOpacity(0.05),
                                                      blurRadius: 8,
                                                      offset: const Offset(
                                                        0,
                                                        2,
                                                      ),
                                                    ),
                                                  ]
                                                : null,
                                          ),
                                          child: Center(
                                            child: Text(
                                              'New Client',
                                              style: TextStyle(
                                                color: _showCreateClientForm
                                                    ? Colors.black87
                                                    : Colors.grey.shade600,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 15,
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

                              // Show search or create form
                              if (!_showCreateClientForm) ...[
                                ClientSearchWidget(
                                  onClientSelected: (client) {
                                    setState(() {
                                      if (client.name.isNotEmpty &&
                                          client.phone.isNotEmpty) {
                                        _selectedClient = client;
                                      } else {
                                        _selectedClient = null;
                                      }
                                    });
                                  },
                                ),
                              ] else ...[
                                // Create New Client Form
                                _buildTextField(
                                  controller: _clientNameController,
                                  label: 'Name',
                                  hint: 'Enter client name',
                                  icon: Icons.person_rounded,
                                  isRequired: true,
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Name is required';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                _buildTextField(
                                  controller: _clientPhoneController,
                                  label: 'Phone',
                                  hint: '+40 7123 234 560 ',
                                  icon: Icons.phone_rounded,
                                  keyboardType: TextInputType.phone,
                                  isRequired: true,
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Phone is required';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                _buildTextField(
                                  controller: _clientEmailController,
                                  label: 'Email',
                                  hint: 'client@example.com',
                                  icon: Icons.email_rounded,
                                  keyboardType: TextInputType.emailAddress,
                                  validator: (value) {
                                    if (value != null && value.isNotEmpty) {
                                      if (!value.contains('@')) {
                                        return 'Please enter a valid email';
                                      }
                                    }
                                    return null;
                                  },
                                ),
                              ],
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Number of Guests',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyLarge,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                          Icons.remove_circle_outline,
                                        ),
                                        onPressed: () {
                                          if (_numberOfGuests > 1) {
                                            setState(() {
                                              _numberOfGuests--;
                                            });
                                          }
                                        },
                                        color: const Color(0xFF007AFF),
                                      ),
                                      Container(
                                        width: 50,
                                        alignment: Alignment.center,
                                        child: Text(
                                          '$_numberOfGuests',
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.add_circle_outline,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _numberOfGuests++;
                                          });
                                        },
                                        color: const Color(0xFF007AFF),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Booking Details Section
                      Text(
                        'Booking Details',
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
                              // Number of Rooms (always visible)
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Number of Rooms',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'How many rooms do you need?',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                          Icons.remove_circle_outline,
                                        ),
                                        onPressed: () {
                                          if (_numberOfRooms > 1) {
                                            setState(() {
                                              _numberOfRooms--;
                                              if (_selectedRooms.length >
                                                  _numberOfRooms) {
                                                _selectedRooms = _selectedRooms
                                                    .sublist(0, _numberOfRooms);
                                              }
                                              // Reset next to each other if only 1 room
                                              if (_numberOfRooms < 2) {
                                                _roomsNextToEachOther = false;
                                              }
                                            });
                                          }
                                        },
                                        color: const Color(0xFF007AFF),
                                      ),
                                      Container(
                                        width: 50,
                                        alignment: Alignment.center,
                                        child: Text(
                                          '$_numberOfRooms',
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.add_circle_outline,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _numberOfRooms++;
                                            while (_selectedRooms.length <
                                                _numberOfRooms) {
                                              _selectedRooms.add('');
                                            }
                                          });
                                        },
                                        color: const Color(0xFF007AFF),
                                      ),
                                    ],
                                  ),
                                ],
                              ),

                              // Next to each other checkbox (shown when 2+ rooms)
                              if (_numberOfRooms >= 2) ...[
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Checkbox(
                                      value: _roomsNextToEachOther,
                                      onChanged: (value) {
                                        setState(() {
                                          _roomsNextToEachOther =
                                              value ?? false;
                                        });
                                      },
                                      activeColor: const Color(0xFF007AFF),
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Next to each other?',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Check in rooms together',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],

                              const SizedBox(height: 24),
                              const Divider(),
                              const SizedBox(height: 16),

                              // Specific Room Checkbox
                              Row(
                                children: [
                                  Checkbox(
                                    value: _wantsSpecificRoom,
                                    onChanged: (value) {
                                      setState(() {
                                        _wantsSpecificRoom = value ?? false;
                                        if (!_wantsSpecificRoom) {
                                          _selectedRooms = [];
                                        } else {
                                          _selectedRooms = List.generate(
                                            _numberOfRooms,
                                            (index) => '',
                                          );
                                        }
                                      });
                                    },
                                    activeColor: const Color(0xFF007AFF),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Select specific room(s)',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Assign specific rooms to this booking',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              // Room Selection (shown when checkbox is checked - indented)
                              if (_wantsSpecificRoom) ...[
                                const SizedBox(height: 16),
                                Padding(
                                  padding: const EdgeInsets.only(left: 48),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: List.generate(_numberOfRooms, (
                                      index,
                                    ) {
                                      return Padding(
                                        padding: EdgeInsets.only(
                                          bottom: index < _numberOfRooms - 1
                                              ? 16
                                              : 0,
                                        ),
                                        child: DropdownButtonFormField<String>(
                                          value:
                                              index < _selectedRooms.length &&
                                                  _selectedRooms[index]
                                                      .isNotEmpty
                                              ? _selectedRooms[index]
                                              : null,
                                          decoration: InputDecoration(
                                            labelText: _numberOfRooms == 1
                                                ? 'Select Room'
                                                : 'Room ${index + 1}',
                                            hintText: 'Choose a room',
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            filled: true,
                                            fillColor: Colors.grey.shade50,
                                            prefixIcon: const Icon(
                                              Icons.hotel_rounded,
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 16,
                                                  vertical: 16,
                                                ),
                                          ),
                                          style: const TextStyle(
                                            fontSize: 16,
                                            color: Colors.black87,
                                          ),
                                          dropdownColor: Colors.white,
                                          items: _rooms
                                              .where(
                                                (room) =>
                                                    !_selectedRooms.contains(
                                                      room,
                                                    ) ||
                                                    _selectedRooms[index] ==
                                                        room,
                                              )
                                              .map((room) {
                                                return DropdownMenuItem(
                                                  value: room,
                                                  child: Text(
                                                    'Room $room',
                                                    style: const TextStyle(
                                                      color: Colors.black87,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                );
                                              })
                                              .toList(),
                                          onChanged: (value) {
                                            setState(() {
                                              if (index <
                                                  _selectedRooms.length) {
                                                _selectedRooms[index] =
                                                    value ?? '';
                                              } else {
                                                while (_selectedRooms.length <=
                                                    index) {
                                                  _selectedRooms.add('');
                                                }
                                                _selectedRooms[index] =
                                                    value ?? '';
                                              }
                                            });
                                          },
                                          validator: (value) {
                                            if (_wantsSpecificRoom &&
                                                (value == null ||
                                                    value.isEmpty)) {
                                              return 'Please select a room';
                                            }
                                            return null;
                                          },
                                        ),
                                      );
                                    }),
                                  ),
                                ),
                              ],

                              const SizedBox(height: 24),
                              const Divider(),
                              const SizedBox(height: 16),

                              // Check-in Date
                              GestureDetector(
                                onTap: _selectCheckInDate,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.calendar_today_rounded,
                                        color: Colors.grey.shade600,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Check-in Date',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _checkInDate != null
                                                  ? DateFormat(
                                                      'MMM d, yyyy',
                                                    ).format(_checkInDate!)
                                                  : 'Select date',
                                              style: TextStyle(
                                                fontSize: 16,
                                                color: _checkInDate != null
                                                    ? Colors.black87
                                                    : Colors.grey.shade600,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        color: Colors.grey.shade400,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Check-out Date
                              GestureDetector(
                                onTap: _selectCheckOutDate,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.event_rounded,
                                        color: Colors.grey.shade600,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Check-out Date',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _checkOutDate != null
                                                  ? DateFormat(
                                                      'MMM d, yyyy',
                                                    ).format(_checkOutDate!)
                                                  : 'Select date',
                                              style: TextStyle(
                                                fontSize: 16,
                                                color: _checkOutDate != null
                                                    ? Colors.black87
                                                    : Colors.grey.shade600,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        color: Colors.grey.shade400,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Number of Nights (calculated)
                              if (_numberOfNights > 0)
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF007AFF,
                                    ).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.bed_rounded,
                                        color: Color(0xFF007AFF),
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '$_numberOfNights ${_numberOfNights == 1 ? 'night' : 'nights'}',
                                        style: const TextStyle(
                                          color: Color(0xFF007AFF),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 16),

                              // Booking Status
                              DropdownButtonFormField<String>(
                                value: _bookingStatus,
                                decoration: InputDecoration(
                                  labelText: 'Status',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                  prefixIcon: const Icon(Icons.info_rounded),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 16,
                                  ),
                                ),
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.black87,
                                ),
                                dropdownColor: Colors.white,
                                items: _statusOptions.map((status) {
                                  return DropdownMenuItem(
                                    value: status,
                                    child: Text(
                                      status,
                                      style: const TextStyle(
                                        color: Colors.black87,
                                        fontSize: 16,
                                      ),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  setState(() {
                                    _bookingStatus = value!;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Additional Notes Section
                      Text(
                        'Additional Notes',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 22,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: TextFormField(
                            controller: _notesController,
                            decoration: InputDecoration(
                              labelText: 'Notes',
                              hintText: 'Any special requests or notes...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              alignLabelWithHint: true,
                              contentPadding: const EdgeInsets.all(16),
                            ),
                            style: const TextStyle(fontSize: 16),
                            maxLines: 4,
                            textAlignVertical: TextAlignVertical.top,
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Save Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _submitBooking,
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
                            'Save Booking',
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
    int? maxLines,
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
      maxLines: maxLines ?? 1,
      validator: validator,
    );
  }
}

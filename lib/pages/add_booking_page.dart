import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
  final _guestNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _notesController = TextEditingController();

  List<String> _selectedRooms = [];
  DateTime? _checkInDate;
  DateTime? _checkOutDate;
  int _numberOfGuests = 1;
  int _numberOfRooms = 1;
  String _bookingStatus = 'Confirmed';
  bool _wantsSpecificRoom = false;

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
    _guestNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
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
        // If check-out is before check-in, adjust it
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

  void _submitBooking() {
    if (_formKey.currentState!.validate()) {
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

      // Here you would save the booking
      final selectedRoomNumbers = _selectedRooms
          .where((room) => room.isNotEmpty)
          .toList();
      final roomInfo = _wantsSpecificRoom
          ? (selectedRoomNumbers.length == 1
                ? 'Room ${selectedRoomNumbers.first}'
                : 'Rooms: ${selectedRoomNumbers.map((r) => 'Room $r').join(", ")}')
          : '$_numberOfRooms ${_numberOfRooms == 1 ? 'room' : 'rooms'} (assignment pending)';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Booking created for ${_guestNameController.text} - $roomInfo',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF34C759),
        ),
      );

      // Navigate back
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F5F7),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
          color: Colors.black87,
        ),
        title: const Text(
          'New Booking',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 17,
            color: Colors.black87,
          ),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Guest Information Section
                _buildSectionHeader('Guest Information'),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _guestNameController,
                          decoration: InputDecoration(
                            labelText: 'Guest Name',
                            hintText: 'Enter guest name',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            prefixIcon: const Icon(Icons.person_rounded),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                          ),
                          style: const TextStyle(fontSize: 16),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter guest name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _emailController,
                          decoration: InputDecoration(
                            labelText: 'Email',
                            hintText: 'guest@example.com',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            prefixIcon: const Icon(Icons.email_rounded),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                          ),
                          style: const TextStyle(fontSize: 16),
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
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _phoneController,
                          decoration: InputDecoration(
                            labelText: 'Phone Number',
                            hintText: '+1 (555) 123-4567',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            prefixIcon: const Icon(Icons.phone_rounded),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                          ),
                          style: const TextStyle(fontSize: 16),
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Number of Guests',
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline),
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
                                  icon: const Icon(Icons.add_circle_outline),
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

                const SizedBox(height: 32),

                // Booking Details Section
                _buildSectionHeader('Booking Details'),
                const SizedBox(height: 16),
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
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: () {
                                    if (_numberOfRooms > 1) {
                                      setState(() {
                                        _numberOfRooms--;
                                        // Adjust selected rooms list
                                        if (_selectedRooms.length >
                                            _numberOfRooms) {
                                          _selectedRooms = _selectedRooms
                                              .sublist(0, _numberOfRooms);
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
                                  icon: const Icon(Icons.add_circle_outline),
                                  onPressed: () {
                                    setState(() {
                                      _numberOfRooms++;
                                      // Expand selected rooms list
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
                                    // Initialize with empty strings for each room
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
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: List.generate(_numberOfRooms, (index) {
                                return Padding(
                                  padding: EdgeInsets.only(
                                    bottom: index < _numberOfRooms - 1 ? 16 : 0,
                                  ),
                                  child: DropdownButtonFormField<String>(
                                    value:
                                        index < _selectedRooms.length &&
                                            _selectedRooms[index].isNotEmpty
                                        ? _selectedRooms[index]
                                        : null,
                                    decoration: InputDecoration(
                                      labelText: _numberOfRooms == 1
                                          ? 'Select Room'
                                          : 'Room ${index + 1}',
                                      hintText: 'Choose a room',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
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
                                              !_selectedRooms.contains(room) ||
                                              _selectedRooms[index] == room,
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
                                        if (index < _selectedRooms.length) {
                                          _selectedRooms[index] = value ?? '';
                                        } else {
                                          // Ensure list is long enough
                                          while (_selectedRooms.length <=
                                              index) {
                                            _selectedRooms.add('');
                                          }
                                          _selectedRooms[index] = value ?? '';
                                        }
                                      });
                                    },
                                    validator: (value) {
                                      if (_wantsSpecificRoom &&
                                          (value == null || value.isEmpty)) {
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
                        InkWell(
                          onTap: _selectCheckInDate,
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Check-in Date',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              prefixIcon: const Icon(
                                Icons.calendar_today_rounded,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                            ),
                            child: Text(
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
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Check-out Date
                        InkWell(
                          onTap: _selectCheckOutDate,
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Check-out Date',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              prefixIcon: const Icon(
                                Icons.calendar_today_rounded,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                            ),
                            child: Text(
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
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Number of Nights (calculated)
                        if (_numberOfNights > 0)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF007AFF).withOpacity(0.1),
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
                const SizedBox(height: 32),

                // Additional Notes Section
                _buildSectionHeader('Additional Notes'),
                const SizedBox(height: 16),
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
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }
}

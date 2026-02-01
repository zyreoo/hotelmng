import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/user_model.dart';
import '../models/booking_model.dart';
import '../models/service_model.dart';
import '../services/firebase_service.dart';
import '../services/hotel_provider.dart';
import '../widgets/client_search_widget.dart';
import 'services_page.dart';

class AddBookingPage extends StatefulWidget {
  /// When set, opens in edit mode: form pre-filled and save updates this document.
  final BookingModel? existingBooking;
  final String? preselectedRoom;
  final DateTime? preselectedStartDate;
  final DateTime? preselectedEndDate;
  final int? preselectedNumberOfRooms;
  final bool? preselectedRoomsNextToEachOther;
  final List<int>? preselectedRoomsIndex;

  const AddBookingPage({
    super.key,
    this.existingBooking,
    this.preselectedRoom,
    this.preselectedStartDate,
    this.preselectedEndDate,
    this.preselectedNumberOfRooms,
    this.preselectedRoomsNextToEachOther,
    this.preselectedRoomsIndex,
  });

  @override
  State<AddBookingPage> createState() => _AddBookingPageState();
}

class _AddBookingPageState extends State<AddBookingPage> {
  final _formKey = GlobalKey<FormState>();
  final _firebaseService = FirebaseService();
  final _notesController = TextEditingController();
  final _amountPaidController = TextEditingController();
  final _pricePerNightController = TextEditingController();

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
  String _paymentMethod = 'Cash';
  String _advancePaymentMethod = 'Cash';
  bool _wantsSpecificRoom = false;
  int? _advancePercent;
  String _advanceStatus = 'not_required'; // not_required, pending, received
  final _advancePercentController = TextEditingController();
  final _advanceAmountPaidController = TextEditingController();
  bool _roomsNextToEachOther = false;

  // Add-on services (loaded from Firestore, selected for this booking)
  List<ServiceModel> _availableServices = [];
  List<BookingServiceItem> _selectedServices = [];

  // Rooms loaded from Firestore (hotel-specific)
  List<String> _roomNames = [];
  List<int>? _pendingPreselectedRoomIndexes;

  @override
  void initState() {
    super.initState();
    // Edit mode: pre-fill from full booking so multi-room stays stay unified
    if (widget.existingBooking != null) {
      final b = widget.existingBooking!;
      _selectedClient = UserModel(
        id: b.userId,
        name: b.userName,
        phone: b.userPhone,
        email: b.userEmail,
      );
      _clientNameController.text = b.userName;
      _clientPhoneController.text = b.userPhone;
      _clientEmailController.text = b.userEmail ?? '';
      _checkInDate = b.checkIn;
      _checkOutDate = b.checkOut;
      _numberOfRooms = b.numberOfRooms;
      _numberOfGuests = b.numberOfGuests;
      _bookingStatus = b.status;
      _amountPaidController.text = b.amountOfMoneyPaid > 0
          ? b.amountOfMoneyPaid.toString()
          : '';
      _pricePerNightController.text =
          b.pricePerNight != null && b.pricePerNight! > 0
              ? b.pricePerNight.toString()
              : '';
      _paymentMethod = b.paymentMethod.isNotEmpty
          ? b.paymentMethod
          : BookingModel.paymentMethods.first;
      _advancePercent = b.advancePercent;
      _advancePercentController.text =
          b.advancePercent != null ? b.advancePercent.toString() : '';
      _advanceAmountPaidController.text =
          b.advanceAmountPaid > 0 ? b.advanceAmountPaid.toString() : '';
      _advancePaymentMethod = (b.advancePaymentMethod != null &&
              b.advancePaymentMethod!.isNotEmpty)
          ? b.advancePaymentMethod!
          : BookingModel.paymentMethods.first;
      _advanceStatus = (b.advanceStatus != null &&
              BookingModel.advanceStatusOptions.contains(b.advanceStatus))
          ? b.advanceStatus!
          : (b.advancePercent != null && b.advancePercent! > 0
              ? (b.advanceAmountPaid >= (b.calculatedTotal * b.advancePercent! / 100).round()
                  ? 'received'
                  : 'pending')
              : 'not_required');
      _notesController.text = b.notes ?? '';
      _wantsSpecificRoom =
          b.selectedRooms != null && b.selectedRooms!.isNotEmpty;
      _roomsNextToEachOther = b.nextToEachOther;
      _selectedRooms = b.selectedRooms != null
          ? List<String>.from(b.selectedRooms!)
          : <String>[];
      while (_selectedRooms.length < _numberOfRooms) {
        _selectedRooms.add('');
      }
      _selectedServices = b.selectedServices != null
          ? List<BookingServiceItem>.from(b.selectedServices!)
          : <BookingServiceItem>[];
    } else {
      if (widget.preselectedRoom != null) {
        _selectedRooms = [widget.preselectedRoom!];
        _wantsSpecificRoom = true;
        _numberOfRooms = 1;
      }
      if (widget.preselectedNumberOfRooms != null &&
          widget.preselectedNumberOfRooms! > 0) {
        _numberOfRooms = widget.preselectedNumberOfRooms!;
        while (_selectedRooms.length < _numberOfRooms) {
          _selectedRooms.add('');
        }
      }
      _checkInDate = widget.preselectedStartDate;
      _checkOutDate = widget.preselectedEndDate;
      if (widget.preselectedRoomsNextToEachOther == true &&
          _numberOfRooms >= 2) {
        _roomsNextToEachOther = true;
      }
      if (widget.preselectedRoomsIndex != null &&
          widget.preselectedRoomsIndex!.isNotEmpty) {
        _wantsSpecificRoom = true;
        if (_numberOfRooms < widget.preselectedRoomsIndex!.length) {
          _numberOfRooms = widget.preselectedRoomsIndex!.length;
        }
        _selectedRooms = List.generate(_numberOfRooms, (_) => '');
        _pendingPreselectedRoomIndexes = widget.preselectedRoomsIndex;
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final hotelId = HotelProvider.of(context).hotelId;
    if (hotelId != null) {
      _loadServices(hotelId);
      _loadRooms(hotelId);
    }
  }

  Future<void> _loadServices(String hotelId) async {
    final list = await _firebaseService.getServices(hotelId);
    if (mounted) setState(() => _availableServices = list);
  }

  Future<void> _loadRooms(String hotelId) async {
    final list = await _firebaseService.getRooms(hotelId);
    if (!mounted) return;
    final names = list.map((r) => r.name).toList();
    List<int>? pending = _pendingPreselectedRoomIndexes;
    if (pending != null && pending.isNotEmpty && names.isNotEmpty) {
      _pendingPreselectedRoomIndexes = null;
      while (_selectedRooms.length < _numberOfRooms) {
        _selectedRooms.add('');
      }
      for (var i = 0; i < pending.length && i < _selectedRooms.length; i++) {
        final roomIndex = pending[i];
        if (roomIndex >= 0 && roomIndex < names.length) {
          _selectedRooms[i] = names[roomIndex];
        }
      }
    }
    setState(() => _roomNames = names);
  }

  /// Finds N available rooms for [checkIn, checkOut). Returns room names to assign, or null if not enough space.
  /// When [roomsNextToEachOther] is true, returns the first contiguous block of N rooms in _roomNames order.
  Future<List<String>?> _findAvailableRooms(String hotelId) async {
    if (_checkInDate == null || _checkOutDate == null || _roomNames.isEmpty) return null;
    final checkIn = DateTime(_checkInDate!.year, _checkInDate!.month, _checkInDate!.day);
    final checkOut = DateTime(_checkOutDate!.year, _checkOutDate!.month, _checkOutDate!.day);
    if (!checkOut.isAfter(checkIn)) return null;

    // Fetch bookings that might overlap the range (wide window)
    final start = checkIn.subtract(const Duration(days: 60));
    final end = checkOut.add(const Duration(days: 60));
    final all = await _firebaseService.getBookings(hotelId, startDate: start, endDate: end);
    final overlapping = all.where((b) {
      if (b.status == 'Cancelled') return false;
      if (widget.existingBooking != null && b.id == widget.existingBooking!.id) return false;
      final bStart = DateTime(b.checkIn.year, b.checkIn.month, b.checkIn.day);
      final bEnd = DateTime(b.checkOut.year, b.checkOut.month, b.checkOut.day);
      return bStart.isBefore(checkOut) && bEnd.isAfter(checkIn);
    }).toList();

    // For each night in [checkIn, checkOut), which rooms are occupied?
    final occupiedByNight = <DateTime, Set<String>>{};
    for (var d = checkIn; d.isBefore(checkOut); d = d.add(const Duration(days: 1))) {
      occupiedByNight[d] = {};
      for (final b in overlapping) {
        if (b.selectedRooms == null || b.selectedRooms!.isEmpty) continue;
        final bStart = DateTime(b.checkIn.year, b.checkIn.month, b.checkIn.day);
        final bEnd = DateTime(b.checkOut.year, b.checkOut.month, b.checkOut.day);
        if (!d.isBefore(bStart) && d.isBefore(bEnd)) {
          for (final r in b.selectedRooms!) {
            occupiedByNight[d]!.add(r);
          }
        }
      }
    }

    // Rooms that are free for every night in the range
    final available = <String>[];
    for (final room in _roomNames) {
      var free = true;
      for (var d = checkIn; d.isBefore(checkOut); d = d.add(const Duration(days: 1))) {
        if (occupiedByNight[d]!.contains(room)) {
          free = false;
          break;
        }
      }
      if (free) available.add(room);
    }

    final n = _numberOfRooms;
    if (available.length < n) return null;

    if (_roomsNextToEachOther && n >= 2) {
      // First contiguous block of N in _roomNames order
      for (var i = 0; i <= _roomNames.length - n; i++) {
        final block = _roomNames.sublist(i, i + n);
        if (block.every((r) => available.contains(r))) return block;
      }
      return null;
    }

    // First N available (in _roomNames order)
    return available.take(n).toList();
  }

  int get _servicesSubtotal =>
      _selectedServices.fold(0, (sum, s) => sum + s.lineTotal);

  int get _pricePerNight =>
      int.tryParse(_pricePerNightController.text.trim()) ?? 0;

  int get _roomSubtotal =>
      _numberOfNights * _numberOfRooms * _pricePerNight;

  int get _suggestedTotal => _roomSubtotal + _servicesSubtotal;

  int get _advanceAmountRequired =>
      _advancePercent != null && _advancePercent! > 0 && _suggestedTotal > 0
          ? (_suggestedTotal * _advancePercent! / 100).round()
          : 0;

  int get _advanceAmountPaid =>
      int.tryParse(_advanceAmountPaidController.text.trim()) ?? 0;

  /// Derived status for display (paid/waiting/not_required). Stored status is _advanceStatus (not_required/pending/received).
  String get _advanceDisplayStatus {
    if (_advancePercent == null || _advancePercent! <= 0) return 'not_required';
    if (_advanceStatus == 'received') return 'paid';
    if (_advanceAmountPaid >= _advanceAmountRequired) return 'paid';
    return 'waiting';
  }

  int get _remainingBalance =>
      (_suggestedTotal - _advanceAmountPaid).clamp(0, _suggestedTotal);

  void _updateAmountFromSuggested() {
    final suggested = _suggestedTotal;
    if (suggested > 0 &&
        (int.tryParse(_amountPaidController.text.trim()) ?? 0) == 0) {
      _amountPaidController.text = suggested.toString();
    }
  }

  void _setServiceQuantity(ServiceModel service, int quantity) {
    setState(() {
      _selectedServices.removeWhere((s) => s.serviceId == service.id);
      if (quantity > 0 && service.id != null) {
        _selectedServices.add(BookingServiceItem(
          serviceId: service.id!,
          name: service.name,
          unitPrice: service.price,
          quantity: quantity,
        ));
      }
      _updateAmountFromSuggested();
    });
  }

  int _getServiceQuantity(ServiceModel service) {
    try {
      return _selectedServices
          .firstWhere((s) => s.serviceId == service.id)
          .quantity;
    } catch (_) {
      return 0;
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    _amountPaidController.dispose();
    _pricePerNightController.dispose();
    _advancePercentController.dispose();
    _advanceAmountPaidController.dispose();
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
        final hotelId = HotelProvider.of(context).hotelId;
        if (hotelId == null) {
          if (mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No hotel selected')),
            );
          }
          return;
        }

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
            hotelId,
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
            userId = await _firebaseService.createUser(hotelId, clientToUse);
            // Create user object with the new ID
            userToUse = clientToUse.copyWith(id: userId);
            // Update selected client for future use
            setState(() {
              _selectedClient = userToUse;
              _showCreateClientForm = false;
            });
          }
        }

        // Step 2: Resolve room assignment (specific rooms or auto-assign where there is space)
        List<String>? selectedRoomNumbers;
        if (_wantsSpecificRoom) {
          selectedRoomNumbers = _selectedRooms.where((room) => room.isNotEmpty).toList();
        } else {
          final assigned = await _findAvailableRooms(hotelId);
          if (assigned == null || assigned.length != _numberOfRooms) {
            if (mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Not enough rooms available for this period. Try different dates or fewer rooms, or select specific rooms.',
                  ),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
            return;
          }
          selectedRoomNumbers = assigned;
        }

        // Step 3: Build booking with user information

        final amountPaid = int.tryParse(_amountPaidController.text.trim()) ?? 0;
        final booking = BookingModel(
          id: widget.existingBooking?.id,
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
          createdAt: widget.existingBooking?.createdAt,
          amountOfMoneyPaid: amountPaid,
          paymentMethod: _paymentMethod,
          pricePerNight: _pricePerNight > 0 ? _pricePerNight : null,
          selectedServices: _selectedServices.isEmpty
              ? null
              : List<BookingServiceItem>.from(_selectedServices),
          advancePercent: () {
            final p =
                int.tryParse(_advancePercentController.text.trim());
            return p != null && p > 0 ? p : null;
          }(),
          advanceAmountPaid:
              int.tryParse(_advanceAmountPaidController.text.trim()) ?? 0,
          advancePaymentMethod: _advancePaymentMethod,
          advanceStatus: _advanceStatus,
        );

        // Step 4: Update or create in Firebase
        if (widget.existingBooking != null) {
          await _firebaseService.updateBooking(hotelId, booking);
        } else {
          await _firebaseService.createBooking(hotelId, booking);
        }

        // Close loading dialog
        if (mounted) Navigator.pop(context);

        // Show success (include assigned rooms when auto-assigned)
        if (mounted) {
          final roomInfo = selectedRoomNumbers.isNotEmpty
              ? ' (${selectedRoomNumbers.join(', ')})'
              : '';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                widget.existingBooking != null
                    ? 'Booking updated for ${userToUse.name}'
                    : 'Booking created for ${userToUse.name}$roomInfo',
              ),
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
    final horizontalPadding = MediaQuery.of(context).size.width >= 768 ? 24.0 : 16.0;
    
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
                                  widget.existingBooking != null
                                      ? 'Edit Booking'
                                      : 'New Booking',
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
                                  widget.existingBooking != null
                                      ? 'Update reservation'
                                      : 'Create a new reservation',
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
                                  initialClient: _selectedClient,
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
                                          items: _roomNames
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
                                items: BookingModel.statusOptions
                                    .map((status) {
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

                      // Price section (room + services + total) — last above Additional Notes
                      Text(
                        'Price',
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
                              // Price per night
                              Text(
                                'Price per night (per room)',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _pricePerNightController,
                                decoration: InputDecoration(
                                  hintText: 'e.g. 100',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                  prefixIcon: const Icon(Icons.euro_rounded),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                ),
                                keyboardType: TextInputType.number,
                                onChanged: (_) {
                                  setState(() {});
                                  _updateAmountFromSuggested();
                                },
                              ),
                              if (_numberOfNights > 0 && _pricePerNight > 0) ...[
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.nights_stay_rounded,
                                      size: 18,
                                      color: Colors.grey.shade600,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '$_numberOfNights night${_numberOfNights == 1 ? '' : 's'} × $_numberOfRooms room${_numberOfRooms == 1 ? '' : 's'} × $_pricePerNight = $_roomSubtotal',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '$_roomSubtotal',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF007AFF),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 20),
                              const Divider(height: 1),
                              const SizedBox(height: 16),
                              // Services
                              Row(
                                children: [
                                  Text(
                                    'Services',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton.icon(
                                    onPressed: () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const ServicesPage(),
                                        ),
                                      );
                                      final hid = HotelProvider.of(context).hotelId;
                                      if (hid != null) _loadServices(hid);
                                    },
                                    icon: const Icon(Icons.add_circle_outline,
                                        size: 18),
                                    label: const Text('Add more services'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: const Color(0xFF007AFF),
                                    ),
                                  ),
                                ],
                              ),
                              if (_availableServices.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: Text(
                                    'No services yet. Tap "Add more services" to add breakfast, spa, sauna, etc.',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                )
                              else
                                ..._availableServices.map((service) {
                                  final qty = _getServiceQuantity(service);
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                service.name,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 15,
                                                ),
                                              ),
                                              Text(
                                                '${service.price} per unit',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(
                                                  Icons.remove_circle_outline),
                                              onPressed: qty > 0
                                                  ? () => _setServiceQuantity(
                                                        service,
                                                        qty - 1,
                                                      )
                                                  : null,
                                              color: const Color(0xFF007AFF),
                                            ),
                                            SizedBox(
                                              width: 28,
                                              child: Text(
                                                '$qty',
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 15,
                                                ),
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                  Icons.add_circle_outline),
                                              onPressed: () =>
                                                  _setServiceQuantity(
                                                service,
                                                qty + 1,
                                              ),
                                              color: const Color(0xFF007AFF),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              if (_selectedServices.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                ..._selectedServices.map((s) => Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            '${s.name} — ${s.quantity} × ${s.unitPrice}',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                          Text(
                                            '${s.lineTotal}',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                              color: Colors.grey.shade800,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Services subtotal',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                      ),
                                    ),
                                    Text(
                                      '$_servicesSubtotal',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                        color: Color(0xFF007AFF),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 20),
                              const Divider(height: 1),
                              const SizedBox(height: 16),
                              // Suggested total
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Suggested total (room + services)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                      color: Colors.grey.shade800,
                                    ),
                                  ),
                                  Text(
                                    '$_suggestedTotal',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 17,
                                      color: Color(0xFF007AFF),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              const Divider(height: 1),
                              const SizedBox(height: 16),
                              // Advance payment
                              Text(
                                'Advance payment',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: TextFormField(
                                      controller: _advancePercentController,
                                      decoration: InputDecoration(
                                        labelText: 'Advance %',
                                        hintText: 'e.g. 30',
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        filled: true,
                                        fillColor: Colors.grey.shade50,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 14,
                                        ),
                                      ),
                                      keyboardType: TextInputType.number,
                                      onChanged: (_) {
                                        setState(() {
                                          final p =
                                              int.tryParse(
                                                      _advancePercentController
                                                          .text.trim()) ??
                                                  0;
                                          _advancePercent =
                                              p > 0 ? p : null;
                                          if (p > 0 &&
                                              _advanceStatus == 'not_required') {
                                            _advanceStatus = 'pending';
                                          }
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 2,
                                    child: TextFormField(
                                      controller:
                                          _advanceAmountPaidController,
                                      decoration: InputDecoration(
                                        labelText: 'Advance paid',
                                        hintText: '0',
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        filled: true,
                                        fillColor: Colors.grey.shade50,
                                        prefixIcon: const Icon(
                                            Icons.payments_rounded,
                                            size: 20),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 14,
                                        ),
                                      ),
                                      keyboardType: TextInputType.number,
                                      onChanged: (_) {
                                        setState(() {
                                          // From advance paid, calculate and update the %
                                          final paid = int.tryParse(
                                                  _advanceAmountPaidController
                                                      .text
                                                      .trim()) ??
                                              0;
                                          if (_suggestedTotal > 0 &&
                                              paid >= 0) {
                                            final p = (paid * 100 /
                                                    _suggestedTotal)
                                                .round();
                                            _advancePercent =
                                                p > 0 ? p : null;
                                            _advancePercentController.text =
                                                p > 0 ? p.toString() : '';
                                          }
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              if (_advancePercent != null &&
                                  _advancePercent! > 0 &&
                                  _suggestedTotal > 0) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Required: $_advanceAmountRequired ($_advancePercent% of total $_suggestedTotal)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                value: BookingModel.paymentMethods
                                        .contains(_advancePaymentMethod)
                                    ? _advancePaymentMethod
                                    : BookingModel.paymentMethods.first,
                                decoration: InputDecoration(
                                  labelText: 'Advance payment method',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                ),
                                items: BookingModel.paymentMethods
                                    .map((m) => DropdownMenuItem(
                                          value: m,
                                          child: Text(m),
                                        ))
                                    .toList(),
                                onChanged: (v) => setState(() {
                                      _advancePaymentMethod =
                                          v ?? BookingModel.paymentMethods.first;
                                    }),
                              ),
                              const SizedBox(height: 12),
                              // Advance status: received or pending (when advance is used)
                              if (_advancePercent != null &&
                                  _advancePercent! > 0) ...[
                                Text(
                                  'Advance received?',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    ChoiceChip(
                                      label: const Text('Pending'),
                                      selected: _advanceStatus == 'pending',
                                      onSelected: (v) => setState(() {
                                            _advanceStatus = 'pending';
                                          }),
                                      selectedColor: const Color(0xFFFF9500)
                                          .withOpacity(0.3),
                                    ),
                                    const SizedBox(width: 8),
                                    ChoiceChip(
                                      label: const Text('Received'),
                                      selected: _advanceStatus == 'received',
                                      onSelected: (v) => setState(() {
                                            _advanceStatus = 'received';
                                          }),
                                      selectedColor: const Color(0xFF34C759)
                                          .withOpacity(0.3),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                              ],
                              // Remaining balance (they owe you)
                              if (_suggestedTotal > 0) ...[
                                Row(
                                  children: [
                                    Icon(Icons.account_balance_wallet_rounded,
                                        size: 18,
                                        color: Colors.grey.shade700),
                                    const SizedBox(width: 8),
                                    Text(
                                      'They owe you: $_remainingBalance',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: _remainingBalance > 0
                                            ? const Color(0xFFFF9500)
                                            : Colors.grey.shade800,
                                      ),
                                    ),
                                    Text(
                                      ' (total $_suggestedTotal − advance $_advanceAmountPaid)',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                              ],
                              Builder(
                                builder: (context) {
                                  if (_advanceDisplayStatus == 'not_required') {
                                    return Row(
                                      children: [
                                        Icon(Icons.info_outline_rounded,
                                            size: 18,
                                            color: Colors.grey.shade600),
                                        const SizedBox(width: 8),
                                        Text(
                                          'No advance required',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ],
                                    );
                                  }
                                  if (_advanceDisplayStatus == 'paid') {
                                    return Row(
                                      children: [
                                        Icon(Icons.check_circle_rounded,
                                            size: 18,
                                            color: const Color(0xFF34C759)),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Advance paid ($_advanceAmountPaid) — $_advancePaymentMethod',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey.shade800,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    );
                                  }
                                  return Row(
                                    children: [
                                      Icon(Icons.schedule_rounded,
                                          size: 18,
                                          color: const Color(0xFFFF9500)),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Waiting for advance: $_advanceAmountPaid / $_advanceAmountRequired ($_advancePercent%)',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey.shade800,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 16),
                              // Amount paid (total)
                              TextFormField(
                                controller: _amountPaidController,
                                decoration: InputDecoration(
                                  labelText: 'Amount paid (total)',
                                  hintText: '0 or same as suggested total',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                  prefixIcon: const Icon(Icons.payments_rounded),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 16,
                                  ),
                                ),
                                style: const TextStyle(fontSize: 16),
                                keyboardType: TextInputType.number,
                              ),
                              const SizedBox(height: 16),
                              // Payment method
                              DropdownButtonFormField<String>(
                                value: BookingModel.paymentMethods
                                        .contains(_paymentMethod)
                                    ? _paymentMethod
                                    : BookingModel.paymentMethods.first,
                                decoration: InputDecoration(
                                  labelText: 'Payment method',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                  prefixIcon: const Icon(
                                    Icons.credit_card_rounded,
                                  ),
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
                                items: BookingModel.paymentMethods
                                    .map((method) {
                                  return DropdownMenuItem(
                                    value: method,
                                    child: Text(
                                      method,
                                      style: const TextStyle(
                                        color: Colors.black87,
                                        fontSize: 16,
                                      ),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  setState(() {
                                    _paymentMethod = value ?? 'Cash';
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

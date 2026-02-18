import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/user_model.dart';
import '../models/booking_model.dart';
import '../models/room_model.dart';
import '../models/service_model.dart';
import '../services/firebase_service.dart';
import '../services/hotel_provider.dart';
import '../services/auth_provider.dart';
import '../utils/currency_formatter.dart';
import '../utils/money_input_formatter.dart';
import '../utils/stayora_colors.dart';
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
  List<RoomModel> _roomModels = [];
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
          ? CurrencyFormatter.formatStoredAmountForInput(b.amountOfMoneyPaid)
          : '';
      _pricePerNightController.text =
          b.pricePerNight != null && b.pricePerNight! > 0
              ? CurrencyFormatter.formatStoredAmountForInput(b.pricePerNight!)
              : '';
      _paymentMethod = b.paymentMethod.isNotEmpty
          ? b.paymentMethod
          : BookingModel.paymentMethods.first;
      _advancePercent = b.advancePercent;
      _advancePercentController.text =
          b.advancePercent != null ? b.advancePercent.toString() : '';
      _advanceAmountPaidController.text =
          b.advanceAmountPaid > 0
              ? CurrencyFormatter.formatStoredAmountForInput(b.advanceAmountPaid)
              : '';
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
    final userId = AuthScopeData.of(context).uid;
    if (hotelId != null && userId != null) {
      _loadServices(userId, hotelId);
      _loadRooms(userId, hotelId);
    }
  }

  Future<void> _loadServices(String userId, String hotelId) async {
    final list = await _firebaseService.getServices(userId, hotelId);
    if (mounted) setState(() => _availableServices = list);
  }

  Future<void> _loadRooms(String userId, String hotelId) async {
    final list = await _firebaseService.getRooms(userId, hotelId);
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
    setState(() {
      _roomNames = names;
      _roomModels = list;
    });
  }

  /// Build a map from room name to room ID for the current hotel's rooms.
  Map<String, String> get _roomNameToId =>
      {for (final r in _roomModels) if (r.id != null) r.name: r.id!};

  /// Finds N available rooms for [checkIn, checkOut). Returns room names to assign, or null if not enough space.
  /// When [roomsNextToEachOther] is true, returns the first contiguous block of N rooms in _roomNames order.
  Future<List<String>?> _findAvailableRooms(String userId, String hotelId) async {
    if (_checkInDate == null || _checkOutDate == null || _roomNames.isEmpty) return null;
    final checkIn = DateTime(_checkInDate!.year, _checkInDate!.month, _checkInDate!.day);
    final checkOut = DateTime(_checkOutDate!.year, _checkOutDate!.month, _checkOutDate!.day);
    if (!checkOut.isAfter(checkIn)) return null;

    // Fetch bookings that might overlap the range (wide window)
    final start = checkIn.subtract(const Duration(days: 60));
    final end = checkOut.add(const Duration(days: 60));
    final all = await _firebaseService.getBookings(userId, hotelId, startDate: start, endDate: end);
    final overlapping = all.where((b) {
      if (b.status == 'Cancelled' || b.status == 'Waiting list') return false;
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

  /// Returns true if the currently selected specific rooms are free for every night in [checkIn, checkOut).
  /// Excludes Cancelled and Waiting list from occupancy; excludes current booking when editing.
  Future<bool> _areSelectedRoomsAvailable(String userId, String hotelId) async {
    if (_checkInDate == null || _checkOutDate == null || _roomNames.isEmpty) return false;
    final roomsToCheck = _selectedRooms.where((r) => r.isNotEmpty).toList();
    if (roomsToCheck.isEmpty) return false;
    final checkIn = DateTime(_checkInDate!.year, _checkInDate!.month, _checkInDate!.day);
    final checkOut = DateTime(_checkOutDate!.year, _checkOutDate!.month, _checkOutDate!.day);
    if (!checkOut.isAfter(checkIn)) return false;

    final start = checkIn.subtract(const Duration(days: 60));
    final end = checkOut.add(const Duration(days: 60));
    final all = await _firebaseService.getBookings(userId, hotelId, startDate: start, endDate: end);
    final overlapping = all.where((b) {
      if (b.status == 'Cancelled' || b.status == 'Waiting list') return false;
      if (widget.existingBooking != null && b.id == widget.existingBooking!.id) return false;
      final bStart = DateTime(b.checkIn.year, b.checkIn.month, b.checkIn.day);
      final bEnd = DateTime(b.checkOut.year, b.checkOut.month, b.checkOut.day);
      return bStart.isBefore(checkOut) && bEnd.isAfter(checkIn);
    }).toList();

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

    for (final room in roomsToCheck) {
      for (var d = checkIn; d.isBefore(checkOut); d = d.add(const Duration(days: 1))) {
        if (occupiedByNight[d]!.contains(room)) return false;
      }
    }
    return true;
  }

  int get _servicesSubtotal =>
      _selectedServices.fold(0, (sum, s) => sum + s.lineTotal);

  int get _pricePerNight =>
      CurrencyFormatter.parseMoneyStringToCents(_pricePerNightController.text.trim());

  int get _roomSubtotal =>
      _numberOfNights * _numberOfRooms * _pricePerNight;

  int get _suggestedTotal => _roomSubtotal + _servicesSubtotal;

  int get _advanceAmountRequired =>
      _advancePercent != null && _advancePercent! > 0 && _suggestedTotal > 0
          ? (_suggestedTotal * _advancePercent! / 100).round()
          : 0;

  int get _advanceAmountPaid =>
      CurrencyFormatter.parseMoneyStringToCents(_advanceAmountPaidController.text.trim());

  /// Derived status for display (paid/waiting/not_required). Stored status is _advanceStatus (not_required/pending/received).
  String get _advanceDisplayStatus {
    if (_advancePercent == null || _advancePercent! <= 0) return 'not_required';
    if (_advanceStatus == 'received') return 'paid';
    if (_advanceAmountPaid >= _advanceAmountRequired) return 'paid';
    return 'waiting';
  }

  int get _remainingBalance =>
      (_suggestedTotal - _advanceAmountPaid).clamp(0, _suggestedTotal);

  int get _maxRooms => _roomNames.isEmpty ? 1 : _roomNames.length;

  Future<int?> _showNumberInputDialog({
    required String title,
    required int initialValue,
    required int minValue,
    int? maxValue,
  }) async {
    final controller = TextEditingController(text: initialValue.toString());
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Enter a number',
            ),
            validator: (value) {
              final v = int.tryParse(value?.trim() ?? '');
              if (v == null) return 'Enter a valid number';
              if (v < minValue) {
                return 'Must be at least $minValue';
              }
              if (maxValue != null && v > maxValue) {
                return 'Maximum is $maxValue';
              }
              return null;
            },
            onFieldSubmitted: (_) {
              if (formKey.currentState!.validate()) {
                Navigator.of(ctx).pop(int.parse(controller.text.trim()));
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(ctx).pop(int.parse(controller.text.trim()));
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    return result;
  }

  void _updateNumberOfRooms(int newCount) {
    newCount = newCount.clamp(1, _maxRooms);
    setState(() {
      if (newCount < _numberOfRooms) {
        _numberOfRooms = newCount;
        if (_selectedRooms.length > _numberOfRooms) {
          _selectedRooms = _selectedRooms.sublist(0, _numberOfRooms);
        }
        if (_numberOfRooms < 2) {
          _roomsNextToEachOther = false;
        }
      } else if (newCount > _numberOfRooms) {
        _numberOfRooms = newCount;
        while (_selectedRooms.length < _numberOfRooms) {
          _selectedRooms.add('');
        }
      }
    });
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
        )        );
      }
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
      builder: (context, child) => child!,
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
      builder: (context, child) => child!,
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

      // Show loading on the same navigator as this page so we can close it correctly
      showDialog(
        context: context,
        barrierDismissible: false,
        useRootNavigator: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      try {
        final hotelId = HotelProvider.of(context).hotelId;
        final authUserId = AuthScopeData.of(context).uid;
        if (hotelId == null || authUserId == null) {
          if (mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No hotel selected or not authenticated')),
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
            authUserId,
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
            userId = await _firebaseService.createUser(authUserId, hotelId, clientToUse);
            // Create user object with the new ID
            userToUse = clientToUse.copyWith(id: userId);
            // Update selected client for future use
            setState(() {
              _selectedClient = userToUse;
              _showCreateClientForm = false;
            });
          }
        }

        // Step 2: Resolve room assignment or detect over capacity (then save as Waiting list)
        // When "next to each other" is checked, always use the first available contiguous block; if none, waiting list.
        List<String>? selectedRoomNumbers;
        bool overCapacity = false;
        if (_roomsNextToEachOther && _numberOfRooms >= 2) {
          // Next to each other: assign first contiguous block only; no contiguous block → waiting list
          final assigned = await _findAvailableRooms(authUserId, hotelId);
          if (assigned == null || assigned.length != _numberOfRooms) {
            overCapacity = true;
            selectedRoomNumbers = null;
          } else {
            selectedRoomNumbers = assigned;
          }
        } else if (_wantsSpecificRoom) {
          final rooms = _selectedRooms.where((room) => room.isNotEmpty).toList();
          if (rooms.length != _numberOfRooms) {
            if (mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Please select all $_numberOfRooms ${_numberOfRooms == 1 ? 'room' : 'rooms'}',
                  ),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
            return;
          }
          final available = await _areSelectedRoomsAvailable(authUserId, hotelId);
          if (!available) {
            overCapacity = true;
            selectedRoomNumbers = rooms;
          } else {
            selectedRoomNumbers = rooms;
          }
        } else {
          final assigned = await _findAvailableRooms(authUserId, hotelId);
          if (assigned == null || assigned.length != _numberOfRooms) {
            overCapacity = true;
            selectedRoomNumbers = null;
          } else {
            selectedRoomNumbers = assigned;
          }
        }

        // Step 3: Build booking with user information (use 'Waiting list' when over capacity)
        final statusToSave = overCapacity ? 'Waiting list' : _bookingStatus;
        final amountPaid = CurrencyFormatter.parseMoneyStringToCents(_amountPaidController.text.trim());
        final nameToId = _roomNameToId;
        final selectedRoomIds = selectedRoomNumbers
            ?.map((name) => nameToId[name])
            .whereType<String>()
            .toList();
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
          selectedRoomIds: selectedRoomIds?.isNotEmpty == true ? selectedRoomIds : null,
          numberOfGuests: _numberOfGuests,
          status: statusToSave,
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
              CurrencyFormatter.parseMoneyStringToCents(_advanceAmountPaidController.text.trim()),
          advancePaymentMethod: _advancePaymentMethod,
          advanceStatus: _advanceStatus,
        );

        // Step 4: Update or create in Firebase
        if (widget.existingBooking != null) {
          await _firebaseService.updateBooking(authUserId, hotelId, booking);
        } else {
          await _firebaseService.createBooking(authUserId, hotelId, booking);
        }

        // Close loading dialog
        if (mounted) Navigator.pop(context);

        // Show success (or waiting-list message when over capacity)
        if (mounted) {
          if (overCapacity) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'No capacity for these dates — added to waiting list. You can move it to confirmed when a room becomes available.',
                ),
                behavior: SnackBarBehavior.floating,
                backgroundColor: StayoraColors.purple,
              ),
            );
          } else {
            final roomInfo = selectedRoomNumbers != null && selectedRoomNumbers.isNotEmpty
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
                backgroundColor: StayoraColors.success,
              ),
            );
          }
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

  Future<void> _confirmDeleteBooking() async {
    final booking = widget.existingBooking;
    if (booking == null || booking.id == null) return;
    final userId = AuthScopeData.of(context).uid;
    final hotelId = HotelProvider.of(context).hotelId;
    if (userId == null || hotelId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete booking?',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 17,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        content: Text(
          'This will permanently delete the booking for ${booking.userName}. This action cannot be undone.',
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: StayoraColors.blue)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _firebaseService.deleteBooking(userId, hotelId, booking.id!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Booking for ${booking.userName} deleted'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: StayoraColors.blue,
        ),
      );
      if (Navigator.canPop(context)) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = MediaQuery.of(context).size.width >= 768 ? 24.0 : 16.0;
    final hotel = HotelProvider.of(context).currentHotel;
    final currencyFormatter = CurrencyFormatter.fromHotel(hotel);
    
    return Scaffold(
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
                              color: StayoraColors.blue,
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
                                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          if (widget.existingBooking != null)
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded),
                              onPressed: _confirmDeleteBooking,
                              color: Theme.of(context).colorScheme.error,
                              tooltip: 'Delete booking',
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
                              Builder(
                                builder: (context) {
                                  final cs = Theme.of(context).colorScheme;
                                  return Container(
                                    decoration: BoxDecoration(
                                      color: cs.surfaceContainerHighest,
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
                                                    ? cs.surface
                                                    : Colors.transparent,
                                                borderRadius: BorderRadius.circular(8),
                                                boxShadow: !_showCreateClientForm
                                                    ? [
                                                        BoxShadow(
                                                          color: cs.shadow.withOpacity(0.05),
                                                          blurRadius: 8,
                                                          offset: const Offset(0, 2),
                                                        ),
                                                      ]
                                                    : null,
                                              ),
                                              child: Center(
                                                child: Text(
                                                  'Search Client',
                                                  style: TextStyle(
                                                    color: !_showCreateClientForm
                                                        ? cs.onSurface
                                                        : cs.onSurfaceVariant,
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
                                                    ? cs.surface
                                                    : Colors.transparent,
                                                borderRadius: BorderRadius.circular(8),
                                                boxShadow: _showCreateClientForm
                                                    ? [
                                                        BoxShadow(
                                                          color: cs.shadow.withOpacity(0.05),
                                                          blurRadius: 8,
                                                          offset: const Offset(0, 2),
                                                        ),
                                                      ]
                                                    : null,
                                              ),
                                              child: Center(
                                                child: Text(
                                                  'New Client',
                                                  style: TextStyle(
                                                    color: _showCreateClientForm
                                                        ? cs.onSurface
                                                        : cs.onSurfaceVariant,
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
                                  );
                                },
                              ),
                              const SizedBox(height: 20),

                              // Show search or create form
                              if (!_showCreateClientForm) ...[
                                ClientSearchWidget(
                                  hotelId: HotelProvider.of(context).hotelId,
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
                                        color: StayoraColors.blue,
                                      ),
                                      GestureDetector(
                                        onTap: () async {
                                          final value = await _showNumberInputDialog(
                                            title: 'Number of guests',
                                            initialValue: _numberOfGuests,
                                            minValue: 1,
                                          );
                                          if (value != null) {
                                            setState(() {
                                              _numberOfGuests = value;
                                            });
                                          }
                                        },
                                        child: Container(
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
                                        color: StayoraColors.blue,
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
                              // Check-in Date
                              GestureDetector(
                                onTap: _selectCheckInDate,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
                                    ),
                                  ),
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.calendar_today_rounded,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                                                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                                                    ? Theme.of(context).colorScheme.onSurface
                                                    : Theme.of(context).colorScheme.onSurfaceVariant,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
                                    ),
                                  ),
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.event_rounded,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                                                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                                                    ? Theme.of(context).colorScheme.onSurface
                                                    : Theme.of(context).colorScheme.onSurfaceVariant,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),

                              const Divider(),
                              const SizedBox(height: 16),

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
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                                            _updateNumberOfRooms(
                                              _numberOfRooms - 1,
                                            );
                                          }
                                        },
                                        color: StayoraColors.blue,
                                      ),
                                      GestureDetector(
                                        onTap: () async {
                                          final value = await _showNumberInputDialog(
                                            title: 'Number of rooms',
                                            initialValue: _numberOfRooms,
                                            minValue: 1,
                                            maxValue: _maxRooms,
                                          );
                                          if (value != null) {
                                            _updateNumberOfRooms(value);
                                          }
                                        },
                                        child: Container(
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
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.add_circle_outline,
                                        ),
                                        onPressed: () {
                                          _updateNumberOfRooms(
                                            _numberOfRooms + 1,
                                          );
                                        },
                                        color: StayoraColors.blue,
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
                                      activeColor: StayoraColors.blue,
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
                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                                    activeColor: StayoraColors.blue,
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
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                                      final availableOptions = _roomNames
                                          .where(
                                            (room) =>
                                                !_selectedRooms.contains(room) ||
                                                _selectedRooms[index] == room,
                                          )
                                          .toList();
                                      final currentValue = index <
                                                  _selectedRooms.length &&
                                              _selectedRooms[index].isNotEmpty
                                          ? _selectedRooms[index]
                                          : null;
                                      final valueNotInList = currentValue !=
                                          null &&
                                          !availableOptions
                                              .contains(currentValue);
                                      final items = [
                                        ...availableOptions.map(
                                          (room) => DropdownMenuItem(
                                            value: room,
                                            child: Text(
                                              'Room $room',
                                              style: TextStyle(
                                                color: Theme.of(context).colorScheme.onSurface,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (valueNotInList)
                                          DropdownMenuItem(
                                            value: currentValue,
                                            child: Text(
                                              'Room $currentValue (no longer available)',
                                              style: TextStyle(
                                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                      ];
                                      final dropdownValue = (currentValue !=
                                                  null &&
                                              (availableOptions.contains(
                                                    currentValue) ||
                                                  valueNotInList))
                                          ? currentValue
                                          : null;
                                      return Padding(
                                        padding: EdgeInsets.only(
                                          bottom: index < _numberOfRooms - 1
                                              ? 16
                                              : 0,
                                        ),
                                        child: DropdownButtonFormField<String>(
                                          value: dropdownValue,
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
                                            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                                            prefixIcon: const Icon(
                                              Icons.hotel_rounded,
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 16,
                                                  vertical: 16,
                                                ),
                                          ),
                                          style: TextStyle(
                                            fontSize: 16,
                                            color: Theme.of(context).colorScheme.onSurface,
                                          ),
                                          dropdownColor: Theme.of(context).colorScheme.surface,
                                          items: items,
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

                              // Number of Nights (calculated)
                              if (_numberOfNights > 0)
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: StayoraColors.blue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.bed_rounded,
                                        color: StayoraColors.blue,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '$_numberOfNights ${_numberOfNights == 1 ? 'night' : 'nights'}',
                                        style: const TextStyle(
                                          color: StayoraColors.blue,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 16),
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
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _pricePerNightController,
                                decoration: InputDecoration(
                                  hintText: 'e.g. 100.00 or 100,50',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                                  prefixIcon: const Icon(Icons.euro_rounded),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                ),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [
                                  MoneyInputFormatter(),
                                ],
                                onChanged: (_) {
                                  setState(() {});
                                },
                                onEditingComplete: () {
                                  final cents = CurrencyFormatter.parseMoneyStringToCents(
                                      _pricePerNightController.text.trim());
                                  if (cents > 0) {
                                    _pricePerNightController.text =
                                        CurrencyFormatter.formatCentsForInput(cents);
                                  }
                                  setState(() {});
                                },
                              ),
                              if (_numberOfNights > 0 && _pricePerNight > 0) ...[
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.nights_stay_rounded,
                                      size: 18,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '$_numberOfNights night${_numberOfNights == 1 ? '' : 's'} × $_numberOfRooms room${_numberOfRooms == 1 ? '' : 's'} × ${currencyFormatter.formatCompact(_pricePerNight)}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        currencyFormatter.formatCompact(_roomSubtotal),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: StayoraColors.blue,
                                        ),
                                        overflow: TextOverflow.ellipsis,
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
                                  Flexible(
                                    child: TextButton.icon(
                                      onPressed: () async {
                                        await Navigator.of(context, rootNavigator: false).push(
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                const ServicesPage(),
                                          ),
                                        );
                                        final hid = HotelProvider.of(context).hotelId;
                                        final uid = AuthScopeData.of(context).uid;
                                        if (hid != null && uid != null) _loadServices(uid, hid);
                                      },
                                      icon: const Icon(Icons.add_circle_outline,
                                          size: 18),
                                      label: Text(
                                        'Add more services',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      style: TextButton.styleFrom(
                                        foregroundColor: StayoraColors.blue,
                                      ),
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
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                                                '${currencyFormatter.formatCompact(service.price)} per unit',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                                              color: StayoraColors.blue,
                                            ),
                                            GestureDetector(
                                              onTap: () async {
                                                final value =
                                                    await _showNumberInputDialog(
                                                  title:
                                                      'Quantity for ${service.name}',
                                                  initialValue: qty,
                                                  minValue: 0,
                                                );
                                                if (value != null) {
                                                  _setServiceQuantity(
                                                    service,
                                                    value,
                                                  );
                                                }
                                              },
                                              child: SizedBox(
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
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                  Icons.add_circle_outline),
                                              onPressed: () =>
                                                  _setServiceQuantity(
                                                service,
                                                qty + 1,
                                              ),
                                              color: StayoraColors.blue,
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
                                            '${s.name} — ${s.quantity} × ${currencyFormatter.formatCompact(s.unitPrice)}',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                          Text(
                                            currencyFormatter.formatCompact(s.lineTotal),
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                              color: Theme.of(context).colorScheme.onSurface,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Services subtotal',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      currencyFormatter.formatCompact(_servicesSubtotal),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                        color: StayoraColors.blue,
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
                                  Expanded(
                                    child: Text(
                                      'Suggested total (room + services)',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                        color: Theme.of(context).colorScheme.onSurface,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    currencyFormatter.formatCompact(_suggestedTotal),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 17,
                                      color: StayoraColors.blue,
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
                                        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 14,
                                        ),
                                      ),
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ],
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
                                          if (p > 0 && _suggestedTotal > 0) {
                                            final amount = (_suggestedTotal * p / 100).round();
                                            _advanceAmountPaidController.text = CurrencyFormatter.formatCentsForInput(amount);
                                          } else {
                                            _advanceAmountPaidController.text = '';
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
                                        hintText: 'e.g. 0 or 20.00',
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        filled: true,
                                        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                                        prefixIcon: const Icon(
                                            Icons.payments_rounded,
                                            size: 20),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 14,
                                        ),
                                      ),
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      inputFormatters: [
                                        MoneyInputFormatter(),
                                      ],
                                      onChanged: (_) {
                                        setState(() {
                                          final paid = CurrencyFormatter.parseMoneyStringToCents(
                                              _advanceAmountPaidController.text.trim());
                                          if (_suggestedTotal > 0 && paid >= 0) {
                                            final p = (paid * 100 / _suggestedTotal).round();
                                            _advancePercent = p > 0 ? p : null;
                                            _advancePercentController.text = p > 0 ? p.toString() : '';
                                          }
                                        });
                                      },
                                      onEditingComplete: () {
                                        final cents = CurrencyFormatter.parseMoneyStringToCents(
                                            _advanceAmountPaidController.text.trim());
                                        if (cents > 0) {
                                          _advanceAmountPaidController.text =
                                              CurrencyFormatter.formatCentsForInput(cents);
                                        }
                                        setState(() {});
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
                                  'Required: ${currencyFormatter.formatCompact(_advanceAmountRequired)} ($_advancePercent% of total ${currencyFormatter.formatCompact(_suggestedTotal)})',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                initialValue: BookingModel.paymentMethods
                                        .contains(_advancePaymentMethod)
                                    ? _advancePaymentMethod
                                    : BookingModel.paymentMethods.first,
                                decoration: InputDecoration(
                                  labelText: 'Advance payment method',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ChoiceChip(
                                        label: const Text('Pending'),
                                        selected: _advanceStatus == 'pending',
                                        onSelected: (v) => setState(() {
                                              _advanceStatus = 'pending';
                                              _amountPaidController.clear();
                                            }),
                                        selectedColor: StayoraColors.warning
                                            .withOpacity(0.3),
                                      ),
                                      const SizedBox(width: 8),
                                      ChoiceChip(
                                        label: const Text('Received'),
                                        selected: _advanceStatus == 'received',
                                        onSelected: (v) => setState(() {
                                              _advanceStatus = 'received';
                                            }),
                                        selectedColor: StayoraColors.success
                                            .withOpacity(0.3),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              // "They owe you" and "Advance paid" only when advance is received (not when pending)
                              if (_advanceStatus == 'received' &&
                                  _suggestedTotal > 0) ...[
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.account_balance_wallet_rounded,
                                        size: 18,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'They owe you: ${currencyFormatter.formatCompact(_remainingBalance)} (total ${currencyFormatter.formatCompact(_suggestedTotal)} − advance ${currencyFormatter.formatCompact(_advanceAmountPaid)})',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: _remainingBalance > 0
                                              ? StayoraColors.warning
                                              : Theme.of(context).colorScheme.onSurface,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 2,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Icon(Icons.check_circle_rounded,
                                        size: 18,
                                        color: StayoraColors.success),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Advance paid (${currencyFormatter.formatCompact(_advanceAmountPaid)}) — $_advancePaymentMethod',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Theme.of(context).colorScheme.onSurface,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 2,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                              ],
                              // When advance is pending: only show waiting message (no "They owe you", no "Advance paid")
                              Builder(
                                builder: (context) {
                                  if (_advanceDisplayStatus == 'not_required') {
                                    return Row(
                                      children: [
                                        Icon(Icons.info_outline_rounded,
                                            size: 18,
                                            color: Theme.of(context).colorScheme.onSurfaceVariant),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'No advance required',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    );
                                  }
                                  if (_advanceStatus == 'received') {
                                    return const SizedBox.shrink();
                                  }
                                  return const SizedBox.shrink();
                                },
                              ),
                              const SizedBox(height: 16),
                              // Amount paid (total)
                              TextFormField(
                                controller: _amountPaidController,
                                decoration: InputDecoration(
                                  labelText: 'Amount paid (total)',
                                  hintText: 'e.g. 20.00 or 150,50',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                                  prefixIcon: const Icon(Icons.payments_rounded),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 16,
                                  ),
                                ),
                                style: const TextStyle(fontSize: 16),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [
                                  MoneyInputFormatter(),
                                ],
                                onEditingComplete: () {
                                  final cents = CurrencyFormatter.parseMoneyStringToCents(
                                      _amountPaidController.text.trim());
                                  if (cents > 0) {
                                    _amountPaidController.text =
                                        CurrencyFormatter.formatCentsForInput(cents);
                                  }
                                  setState(() {});
                                },
                              ),
                              const SizedBox(height: 16),
                              // Payment method
                              DropdownButtonFormField<String>(
                                initialValue: BookingModel.paymentMethods
                                        .contains(_paymentMethod)
                                    ? _paymentMethod
                                    : BookingModel.paymentMethods.first,
                                decoration: InputDecoration(
                                  labelText: 'Payment method',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                                  prefixIcon: const Icon(
                                    Icons.credit_card_rounded,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 16,
                                  ),
                                ),
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                                dropdownColor: Theme.of(context).colorScheme.surface,
                                items: BookingModel.paymentMethods
                                    .map((method) {
                                  return DropdownMenuItem(
                                    value: method,
                                    child: Text(
                                      method,
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.onSurface,
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

                      // Booking Status (above notes)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: DropdownButtonFormField<String>(
                            initialValue: _bookingStatus,
                            decoration: InputDecoration(
                              labelText: 'Status',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                              prefixIcon: const Icon(Icons.info_rounded),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                            ),
                            style: TextStyle(
                              fontSize: 16,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            dropdownColor: Theme.of(context).colorScheme.surface,
                            items: BookingModel.statusOptions
                                .map((status) {
                              return DropdownMenuItem(
                                value: status,
                                child: Text(
                                  status,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface,
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
                              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                            backgroundColor: StayoraColors.blue,
                            foregroundColor: Theme.of(context).colorScheme.onPrimary,
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
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outline.withOpacity(0.5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outline.withOpacity(0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: StayoraColors.blue, width: 2),
        ),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        prefixIcon: Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
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

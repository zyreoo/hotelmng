import 'service_model.dart';

class BookingModel {
  final String? id;
  final String userId;
  final String userName;
  final String userPhone;
  final String? userEmail;
  final DateTime checkIn;
  final DateTime checkOut;
  final int numberOfRooms;
  final bool nextToEachOther;
  /// Room names stored at booking time (legacy + backward compat display).
  final List<String>? selectedRooms;
  /// Room document IDs — use these to resolve current room names so renaming
  /// a room is reflected in old bookings too.
  final List<String>? selectedRoomIds;
  final int numberOfGuests;
  final String status; // Confirmed, Pending, Cancelled, Paid, Unpaid
  final String? notes;
  final DateTime createdAt;
  final int amountOfMoneyPaid;
  final String paymentMethod;
  /// Price per night (per room). Same unit as amountOfMoneyPaid (e.g. cents).
  final int? pricePerNight;
  /// Add-on services (breakfast, spa, etc.) selected for this booking.
  final List<BookingServiceItem>? selectedServices;
  /// Advance payment: required percentage of total (e.g. 30 = 30%).
  final int? advancePercent;
  /// Advance payment: amount already paid (same unit as amountOfMoneyPaid).
  final int advanceAmountPaid;
  /// How the advance was paid (when paid).
  final String? advancePaymentMethod;
  /// Advance received status: not_required, pending, received.
  final String? advanceStatus;

  static const List<String> advanceStatusOptions = [
    'not_required',
    'pending',
    'received',
  ];

  static const List<String> statusOptions = [
    'Confirmed',
    'Pending',
    'Cancelled',
    'Paid',
    'Unpaid',
    'Waiting list',
  ];

  static const List<String> paymentMethods = [
    'Cash',
    'Card',
    'Bank Transfer',
    'Other',
  ];

  BookingModel({
    this.id,
    required this.userId,
    required this.userName,
    required this.userPhone,
    this.userEmail,
    required this.checkIn,
    required this.checkOut,
    required this.numberOfRooms,
    this.nextToEachOther = false,
    this.selectedRooms,
    this.selectedRoomIds,
    required this.numberOfGuests,
    required this.status,
    this.notes,
    DateTime? createdAt,
    this.amountOfMoneyPaid = 0,
    this.paymentMethod = '',
    this.pricePerNight,
    this.selectedServices,
    this.advancePercent,
    this.advanceAmountPaid = 0,
    this.advancePaymentMethod,
    this.advanceStatus,
    this.checkedInAt,
    this.checkedOutAt,
  }) : createdAt = createdAt ?? DateTime.now();

  int get numberOfNights {
    return checkOut.difference(checkIn).inDays;
  }

  /// Room total: nights × rooms × price per night.
  int get roomSubtotal =>
      numberOfNights * numberOfRooms * (pricePerNight ?? 0);

  /// Sum of (unitPrice * quantity) for all selected services.
  int get servicesSubtotal =>
      selectedServices?.fold<int>(0, (sum, s) => sum + s.lineTotal) ?? 0;

  /// Suggested total: room + services.
  int get calculatedTotal => roomSubtotal + servicesSubtotal;

  /// Advance amount required (from advancePercent of calculatedTotal).
  int get advanceAmountRequired =>
      advancePercent != null && advancePercent! > 0
          ? (calculatedTotal * advancePercent! / 100).round()
          : 0;

  /// Optional: timestamp when the guest physically checked in.
  final DateTime? checkedInAt;

  /// Optional: timestamp when the guest physically checked out.
  final DateTime? checkedOutAt;

  /// Advance payment status for display: not_required, waiting, paid. Uses stored advanceStatus when set, else derived from amount.
  String get advancePaymentStatus {
    if (advanceStatus != null && advanceStatus!.isNotEmpty) {
      if (advanceStatus == 'received') return 'paid';
      if (advanceStatus == 'pending') return 'waiting';
      return advanceStatus!;
    }
    if (advancePercent == null || advancePercent! <= 0) return 'not_required';
    if (advanceAmountPaid >= advanceAmountRequired) return 'paid';
    return 'waiting';
  }

  /// Remaining balance: total − advance paid (what they still owe).
  int get remainingBalance =>
      (calculatedTotal - advanceAmountPaid).clamp(0, calculatedTotal);

  /// Returns room names resolved via current [roomIdToName] map when IDs are
  /// stored, falling back to the legacy stored names for older bookings.
  List<String> resolvedSelectedRooms(Map<String, String> roomIdToName) {
    if (selectedRoomIds != null && selectedRoomIds!.isNotEmpty) {
      final resolved = selectedRoomIds!
          .map((id) => roomIdToName[id] ?? '')
          .where((name) => name.isNotEmpty)
          .toList();
      if (resolved.isNotEmpty) return resolved;
    }
    return selectedRooms ?? [];
  }

  // Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'userName': userName,
      'userPhone': userPhone,
      'userEmail': userEmail,
      'checkIn': checkIn.toIso8601String(),
      'checkOut': checkOut.toIso8601String(),
      'numberOfRooms': numberOfRooms,
      'nextToEachOther': nextToEachOther,
      'selectedRooms': selectedRooms,
      if (selectedRoomIds != null) 'selectedRoomIds': selectedRoomIds,
      'numberOfGuests': numberOfGuests,
      'status': status,
      'notes': notes,
      'createdAt': createdAt.toIso8601String(),
      'amountOfMoneyPaid': amountOfMoneyPaid,
      'paymentMethod': paymentMethod,
      if (pricePerNight != null) 'pricePerNight': pricePerNight!,
      'selectedServices': selectedServices
          ?.map((s) => s.toMap())
          .toList(),
      if (advancePercent != null) 'advancePercent': advancePercent!,
      'advanceAmountPaid': advanceAmountPaid,
      if (advancePaymentMethod != null && advancePaymentMethod!.isNotEmpty)
        'advancePaymentMethod': advancePaymentMethod,
      if (advanceStatus != null && advanceStatus!.isNotEmpty)
        'advanceStatus': advanceStatus,
      if (checkedInAt != null) 'checkedInAt': checkedInAt!.toIso8601String(),
      if (checkedOutAt != null) 'checkedOutAt': checkedOutAt!.toIso8601String(),
    };
  }

  // Create from Firestore document
  factory BookingModel.fromFirestore(Map<String, dynamic> data, String id) {
    return BookingModel(
      id: id,
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? '',
      userPhone: data['userPhone'] ?? '',
      userEmail: data['userEmail'],
      checkIn: DateTime.parse(data['checkIn']),
      checkOut: DateTime.parse(data['checkOut']),
      numberOfRooms: data['numberOfRooms'] ?? 1,
      nextToEachOther: data['nextToEachOther'] ?? false,
      selectedRooms: data['selectedRooms'] != null
          ? List<String>.from(data['selectedRooms'])
          : null,
      selectedRoomIds: data['selectedRoomIds'] != null
          ? List<String>.from(data['selectedRoomIds'])
          : null,
      numberOfGuests: data['numberOfGuests'] ?? 1,
      status: data['status'] ?? 'Confirmed',
      notes: data['notes'],
      createdAt: data['createdAt'] != null
          ? DateTime.parse(data['createdAt'])
          : DateTime.now(),
      amountOfMoneyPaid: (data['amountOfMoneyPaid'] is int)
          ? data['amountOfMoneyPaid'] as int
          : int.tryParse(data['amountOfMoneyPaid']?.toString() ?? '0') ?? 0,
      paymentMethod: data['paymentMethod']?.toString() ?? '',
      pricePerNight: data['pricePerNight'] != null
          ? ((data['pricePerNight'] is int)
              ? data['pricePerNight'] as int
              : int.tryParse(data['pricePerNight']?.toString() ?? '') ?? 0)
          : null,
      selectedServices: data['selectedServices'] != null
          ? (data['selectedServices'] as List)
              .map((e) => BookingServiceItem.fromMap(
                  Map<String, dynamic>.from(e as Map)))
              .toList()
          : null,
      advancePercent: data['advancePercent'] != null
          ? ((data['advancePercent'] is int)
              ? data['advancePercent'] as int
              : int.tryParse(data['advancePercent']?.toString() ?? '') ?? 0)
          : null,
      advanceAmountPaid: (data['advanceAmountPaid'] is int)
          ? data['advanceAmountPaid'] as int
          : int.tryParse(data['advanceAmountPaid']?.toString() ?? '0') ?? 0,
      advancePaymentMethod: data['advancePaymentMethod']?.toString(),
      advanceStatus: data['advanceStatus']?.toString(),
      checkedInAt: data['checkedInAt'] != null
          ? DateTime.tryParse(data['checkedInAt'].toString())
          : null,
      checkedOutAt: data['checkedOutAt'] != null
          ? DateTime.tryParse(data['checkedOutAt'].toString())
          : null,
    );
  }

  // Create a copy with updated fields
  BookingModel copyWith({
    String? id,
    String? userId,
    String? userName,
    String? userPhone,
    String? userEmail,
    DateTime? checkIn,
    DateTime? checkOut,
    int? numberOfRooms,
    bool? nextToEachOther,
    List<String>? selectedRooms,
    List<String>? selectedRoomIds,
    int? numberOfGuests,
    String? status,
    String? notes,
    DateTime? createdAt,
    int? amountOfMoneyPaid,
    String? paymentMethod,
    int? pricePerNight,
    List<BookingServiceItem>? selectedServices,
    int? advancePercent,
    int? advanceAmountPaid,
    String? advancePaymentMethod,
    String? advanceStatus,
    DateTime? checkedInAt,
    DateTime? checkedOutAt,
    bool clearCheckedInAt = false,
    bool clearCheckedOutAt = false,
  }) {
    return BookingModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userPhone: userPhone ?? this.userPhone,
      userEmail: userEmail ?? this.userEmail,
      checkIn: checkIn ?? this.checkIn,
      checkOut: checkOut ?? this.checkOut,
      numberOfRooms: numberOfRooms ?? this.numberOfRooms,
      nextToEachOther: nextToEachOther ?? this.nextToEachOther,
      selectedRooms: selectedRooms ?? this.selectedRooms,
      selectedRoomIds: selectedRoomIds ?? this.selectedRoomIds,
      numberOfGuests: numberOfGuests ?? this.numberOfGuests,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      amountOfMoneyPaid: amountOfMoneyPaid ?? this.amountOfMoneyPaid,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      pricePerNight: pricePerNight ?? this.pricePerNight,
      selectedServices: selectedServices ?? this.selectedServices,
      advancePercent: advancePercent ?? this.advancePercent,
      advanceAmountPaid: advanceAmountPaid ?? this.advanceAmountPaid,
      advancePaymentMethod: advancePaymentMethod ?? this.advancePaymentMethod,
      advanceStatus: advanceStatus ?? this.advanceStatus,
      checkedInAt: clearCheckedInAt ? null : (checkedInAt ?? this.checkedInAt),
      checkedOutAt: clearCheckedOutAt ? null : (checkedOutAt ?? this.checkedOutAt),
    );
  }
}

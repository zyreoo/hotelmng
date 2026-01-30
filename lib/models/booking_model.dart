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
  final List<String>? selectedRooms; // Room numbers if specific rooms selected
  final int numberOfGuests;
  final String status; // Confirmed, Pending, Cancelled, Paid, Unpaid
  final String? notes;
  final DateTime createdAt;
  final int amountOfMoneyPaid;
  final String paymentMethod;

  static const List<String> statusOptions = [
    'Confirmed',
    'Pending',
    'Cancelled',
    'Paid',
    'Unpaid',
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
    required this.numberOfGuests,
    required this.status,
    this.notes,
    DateTime? createdAt,
    this.amountOfMoneyPaid = 0,
    this.paymentMethod = '',
  }) : createdAt = createdAt ?? DateTime.now();

  int get numberOfNights {
    return checkOut.difference(checkIn).inDays;
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
      'numberOfGuests': numberOfGuests,
      'status': status,
      'notes': notes,
      'createdAt': createdAt.toIso8601String(),
      'amountOfMoneyPaid': amountOfMoneyPaid,
      'paymentMethod': paymentMethod,
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
    int? numberOfGuests,
    String? status,
    String? notes,
    DateTime? createdAt,
    int? amountOfMoneyPaid,
    String? paymentMethod,
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
      numberOfGuests: numberOfGuests ?? this.numberOfGuests,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      amountOfMoneyPaid: amountOfMoneyPaid ?? this.amountOfMoneyPaid,
      paymentMethod: paymentMethod ?? this.paymentMethod,
    );
  }
}

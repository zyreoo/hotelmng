import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/user_model.dart';
import '../models/booking_model.dart';
import '../models/employer_model.dart';
import '../models/service_model.dart';
import '../models/room_model.dart';
import '../models/shift_model.dart';

class FirebaseService {
  FirebaseFirestore? _firestore;

  FirebaseFirestore get firestore {
    if (_firestore == null) {
      try {
        _firestore = FirebaseFirestore.instance;
      } catch (e) {
        throw Exception(
          'Firebase is not initialized. Please configure Firebase first.',
        );
      }
    }
    return _firestore!;
  }

  bool get isInitialized {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// All data is stored under users/{userId}/hotels/{hotelId}/...
  /// This provides proper data isolation per user and hotel.
  CollectionReference<Map<String, dynamic>> _usersRef(
    String userId,
    String hotelId,
  ) => firestore
      .collection('users')
      .doc(userId)
      .collection('hotels')
      .doc(hotelId)
      .collection('clients');
  CollectionReference<Map<String, dynamic>> _bookingsRef(
    String userId,
    String hotelId,
  ) => firestore
      .collection('users')
      .doc(userId)
      .collection('hotels')
      .doc(hotelId)
      .collection('bookings');
  CollectionReference<Map<String, dynamic>> _employersRef(
    String userId,
    String hotelId,
  ) => firestore
      .collection('users')
      .doc(userId)
      .collection('hotels')
      .doc(hotelId)
      .collection('employers');
  CollectionReference<Map<String, dynamic>> _rolesRef(
    String userId,
    String hotelId,
  ) => firestore
      .collection('users')
      .doc(userId)
      .collection('hotels')
      .doc(hotelId)
      .collection('roles');
  CollectionReference<Map<String, dynamic>> _departmentsRef(
    String userId,
    String hotelId,
  ) => firestore
      .collection('users')
      .doc(userId)
      .collection('hotels')
      .doc(hotelId)
      .collection('departments');
  CollectionReference<Map<String, dynamic>> _servicesRef(
    String userId,
    String hotelId,
  ) => firestore
      .collection('users')
      .doc(userId)
      .collection('hotels')
      .doc(hotelId)
      .collection('services');
  CollectionReference<Map<String, dynamic>> _roomsRef(
    String userId,
    String hotelId,
  ) => firestore
      .collection('users')
      .doc(userId)
      .collection('hotels')
      .doc(hotelId)
      .collection('rooms');
  CollectionReference<Map<String, dynamic>> _shiftsRef(
    String userId,
    String hotelId,
  ) => firestore
      .collection('users')
      .doc(userId)
      .collection('hotels')
      .doc(hotelId)
      .collection('shifts');

  // ─── Shift operations ────────────────────────────────────────────────────
  Future<String> createShift(
    String userId,
    String hotelId,
    ShiftModel shift,
  ) async {
    if (!isInitialized) throw Exception('Firebase not initialized.');
    if (shift.employeeId.trim().isEmpty) {
      throw ArgumentError('Employee is required.');
    }
    final ref = await _shiftsRef(userId, hotelId).add(shift.toFirestore());
    return ref.id;
  }

  // ─── Room operations ─────────────────────────────────────────────────────
  Future<List<RoomModel>> getRooms(String userId, String hotelId) async {
    if (!isInitialized) return [];
    final snapshot = await _roomsRef(userId, hotelId).orderBy('name').get();
    return snapshot.docs
        .map((d) => RoomModel.fromFirestore(d.data(), d.id))
        .toList();
  }

  Stream<List<RoomModel>> roomsSnapshot(String userId, String hotelId) {
    if (!isInitialized) return Stream.value([]);
    return _roomsRef(userId, hotelId)
        .orderBy('name')
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => RoomModel.fromFirestore(d.data(), d.id))
              .toList(),
        );
  }

  Future<String> createRoom(String userId, String hotelId, String name) async {
    if (!isInitialized) throw Exception('Firebase not initialized.');
    if (name.trim().isEmpty) throw ArgumentError('Room name is required.');
    final ref = await _roomsRef(userId, hotelId).add({'name': name.trim()});
    return ref.id;
  }

  Future<void> updateRoom(
    String userId,
    String hotelId,
    String roomId,
    String name,
  ) async {
    if (!isInitialized) throw Exception('Firebase not initialized.');
    if (name.trim().isEmpty) throw ArgumentError('Room name is required.');
    await _roomsRef(userId, hotelId).doc(roomId).update({'name': name.trim()});
  }

  Future<void> updateRoomHousekeeping(
    String userId,
    String hotelId,
    String roomId,
    String housekeepingStatus,
  ) async {
    if (!isInitialized) throw Exception('Firebase not initialized.');
    await _roomsRef(userId, hotelId)
        .doc(roomId)
        .update({'housekeepingStatus': housekeepingStatus});
  }

  Future<void> updateRoomTags(
    String userId,
    String hotelId,
    String roomId,
    List<String> tags,
  ) async {
    if (!isInitialized) throw Exception('Firebase not initialized.');
    await _roomsRef(userId, hotelId).doc(roomId).update({'tags': tags});
  }

  Future<void> deleteRoom(String userId, String hotelId, String roomId) async {
    if (!isInitialized) throw Exception('Firebase not initialized.');
    await _roomsRef(userId, hotelId).doc(roomId).delete();
  }

  // ─── User operations (clients/guests) ─────────────────────────────────────
  Future<String> createUser(
    String userId,
    String hotelId,
    UserModel user,
  ) async {
    if (!isInitialized) {
      throw Exception(
        'Firebase is not initialized. Please configure Firebase first.',
      );
    }
    if (user.name.trim().isEmpty || user.phone.trim().isEmpty) {
      throw ArgumentError('User name and phone are required.');
    }
    final data = user.toFirestore();
    final docRef = await _usersRef(userId, hotelId).add(data);
    return docRef.id;
  }

  /// Search clients by name or phone. Fetches from users/{userId}/hotels/{hotelId}/clients
  /// and filters in memory so no composite index is required.
  Future<List<UserModel>> searchUsers(
    String userId,
    String hotelId,
    String query,
  ) async {
    if (query.isEmpty) return [];
    if (!isInitialized) return [];

    final queryLower = query.trim().toLowerCase();
    final queryTrimmed = query.trim();
    if (queryTrimmed.isEmpty) return [];

    final snapshot = await _usersRef(userId, hotelId).limit(200).get();
    final results = snapshot.docs
        .map((doc) => UserModel.fromFirestore(doc.data(), doc.id))
        .where((user) {
          final nameMatch = user.name.toLowerCase().contains(queryLower);
          final phoneMatch = user.phone.contains(queryTrimmed);
          return nameMatch || phoneMatch;
        })
        .toList();

    return results;
  }

  Future<UserModel?> getUserById(
    String userId,
    String hotelId,
    String clientId,
  ) async {
    if (!isInitialized) return null;
    final doc = await _usersRef(userId, hotelId).doc(clientId).get();
    if (doc.exists && doc.data() != null) {
      return UserModel.fromFirestore(doc.data()!, doc.id);
    }
    return null;
  }

  Future<UserModel?> getUserByPhone(
    String userId,
    String hotelId,
    String phone,
  ) async {
    if (!isInitialized) return null;
    final query = await _usersRef(
      userId,
      hotelId,
    ).where('phone', isEqualTo: phone).limit(1).get();

    if (query.docs.isNotEmpty) {
      final doc = query.docs.first;
      return UserModel.fromFirestore(doc.data(), doc.id);
    }
    return null;
  }

  Future<String> createBooking(
    String userId,
    String hotelId,
    BookingModel booking,
  ) async {
    if (!isInitialized) {
      throw Exception(
        'Firebase is not initialized. Please configure Firebase first.',
      );
    }
    final docRef = await _bookingsRef(
      userId,
      hotelId,
    ).add(booking.toFirestore());
    return docRef.id;
  }

  Future<List<BookingModel>> getBookings(
    String userId,
    String hotelId, {
    DateTime? startDate,
    DateTime? endDate,
    String? clientId,
  }) async {
    if (!isInitialized) return [];
    Query<Map<String, dynamic>> q = _bookingsRef(userId, hotelId);

    if (clientId != null) q = q.where('userId', isEqualTo: clientId);
    if (startDate != null) {
      q = q.where(
        'checkIn',
        isGreaterThanOrEqualTo: startDate.toIso8601String(),
      );
    }
    if (endDate != null) {
      q = q.where('checkOut', isLessThanOrEqualTo: endDate.toIso8601String());
    }

    final snapshot = await q.orderBy('checkIn').get();
    return snapshot.docs
        .map((doc) => BookingModel.fromFirestore(doc.data(), doc.id))
        .toList();
  }

  Future<BookingModel?> getBookingById(
    String userId,
    String hotelId,
    String bookingId,
  ) async {
    if (!isInitialized) return null;
    final doc = await _bookingsRef(userId, hotelId).doc(bookingId).get();
    if (doc.exists && doc.data() != null) {
      return BookingModel.fromFirestore(doc.data()!, doc.id);
    }
    return null;
  }

  Future<void> updateBooking(
    String userId,
    String hotelId,
    BookingModel booking,
  ) async {
    if (!isInitialized || booking.id == null) return;
    await _bookingsRef(
      userId,
      hotelId,
    ).doc(booking.id).update(booking.toFirestore());
  }

  Future<void> deleteBooking(
    String userId,
    String hotelId,
    String bookingId,
  ) async {
    if (!isInitialized) return;
    await _bookingsRef(userId, hotelId).doc(bookingId).delete();
  }

  /// Stream of bookings for calendar (hotel-scoped), with optional single-field
  /// date filter. Only one inequality field is used to avoid composite-index
  /// requirements; further filtering can be done in memory.
  Stream<QuerySnapshot<Map<String, dynamic>>> bookingsSnapshot(
    String userId,
    String hotelId, {
    DateTime? startDate,
    DateTime? endDate,
  }) {
    if (!isInitialized) return const Stream.empty();
    Query<Map<String, dynamic>> q = _bookingsRef(userId, hotelId);
    if (startDate != null) {
      q = q.where(
        'checkIn',
        isGreaterThanOrEqualTo: startDate.toIso8601String(),
      );
    }
    if (endDate != null) {
      q = q.where('checkOut', isLessThanOrEqualTo: endDate.toIso8601String());
    }
    return q.orderBy('checkIn').snapshots();
  }

  /// Real-time stream of all clients for a hotel.
  Stream<List<UserModel>> clientsStream(String userId, String hotelId) {
    if (!isInitialized) return Stream.value([]);
    return _usersRef(userId, hotelId).snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => UserModel.fromFirestore(doc.data(), doc.id))
              .toList(),
        );
  }

  /// Updates an existing client document.
  Future<void> updateClient(
    String userId,
    String hotelId,
    UserModel client,
  ) async {
    if (!isInitialized || client.id == null) return;
    await _usersRef(userId, hotelId).doc(client.id!).update(client.toFirestore());
  }

  /// Real-time stream of bookings with check-in on or after [checkInOnOrAfter].
  /// Uses a single inequality so no composite index is needed. Keeps the result
  /// set small so add/update/delete stays fast.
  Stream<QuerySnapshot<Map<String, dynamic>>> bookingsStream(
    String userId,
    String hotelId, {
    DateTime? checkInOnOrAfter,
  }) {
    if (!isInitialized) return const Stream.empty();
    Query<Map<String, dynamic>> q = _bookingsRef(userId, hotelId);
    if (checkInOnOrAfter != null) {
      q = q.where(
        'checkIn',
        isGreaterThanOrEqualTo: checkInOnOrAfter.toIso8601String(),
      );
    }
    return q.orderBy('checkIn').snapshots();
  }

  /// Real-time stream of a single booking document (for the detail panel).
  Stream<DocumentSnapshot<Map<String, dynamic>>> bookingDocStream(
    String userId,
    String hotelId,
    String bookingId,
  ) {
    if (!isInitialized) return const Stream.empty();
    return _bookingsRef(userId, hotelId).doc(bookingId).snapshots();
  }

  /// Stream of raw booking document changes for the calendar grid.
  /// Filters by checkOut > rangeStart so only bookings that overlap the visible
  /// date window are returned. Additional filtering is done in the calendar state.
  Stream<QuerySnapshot<Map<String, dynamic>>> bookingsStreamForCalendar(
    String userId,
    String hotelId,
    DateTime rangeStart,
  ) {
    if (!isInitialized) return const Stream.empty();
    return _bookingsRef(userId, hotelId)
        .where('checkOut', isGreaterThan: rangeStart.toIso8601String())
        .snapshots();
  }

  /// Stream of all bookings currently on the waiting list.
  Stream<QuerySnapshot<Map<String, dynamic>>> waitingListBookingsStream(
    String userId,
    String hotelId,
  ) {
    if (!isInitialized) return const Stream.empty();
    return _bookingsRef(userId, hotelId)
        .where('status', isEqualTo: 'Waiting list')
        .snapshots();
  }

  // ─── Employer operations ─────────────────────────────────────────────────
  Future<List<EmployerModel>> getEmployers(
    String userId,
    String hotelId,
  ) async {
    if (!isInitialized) return [];
    final snapshot = await _employersRef(userId, hotelId).limit(500).get();
    return snapshot.docs
        .map((d) => EmployerModel.fromFirestore(d.data(), d.id))
        .toList();
  }

  Future<List<EmployerModel>> searchEmployers(
    String userId,
    String hotelId,
    String query,
  ) async {
    if (!isInitialized || query.trim().isEmpty) return [];
    final q = query.trim().toLowerCase();
    final snapshot = await _employersRef(userId, hotelId).limit(100).get();
    return snapshot.docs
        .map((d) => EmployerModel.fromFirestore(d.data(), d.id))
        .where(
          (e) =>
              e.name.toLowerCase().contains(q) ||
              e.phone.contains(query.trim()) ||
              e.role.toLowerCase().contains(q) ||
              e.email.toLowerCase().contains(q),
        )
        .toList();
  }

  Future<String> createEmployer(
    String userId,
    String hotelId,
    EmployerModel employer,
  ) async {
    if (!isInitialized) {
      throw Exception(
        'Firebase is not initialized. Please configure Firebase first.',
      );
    }
    final docRef = await _employersRef(
      userId,
      hotelId,
    ).add(employer.toFirestore());
    return docRef.id;
  }

  Future<void> updateEmployer(
    String userId,
    String hotelId,
    EmployerModel employer,
  ) async {
    if (!isInitialized || employer.id == null || employer.id!.isEmpty) {
      throw Exception('Cannot update employer: missing id.');
    }
    final data = employer.toFirestore();
    data['updatedAt'] = DateTime.now().toIso8601String();
    await _employersRef(userId, hotelId).doc(employer.id!).update(data);
  }

  // ─── Roles and departments (per hotel) ────────────────────────────────────
  Future<List<String>> getRoles(String userId, String hotelId) async {
    if (!isInitialized) return [];
    final snapshot = await _rolesRef(userId, hotelId).get();
    final list = snapshot.docs
        .map((d) => d.data()['name'] as String? ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
    list.sort();
    return list;
  }

  Future<List<String>> getDepartments(String userId, String hotelId) async {
    if (!isInitialized) return [];
    final snapshot = await _departmentsRef(userId, hotelId).get();
    final list = snapshot.docs
        .map((d) => d.data()['name'] as String? ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
    list.sort();
    return list;
  }

  Future<void> addRole(String userId, String hotelId, String name) async {
    if (!isInitialized || name.trim().isEmpty) return;
    final trimmed = name.trim();
    final existing = await _rolesRef(
      userId,
      hotelId,
    ).where('name', isEqualTo: trimmed).limit(1).get();
    if (existing.docs.isEmpty) {
      await _rolesRef(userId, hotelId).add({'name': trimmed});
    }
  }

  Future<void> addDepartment(String userId, String hotelId, String name) async {
    if (!isInitialized || name.trim().isEmpty) return;
    final trimmed = name.trim();
    final existing = await _departmentsRef(
      userId,
      hotelId,
    ).where('name', isEqualTo: trimmed).limit(1).get();
    if (existing.docs.isEmpty) {
      await _departmentsRef(userId, hotelId).add({'name': trimmed});
    }
  }

  // ─── Services (per hotel) ─────────────────────────────────────────────────
  Stream<List<ServiceModel>> getServicesStream(String userId, String hotelId) {
    if (!isInitialized) return Stream.value([]);
    return _servicesRef(userId, hotelId).snapshots().map((snapshot) {
      final list = snapshot.docs
          .map((d) => ServiceModel.fromFirestore(d.data(), d.id))
          .toList();
      list.sort((a, b) => a.name.compareTo(b.name));
      return list;
    });
  }

  Future<List<ServiceModel>> getServices(String userId, String hotelId) async {
    if (!isInitialized) return [];
    final snapshot = await _servicesRef(userId, hotelId).get();
    final list = snapshot.docs
        .map((d) => ServiceModel.fromFirestore(d.data(), d.id))
        .toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  Future<String> addService(
    String userId,
    String hotelId,
    ServiceModel service,
  ) async {
    if (!isInitialized) {
      throw Exception('Firebase is not initialized.');
    }
    if (service.name.trim().isEmpty) {
      throw ArgumentError('Service name is required.');
    }
    final docRef = await _servicesRef(
      userId,
      hotelId,
    ).add(service.toFirestore());
    return docRef.id;
  }

  Future<void> updateService(
    String userId,
    String hotelId,
    ServiceModel service,
  ) async {
    if (!isInitialized || service.id == null || service.id!.isEmpty) {
      throw Exception('Cannot update service: missing id.');
    }
    await _servicesRef(
      userId,
      hotelId,
    ).doc(service.id!).update(service.toFirestore());
  }

  Future<void> deleteService(
    String userId,
    String hotelId,
    String serviceId,
  ) async {
    if (!isInitialized) return;
    await _servicesRef(userId, hotelId).doc(serviceId).delete();
  }
}

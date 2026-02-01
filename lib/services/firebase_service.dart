import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/user_model.dart';
import '../models/booking_model.dart';
import '../models/employer_model.dart';
import '../models/service_model.dart';

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

  /// All data is stored under hotels/{hotelId}/...
  CollectionReference<Map<String, dynamic>> _usersRef(String hotelId) =>
      firestore.collection('hotels').doc(hotelId).collection('users');
  CollectionReference<Map<String, dynamic>> _bookingsRef(String hotelId) =>
      firestore.collection('hotels').doc(hotelId).collection('bookings');
  CollectionReference<Map<String, dynamic>> _employersRef(String hotelId) =>
      firestore.collection('hotels').doc(hotelId).collection('employers');
  CollectionReference<Map<String, dynamic>> _rolesRef(String hotelId) =>
      firestore.collection('hotels').doc(hotelId).collection('roles');
  CollectionReference<Map<String, dynamic>> _departmentsRef(String hotelId) =>
      firestore.collection('hotels').doc(hotelId).collection('departments');
  CollectionReference<Map<String, dynamic>> _servicesRef(String hotelId) =>
      firestore.collection('hotels').doc(hotelId).collection('services');

  // ─── User operations (clients/guests) ─────────────────────────────────────
  Future<String> createUser(String hotelId, UserModel user) async {
    if (!isInitialized) {
      throw Exception(
        'Firebase is not initialized. Please configure Firebase first.',
      );
    }
    if (user.name.trim().isEmpty || user.phone.trim().isEmpty) {
      throw ArgumentError('User name and phone are required.');
    }
    final data = user.toFirestore();
    final docRef = await _usersRef(hotelId).add(data);
    return docRef.id;
  }

  Future<List<UserModel>> searchUsers(String hotelId, String query) async {
    if (query.isEmpty) return [];

    final queryLower = query.toLowerCase();
    final queryUpper = query.toUpperCase();
    if (!isInitialized) return [];

    final nameQuery1 = await _usersRef(hotelId)
        .where('name', isGreaterThanOrEqualTo: queryLower)
        .where('name', isLessThan: queryLower + 'z')
        .limit(20)
        .get();

    final nameQuery2 = await _usersRef(hotelId)
        .where('name', isGreaterThanOrEqualTo: queryUpper)
        .where('name', isLessThan: queryUpper + 'z')
        .limit(20)
        .get();

    final phoneQuery = await _usersRef(hotelId)
        .where('phone', isGreaterThanOrEqualTo: query)
        .where('phone', isLessThan: query + 'z')
        .limit(20)
        .get();

    final allDocs = <String, DocumentSnapshot<Map<String, dynamic>>>{};
    for (var doc in nameQuery1.docs) allDocs[doc.id] = doc;
    for (var doc in nameQuery2.docs) allDocs[doc.id] = doc;
    for (var doc in phoneQuery.docs) allDocs[doc.id] = doc;

    final results = allDocs.values
        .map((doc) => UserModel.fromFirestore(doc.data()!, doc.id))
        .where((user) {
          final nameMatch = user.name.toLowerCase().contains(queryLower);
          final phoneMatch = user.phone.contains(query);
          return nameMatch || phoneMatch;
        })
        .toList();

    return results;
  }

  Future<UserModel?> getUserById(String hotelId, String userId) async {
    if (!isInitialized) return null;
    final doc = await _usersRef(hotelId).doc(userId).get();
    if (doc.exists && doc.data() != null) {
      return UserModel.fromFirestore(doc.data()!, doc.id);
    }
    return null;
  }

  Future<UserModel?> getUserByPhone(String hotelId, String phone) async {
    if (!isInitialized) return null;
    final query = await _usersRef(hotelId)
        .where('phone', isEqualTo: phone)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      final doc = query.docs.first;
      return UserModel.fromFirestore(doc.data()!, doc.id);
    }
    return null;
  }

  // ─── Booking operations ─────────────────────────────────────────────────
  Future<String> createBooking(String hotelId, BookingModel booking) async {
    if (!isInitialized) {
      throw Exception(
        'Firebase is not initialized. Please configure Firebase first.',
      );
    }
    final docRef = await _bookingsRef(hotelId).add(booking.toFirestore());
    return docRef.id;
  }

  Future<List<BookingModel>> getBookings(
    String hotelId, {
    DateTime? startDate,
    DateTime? endDate,
    String? userId,
  }) async {
    if (!isInitialized) return [];
    Query<Map<String, dynamic>> q = _bookingsRef(hotelId);

    if (userId != null) q = q.where('userId', isEqualTo: userId);
    if (startDate != null) {
      q = q.where('checkIn',
          isGreaterThanOrEqualTo: startDate.toIso8601String());
    }
    if (endDate != null) {
      q = q.where('checkOut',
          isLessThanOrEqualTo: endDate.toIso8601String());
    }

    final snapshot = await q.orderBy('checkIn').get();
    return snapshot.docs
        .map((doc) =>
            BookingModel.fromFirestore(doc.data(), doc.id))
        .toList();
  }

  Future<BookingModel?> getBookingById(String hotelId, String bookingId) async {
    if (!isInitialized) return null;
    final doc = await _bookingsRef(hotelId).doc(bookingId).get();
    if (doc.exists && doc.data() != null) {
      return BookingModel.fromFirestore(doc.data()!, doc.id);
    }
    return null;
  }

  Future<void> updateBooking(String hotelId, BookingModel booking) async {
    if (!isInitialized || booking.id == null) return;
    await _bookingsRef(hotelId)
        .doc(booking.id)
        .update(booking.toFirestore());
  }

  Future<void> deleteBooking(String hotelId, String bookingId) async {
    if (!isInitialized) return;
    await _bookingsRef(hotelId).doc(bookingId).delete();
  }

  /// Stream of bookings for calendar (hotel-scoped).
  Stream<QuerySnapshot<Map<String, dynamic>>> bookingsSnapshot(
    String hotelId, {
    DateTime? startDate,
    DateTime? endDate,
  }) {
    if (!isInitialized) return const Stream.empty();
    Query<Map<String, dynamic>> q = _bookingsRef(hotelId);
    if (startDate != null) {
      q = q.where('checkIn',
          isGreaterThanOrEqualTo: startDate.toIso8601String());
    }
    if (endDate != null) {
      q = q.where('checkOut',
          isLessThanOrEqualTo: endDate.toIso8601String());
    }
    return q.orderBy('checkIn').snapshots();
  }

  // ─── Employer operations ─────────────────────────────────────────────────
  Future<List<EmployerModel>> searchEmployers(
      String hotelId, String query) async {
    if (!isInitialized || query.trim().isEmpty) return [];
    final q = query.trim().toLowerCase();
    final snapshot = await _employersRef(hotelId).limit(100).get();
    return snapshot.docs
        .map((d) => EmployerModel.fromFirestore(d.data(), d.id))
        .where((e) =>
            e.name.toLowerCase().contains(q) ||
            e.phone.contains(query.trim()) ||
            e.role.toLowerCase().contains(q) ||
            e.email.toLowerCase().contains(q))
        .toList();
  }

  Future<String> createEmployer(
      String hotelId, EmployerModel employer) async {
    if (!isInitialized) {
      throw Exception(
        'Firebase is not initialized. Please configure Firebase first.',
      );
    }
    final docRef = await _employersRef(hotelId).add(employer.toFirestore());
    return docRef.id;
  }

  Future<void> updateEmployer(
      String hotelId, EmployerModel employer) async {
    if (!isInitialized || employer.id == null || employer.id!.isEmpty) {
      throw Exception('Cannot update employer: missing id.');
    }
    final data = employer.toFirestore();
    data['updatedAt'] = DateTime.now().toIso8601String();
    await _employersRef(hotelId).doc(employer.id!).update(data);
  }

  // ─── Roles and departments (per hotel) ────────────────────────────────────
  Future<List<String>> getRoles(String hotelId) async {
    if (!isInitialized) return [];
    final snapshot = await _rolesRef(hotelId).get();
    final list = snapshot.docs
        .map((d) => d.data()['name'] as String? ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
    list.sort();
    return list;
  }

  Future<List<String>> getDepartments(String hotelId) async {
    if (!isInitialized) return [];
    final snapshot = await _departmentsRef(hotelId).get();
    final list = snapshot.docs
        .map((d) => d.data()['name'] as String? ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
    list.sort();
    return list;
  }

  Future<void> addRole(String hotelId, String name) async {
    if (!isInitialized || name.trim().isEmpty) return;
    final trimmed = name.trim();
    final existing = await _rolesRef(hotelId)
        .where('name', isEqualTo: trimmed)
        .limit(1)
        .get();
    if (existing.docs.isEmpty) {
      await _rolesRef(hotelId).add({'name': trimmed});
    }
  }

  Future<void> addDepartment(String hotelId, String name) async {
    if (!isInitialized || name.trim().isEmpty) return;
    final trimmed = name.trim();
    final existing = await _departmentsRef(hotelId)
        .where('name', isEqualTo: trimmed)
        .limit(1)
        .get();
    if (existing.docs.isEmpty) {
      await _departmentsRef(hotelId).add({'name': trimmed});
    }
  }

  // ─── Services (per hotel) ─────────────────────────────────────────────────
  Stream<List<ServiceModel>> getServicesStream(String hotelId) {
    if (!isInitialized) return Stream.value([]);
    return _servicesRef(hotelId).snapshots().map((snapshot) {
      final list = snapshot.docs
          .map((d) => ServiceModel.fromFirestore(d.data(), d.id))
          .toList();
      list.sort((a, b) => a.name.compareTo(b.name));
      return list;
    });
  }

  Future<List<ServiceModel>> getServices(String hotelId) async {
    if (!isInitialized) return [];
    final snapshot = await _servicesRef(hotelId).get();
    final list = snapshot.docs
        .map((d) => ServiceModel.fromFirestore(d.data(), d.id))
        .toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  Future<String> addService(String hotelId, ServiceModel service) async {
    if (!isInitialized) {
      throw Exception('Firebase is not initialized.');
    }
    if (service.name.trim().isEmpty) {
      throw ArgumentError('Service name is required.');
    }
    final docRef =
        await _servicesRef(hotelId).add(service.toFirestore());
    return docRef.id;
  }

  Future<void> updateService(
      String hotelId, ServiceModel service) async {
    if (!isInitialized || service.id == null || service.id!.isEmpty) {
      throw Exception('Cannot update service: missing id.');
    }
    await _servicesRef(hotelId)
        .doc(service.id!)
        .update(service.toFirestore());
  }

  Future<void> deleteService(String hotelId, String serviceId) async {
    if (!isInitialized) return;
    await _servicesRef(hotelId).doc(serviceId).delete();
  }
}

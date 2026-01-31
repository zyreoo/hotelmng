import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/user_model.dart';
import '../models/booking_model.dart';
import '../models/employer_model.dart';

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

  // User operations (clients/guests stored in Firestore 'users' collection)
  /// Creates a new user (client/guest) in Firestore and returns the document ID.
  /// Throws if Firebase is not initialized or if name/phone are empty.
  Future<String> createUser(UserModel user) async {
    if (!isInitialized) {
      throw Exception(
        'Firebase is not initialized. Please configure Firebase first.',
      );
    }
    if (user.name.trim().isEmpty || user.phone.trim().isEmpty) {
      throw ArgumentError('User name and phone are required.');
    }
    final data = user.toFirestore();
    final docRef = await firestore.collection('users').add(data);
    return docRef.id;
  }

  Future<List<UserModel>> searchUsers(String query) async {
    if (query.isEmpty) {
      return [];
    }

    final queryLower = query.toLowerCase();
    final queryUpper = query.toUpperCase();

    if (!isInitialized) {
      return [];
    }

    // Search by name (case-insensitive by checking both cases)
    final nameQuery1 = await firestore
        .collection('users')
        .where('name', isGreaterThanOrEqualTo: queryLower)
        .where('name', isLessThan: queryLower + 'z')
        .limit(20)
        .get();

    final nameQuery2 = await firestore
        .collection('users')
        .where('name', isGreaterThanOrEqualTo: queryUpper)
        .where('name', isLessThan: queryUpper + 'z')
        .limit(20)
        .get();

    // Search by phone
    final phoneQuery = await firestore
        .collection('users')
        .where('phone', isGreaterThanOrEqualTo: query)
        .where('phone', isLessThan: query + 'z')
        .limit(20)
        .get();

    // Combine and deduplicate
    final allDocs = <String, DocumentSnapshot>{};
    for (var doc in nameQuery1.docs) {
      allDocs[doc.id] = doc;
    }
    for (var doc in nameQuery2.docs) {
      allDocs[doc.id] = doc;
    }
    for (var doc in phoneQuery.docs) {
      allDocs[doc.id] = doc;
    }

    // Filter results to match query (case-insensitive)
    final results = allDocs.values
        .map(
          (doc) => UserModel.fromFirestore(
            doc.data() as Map<String, dynamic>,
            doc.id,
          ),
        )
        .where((user) {
          final nameMatch = user.name.toLowerCase().contains(queryLower);
          final phoneMatch = user.phone.contains(query);
          return nameMatch || phoneMatch;
        })
        .toList();

    return results;
  }

  Future<UserModel?> getUserById(String userId) async {
    if (!isInitialized) return null;
    final doc = await firestore.collection('users').doc(userId).get();
    if (doc.exists) {
      return UserModel.fromFirestore(doc.data()!, doc.id);
    }
    return null;
  }

  Future<UserModel?> getUserByPhone(String phone) async {
    if (!isInitialized) return null;
    final query = await firestore
        .collection('users')
        .where('phone', isEqualTo: phone)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      final doc = query.docs.first;
      return UserModel.fromFirestore(doc.data(), doc.id);
    }
    return null;
  }

  // Booking operations
  Future<String> createBooking(BookingModel booking) async {
    if (!isInitialized) {
      throw Exception(
        'Firebase is not initialized. Please configure Firebase first.',
      );
    }
    final docRef = await firestore
        .collection('bookings')
        .add(booking.toFirestore());
    return docRef.id;
  }

  Future<List<BookingModel>> getBookings({
    DateTime? startDate,
    DateTime? endDate,
    String? userId,
  }) async {
    if (!isInitialized) return [];
    Query query = firestore.collection('bookings');

    if (userId != null) {
      query = query.where('userId', isEqualTo: userId);
    }

    if (startDate != null) {
      query = query.where(
        'checkIn',
        isGreaterThanOrEqualTo: startDate.toIso8601String(),
      );
    }

    if (endDate != null) {
      query = query.where(
        'checkOut',
        isLessThanOrEqualTo: endDate.toIso8601String(),
      );
    }

    final snapshot = await query.orderBy('checkIn').get();
    return snapshot.docs
        .map(
          (doc) => BookingModel.fromFirestore(
            doc.data() as Map<String, dynamic>,
            doc.id,
          ),
        )
        .toList();
  }

  Future<BookingModel?> getBookingById(String bookingId) async {
    if (!isInitialized) return null;
    final doc = await firestore.collection('bookings').doc(bookingId).get();
    if (doc.exists) {
      return BookingModel.fromFirestore(doc.data()!, doc.id);
    }
    return null;
  }

  Future<void> updateBooking(BookingModel booking) async {
    if (!isInitialized || booking.id == null) return;
    await firestore
        .collection('bookings')
        .doc(booking.id)
        .update(booking.toFirestore());
  }

  Future<void> deleteBooking(String bookingId) async {
    if (!isInitialized) return;
    await firestore.collection('bookings').doc(bookingId).delete();
  }

  // Employer operations
  Future<List<EmployerModel>> searchEmployers(String query) async {
    if (!isInitialized || query.trim().isEmpty) return [];
    final q = query.trim().toLowerCase();
    final snapshot =
        await firestore.collection('employers').limit(100).get();
    return snapshot.docs
        .map((d) => EmployerModel.fromFirestore(d.data(), d.id))
        .where((e) =>
            e.name.toLowerCase().contains(q) ||
            e.phone.contains(query.trim()) ||
            e.role.toLowerCase().contains(q) ||
            e.email.toLowerCase().contains(q))
        .toList();
  }

  Future<String> createEmployer(EmployerModel employer) async {
    if (!isInitialized) {
      throw Exception(
        'Firebase is not initialized. Please configure Firebase first.',
      );
    }
    final docRef = await firestore
        .collection('employers')
        .add(employer.toFirestore());
    return docRef.id;
  }

  Future<void> updateEmployer(EmployerModel employer) async {
    if (!isInitialized || employer.id == null || employer.id!.isEmpty) {
      throw Exception('Cannot update employer: missing id.');
    }
    final data = employer.toFirestore();
    data['updatedAt'] = DateTime.now().toIso8601String();
    await firestore.collection('employers').doc(employer.id!).update(data);
  }

  // Roles and departments (custom "Other" values saved for dropdowns)
  Future<List<String>> getRoles() async {
    if (!isInitialized) return [];
    final snapshot = await firestore.collection('roles').get();
    final list = snapshot.docs
        .map((d) => d.data()['name'] as String? ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
    list.sort();
    return list;
  }

  Future<List<String>> getDepartments() async {
    if (!isInitialized) return [];
    final snapshot = await firestore.collection('departments').get();
    final list = snapshot.docs
        .map((d) => d.data()['name'] as String? ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
    list.sort();
    return list;
  }

  /// Saves a custom role to the DB so it appears in the dropdown next time.
  Future<void> addRole(String name) async {
    if (!isInitialized || name.trim().isEmpty) return;
    final trimmed = name.trim();
    final existing = await firestore
        .collection('roles')
        .where('name', isEqualTo: trimmed)
        .limit(1)
        .get();
    if (existing.docs.isEmpty) {
      await firestore.collection('roles').add({'name': trimmed});
    }
  }

  /// Saves a custom department to the DB so it appears in the dropdown next time.
  Future<void> addDepartment(String name) async {
    if (!isInitialized || name.trim().isEmpty) return;
    final trimmed = name.trim();
    final existing = await firestore
        .collection('departments')
        .where('name', isEqualTo: trimmed)
        .limit(1)
        .get();
    if (existing.docs.isEmpty) {
      await firestore.collection('departments').add({'name': trimmed});
    }
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/user_model.dart';
import '../models/booking_model.dart';

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

  // User operations
  Future<String> createUser(UserModel user) async {
    if (!isInitialized) {
      throw Exception(
        'Firebase is not initialized. Please configure Firebase first.',
      );
    }
    final docRef = await firestore.collection('users').add(user.toFirestore());
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
}

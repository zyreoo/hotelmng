/// Firestore implementation of [AuditLogWriter].
/// Writes to users/{userId}/hotels/{hotelId}/audit_logs with server timestamp.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/audit_log_models.dart';
import '../utils/audit_log_writer.dart';

/// Writes audit log entries to Firestore. Does not throw; the logger layer
/// catches any errors. Create with the current user and hotel context.
class FirestoreAuditLogWriter implements AuditLogWriter {
  FirestoreAuditLogWriter({
    required this.userId,
    required this.hotelId,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final String userId;
  final String hotelId;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _auditRef =>
      _firestore
          .collection('users')
          .doc(userId)
          .collection('hotels')
          .doc(hotelId)
          .collection('audit_logs');

  @override
  Future<void> write(AuditLogData data) async {
    final doc = data.toDocument();
    doc['timestamp'] = FieldValue.serverTimestamp();
    await _auditRef.add(doc);
  }
}

/// Domain models for audit log entries.
///
/// No UI, no Firebase. [toDocument] produces a JSON-safe map for storage.
/// Metadata must not contain sensitive data (no name/phone/email).

/// Supported audit actions for booking-related events.
abstract class AuditAction {
  static const String bookingCreated = 'BOOKING_CREATED';
  static const String bookingUpdated = 'BOOKING_UPDATED';
  static const String bookingDeleted = 'BOOKING_DELETED';
  static const String validationFailed = 'VALIDATION_FAILED';
  static const String overlapBlocked = 'OVERLAP_BLOCKED';
  static const String checkIn = 'CHECK_IN';
  static const String checkOut = 'CHECK_OUT';
}

/// Data for one audit log entry. All fields are stored; [metadata] is optional
/// and must be JSON-safe with no sensitive PII.
class AuditLogData {
  final String action;
  final String bookingId;
  final String roomId;
  final String userId;
  final Map<String, dynamic> metadata;

  const AuditLogData({
    required this.action,
    required this.bookingId,
    required this.roomId,
    required this.userId,
    this.metadata = const {},
  });

  /// Produces a map suitable for Firestore (or other storage).
  /// Strips null values from metadata; only JSON-safe values.
  /// Server timestamp is added by the writer, not here.
  Map<String, dynamic> toDocument() {
    final meta = _sanitizeMetadata(metadata);
    return <String, dynamic>{
      'action': action,
      'bookingId': bookingId,
      'roomId': roomId,
      'userId': userId,
      'metadata': meta,
    };
  }

  /// Ensure metadata is JSON-safe: only primitives and nested Map/List.
  /// Removes nulls. No personal data.
  static Map<String, dynamic> _sanitizeMetadata(Map<String, dynamic>? m) {
    if (m == null || m.isEmpty) return {};
    final out = <String, dynamic>{};
    for (final e in m.entries) {
      if (e.value == null) continue;
      if (e.value is Map) {
        out[e.key] = _sanitizeMetadata(Map<String, dynamic>.from(e.value as Map));
      } else if (e.value is List) {
        out[e.key] = (e.value as List).map((x) => x is Map ? _sanitizeMetadata(Map<String, dynamic>.from(x)) : x).toList();
      } else if (e.value is num || e.value is bool || e.value is String) {
        out[e.key] = e.value;
      }
    }
    return out;
  }
}

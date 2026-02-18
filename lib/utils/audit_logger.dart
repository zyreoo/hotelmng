/// Non-blocking audit logging for booking actions.
///
/// MUST catch all errors and never throw. Logging happens asynchronously;
/// callers can fire-and-forget. On writer failure, only a minimal debug
/// print is used (no rethrow).

import 'audit_log_models.dart';
import 'audit_log_writer.dart';

/// Logs a booking-related action via [writer]. Never throws.
/// [action] is the audit action (e.g. [AuditAction.bookingCreated]); the written
/// document uses this action. Returns a Future that completes when the write
/// is attempted. Callers may fire-and-forget.
Future<void> logBookingAction(
  String action,
  AuditLogData data,
  AuditLogWriter writer,
) async {
  try {
    final entry = AuditLogData(
      action: action,
      bookingId: data.bookingId,
      roomId: data.roomId,
      userId: data.userId,
      metadata: data.metadata,
    );
    await writer.write(entry);
  } catch (e, st) {
    // Must not crash app; no rethrow. Minimal structured debug only.
    // ignore: avoid_print
    print('AuditLog: write failed action=$action bookingId=${data.bookingId} error=$e');
    assert(() {
      // ignore: avoid_print
      print(st);
      return true;
    }());
  }
}

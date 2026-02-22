import 'package:hotelmng/utils/audit_log_models.dart';
import 'package:hotelmng/utils/audit_log_writer.dart';
import 'package:hotelmng/utils/audit_logger.dart';
import 'package:hotelmng/utils/booking_input_validator.dart';
import 'package:hotelmng/utils/booking_overlap_validator.dart';

/// Example: before save (create or update).
/// Caller is responsible for loading [existingBookings] (e.g. from Firestore)
/// for the room(s) being booked. Then validate and optionally log failures.
void exampleBeforeSave({
  required String? roomId,
  required DateTime? checkInUtc,
  required DateTime? checkOutUtc,
  required List<BookingInput> existingBookings,
  String? bookingIdForEdit,
  required String userId,
  required AuditLogWriter auditWriter,
}) {
  final error = validateBookingRawInput(
    roomId: roomId,
    checkInUtc: checkInUtc,
    checkOutUtc: checkOutUtc,
    existingBookings: existingBookings,
    bookingIdForEdit: bookingIdForEdit,
  );

  if (error != null) {
    // 2) Return structured error to caller — caller decides UI (SnackBar, dialog, etc.)
    // return error;

    // 3) Optional: log validation failure (non-blocking; must not throw)
    final isOverlap = error.code == 'BOOKING_OVERLAP';
    final action = isOverlap
        ? AuditAction.overlapBlocked
        : AuditAction.validationFailed;
    final metadata = <String, dynamic>{
      'errorCode': error.code,
      'field': error.field,
    };
    if (error.conflictingBookingId != null) {
      metadata['conflictingBookingId'] = error.conflictingBookingId;
    }
    final data = AuditLogData(
      action: action,
      bookingId: bookingIdForEdit ?? '',
      roomId: roomId ?? '',
      userId: userId,
      metadata: metadata,
    );
    logBookingAction(action, data, auditWriter); // fire-and-forget
    return;
  }

  // 4) Proceed to save (create/update) in Firebase — not shown here.
}

/// Example: after successful create.
void exampleAfterCreate({
  required String bookingId,
  required String roomId,
  required String userId,
  required AuditLogWriter auditWriter,
}) {
  final data = AuditLogData(
    action: AuditAction.bookingCreated,
    bookingId: bookingId,
    roomId: roomId,
    userId: userId,
  );
  logBookingAction(AuditAction.bookingCreated, data, auditWriter);
}

/// Example: after successful update.
void exampleAfterUpdate({
  required String bookingId,
  required String roomId,
  required String userId,
  required AuditLogWriter auditWriter,
}) {
  final data = AuditLogData(
    action: AuditAction.bookingUpdated,
    bookingId: bookingId,
    roomId: roomId,
    userId: userId,
  );
  logBookingAction(AuditAction.bookingUpdated, data, auditWriter);
}

/// Example: after successful delete.
void exampleAfterDelete({
  required String bookingId,
  required String roomId,
  required String userId,
  required AuditLogWriter auditWriter,
}) {
  final data = AuditLogData(
    action: AuditAction.bookingDeleted,
    bookingId: bookingId,
    roomId: roomId,
    userId: userId,
  );
  logBookingAction(AuditAction.bookingDeleted, data, auditWriter);
}

/// Domain models and validation logic for detecting booking overlaps.
///
/// This module is intentionally pure:
/// - No UI dependencies
/// - No Firebase or network calls
/// - All functions are fully unit-testable
///
/// All DateTime values are treated as UTC and interpreted as
/// half-open intervals: [checkInUtc, checkOutUtc) where check-out is exclusive.

/// Lightweight booking input used only for validation.
class BookingInput {
  final String bookingId;
  final String roomId;
  final DateTime checkInUtc;
  final DateTime checkOutUtc;

  BookingInput({
    required this.bookingId,
    required this.roomId,
    required DateTime checkInUtc,
    required DateTime checkOutUtc,
  })  : checkInUtc = checkInUtc.toUtc(),
        checkOutUtc = checkOutUtc.toUtc();
}

/// Structured error returned by [validateBooking].
class BookingOverlapError {
  final String code;
  final String message;
  final String? conflictingBookingId;

  const BookingOverlapError({
    required this.code,
    required this.message,
    this.conflictingBookingId,
  });

  /// Factory for invalid date ranges (check-in >= check-out).
  factory BookingOverlapError.invalidDates() => const BookingOverlapError(
        code: 'INVALID_DATES',
        message: 'Check-in must be before check-out',
      );

  /// Factory for a detected overlap with another booking.
  factory BookingOverlapError.bookingOverlap(String conflictingBookingId) =>
      BookingOverlapError(
        code: 'BOOKING_OVERLAP',
        message: 'Room is already booked for selected dates',
        conflictingBookingId: conflictingBookingId,
      );
}

/// Validate [newBooking] against a list of [existingBookings].
///
/// Returns:
/// - `null` when the new booking is valid.
/// - [BookingOverlapError.invalidDates] when check-in >= check-out.
/// - [BookingOverlapError.bookingOverlap] when an overlap is detected for the
///   same room, with [conflictingBookingId] set to the first conflicting one.
///
/// Rules:
/// - Dates are UTC and treated as [checkInUtc, checkOutUtc) (check-out exclusive).
/// - Overlap condition:
///       new.checkIn < existing.checkOut &&
///       new.checkOut > existing.checkIn
/// - Only bookings for the same roomId are compared.
/// - When editing, the booking with the same bookingId is ignored.
BookingOverlapError? validateBooking(
  BookingInput newBooking,
  List<BookingInput> existingBookings,
) {
  final checkIn = newBooking.checkInUtc;
  final checkOut = newBooking.checkOutUtc;

  // 1) Basic range validation.
  if (!checkIn.isBefore(checkOut)) {
    return BookingOverlapError.invalidDates();
  }

  // 2) Overlap check against existing bookings for the same room.
  for (final existing in existingBookings) {
    // Skip different rooms.
    if (existing.roomId != newBooking.roomId) continue;

    // When editing, ignore the same bookingId.
    if (existing.bookingId == newBooking.bookingId) continue;

    final existingStart = existing.checkInUtc;
    final existingEnd = existing.checkOutUtc;

    if (_intervalsOverlap(
      checkIn,
      checkOut,
      existingStart,
      existingEnd,
    )) {
      return BookingOverlapError.bookingOverlap(existing.bookingId);
    }
  }

  // 3) No conflicts.
  return null;
}

/// Returns true if two half-open intervals [aStart, aEnd) and [bStart, bEnd)
/// overlap in time.
///
/// This uses the standard condition for overlap:
///   aStart < bEnd && aEnd > bStart
///
/// Because check-out is exclusive, same-moment boundaries like:
/// - aEnd == bStart  => allowed
/// - aStart == bEnd  => allowed
bool _intervalsOverlap(
  DateTime aStart,
  DateTime aEnd,
  DateTime bStart,
  DateTime bEnd,
) {
  return aStart.isBefore(bEnd) && aEnd.isAfter(bStart);
}


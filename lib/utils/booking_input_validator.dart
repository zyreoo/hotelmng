/// Strict, testable input validation for bookings.
///
/// Framework-agnostic: no Flutter, no database calls.
/// All comparisons in UTC; checkOut is exclusive (half-open interval).
/// Returns structured [ValidationError] or null; never throws.

import 'package:hotelmng/utils/booking_overlap_validator.dart';

/// Structured validation error returned by validators.
/// Use [toJson] for serialization; [conflictingBookingId] only set for overlap.
class ValidationError {
  final String code;
  final String message;
  final String field;
  final String? conflictingBookingId;

  const ValidationError({
    required this.code,
    required this.message,
    required this.field,
    this.conflictingBookingId,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'code': code,
      'message': message,
      'field': field,
    };
    if (conflictingBookingId != null) {
      map['conflictingBookingId'] = conflictingBookingId;
    }
    return map;
  }
}

/// Default max future check-in: 2 years from reference date.
const int maxFutureCheckInDays = 730;

/// Validates a fully constructed [BookingInput] against business rules and
/// [existingBookings]. Returns the first [ValidationError] or null if valid.
///
/// Rules (first failure wins):
/// 1) roomId non-empty
/// 2) checkIn < checkOut (invalid range)
/// 3) Stay length >= 1 night (date-only UTC)
/// 4) checkIn not more than [maxFutureCheckInDays] in the future from [nowUtc]
/// 5) No overlap with existing bookings (same room; ignores same bookingId when editing)
///
/// [nowUtc] is injectable for tests; defaults to [DateTime.now].toUtc().
ValidationError? validateBookingInput({
  required BookingInput booking,
  required List<BookingInput> existingBookings,
  DateTime Function()? nowUtc,
}) {
  final now = (nowUtc ?? () => DateTime.now().toUtc())();

  // 1) roomId must exist and not be empty
  if (booking.roomId.trim().isEmpty) {
    return const ValidationError(
      code: 'MISSING_ROOM_ID',
      message: 'Room is required',
      field: 'roomId',
    );
  }

  final checkIn = booking.checkInUtc;
  final checkOut = booking.checkOutUtc;

  // 2) checkIn < checkOut (invalid range)
  if (!checkIn.isBefore(checkOut)) {
    return const ValidationError(
      code: 'INVALID_DATES',
      message: 'Check-in must be before check-out',
      field: 'dateRange',
    );
  }

  // 3) Stay length at least 1 night (exclusive checkout; date-only UTC)
  final checkInDate = _dateOnlyUtc(checkIn);
  final checkOutDate = _dateOnlyUtc(checkOut);
  if (!checkOutDate.isAfter(checkInDate)) {
    return const ValidationError(
      code: 'STAY_TOO_SHORT',
      message: 'Stay must be at least 1 night',
      field: 'dateRange',
    );
  }

  // 4) checkIn not more than 2 years in the future
  final maxFuture = now.add(const Duration(days: maxFutureCheckInDays));
  if (checkIn.isAfter(maxFuture)) {
    return const ValidationError(
      code: 'DATE_TOO_FAR',
      message: 'Check-in cannot be more than 2 years in the future',
      field: 'checkInDate',
    );
  }

  // 5) No overlap with existing bookings
  final overlapError = validateBooking(booking, existingBookings);
  if (overlapError != null) {
    if (overlapError.code == 'INVALID_DATES') {
      return const ValidationError(
        code: 'INVALID_DATES',
        message: 'Check-in must be before check-out',
        field: 'dateRange',
      );
    }
    return ValidationError(
      code: 'BOOKING_OVERLAP',
      message: overlapError.message,
      field: 'overlap',
      conflictingBookingId: overlapError.conflictingBookingId,
    );
  }

  return null;
}

/// Validates raw inputs before building a [BookingInput].
/// Use when dates may be null (e.g. from form or parsing).
///
/// Returns first failure:
/// - MISSING_ROOM_ID if roomId is null or blank
/// - MISSING_DATES if checkInUtc or checkOutUtc is null
/// - Then same rules as [validateBookingInput]: INVALID_DATES, STAY_TOO_SHORT,
///   DATE_TOO_FAR, BOOKING_OVERLAP
///
/// [bookingIdForEdit] when non-null is used as the booking id for overlap check
/// (existing booking with same id is ignored). Pass a placeholder for new bookings.
ValidationError? validateBookingRawInput({
  required String? roomId,
  required DateTime? checkInUtc,
  required DateTime? checkOutUtc,
  required List<BookingInput> existingBookings,
  String? bookingIdForEdit,
  DateTime Function()? nowUtc,
}) {
  // 1) roomId must exist and not be empty
  if (roomId == null || roomId.trim().isEmpty) {
    return const ValidationError(
      code: 'MISSING_ROOM_ID',
      message: 'Room is required',
      field: 'roomId',
    );
  }

  // 2) Dates must be present
  if (checkInUtc == null) {
    return const ValidationError(
      code: 'MISSING_DATES',
      message: 'Check-in date is required',
      field: 'checkInDate',
    );
  }
  if (checkOutUtc == null) {
    return const ValidationError(
      code: 'MISSING_DATES',
      message: 'Check-out date is required',
      field: 'checkOutDate',
    );
  }

  final booking = BookingInput(
    bookingId: bookingIdForEdit ?? '',
    roomId: roomId.trim(),
    checkInUtc: checkInUtc,
    checkOutUtc: checkOutUtc,
  );

  return validateBookingInput(
    booking: booking,
    existingBookings: existingBookings,
    nowUtc: nowUtc,
  );
}

/// Normalize to midnight UTC for date-only comparison.
DateTime _dateOnlyUtc(DateTime dt) {
  final utc = dt.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}

import 'package:flutter_test/flutter_test.dart';
import 'package:hotelmng/utils/booking_input_validator.dart';
import 'package:hotelmng/utils/booking_overlap_validator.dart';

void main() {
  group('validateBookingInput', () {
    test('missing roomId returns MISSING_ROOM_ID', () {
      final booking = BookingInput(
        bookingId: 'b1',
        roomId: '   ',
        checkInUtc: DateTime.utc(2025, 1, 10),
        checkOutUtc: DateTime.utc(2025, 1, 12),
      );
      final err = validateBookingInput(
        booking: booking,
        existingBookings: [],
      );
      expect(err, isNotNull);
      expect(err!.code, 'MISSING_ROOM_ID');
      expect(err.field, 'roomId');
    });

    test('invalid dates (checkIn >= checkOut) returns INVALID_DATES', () {
      final booking = BookingInput(
        bookingId: 'b1',
        roomId: '101',
        checkInUtc: DateTime.utc(2025, 1, 12),
        checkOutUtc: DateTime.utc(2025, 1, 10),
      );
      final err = validateBookingInput(
        booking: booking,
        existingBookings: [],
      );
      expect(err, isNotNull);
      expect(err!.code, 'INVALID_DATES');
      expect(err.field, 'dateRange');
    });

    test('same-day stay (0 nights) returns STAY_TOO_SHORT', () {
      final booking = BookingInput(
        bookingId: 'b1',
        roomId: '101',
        checkInUtc: DateTime.utc(2025, 1, 10, 8),
        checkOutUtc: DateTime.utc(2025, 1, 10, 18),
      );
      final err = validateBookingInput(
        booking: booking,
        existingBookings: [],
      );
      expect(err, isNotNull);
      expect(err!.code, 'STAY_TOO_SHORT');
      expect(err.field, 'dateRange');
    });

    test('checkIn more than 2 years in future returns DATE_TOO_FAR', () {
      final now = DateTime.utc(2025, 1, 1);
      final booking = BookingInput(
        bookingId: 'b1',
        roomId: '101',
        checkInUtc: DateTime.utc(2027, 6, 1),
        checkOutUtc: DateTime.utc(2027, 6, 3),
      );
      final err = validateBookingInput(
        booking: booking,
        existingBookings: [],
        nowUtc: () => now,
      );
      expect(err, isNotNull);
      expect(err!.code, 'DATE_TOO_FAR');
      expect(err.field, 'checkInDate');
    });

    test('overlap returns BOOKING_OVERLAP with conflictingBookingId', () {
      final existing = BookingInput(
        bookingId: 'existing',
        roomId: '101',
        checkInUtc: DateTime.utc(2025, 1, 10),
        checkOutUtc: DateTime.utc(2025, 1, 15),
      );
      final newBooking = BookingInput(
        bookingId: 'new',
        roomId: '101',
        checkInUtc: DateTime.utc(2025, 1, 12),
        checkOutUtc: DateTime.utc(2025, 1, 16),
      );
      final err = validateBookingInput(
        booking: newBooking,
        existingBookings: [existing],
      );
      expect(err, isNotNull);
      expect(err!.code, 'BOOKING_OVERLAP');
      expect(err.field, 'overlap');
      expect(err.conflictingBookingId, 'existing');
    });

    test('non-overlap returns null', () {
      final existing = BookingInput(
        bookingId: 'existing',
        roomId: '101',
        checkInUtc: DateTime.utc(2025, 1, 10),
        checkOutUtc: DateTime.utc(2025, 1, 12),
      );
      final newBooking = BookingInput(
        bookingId: 'new',
        roomId: '101',
        checkInUtc: DateTime.utc(2025, 1, 12),
        checkOutUtc: DateTime.utc(2025, 1, 14),
      );
      final err = validateBookingInput(
        booking: newBooking,
        existingBookings: [existing],
      );
      expect(err, isNull);
    });

    test('edit same bookingId ignores self, returns null', () {
      final existing = BookingInput(
        bookingId: 'b1',
        roomId: '101',
        checkInUtc: DateTime.utc(2025, 1, 10),
        checkOutUtc: DateTime.utc(2025, 1, 12),
      );
      final edited = BookingInput(
        bookingId: 'b1',
        roomId: '101',
        checkInUtc: DateTime.utc(2025, 1, 11),
        checkOutUtc: DateTime.utc(2025, 1, 13),
      );
      final err = validateBookingInput(
        booking: edited,
        existingBookings: [existing],
      );
      expect(err, isNull);
    });

    test('valid booking returns null', () {
      final booking = BookingInput(
        bookingId: 'b1',
        roomId: '101',
        checkInUtc: DateTime.utc(2025, 1, 10),
        checkOutUtc: DateTime.utc(2025, 1, 12),
      );
      final err = validateBookingInput(
        booking: booking,
        existingBookings: [],
      );
      expect(err, isNull);
    });
  });

  group('validateBookingRawInput', () {
    test('missing roomId returns MISSING_ROOM_ID', () {
      final err = validateBookingRawInput(
        roomId: null,
        checkInUtc: DateTime.utc(2025, 1, 10),
        checkOutUtc: DateTime.utc(2025, 1, 12),
        existingBookings: [],
      );
      expect(err, isNotNull);
      expect(err!.code, 'MISSING_ROOM_ID');
    });

    test('empty roomId returns MISSING_ROOM_ID', () {
      final err = validateBookingRawInput(
        roomId: '  ',
        checkInUtc: DateTime.utc(2025, 1, 10),
        checkOutUtc: DateTime.utc(2025, 1, 12),
        existingBookings: [],
      );
      expect(err, isNotNull);
      expect(err!.code, 'MISSING_ROOM_ID');
    });

    test('missing checkInUtc returns MISSING_DATES', () {
      final err = validateBookingRawInput(
        roomId: '101',
        checkInUtc: null,
        checkOutUtc: DateTime.utc(2025, 1, 12),
        existingBookings: [],
      );
      expect(err, isNotNull);
      expect(err!.code, 'MISSING_DATES');
      expect(err.field, 'checkInDate');
    });

    test('missing checkOutUtc returns MISSING_DATES', () {
      final err = validateBookingRawInput(
        roomId: '101',
        checkInUtc: DateTime.utc(2025, 1, 10),
        checkOutUtc: null,
        existingBookings: [],
      );
      expect(err, isNotNull);
      expect(err!.code, 'MISSING_DATES');
      expect(err.field, 'checkOutDate');
    });

    test('invalid dates (checkIn >= checkOut) returns INVALID_DATES', () {
      final err = validateBookingRawInput(
        roomId: '101',
        checkInUtc: DateTime.utc(2025, 1, 12),
        checkOutUtc: DateTime.utc(2025, 1, 10),
        existingBookings: [],
      );
      expect(err, isNotNull);
      expect(err!.code, 'INVALID_DATES');
    });

    test('same-day stay (0 nights) returns STAY_TOO_SHORT', () {
      // checkIn < checkOut but same calendar day -> 0 nights
      final err = validateBookingRawInput(
        roomId: '101',
        checkInUtc: DateTime.utc(2025, 1, 10, 8),
        checkOutUtc: DateTime.utc(2025, 1, 10, 18),
        existingBookings: [],
      );
      expect(err, isNotNull);
      expect(err!.code, 'STAY_TOO_SHORT');
    });

    test('same moment checkIn and checkOut returns INVALID_DATES', () {
      final err = validateBookingRawInput(
        roomId: '101',
        checkInUtc: DateTime.utc(2025, 1, 10),
        checkOutUtc: DateTime.utc(2025, 1, 10),
        existingBookings: [],
      );
      expect(err, isNotNull);
      expect(err!.code, 'INVALID_DATES');
    });

    test('date too far with nowUtc injection returns DATE_TOO_FAR', () {
      final err = validateBookingRawInput(
        roomId: '101',
        checkInUtc: DateTime.utc(2028, 1, 1),
        checkOutUtc: DateTime.utc(2028, 1, 3),
        existingBookings: [],
        nowUtc: () => DateTime.utc(2025, 1, 1),
      );
      expect(err, isNotNull);
      expect(err!.code, 'DATE_TOO_FAR');
    });

    test('overlap returns BOOKING_OVERLAP with conflictingBookingId', () {
      final existing = BookingInput(
        bookingId: 'other',
        roomId: '101',
        checkInUtc: DateTime.utc(2025, 1, 10),
        checkOutUtc: DateTime.utc(2025, 1, 15),
      );
      final err = validateBookingRawInput(
        roomId: '101',
        checkInUtc: DateTime.utc(2025, 1, 12),
        checkOutUtc: DateTime.utc(2025, 1, 16),
        existingBookings: [existing],
        bookingIdForEdit: 'new',
      );
      expect(err, isNotNull);
      expect(err!.code, 'BOOKING_OVERLAP');
      expect(err.conflictingBookingId, 'other');
    });

    test('valid raw input returns null', () {
      final err = validateBookingRawInput(
        roomId: '101',
        checkInUtc: DateTime.utc(2025, 1, 10),
        checkOutUtc: DateTime.utc(2025, 1, 12),
        existingBookings: [],
      );
      expect(err, isNull);
    });
  });

  group('ValidationError.toJson', () {
    test('includes code message field and optional conflictingBookingId', () {
      final err = ValidationError(
        code: 'BOOKING_OVERLAP',
        message: 'Room is already booked',
        field: 'overlap',
        conflictingBookingId: 'x123',
      );
      final json = err.toJson();
      expect(json['code'], 'BOOKING_OVERLAP');
      expect(json['message'], 'Room is already booked');
      expect(json['field'], 'overlap');
      expect(json['conflictingBookingId'], 'x123');
    });
  });
}

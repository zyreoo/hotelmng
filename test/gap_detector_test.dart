import 'package:flutter_test/flutter_test.dart';
import 'package:hotelmng/utils/gap_detector.dart';

void main() {
  group('detectGaps', () {
    test('empty list returns no gaps', () {
      expect(detectGaps([]), isEmpty);
    });

    test('single booking returns no gaps', () {
      final booking = GapBookingInput(
        bookingId: 'b1',
        roomId: '101',
        checkInUtc: DateTime.utc(2025, 1, 10),
        checkOutUtc: DateTime.utc(2025, 1, 12),
      );
      expect(detectGaps([booking]), isEmpty);
    });

    test('back-to-back bookings (no gap) returns empty', () {
      final b1 = GapBookingInput(
        bookingId: 'b1',
        roomId: '101',
        checkInUtc: DateTime.utc(2025, 1, 10),
        checkOutUtc: DateTime.utc(2025, 1, 12),
      );
      final b2 = GapBookingInput(
        bookingId: 'b2',
        roomId: '101',
        checkInUtc: DateTime.utc(2025, 1, 12),
        checkOutUtc: DateTime.utc(2025, 1, 15),
      );
      expect(detectGaps([b1, b2]), isEmpty);
    });

    test('overlapping bookings returns no gap', () {
      final b1 = GapBookingInput(
        bookingId: 'b1',
        roomId: '101',
        checkInUtc: DateTime.utc(2025, 1, 10),
        checkOutUtc: DateTime.utc(2025, 1, 14),
      );
      final b2 = GapBookingInput(
        bookingId: 'b2',
        roomId: '101',
        checkInUtc: DateTime.utc(2025, 1, 12),
        checkOutUtc: DateTime.utc(2025, 1, 16),
      );
      expect(detectGaps([b1, b2]), isEmpty);
    });

    test('1-night gap is detected', () {
      final b1 = GapBookingInput(
        bookingId: 'b1',
        roomId: '101',
        checkInUtc: DateTime.utc(2025, 1, 10),
        checkOutUtc: DateTime.utc(2025, 1, 12),
      );
      final b2 = GapBookingInput(
        bookingId: 'b2',
        roomId: '101',
        checkInUtc: DateTime.utc(2025, 1, 13),
        checkOutUtc: DateTime.utc(2025, 1, 15),
      );
      final gaps = detectGaps([b1, b2]);
      expect(gaps, hasLength(1));
      expect(gaps.first.gapNights, 1);
      expect(gaps.first.previousBookingId, 'b1');
      expect(gaps.first.nextBookingId, 'b2');
    });

    test('2-night gap is detected', () {
      final b1 = GapBookingInput(
        bookingId: 'b1',
        roomId: '101',
        checkInUtc: DateTime.utc(2025, 1, 10),
        checkOutUtc: DateTime.utc(2025, 1, 12),
      );
      final b2 = GapBookingInput(
        bookingId: 'b2',
        roomId: '101',
        checkInUtc: DateTime.utc(2025, 1, 14),
        checkOutUtc: DateTime.utc(2025, 1, 16),
      );
      final gaps = detectGaps([b1, b2]);
      expect(gaps, hasLength(1));
      expect(gaps.first.gapNights, 2);
    });

    test('3-night gap is ignored', () {
      final b1 = GapBookingInput(
        bookingId: 'b1',
        roomId: '101',
        checkInUtc: DateTime.utc(2025, 1, 10),
        checkOutUtc: DateTime.utc(2025, 1, 12),
      );
      final b2 = GapBookingInput(
        bookingId: 'b2',
        roomId: '101',
        checkInUtc: DateTime.utc(2025, 1, 15),
        checkOutUtc: DateTime.utc(2025, 1, 17),
      );
      expect(detectGaps([b1, b2]), isEmpty);
    });

    test('different rooms are treated independently', () {
      final a1 = GapBookingInput(
        bookingId: 'a1',
        roomId: '101',
        checkInUtc: DateTime.utc(2025, 1, 10),
        checkOutUtc: DateTime.utc(2025, 1, 12),
      );
      final a2 = GapBookingInput(
        bookingId: 'a2',
        roomId: '101',
        checkInUtc: DateTime.utc(2025, 1, 13),
        checkOutUtc: DateTime.utc(2025, 1, 15),
      );
      final b1 = GapBookingInput(
        bookingId: 'b1',
        roomId: '102',
        checkInUtc: DateTime.utc(2025, 1, 10),
        checkOutUtc: DateTime.utc(2025, 1, 12),
      );
      final b2 = GapBookingInput(
        bookingId: 'b2',
        roomId: '102',
        checkInUtc: DateTime.utc(2025, 1, 12),
        checkOutUtc: DateTime.utc(2025, 1, 14),
      );
      final gaps = detectGaps([a1, a2, b1, b2]);
      expect(gaps, hasLength(1));
      expect(gaps.first.roomId, '101');
    });

    test('bookings in reverse order still detected', () {
      final b2 = GapBookingInput(
        bookingId: 'b2',
        roomId: '101',
        checkInUtc: DateTime.utc(2025, 1, 14),
        checkOutUtc: DateTime.utc(2025, 1, 16),
      );
      final b1 = GapBookingInput(
        bookingId: 'b1',
        roomId: '101',
        checkInUtc: DateTime.utc(2025, 1, 10),
        checkOutUtc: DateTime.utc(2025, 1, 12),
      );
      final gaps = detectGaps([b2, b1]);
      expect(gaps, hasLength(1));
      expect(gaps.first.gapNights, 2);
    });

    test('invalid booking is ignored', () {
      final invalid = GapBookingInput(
        bookingId: 'bad',
        roomId: '101',
        checkInUtc: DateTime.utc(2025, 1, 12),
        checkOutUtc: DateTime.utc(2025, 1, 10),
      );
      final valid = GapBookingInput(
        bookingId: 'ok',
        roomId: '101',
        checkInUtc: DateTime.utc(2025, 1, 15),
        checkOutUtc: DateTime.utc(2025, 1, 17),
      );
      expect(detectGaps([invalid, valid]), isEmpty);
    });

    test('does not mutate original list', () {
      final b2 = GapBookingInput(
        bookingId: 'b2',
        roomId: '101',
        checkInUtc: DateTime.utc(2025, 1, 14),
        checkOutUtc: DateTime.utc(2025, 1, 16),
      );
      final b1 = GapBookingInput(
        bookingId: 'b1',
        roomId: '101',
        checkInUtc: DateTime.utc(2025, 1, 10),
        checkOutUtc: DateTime.utc(2025, 1, 12),
      );
      final original = [b2, b1];
      detectGaps(original);
      expect(original[0].bookingId, 'b2');
      expect(original[1].bookingId, 'b1');
    });

    test('BookingGap.toJson contains correct keys', () {
      final b1 = GapBookingInput(
        bookingId: 'b1',
        roomId: '101',
        checkInUtc: DateTime.utc(2025, 1, 10),
        checkOutUtc: DateTime.utc(2025, 1, 12),
      );
      final b2 = GapBookingInput(
        bookingId: 'b2',
        roomId: '101',
        checkInUtc: DateTime.utc(2025, 1, 13),
        checkOutUtc: DateTime.utc(2025, 1, 15),
      );
      final json = detectGaps([b1, b2]).first.toJson();
      expect(json.keys, containsAll(['roomId', 'gapStart', 'gapEnd', 'gapNights', 'previousBookingId', 'nextBookingId']));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:hotelmng/utils/gap_detector.dart';
import 'package:hotelmng/utils/optimization_suggestions.dart';

GapBookingInput _booking({
  required String id,
  required String roomId,
  required DateTime checkIn,
  required DateTime checkOut,
}) =>
    GapBookingInput(
      bookingId: id,
      roomId: roomId,
      checkInUtc: checkIn,
      checkOutUtc: checkOut,
    );

void main() {
  final fakeNow = DateTime.utc(2025, 1, 1);

  group('generateOptimizationSuggestions', () {
    test('empty bookings returns no suggestions', () {
      final result = generateOptimizationSuggestions([], nowUtc: () => fakeNow);
      expect(result, isEmpty);
    });

    test('fully occupied room returns no suggestions', () {
      final bookings = [
        _booking(
          id: 'b1',
          roomId: '101',
          checkIn: DateTime.utc(2025, 1, 1),
          checkOut: DateTime.utc(2025, 1, 31),
        ),
      ];
      final result = generateOptimizationSuggestions(
        bookings,
        windowStart: fakeNow,
        nowUtc: () => fakeNow,
      );
      expect(result.any((s) => s.type == SuggestionType.lowOccupancy), isFalse);
    });

    test('1-night gap generates SHORT_GAP suggestion', () {
      final bookings = [
        _booking(id: 'b1', roomId: '101', checkIn: DateTime.utc(2025, 1, 5), checkOut: DateTime.utc(2025, 1, 10)),
        _booking(id: 'b2', roomId: '101', checkIn: DateTime.utc(2025, 1, 11), checkOut: DateTime.utc(2025, 1, 15)),
      ];
      final result = generateOptimizationSuggestions(
        bookings,
        windowStart: fakeNow,
        nowUtc: () => fakeNow,
      );
      final gapSuggestion = result.firstWhere((s) => s.type == SuggestionType.shortGap);
      expect(gapSuggestion.roomId, '101');
      expect(gapSuggestion.relatedGapCount, 1);
    });

    test('more than 3 gaps generates FRAGMENTATION', () {
      final bookings = <GapBookingInput>[];
      for (int i = 0; i < 5; i++) {
        final start = DateTime.utc(2025, 1, 1 + i * 3);
        final end = start.add(const Duration(days: 2));
        bookings.add(_booking(id: 'b$i', roomId: '101', checkIn: start, checkOut: end));
      }
      final result = generateOptimizationSuggestions(
        bookings,
        windowStart: fakeNow,
        nowUtc: () => fakeNow,
      );
      expect(result.any((s) => s.type == SuggestionType.fragmentation), isTrue);
    });

    test('occupancy below 50% generates LOW_OCCUPANCY', () {
      final bookings = [
        _booking(id: 'b1', roomId: '101', checkIn: DateTime.utc(2025, 1, 1), checkOut: DateTime.utc(2025, 1, 6)),
      ];
      final result = generateOptimizationSuggestions(
        bookings,
        windowStart: fakeNow,
        windowDays: 30,
        nowUtc: () => fakeNow,
      );
      expect(result.any((s) => s.type == SuggestionType.lowOccupancy), isTrue);
    });

    test('suggestions sorted by impactScore descending', () {
      final bookings = <GapBookingInput>[];
      for (int i = 0; i < 5; i++) {
        final start = DateTime.utc(2025, 1, 1 + i * 3);
        final end = start.add(const Duration(days: 2));
        bookings.add(_booking(id: 'b$i', roomId: '101', checkIn: start, checkOut: end));
      }
      final result = generateOptimizationSuggestions(
        bookings,
        windowStart: fakeNow,
        windowDays: 30,
        nowUtc: () => fakeNow,
      );
      for (int i = 0; i < result.length - 1; i++) {
        expect(result[i].impactScore, greaterThanOrEqualTo(result[i + 1].impactScore));
      }
    });

    test('does not mutate input bookings', () {
      final b2 = _booking(id: 'b2', roomId: '101', checkIn: DateTime.utc(2025, 1, 14), checkOut: DateTime.utc(2025, 1, 16));
      final b1 = _booking(id: 'b1', roomId: '101', checkIn: DateTime.utc(2025, 1, 10), checkOut: DateTime.utc(2025, 1, 12));
      final original = [b2, b1];
      generateOptimizationSuggestions(original, nowUtc: () => fakeNow);
      expect(original[0].bookingId, 'b2');
      expect(original[1].bookingId, 'b1');
    });
  });
}

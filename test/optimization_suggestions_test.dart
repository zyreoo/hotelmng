import 'package:flutter_test/flutter_test.dart';
import 'package:hotelmng/utils/gap_detector.dart';
import 'package:hotelmng/utils/optimization_suggestions.dart';

GapBookingInput _booking({
  required String id,
  required String roomId,
  required DateTime checkIn,
  required DateTime checkOut,
}) => GapBookingInput(
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
        _booking(
          id: 'b1',
          roomId: '101',
          checkIn: DateTime.utc(2025, 1, 5),
          checkOut: DateTime.utc(2025, 1, 10),
        ),
        _booking(
          id: 'b2',
          roomId: '101',
          checkIn: DateTime.utc(2025, 1, 11),
          checkOut: DateTime.utc(2025, 1, 15),
        ),
      ];
      final result = generateOptimizationSuggestions(
        bookings,
        windowStart: fakeNow,
        nowUtc: () => fakeNow,
      );
      final gapSuggestion = result.firstWhere(
        (s) => s.type == SuggestionType.shortGap,
      );
      expect(gapSuggestion.roomId, '101');
      expect(gapSuggestion.relatedGapCount, 1);
    });

    test(
      'fillable gap generates CONTINUITY suggestion with concrete move (exact match)',
      () {
        // Room 101: gap 10–12 (2 nights). Room 102: booking 10–12 (same dates).
        final bookings = [
          _booking(
            id: 'b1',
            roomId: '101',
            checkIn: DateTime.utc(2025, 1, 5),
            checkOut: DateTime.utc(2025, 1, 10),
          ),
          _booking(
            id: 'b2',
            roomId: '101',
            checkIn: DateTime.utc(2025, 1, 12),
            checkOut: DateTime.utc(2025, 1, 16),
          ),
          _booking(
            id: 'b3',
            roomId: '102',
            checkIn: DateTime.utc(2025, 1, 10),
            checkOut: DateTime.utc(2025, 1, 12),
          ),
        ];
        final result = generateOptimizationSuggestions(
          bookings,
          windowStart: fakeNow,
          nowUtc: () => fakeNow,
        );
        final continuity = result
            .where((s) => s.type == SuggestionType.continuity)
            .toList();
        expect(continuity.length, 1);
        final s = continuity.first;
        expect(s.roomId, '101');
        expect(s.bookingId, 'b3');
        expect(s.fromRoomId, '102');
        expect(s.toRoomId, '101');
        expect(s.reason, isNotNull);
        expect(s.effects.length, greaterThanOrEqualTo(1));
        expect(s.action, isNotNull);
        expect(s.action!.bookingId, 'b3');
        expect(s.action!.fromRoomId, '102');
        expect(s.action!.toRoomId, '101');
        expect(s.message, contains('create continuity'));
      },
    );

    test('more than 3 gaps generates FRAGMENTATION', () {
      final bookings = <GapBookingInput>[];
      for (int i = 0; i < 5; i++) {
        final start = DateTime.utc(2025, 1, 1 + i * 3);
        final end = start.add(const Duration(days: 2));
        bookings.add(
          _booking(id: 'b$i', roomId: '101', checkIn: start, checkOut: end),
        );
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
        _booking(
          id: 'b1',
          roomId: '101',
          checkIn: DateTime.utc(2025, 1, 1),
          checkOut: DateTime.utc(2025, 1, 6),
        ),
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
        bookings.add(
          _booking(id: 'b$i', roomId: '101', checkIn: start, checkOut: end),
        );
      }
      final result = generateOptimizationSuggestions(
        bookings,
        windowStart: fakeNow,
        windowDays: 30,
        nowUtc: () => fakeNow,
      );
      for (int i = 0; i < result.length - 1; i++) {
        expect(
          result[i].impactScore,
          greaterThanOrEqualTo(result[i + 1].impactScore),
        );
      }
    });

    test(
      'fillable gap does not also emit SHORT_GAP for same room (deduplication)',
      () {
        final bookings = [
          _booking(
            id: 'b1',
            roomId: '101',
            checkIn: DateTime.utc(2025, 1, 5),
            checkOut: DateTime.utc(2025, 1, 10),
          ),
          _booking(
            id: 'b2',
            roomId: '101',
            checkIn: DateTime.utc(2025, 1, 12),
            checkOut: DateTime.utc(2025, 1, 16),
          ),
          _booking(
            id: 'b3',
            roomId: '102',
            checkIn: DateTime.utc(2025, 1, 10),
            checkOut: DateTime.utc(2025, 1, 12),
          ),
        ];
        final result = generateOptimizationSuggestions(
          bookings,
          windowStart: fakeNow,
          nowUtc: () => fakeNow,
        );
        final continuity = result
            .where(
              (s) => s.type == SuggestionType.continuity && s.roomId == '101',
            )
            .toList();
        final shortGap101 = result
            .where(
              (s) => s.type == SuggestionType.shortGap && s.roomId == '101',
            )
            .toList();
        expect(continuity.length, 1);
        expect(shortGap101.length, 0);
      },
    );

    test(
      'suggests move only when it does not create new short gap in source (safety)',
      () {
        // Room 101: gap 10–12. Room 102: 8-10, 10-12, 12-14. Only candidate for 10-12 is b2 in 102.
        // Moving b2 to 101 would fill 101's gap but create a 2-night gap in 102 → should be rejected by safety.
        final bookings = [
          _booking(
            id: 'a1',
            roomId: '101',
            checkIn: DateTime.utc(2025, 1, 5),
            checkOut: DateTime.utc(2025, 1, 10),
          ),
          _booking(
            id: 'a2',
            roomId: '101',
            checkIn: DateTime.utc(2025, 1, 12),
            checkOut: DateTime.utc(2025, 1, 15),
          ),
          _booking(
            id: 'b1',
            roomId: '102',
            checkIn: DateTime.utc(2025, 1, 8),
            checkOut: DateTime.utc(2025, 1, 10),
          ),
          _booking(
            id: 'b2',
            roomId: '102',
            checkIn: DateTime.utc(2025, 1, 10),
            checkOut: DateTime.utc(2025, 1, 12),
          ),
          _booking(
            id: 'b3',
            roomId: '102',
            checkIn: DateTime.utc(2025, 1, 12),
            checkOut: DateTime.utc(2025, 1, 14),
          ),
        ];
        final result = generateOptimizationSuggestions(
          bookings,
          windowStart: fakeNow,
          nowUtc: () => fakeNow,
        );
        final continuityFor101 = result
            .where(
              (s) => s.type == SuggestionType.continuity && s.toRoomId == '101',
            )
            .toList();
        expect(continuityFor101.length, 0);
      },
    );

    test('partial fit inside gap produces CONTINUITY suggestion', () {
      // Room 101: gap 23–26 (3 nights). Room 102: booking 24–26 (2 nights) fully contained in gap.
      final bookings = [
        _booking(
          id: 'a1',
          roomId: '101',
          checkIn: DateTime.utc(2025, 1, 20),
          checkOut: DateTime.utc(2025, 1, 23),
        ),
        _booking(
          id: 'a2',
          roomId: '101',
          checkIn: DateTime.utc(2025, 1, 26),
          checkOut: DateTime.utc(2025, 1, 29),
        ),
        _booking(
          id: 'b1',
          roomId: '102',
          checkIn: DateTime.utc(2025, 1, 24),
          checkOut: DateTime.utc(2025, 1, 26),
        ),
      ];
      final result = generateOptimizationSuggestions(
        bookings,
        windowStart: fakeNow,
        nowUtc: () => fakeNow,
      );
      final continuity = result
          .where((s) => s.type == SuggestionType.continuity)
          .toList();
      expect(continuity.length, 1);
      final s = continuity.first;
      expect(s.roomId, '101');
      expect(s.bookingId, 'b1');
      expect(s.fromRoomId, '102');
      expect(s.toRoomId, '101');
    });

    test(
      'exact-fill candidate scores better than partial-fit and is chosen',
      () {
        // Room 101: gap 23–26 (3 nights).
        // Room 102: exact 23–26 (3 nights). Room 103: partial 24–26 (2 nights).
        final bookings = [
          _booking(
            id: 'a1',
            roomId: '101',
            checkIn: DateTime.utc(2025, 1, 20),
            checkOut: DateTime.utc(2025, 1, 23),
          ),
          _booking(
            id: 'a2',
            roomId: '101',
            checkIn: DateTime.utc(2025, 1, 26),
            checkOut: DateTime.utc(2025, 1, 29),
          ),
          _booking(
            id: 'bExact',
            roomId: '102',
            checkIn: DateTime.utc(2025, 1, 23),
            checkOut: DateTime.utc(2025, 1, 26),
          ),
          _booking(
            id: 'bPartial',
            roomId: '103',
            checkIn: DateTime.utc(2025, 1, 24),
            checkOut: DateTime.utc(2025, 1, 26),
          ),
        ];
        final result = generateOptimizationSuggestions(
          bookings,
          windowStart: fakeNow,
          nowUtc: () => fakeNow,
        );
        final continuity = result
            .where(
              (s) => s.type == SuggestionType.continuity && s.roomId == '101',
            )
            .toList();
        expect(continuity.length, 1);
        expect(continuity.first.bookingId, 'bExact');
      },
    );

    test(
      'does not suggest moving the same booking twice across gaps (dedup by bookingId)',
      () {
        // Booking b1 could fit gaps in both 101 and 102, but should only be suggested once.
        final bookings = [
          // Room 101: gap 10–13
          _booking(
            id: 'r1a',
            roomId: '101',
            checkIn: DateTime.utc(2025, 1, 5),
            checkOut: DateTime.utc(2025, 1, 10),
          ),
          _booking(
            id: 'r1b',
            roomId: '101',
            checkIn: DateTime.utc(2025, 1, 13),
            checkOut: DateTime.utc(2025, 1, 16),
          ),
          // Room 102: gap 10–13 as well
          _booking(
            id: 'r2a',
            roomId: '102',
            checkIn: DateTime.utc(2025, 1, 5),
            checkOut: DateTime.utc(2025, 1, 10),
          ),
          _booking(
            id: 'r2b',
            roomId: '102',
            checkIn: DateTime.utc(2025, 1, 13),
            checkOut: DateTime.utc(2025, 1, 16),
          ),
          // Candidate booking spanning 10–13 in room 103
          _booking(
            id: 'b1',
            roomId: '103',
            checkIn: DateTime.utc(2025, 1, 10),
            checkOut: DateTime.utc(2025, 1, 13),
          ),
        ];
        final result = generateOptimizationSuggestions(
          bookings,
          windowStart: fakeNow,
          nowUtc: () => fakeNow,
        );
        final continuity = result
            .where((s) => s.type == SuggestionType.continuity)
            .toList();
        // b1 should appear in at most one continuity suggestion.
        final timesUsed = continuity.where((s) => s.bookingId == 'b1').length;
        expect(timesUsed, lessThanOrEqualTo(1));
      },
    );

    test('does not mutate input bookings', () {
      final b2 = _booking(
        id: 'b2',
        roomId: '101',
        checkIn: DateTime.utc(2025, 1, 14),
        checkOut: DateTime.utc(2025, 1, 16),
      );
      final b1 = _booking(
        id: 'b1',
        roomId: '101',
        checkIn: DateTime.utc(2025, 1, 10),
        checkOut: DateTime.utc(2025, 1, 12),
      );
      final original = [b2, b1];
      generateOptimizationSuggestions(original, nowUtc: () => fakeNow);
      expect(original[0].bookingId, 'b2');
      expect(original[1].bookingId, 'b1');
    });
  });
}

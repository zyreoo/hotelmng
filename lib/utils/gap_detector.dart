/// Gap detection between consecutive bookings in the same room.
///
/// Pure, framework-agnostic, no side effects.
/// All dates are UTC; checkOutDate is exclusive.
library;

/// One detected gap between two consecutive bookings in the same room.
class BookingGap {
  final String roomId;
  final DateTime gapStart;
  final DateTime gapEnd;
  final int gapNights;
  final String previousBookingId;
  final String nextBookingId;

  const BookingGap({
    required this.roomId,
    required this.gapStart,
    required this.gapEnd,
    required this.gapNights,
    required this.previousBookingId,
    required this.nextBookingId,
  });

  Map<String, dynamic> toJson() => {
        'roomId': roomId,
        'gapStart': gapStart.toIso8601String(),
        'gapEnd': gapEnd.toIso8601String(),
        'gapNights': gapNights,
        'previousBookingId': previousBookingId,
        'nextBookingId': nextBookingId,
      };
}

/// Minimal booking descriptor for gap detection.
class GapBookingInput {
  final String bookingId;
  final String roomId;
  final DateTime checkInUtc;
  final DateTime checkOutUtc;

  GapBookingInput({
    required this.bookingId,
    required this.roomId,
    required DateTime checkInUtc,
    required DateTime checkOutUtc,
  })  : checkInUtc = checkInUtc.toUtc(),
        checkOutUtc = checkOutUtc.toUtc();

  bool get _isValid => checkInUtc.isBefore(checkOutUtc);
}

/// Maximum gap size (nights) considered for fill/continuity suggestions.
const int maxFillableGapNights = 3;

/// Detect gaps of 1–3 nights between consecutive bookings (fillable range).
/// [bookings] need not be sorted; groups by roomId, sorts each group.
/// Does NOT mutate [bookings].
List<BookingGap> detectGaps(List<GapBookingInput> bookings) {
  final all = detectAllGaps(bookings);
  return all.where((g) => g.gapNights >= 1 && g.gapNights <= maxFillableGapNights).toList();
}

/// Detect all gaps (any length) between consecutive bookings per room.
/// Used for before/after metrics (gap count, fragmentation). Does NOT mutate [bookings].
List<BookingGap> detectAllGaps(List<GapBookingInput> bookings) {
  if (bookings.isEmpty) return [];
  final Map<String, List<GapBookingInput>> byRoom = {};
  for (final b in bookings) {
    if (!b._isValid) continue;
    byRoom.putIfAbsent(b.roomId, () => []).add(b);
  }
  final List<BookingGap> gaps = [];
  for (final entry in byRoom.entries) {
    final roomId = entry.key;
    final sorted = List<GapBookingInput>.from(entry.value)
      ..sort((a, b) => a.checkInUtc.compareTo(b.checkInUtc));
    if (sorted.length < 2) continue;
    for (int i = 0; i < sorted.length - 1; i++) {
      final current = sorted[i];
      final next = sorted[i + 1];
      final gapStart = current.checkOutUtc;
      final gapEnd = next.checkInUtc;
      if (!gapEnd.isAfter(gapStart)) continue;
      final gapNights = _daysBetween(gapStart, gapEnd);
      if (gapNights < 1) continue;
      gaps.add(BookingGap(
        roomId: roomId,
        gapStart: gapStart,
        gapEnd: gapEnd,
        gapNights: gapNights,
        previousBookingId: current.bookingId,
        nextBookingId: next.bookingId,
      ));
    }
  }
  return gaps;
}

int _daysBetween(DateTime from, DateTime to) {
  final a = _midnightUtc(from);
  final b = _midnightUtc(to);
  return b.difference(a).inDays;
}

DateTime _midnightUtc(DateTime dt) {
  final u = dt.toUtc();
  return DateTime.utc(u.year, u.month, u.day);
}

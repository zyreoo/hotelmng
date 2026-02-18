/// Gap detection between consecutive bookings in the same room.
///
/// Pure, framework-agnostic, no side effects.
/// All dates are UTC; checkOutDate is exclusive.

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

/// Detect gaps of 1–2 nights between consecutive bookings.
/// [bookings] need not be sorted; groups by roomId, sorts each group.
/// Returns only gaps where gapNights is in [1, 2]. Does NOT mutate [bookings].
List<BookingGap> detectGaps(List<GapBookingInput> bookings) {
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
      if (gapNights < 1 || gapNights > 2) continue;
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

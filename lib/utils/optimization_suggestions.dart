/// Rule-based optimization suggestion engine.
///
/// Pure, deterministic, no AI/ML, no side effects.
/// Suggestions are sorted by impactScore descending.

import 'gap_detector.dart';

// ─── Thresholds (all easily override-able in tests) ──────────────────────────

/// Number of gaps within [fragmentationWindowDays] that triggers FRAGMENTATION.
const int fragmentationGapThreshold = 3;

/// Rolling window for fragmentation detection (days).
const int fragmentationWindowDays = 30;

/// Monthly occupancy below this fraction triggers LOW_OCCUPANCY.
const double lowOccupancyThreshold = 0.5;

/// Number of days in a "month" window for occupancy calculation.
const int occupancyWindowDays = 30;

// ─── Suggestion model ─────────────────────────────────────────────────────────

/// Type codes for each suggestion category.
abstract class SuggestionType {
  static const String shortGap = 'SHORT_GAP';
  static const String fragmentation = 'FRAGMENTATION';
  static const String lowOccupancy = 'LOW_OCCUPANCY';
}

/// One actionable suggestion returned by [generateOptimizationSuggestions].
class OptimizationSuggestion {
  /// Discriminator: see [SuggestionType].
  final String type;

  /// Null for hotel-level suggestions (e.g. LOW_OCCUPANCY).
  final String? roomId;

  final String message;

  /// 1–10, higher is more urgent.
  final int impactScore;

  /// Only populated for SHORT_GAP.
  final int? relatedGapCount;

  const OptimizationSuggestion({
    required this.type,
    required this.message,
    required this.impactScore,
    this.roomId,
    this.relatedGapCount,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'type': type,
      'message': message,
      'impactScore': impactScore,
    };
    if (roomId != null) map['roomId'] = roomId;
    if (relatedGapCount != null) map['relatedGapCount'] = relatedGapCount;
    return map;
  }
}

// ─── Main entry point ─────────────────────────────────────────────────────────

/// Generate optimization suggestions from [bookings].
///
/// [windowStart] is the inclusive start of the analysis window (UTC midnight).
/// Defaults to [DateTime.now().toUtc()] midnight if not provided.
/// [windowDays] is the length of the analysis window in days (default 30).
///
/// Returns suggestions sorted by [impactScore] descending; deterministic.
List<OptimizationSuggestion> generateOptimizationSuggestions(
  List<GapBookingInput> bookings, {
  DateTime? windowStart,
  int windowDays = occupancyWindowDays,
  DateTime Function()? nowUtc,
}) {
  final now = (nowUtc ?? () => DateTime.now().toUtc())();
  final winStart = _midnightUtc(windowStart ?? now);
  final winEnd = winStart.add(Duration(days: windowDays));

  // Work only on bookings that overlap the analysis window.
  final windowBookings = bookings
      .where((b) => b._isValid && b.checkOutUtc.isAfter(winStart) && b.checkInUtc.isBefore(winEnd))
      .toList();

  // Detect all short gaps across all rooms (detectGaps handles grouping).
  final allGaps = detectGaps(windowBookings);

  final List<OptimizationSuggestion> suggestions = [];

  // ── 1) SHORT_GAP ──────────────────────────────────────────────────────────
  final shortGaps = allGaps.where((g) => g.gapNights >= 1 && g.gapNights <= 2);
  final gapsByRoom = <String, List<BookingGap>>{};
  for (final g in shortGaps) {
    gapsByRoom.putIfAbsent(g.roomId, () => []).add(g);
  }
  for (final entry in gapsByRoom.entries) {
    final roomId = entry.key;
    final roomGaps = entry.value;
    final totalEmptyNights = roomGaps.fold<int>(0, (sum, g) => sum + g.gapNights);
    // Impact: 1 per empty night, capped at 8.
    final impact = _clamp(totalEmptyNights, 1, 8);
    suggestions.add(OptimizationSuggestion(
      type: SuggestionType.shortGap,
      roomId: roomId,
      message: 'Room $roomId has ${roomGaps.length} short '
          '${roomGaps.length == 1 ? 'gap' : 'gaps'} '
          'this month ($totalEmptyNights empty '
          '${totalEmptyNights == 1 ? 'night' : 'nights'}). '
          'Consider adjusting bookings to reduce empty nights.',
      impactScore: impact,
      relatedGapCount: roomGaps.length,
    ));
  }

  // ── 2) FRAGMENTATION ──────────────────────────────────────────────────────
  //    Any room with > fragmentationGapThreshold gaps in the window.
  //    Use ALL detected gaps (not only short ones) to count fragmentation.
  final allGapsByRoom = <String, List<BookingGap>>{};
  for (final g in allGaps) {
    allGapsByRoom.putIfAbsent(g.roomId, () => []).add(g);
  }
  for (final entry in allGapsByRoom.entries) {
    final roomId = entry.key;
    final roomGaps = entry.value;
    if (roomGaps.length > fragmentationGapThreshold) {
      // Impact: base 6 + 1 per extra gap beyond threshold, capped at 9.
      final extra = roomGaps.length - fragmentationGapThreshold;
      final impact = _clamp(6 + extra, 6, 9);
      suggestions.add(OptimizationSuggestion(
        type: SuggestionType.fragmentation,
        roomId: roomId,
        message: 'Room $roomId schedule is fragmented '
            '(${roomGaps.length} gaps in ${windowDays} days). '
            'Rearranging bookings may create longer availability blocks.',
        impactScore: impact,
      ));
    }
  }

  // ── 3) LOW_OCCUPANCY ──────────────────────────────────────────────────────
  // Only evaluate when there is at least one room tracked in the window;
  // empty data means nothing to evaluate (no rooms registered).
  if (windowBookings.isEmpty) {
    suggestions.sort((a, b) => b.impactScore.compareTo(a.impactScore));
    return suggestions;
  }
  final occupancyRate = _computeOccupancyRate(
    windowBookings: windowBookings,
    winStart: winStart,
    winEnd: winEnd,
    windowDays: windowDays,
  );
  if (occupancyRate < lowOccupancyThreshold) {
    // Impact: 10 at 0%, scales to 5 at 49%.
    final missedFraction = lowOccupancyThreshold - occupancyRate;
    final impact = _clamp((missedFraction / lowOccupancyThreshold * 10).round(), 5, 10);
    final pct = (occupancyRate * 100).round();
    suggestions.add(OptimizationSuggestion(
      type: SuggestionType.lowOccupancy,
      message: 'Occupancy is $pct% this month (below the 50% threshold). '
          'Consider promotions or discounts to increase bookings.',
      impactScore: impact,
    ));
  }

  // ── Sort by impactScore descending; stable within same score ──────────────
  suggestions.sort((a, b) => b.impactScore.compareTo(a.impactScore));
  return suggestions;
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

/// Compute average nightly occupancy rate across all rooms in the window.
/// A night is "occupied" if at least one booking covers it.
/// Returns a value in [0.0, 1.0].
double _computeOccupancyRate({
  required List<GapBookingInput> windowBookings,
  required DateTime winStart,
  required DateTime winEnd,
  required int windowDays,
}) {
  if (windowBookings.isEmpty || windowDays <= 0) return 0.0;

  // Unique rooms in the window.
  final rooms = windowBookings.map((b) => b.roomId).toSet();
  if (rooms.isEmpty) return 0.0;

  // For each room, count distinct nights that are occupied.
  int totalOccupiedNights = 0;
  for (final roomId in rooms) {
    final roomBookings = windowBookings.where((b) => b.roomId == roomId).toList();
    totalOccupiedNights += _occupiedNightsInWindow(roomBookings, winStart, winEnd);
  }

  final totalAvailableNights = rooms.length * windowDays;
  return totalAvailableNights > 0 ? totalOccupiedNights / totalAvailableNights : 0.0;
}

/// Count distinct nights occupied in [winStart, winEnd) for a set of bookings
/// of the same room. Uses a Set of day offsets to handle overlapping bookings.
int _occupiedNightsInWindow(
  List<GapBookingInput> bookings,
  DateTime winStart,
  DateTime winEnd,
) {
  final occupiedDays = <int>{};
  for (final b in bookings) {
    final start = _maxDate(_midnightUtc(b.checkInUtc), winStart);
    final end = _minDate(_midnightUtc(b.checkOutUtc), winEnd);
    if (!end.isAfter(start)) continue;
    final nights = end.difference(start).inDays;
    for (int n = 0; n < nights; n++) {
      occupiedDays.add(start.difference(winStart).inDays + n);
    }
  }
  return occupiedDays.length;
}

DateTime _midnightUtc(DateTime dt) {
  final u = dt.toUtc();
  return DateTime.utc(u.year, u.month, u.day);
}

DateTime _maxDate(DateTime a, DateTime b) => a.isAfter(b) ? a : b;
DateTime _minDate(DateTime a, DateTime b) => a.isBefore(b) ? a : b;

int _clamp(int value, int min, int max) =>
    value < min ? min : (value > max ? max : value);

extension on GapBookingInput {
  bool get _isValid => checkInUtc.isBefore(checkOutUtc);
}

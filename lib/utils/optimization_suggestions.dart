/// Rule-based optimization suggestion engine.
///
/// Pure, deterministic, no AI/ML, no side effects.
/// Emits concrete moves (booking + fromRoom + toRoom) with before/after scoring.
/// Suggestions are sorted by score descending.

import 'gap_detector.dart';

// ─── Debug (set to false to disable console logs) ───────────────────────────
const bool _kDebugOptimization = false;
void _debugLog(String message) {
  if (_kDebugOptimization) {
    // ignore: avoid_print
    print('[Optimization] $message');
  }
}

/// Format DateTime for debug output (date only).
String _debugDate(DateTime dt) {
  final u = dt.toUtc();
  return '${u.year}-${u.month.toString().padLeft(2, '0')}-${u.day.toString().padLeft(2, '0')}';
}

// ─── Thresholds (all easily override-able in tests) ──────────────────────────

/// Number of gaps within [fragmentationWindowDays] that triggers FRAGMENTATION.
const int fragmentationGapThreshold = 3;

/// Rolling window for fragmentation detection (days).
const int fragmentationWindowDays = 30;

/// Monthly occupancy below this fraction triggers LOW_OCCUPANCY.
const double lowOccupancyThreshold = 0.5;

/// Number of days in a "month" window for occupancy calculation.
const int occupancyWindowDays = 30;

/// Max gap size (nights) considered "short" for harm detection.
const int shortGapMaxNights = 2;

// ─── Optional room metadata (for compatibility scoring) ─────────────────────

/// Optional metadata per room. If not provided, compatibility is ignored.
class RoomMeta {
  final String? type;
  final String? floor;
  final int? capacity;
  final bool? accessibility;

  const RoomMeta({this.type, this.floor, this.capacity, this.accessibility});
}

// ─── Action payload (reversible operation) ─────────────────────────────────

/// Reversible move-booking operation for one-click apply.
class MoveBookingAction {
  static const String actionType = 'MOVE_BOOKING';

  final String bookingId;
  final String fromRoomId;
  final String toRoomId;
  final DateTime newCheckIn;
  final DateTime newCheckOut;
  final bool requiresUserConfirm;

  const MoveBookingAction({
    required this.bookingId,
    required this.fromRoomId,
    required this.toRoomId,
    required this.newCheckIn,
    required this.newCheckOut,
    this.requiresUserConfirm = false,
  });

  Map<String, dynamic> toJson() => {
    'actionType': actionType,
    'bookingId': bookingId,
    'fromRoomId': fromRoomId,
    'toRoomId': toRoomId,
    'newCheckIn': newCheckIn.toIso8601String(),
    'newCheckOut': newCheckOut.toIso8601String(),
    'requiresUserConfirm': requiresUserConfirm,
  };
}

// ─── Suggestion model ─────────────────────────────────────────────────────────

/// Type codes for each suggestion category.
abstract class SuggestionType {
  static const String shortGap = 'SHORT_GAP';
  static const String continuity = 'CONTINUITY';
  static const String fragmentation = 'FRAGMENTATION';
  static const String lowOccupancy = 'LOW_OCCUPANCY';
}

/// One suggestion returned by [generateOptimizationSuggestions].
/// Actionable CONTINUITY suggestions include bookingId, fromRoomId, toRoomId, reason, effects, action.
class OptimizationSuggestion {
  final String type;
  final String? roomId;
  final String message;

  /// 1–10, backward-compat display.
  final int impactScore;
  final int? relatedGapCount;

  /// Actionable move: one concrete booking to move (CONTINUITY only).
  final String? bookingId;
  final String? fromRoomId;
  final String? toRoomId;
  final DateTime? gapStart;
  final DateTime? gapEnd;

  /// Numeric score for ranking (targetImprovement − sourceDamage). Higher = better.
  final double? score;

  /// Short human-readable explanation.
  final String? reason;

  /// Measurable before→after effects (e.g. "Room 101 gap count: 3 → 2").
  final List<String> effects;
  final MoveBookingAction? action;

  const OptimizationSuggestion({
    required this.type,
    required this.message,
    required this.impactScore,
    this.roomId,
    this.relatedGapCount,
    this.bookingId,
    this.fromRoomId,
    this.toRoomId,
    this.gapStart,
    this.gapEnd,
    this.score,
    this.reason,
    this.effects = const [],
    this.action,
  });

  /// True if this suggestion has a one-click action (move booking).
  bool get isActionable => action != null;

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'type': type,
      'message': message,
      'impactScore': impactScore,
      'effects': effects,
    };
    if (roomId != null) map['roomId'] = roomId;
    if (relatedGapCount != null) map['relatedGapCount'] = relatedGapCount;
    if (bookingId != null) map['bookingId'] = bookingId;
    if (fromRoomId != null) map['fromRoomId'] = fromRoomId;
    if (toRoomId != null) map['toRoomId'] = toRoomId;
    if (gapStart != null) map['gapStart'] = gapStart!.toIso8601String();
    if (gapEnd != null) map['gapEnd'] = gapEnd!.toIso8601String();
    if (score != null) map['score'] = score!;
    if (reason != null) map['reason'] = reason!;
    if (action != null) map['action'] = action!.toJson();
    return map;
  }
}

// ─── Main entry point ─────────────────────────────────────────────────────────

/// Generate optimization suggestions from [bookings].
///
/// [windowStart] is the inclusive start of the analysis window (UTC midnight).
/// [roomMetadata] optional; when provided, compatibility (type, floor, etc.) is used to prefer moves.
///
/// Returns suggestions sorted by score descending (actionable first), then impactScore. Deterministic.
List<OptimizationSuggestion> generateOptimizationSuggestions(
  List<GapBookingInput> bookings, {
  DateTime? windowStart,
  int windowDays = occupancyWindowDays,
  DateTime Function()? nowUtc,
  Map<String, RoomMeta>? roomMetadata,
}) {
  final now = (nowUtc ?? () => DateTime.now().toUtc())();
  final winStart = _midnightUtc(windowStart ?? now);
  final winEnd = winStart.add(Duration(days: windowDays));

  final windowBookings = bookings
      .where(
        (b) =>
            b._isValid &&
            b.checkOutUtc.isAfter(winStart) &&
            b.checkInUtc.isBefore(winEnd),
      )
      .toList();

  _debugLog(
    'Input: ${bookings.length} bookings, window: ${_debugDate(winStart)}..${_debugDate(winEnd)} ($windowDays days)',
  );
  _debugLog('In-window bookings: ${windowBookings.length}');
  for (var i = 0; i < windowBookings.length && i < 15; i++) {
    final b = windowBookings[i];
    _debugLog(
      '  [$i] id=${b.bookingId} room=${b.roomId} ${_debugDate(b.checkInUtc)} → ${_debugDate(b.checkOutUtc)}',
    );
  }
  if (windowBookings.length > 15)
    _debugLog('  ... and ${windowBookings.length - 15} more');

  final allGaps = detectGaps(windowBookings);
  final allGapsUnfiltered = detectAllGaps(windowBookings);
  final shortGaps = allGaps;

  _debugLog('Detected gaps (1–3 nights): ${shortGaps.length}');
  for (var i = 0; i < shortGaps.length; i++) {
    final g = shortGaps[i];
    _debugLog(
      '  gap[$i] room=${g.roomId} ${_debugDate(g.gapStart)} → ${_debugDate(g.gapEnd)} (${g.gapNights} nights)',
    );
  }

  final List<OptimizationSuggestion> suggestions = [];

  // Collect all actionable continuity candidates first; we'll later sort them,
  // enforce uniqueness per bookingId, and then apply room-level dedup.
  final List<OptimizationSuggestion> continuityCandidates = [];

  // ── 1) CONTINUITY: one concrete move per fillable gap (before dedup) ───────
  for (final gap in shortGaps) {
    // Eligible candidates: bookings in other rooms that either are fully
    // contained in the gap or overlap the gap (longer booking covering the gap).
    // _fitsInTargetWithoutOverlap still ensures we don't conflict with target room.
    final candidates = windowBookings
        .where(
          (b) =>
              b.roomId != gap.roomId &&
              (_isContainedInGap(b, gap) || _overlapsGap(b, gap)),
        )
        .toList();

    _debugLog(
      'Gap room=${gap.roomId} ${_debugDate(gap.gapStart)}→${_debugDate(gap.gapEnd)}: ${candidates.length} candidate(s) (contained or overlaps gap)',
    );
    if (candidates.isEmpty) {
      final others = windowBookings
          .where((b) => b.roomId != gap.roomId)
          .toList();
      _debugLog(
        '  → No booking in another room overlaps this gap (need overlap with [${_debugDate(gap.gapStart)}, ${_debugDate(gap.gapEnd)})). Other-room bookings:',
      );
      for (final b in others.take(10)) {
        final gStart = _midnightUtc(gap.gapStart);
        final gEnd = _midnightUtc(gap.gapEnd);
        final bStart = _midnightUtc(b.checkInUtc);
        final bEnd = _midnightUtc(b.checkOutUtc);
        final why = bStart.isBefore(gStart)
            ? 'checkIn ${_debugDate(b.checkInUtc)} < gapStart'
            : (bEnd.isAfter(gEnd)
                  ? 'checkOut ${_debugDate(b.checkOutUtc)} > gapEnd'
                  : 'ok');
        _debugLog(
          '     ${b.bookingId} room=${b.roomId} ${_debugDate(b.checkInUtc)}→${_debugDate(b.checkOutUtc)}: $why',
        );
      }
      if (others.length > 10)
        _debugLog('     ... and ${others.length - 10} more');
      continue;
    }

    _ScoredMove? best;
    for (final c in candidates) {
      final safe = _isMoveSafe(windowBookings, c);
      if (!safe) {
        _debugLog(
          '  candidate ${c.bookingId} (room ${c.roomId}): skipped — would increase short gaps in source room',
        );
        continue;
      }
      // Try full-date move first (booking keeps same dates).
      final fitsFull = _fitsInTargetWithoutOverlap(windowBookings, c, gap);
      if (fitsFull) {
        final score = _scoreMove(windowBookings, c, gap, roomMetadata);
        if (best == null || score > best.score) {
          best = _ScoredMove(booking: c, gap: gap, score: score);
          _debugLog(
            '  candidate ${c.bookingId} (room ${c.roomId}): score=$score (new best, full-date)',
          );
        }
        continue;
      }
      // Try trimmed-date move: place booking in gap only (reschedule to fit gap).
      final trimmed = _trimmedPlacement(c, gap);
      if (trimmed != null) {
        final (placeStart, placeEnd) = trimmed;
        if (_fitsInTargetWithDates(
          windowBookings,
          gap.roomId,
          placeStart,
          placeEnd,
        )) {
          final score = _scoreMove(
            windowBookings,
            c,
            gap,
            roomMetadata,
            placedCheckIn: placeStart,
            placedCheckOut: placeEnd,
          );
          if (best == null || score > best.score) {
            best = _ScoredMove(
              booking: c,
              gap: gap,
              score: score,
              placedCheckIn: placeStart,
              placedCheckOut: placeEnd,
            );
            _debugLog(
              '  candidate ${c.bookingId} (room ${c.roomId}): score=$score (new best, trimmed to gap)',
            );
          }
        }
      } else {
        _debugLog(
          '  candidate ${c.bookingId} (room ${c.roomId}): skipped — would overlap existing booking in target room',
        );
      }
    }
    if (best == null) {
      _debugLog('  → All candidates rejected by safety or overlap.');
      continue;
    }

    final placeCheckIn = best.placedCheckIn ?? best.booking.checkInUtc;
    final placeCheckOut = best.placedCheckOut ?? best.booking.checkOutUtc;
    final beforeTarget = _roomMetrics(windowBookings, gap.roomId);
    final afterTarget = _roomMetricsAfterMove(
      windowBookings,
      best.booking,
      gap.roomId,
      placeCheckIn,
      placeCheckOut,
    );
    final beforeSource = _roomMetrics(windowBookings, best.booking.roomId);
    final afterSource = _roomMetricsAfterMove(
      windowBookings,
      best.booking,
      best.booking.roomId,
      null,
      null,
    );

    final effects = <String>[
      'Room ${gap.roomId} gap count: ${beforeTarget.shortGapCount} → ${afterTarget.shortGapCount}',
      'Room ${best.booking.roomId} short gaps: ${beforeSource.shortGapCount} → ${afterSource.shortGapCount}',
    ];
    final createsNewGapInSource =
        afterSource.shortGapCount > beforeSource.shortGapCount;
    String reason;
    if (best.isTrimmed) {
      reason =
          'Fills a ${gap.gapNights}-night gap in Room ${gap.roomId} by rescheduling this booking to the gap dates (stay length may change).';
    } else {
      reason = createsNewGapInSource
          ? 'Fills a ${gap.gapNights}-night gap in Room ${gap.roomId}. Note: this creates additional short gaps in Room ${best.booking.roomId}.'
          : 'Fills a ${gap.gapNights}-night gap in Room ${gap.roomId} without creating new gaps in Room ${best.booking.roomId}.';
    }

    _debugLog(
      '  → Selected: move ${best.booking.bookingId} from room ${best.booking.roomId} to ${gap.roomId} (score=${best.score}, trimmed=${best.isTrimmed})',
    );
    continuityCandidates.add(
      OptimizationSuggestion(
        type: SuggestionType.continuity,
        roomId: gap.roomId,
        message: best.isTrimmed
            ? 'Move booking ${best.booking.bookingId} from Room ${best.booking.roomId} to Room ${gap.roomId} to fill the gap (dates will be adjusted to the gap).'
            : 'Move booking ${best.booking.bookingId} from Room ${best.booking.roomId} to Room ${gap.roomId} to create continuity.',
        impactScore: _clamp(6 + gap.gapNights, 7, 10),
        relatedGapCount: 1,
        bookingId: best.booking.bookingId,
        fromRoomId: best.booking.roomId,
        toRoomId: gap.roomId,
        gapStart: gap.gapStart,
        gapEnd: gap.gapEnd,
        score: best.score,
        reason: reason,
        effects: effects,
        action: MoveBookingAction(
          bookingId: best.booking.bookingId,
          fromRoomId: best.booking.roomId,
          toRoomId: gap.roomId,
          newCheckIn: placeCheckIn,
          newCheckOut: placeCheckOut,
          requiresUserConfirm: best.isTrimmed,
        ),
      ),
    );
  }

  // Enforce uniqueness: do not suggest moving the same booking more than once.
  // Sort by score (desc), then impactScore; pick greedily, skipping duplicates.
  continuityCandidates.sort((a, b) {
    final scoreA = a.score ?? double.negativeInfinity;
    final scoreB = b.score ?? double.negativeInfinity;
    if (scoreA != scoreB) return scoreB.compareTo(scoreA);
    return b.impactScore.compareTo(a.impactScore);
  });

  final Set<String> _usedBookingIds = {};
  final Set<String> _roomsWithActionableGap = {};

  _debugLog(
    'Continuity candidates before dedup: ${continuityCandidates.length}',
  );
  for (final c in continuityCandidates) {
    final id = c.bookingId;
    if (id == null) continue;
    if (_usedBookingIds.contains(id)) {
      _debugLog('  Skip duplicate bookingId=$id');
      continue;
    }
    _usedBookingIds.add(id);
    if (c.roomId != null) _roomsWithActionableGap.add(c.roomId!);
    suggestions.add(c);
  }
  _debugLog(
    'Actionable CONTINUITY suggestions after dedup: ${suggestions.where((s) => s.type == SuggestionType.continuity).length}',
  );

  // ── 2) SHORT_GAP only for rooms that have NO actionable continuity ─────────
  final gapsByRoom = <String, List<BookingGap>>{};
  for (final g in shortGaps) {
    if (_roomsWithActionableGap.contains(g.roomId)) continue;
    gapsByRoom.putIfAbsent(g.roomId, () => []).add(g);
  }
  for (final entry in gapsByRoom.entries) {
    final roomId = entry.key;
    final roomGaps = entry.value;
    final totalEmptyNights = roomGaps.fold<int>(
      0,
      (sum, g) => sum + g.gapNights,
    );
    final impact = _clamp(totalEmptyNights, 1, 8);
    suggestions.add(
      OptimizationSuggestion(
        type: SuggestionType.shortGap,
        roomId: roomId,
        message:
            'Room $roomId has ${roomGaps.length} short '
            '${roomGaps.length == 1 ? 'gap' : 'gaps'} '
            'this month ($totalEmptyNights empty nights). '
            'Consider moving a booking from another room (same dates) to fill the gap.',
        impactScore: impact,
        relatedGapCount: roomGaps.length,
      ),
    );
  }

  // ── 3) FRAGMENTATION (informational, no action) ─────────────────────────────
  final allGapsByRoom = <String, List<BookingGap>>{};
  for (final g in allGapsUnfiltered) {
    allGapsByRoom.putIfAbsent(g.roomId, () => []).add(g);
  }
  for (final entry in allGapsByRoom.entries) {
    final roomId = entry.key;
    final roomGaps = entry.value;
    if (roomGaps.length > fragmentationGapThreshold) {
      final extra = roomGaps.length - fragmentationGapThreshold;
      final impact = _clamp(6 + extra, 6, 9);
      suggestions.add(
        OptimizationSuggestion(
          type: SuggestionType.fragmentation,
          roomId: roomId,
          message:
              'Room $roomId schedule is fragmented '
              '(${roomGaps.length} gaps in $windowDays days). '
              'Rearranging bookings may create longer availability blocks.',
          impactScore: impact,
          reason: 'High gap count reduces block availability.',
          effects: ['Room $roomId has ${roomGaps.length} gaps in the window.'],
        ),
      );
    }
  }

  // ── 4) LOW_OCCUPANCY ──────────────────────────────────────────────────────
  if (windowBookings.isEmpty) {
    _sortSuggestions(suggestions);
    return suggestions;
  }
  final occupancyRate = _computeOccupancyRate(
    windowBookings: windowBookings,
    winStart: winStart,
    winEnd: winEnd,
    windowDays: windowDays,
  );
  if (occupancyRate < lowOccupancyThreshold) {
    final missedFraction = lowOccupancyThreshold - occupancyRate;
    final impact = _clamp(
      (missedFraction / lowOccupancyThreshold * 10).round(),
      5,
      10,
    );
    final pct = (occupancyRate * 100).round();
    suggestions.add(
      OptimizationSuggestion(
        type: SuggestionType.lowOccupancy,
        message:
            'Occupancy is $pct% this month (below the 50% threshold). '
            'Consider promotions or discounts to increase bookings.',
        impactScore: impact,
        reason: 'Occupancy below threshold.',
        effects: ['Overall occupancy: $pct%'],
      ),
    );
  }

  _sortSuggestions(suggestions);
  _debugLog(
    'Total suggestions: ${suggestions.length} (continuity: ${suggestions.where((s) => s.type == SuggestionType.continuity).length}, shortGap: ${suggestions.where((s) => s.type == SuggestionType.shortGap).length})',
  );
  return suggestions;
}

void _sortSuggestions(List<OptimizationSuggestion> suggestions) {
  suggestions.sort((a, b) {
    final scoreA = a.score ?? double.negativeInfinity;
    final scoreB = b.score ?? double.negativeInfinity;
    if (scoreA != scoreB) return scoreB.compareTo(scoreA);
    return b.impactScore.compareTo(a.impactScore);
  });
}

class _ScoredMove {
  final GapBookingInput booking;
  final BookingGap gap;
  final double score;

  /// When set, move uses these dates (trimmed to gap) and requires user confirm.
  final DateTime? placedCheckIn;
  final DateTime? placedCheckOut;
  _ScoredMove({
    required this.booking,
    required this.gap,
    required this.score,
    this.placedCheckIn,
    this.placedCheckOut,
  });
  bool get isTrimmed => placedCheckIn != null && placedCheckOut != null;
}

_RoomMetrics _roomMetrics(List<GapBookingInput> bookings, String roomId) {
  final roomBookings = bookings.where((b) => b.roomId == roomId).toList();
  final gaps = detectAllGaps(roomBookings);
  final shortGaps = gaps
      .where((g) => g.gapNights >= 1 && g.gapNights <= shortGapMaxNights)
      .toList();
  final longestBlock = _longestContinuousBlock(roomBookings);
  return _RoomMetrics(
    gapCount: gaps.length,
    shortGapCount: shortGaps.length,
    longestBlockNights: longestBlock,
  );
}

_RoomMetrics _roomMetricsAfterMove(
  List<GapBookingInput> bookings,
  GapBookingInput moveOut,
  String roomId,
  DateTime? addCheckIn,
  DateTime? addCheckOut,
) {
  List<GapBookingInput> simulated = bookings
      .where(
        (b) =>
            !(b.bookingId == moveOut.bookingId && b.roomId == moveOut.roomId),
      )
      .toList();
  if (addCheckIn != null && addCheckOut != null && roomId != moveOut.roomId) {
    simulated = List.from(simulated)
      ..add(
        GapBookingInput(
          bookingId: moveOut.bookingId,
          roomId: roomId,
          checkInUtc: addCheckIn,
          checkOutUtc: addCheckOut,
        ),
      );
  } else if (addCheckIn != null &&
      addCheckOut != null &&
      roomId == moveOut.roomId) {
    simulated = List.from(simulated)
      ..add(
        GapBookingInput(
          bookingId: moveOut.bookingId,
          roomId: roomId,
          checkInUtc: addCheckIn,
          checkOutUtc: addCheckOut,
        ),
      );
  }
  return _roomMetrics(simulated, roomId);
}

class _RoomMetrics {
  final int gapCount;
  final int shortGapCount;
  final int longestBlockNights;
  _RoomMetrics({
    required this.gapCount,
    required this.shortGapCount,
    required this.longestBlockNights,
  });
}

int _longestContinuousBlock(List<GapBookingInput> bookings) {
  if (bookings.isEmpty) return 0;
  final sorted = List<GapBookingInput>.from(bookings)
    ..sort((a, b) => a.checkInUtc.compareTo(b.checkInUtc));
  int maxNights = 0;
  for (final b in sorted) {
    final nights = _midnightUtc(
      b.checkOutUtc,
    ).difference(_midnightUtc(b.checkInUtc)).inDays;
    if (nights > maxNights) maxNights = nights;
  }
  return maxNights;
}

/// True if [candidate] is fully contained within [gap] (date-only, UTC).
/// Uses half-open intervals: [checkIn, checkOut).
bool _isContainedInGap(GapBookingInput candidate, BookingGap gap) {
  final bStart = _midnightUtc(candidate.checkInUtc);
  final bEnd = _midnightUtc(candidate.checkOutUtc);
  final gStart = _midnightUtc(gap.gapStart);
  final gEnd = _midnightUtc(gap.gapEnd);
  if (!bEnd.isAfter(bStart)) return false; // zero-night bookings are invalid
  return !bStart.isBefore(gStart) && !bEnd.isAfter(gEnd);
}

/// True if [candidate] overlaps the gap interval (half-open). Used so we can
/// suggest moving a longer booking that covers the gap when it still fits
/// in the target room (e.g. 2-night booking can fill a 1-night gap if the
/// extra night is free in the target).
bool _overlapsGap(GapBookingInput candidate, BookingGap gap) {
  final bStart = _midnightUtc(candidate.checkInUtc);
  final bEnd = _midnightUtc(candidate.checkOutUtc);
  final gStart = _midnightUtc(gap.gapStart);
  final gEnd = _midnightUtc(gap.gapEnd);
  if (!bEnd.isAfter(bStart)) return false;
  return bStart.isBefore(gEnd) && bEnd.isAfter(gStart);
}

/// True if two half-open intervals [aStart, aEnd) and [bStart, bEnd) overlap.
bool _intervalsOverlap(
  DateTime aStart,
  DateTime aEnd,
  DateTime bStart,
  DateTime bEnd,
) {
  final asUtc = _midnightUtc(aStart);
  final aeUtc = _midnightUtc(aEnd);
  final bsUtc = _midnightUtc(bStart);
  final beUtc = _midnightUtc(bEnd);
  return asUtc.isBefore(beUtc) && bsUtc.isBefore(aeUtc);
}

/// Ensure moving [candidate] into [gap.roomId] in [bookings] does not overlap
/// any existing booking in the target room (half-open intervals).
bool _fitsInTargetWithoutOverlap(
  List<GapBookingInput> bookings,
  GapBookingInput candidate,
  BookingGap gap,
) {
  final bStart = candidate.checkInUtc;
  final bEnd = candidate.checkOutUtc;
  return _fitsInTargetWithDates(bookings, gap.roomId, bStart, bEnd);
}

/// Check if placing a stay [placeStart, placeEnd) in [targetRoomId] would overlap
/// any existing booking in that room.
bool _fitsInTargetWithDates(
  List<GapBookingInput> bookings,
  String targetRoomId,
  DateTime placeStart,
  DateTime placeEnd,
) {
  final targetBookings = bookings
      .where((b) => b.roomId == targetRoomId)
      .toList();
  for (final existing in targetBookings) {
    if (_intervalsOverlap(
      existing.checkInUtc,
      existing.checkOutUtc,
      placeStart,
      placeEnd,
    )) {
      return false;
    }
  }
  return true;
}

/// Trim [candidate] to the gap interval (date-only). Returns (start, end) if
/// overlap is at least 1 night, else null.
(DateTime, DateTime)? _trimmedPlacement(
  GapBookingInput candidate,
  BookingGap gap,
) {
  final gStart = _midnightUtc(gap.gapStart);
  final gEnd = _midnightUtc(gap.gapEnd);
  final bStart = _midnightUtc(candidate.checkInUtc);
  final bEnd = _midnightUtc(candidate.checkOutUtc);
  if (!bEnd.isAfter(bStart) || !gEnd.isAfter(gStart)) return null;
  final placeStart = _maxDate(gStart, bStart);
  final placeEnd = _minDate(gEnd, bEnd);
  if (!placeEnd.isAfter(placeStart)) return null;
  if (placeEnd.difference(placeStart).inDays < 1) return null;
  return (placeStart, placeEnd);
}

/// Reject moves that would increase the number of short gaps (1–2 nights)
/// in the source room after removing the booking.
bool _isMoveSafe(List<GapBookingInput> bookings, GapBookingInput candidate) {
  final before = _roomMetrics(bookings, candidate.roomId);
  final simulated = bookings
      .where(
        (b) =>
            !(b.bookingId == candidate.bookingId &&
                b.roomId == candidate.roomId),
      )
      .toList();
  final after = _roomMetrics(simulated, candidate.roomId);
  return after.shortGapCount <= before.shortGapCount;
}

int _nightsBetween(DateTime from, DateTime to) {
  final a = _midnightUtc(from);
  final b = _midnightUtc(to);
  return b.difference(a).inDays;
}

double _scoreMove(
  List<GapBookingInput> bookings,
  GapBookingInput candidate,
  BookingGap gap,
  Map<String, RoomMeta>? roomMetadata, {
  DateTime? placedCheckIn,
  DateTime? placedCheckOut,
}) {
  final targetCheckIn = placedCheckIn ?? candidate.checkInUtc;
  final targetCheckOut = placedCheckOut ?? candidate.checkOutUtc;
  final beforeTarget = _roomMetrics(bookings, gap.roomId);
  final afterTarget = _roomMetricsAfterMove(
    bookings,
    candidate,
    gap.roomId,
    targetCheckIn,
    targetCheckOut,
  );
  final beforeSource = _roomMetrics(bookings, candidate.roomId);
  final afterSource = _roomMetricsAfterMove(
    bookings,
    candidate,
    candidate.roomId,
    null,
    null,
  );

  double targetImprovement = 0;
  // Gap fill reward: proportional to how many nights of the gap are covered.
  final gapNights = _nightsBetween(gap.gapStart, gap.gapEnd);
  if (gapNights > 0) {
    final overlapStart = _maxDate(
      _midnightUtc(gap.gapStart),
      _midnightUtc(candidate.checkInUtc),
    );
    final overlapEnd = _minDate(
      _midnightUtc(gap.gapEnd),
      _midnightUtc(candidate.checkOutUtc),
    );
    final filledNights = _nightsBetween(
      overlapStart,
      overlapEnd,
    ).clamp(0, gapNights);
    if (filledNights > 0) {
      // Exact fill (filledNights == gapNights) → +10; partial fills scale linearly.
      targetImprovement += 10.0 * (filledNights / gapNights);
    }
  }
  targetImprovement += (beforeTarget.gapCount - afterTarget.gapCount) * 2.0;
  targetImprovement +=
      (afterTarget.longestBlockNights - beforeTarget.longestBlockNights) * 0.5;

  double sourceDamage = 0;
  if (afterSource.shortGapCount > beforeSource.shortGapCount) {
    sourceDamage += 15;
  }
  sourceDamage += (afterSource.gapCount - beforeSource.gapCount) * 3.0;
  if (afterSource.longestBlockNights < beforeSource.longestBlockNights) {
    sourceDamage += 2.0;
  }

  double compatibility = 0;
  if (roomMetadata != null) {
    final fromMeta = roomMetadata[candidate.roomId];
    final toMeta = roomMetadata[gap.roomId];
    if (fromMeta?.type != null &&
        toMeta?.type != null &&
        fromMeta!.type == toMeta!.type)
      compatibility += 2;
    if (fromMeta?.floor != null &&
        toMeta?.floor != null &&
        fromMeta!.floor == toMeta!.floor)
      compatibility += 1;
  }

  return targetImprovement - sourceDamage + compatibility;
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
    final roomBookings = windowBookings
        .where((b) => b.roomId == roomId)
        .toList();
    totalOccupiedNights += _occupiedNightsInWindow(
      roomBookings,
      winStart,
      winEnd,
    );
  }

  final totalAvailableNights = rooms.length * windowDays;
  return totalAvailableNights > 0
      ? totalOccupiedNights / totalAvailableNights
      : 0.0;
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

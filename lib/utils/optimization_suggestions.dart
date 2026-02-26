/// Rule-based optimization suggestion engine.
///
/// Pure, deterministic, no AI/ML, no side effects.
/// Emits concrete moves (booking + fromRoom + toRoom) with before/after scoring.
/// Suggestions are sorted by score descending.
library;

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

  /// Single move (backward compat). Use [actionChain] when multiple moves.
  final MoveBookingAction? action;

  /// Chain of moves to apply in order (e.g. move A to gap, then B to freed slot).
  final List<MoveBookingAction>? actionChain;

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
    this.actionChain,
  });

  /// True if this suggestion has one or more moves to apply.
  bool get isActionable =>
      action != null || (actionChain != null && actionChain!.isNotEmpty);

  /// All actions to apply (chain if present, else single action).
  List<MoveBookingAction> get actions {
    if (actionChain != null && actionChain!.isNotEmpty) return actionChain!;
    if (action != null) return [action!];
    return [];
  }

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
    if (actionChain != null) {
      map['actionChain'] = actionChain!.map((a) => a.toJson()).toList();
    }
    return map;
  }
}

// ─── Main entry point ─────────────────────────────────────────────────────────

/// Generate optimization suggestions from [bookings].
///
/// [windowStart] is the inclusive start of the analysis window (UTC midnight).
/// [roomMetadata] optional; when provided, compatibility (type, floor, etc.) is used to prefer moves.
/// [redlineUtc] if set, only gaps on or after this date (UTC midnight) are considered for moves,
///   and only bookings with check-in strictly after the redline can be moved (so if the redline
///   is on the first or any night of the stay, that booking is not movable).
/// [checkedInBookingIds] booking IDs that are already checked in; these cannot be moved.
///
/// Returns suggestions sorted by score descending (actionable first), then impactScore. Deterministic.
List<OptimizationSuggestion> generateOptimizationSuggestions(
  List<GapBookingInput> bookings, {
  DateTime? windowStart,
  int windowDays = occupancyWindowDays,
  DateTime Function()? nowUtc,
  Map<String, RoomMeta>? roomMetadata,
  DateTime? redlineUtc,
  Set<String>? checkedInBookingIds,
}) {
  final now = (nowUtc ?? () => DateTime.now().toUtc())();
  final winStart = _midnightUtc(windowStart ?? now);
  final winEnd = winStart.add(Duration(days: windowDays));
  final redlineMidnight = redlineUtc != null ? _midnightUtc(redlineUtc) : null;

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
  if (windowBookings.length > 15) {
    _debugLog('  ... and ${windowBookings.length - 15} more');
  }

  final allGaps = detectGaps(windowBookings);
  final allGapsUnfiltered = detectAllGaps(windowBookings);
  List<BookingGap> shortGaps = allGaps;
  if (redlineMidnight != null) {
    shortGaps = shortGaps
        .where(
          (g) => !_midnightUtc(g.gapStart).isBefore(redlineMidnight),
        )
        .toList();
    _debugLog('Short gaps after redline ${_debugDate(redlineMidnight)}: ${shortGaps.length}');
  }

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
    // Only consider bookings whose check-in is strictly after the redline (stay not started yet);
    // exclude checked-in bookings. _fitsInTargetWithoutOverlap ensures no conflict in target room.
    final candidates = windowBookings
        .where(
          (b) =>
              b.roomId != gap.roomId &&
              (redlineMidnight == null ||
                  _midnightUtc(b.checkInUtc).isAfter(redlineMidnight)) &&
              (checkedInBookingIds == null ||
                  !checkedInBookingIds.contains(b.bookingId)) &&
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
      if (others.length > 10) {
        _debugLog('     ... and ${others.length - 10} more');
      }
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
      // Only suggest moves when the booking's full dates fit in the target (same nights, no reschedule).
      final fits = _fitsInTargetWithoutOverlap(windowBookings, c, gap);
      if (!fits) {
        _debugLog(
          '  candidate ${c.bookingId} (room ${c.roomId}): skipped — would overlap existing booking in target room',
        );
        continue;
      }
      final score = _scoreMove(windowBookings, c, gap, roomMetadata);
      if (best == null || score > best.score) {
        best = _ScoredMove(booking: c, gap: gap, score: score);
        _debugLog(
          '  candidate ${c.bookingId} (room ${c.roomId}): score=$score (new best)',
        );
      }
    }
    if (best == null) {
      // Try two-step chain: move B1 from R1 to gap (frees R1), then B2 from R2 to R1.
      final chain = _findTwoStepChain(
        windowBookings,
        gap,
        roomMetadata,
        redlineMidnight: redlineMidnight,
        checkedInBookingIds: checkedInBookingIds,
      );
      if (chain != null) {
        continuityCandidates.add(chain);
        _debugLog('  → Selected 2-step chain: ${chain.actions.length} moves');
      } else {
        _debugLog('  → All candidates rejected by safety or overlap.');
      }
      continue;
    }

    final beforeTarget = _roomMetrics(windowBookings, gap.roomId);
    final afterTarget = _roomMetricsAfterMove(
      windowBookings,
      best.booking,
      gap.roomId,
      best.booking.checkInUtc,
      best.booking.checkOutUtc,
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
    final reason = createsNewGapInSource
        ? 'Fills a ${gap.gapNights}-night gap in Room ${gap.roomId}. Note: this creates additional short gaps in Room ${best.booking.roomId}.'
        : 'Fills a ${gap.gapNights}-night gap in Room ${gap.roomId} without creating new gaps in Room ${best.booking.roomId}.';

    _debugLog(
      '  → Selected: move ${best.booking.bookingId} from room ${best.booking.roomId} to ${gap.roomId} (score=${best.score})',
    );
    continuityCandidates.add(
      OptimizationSuggestion(
        type: SuggestionType.continuity,
        roomId: gap.roomId,
        message:
            'Move booking ${best.booking.bookingId} from Room ${best.booking.roomId} to Room ${gap.roomId} to create continuity (same dates, same number of nights).',
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
          newCheckIn: best.booking.checkInUtc,
          newCheckOut: best.booking.checkOutUtc,
          requiresUserConfirm: false,
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

  final Set<String> usedBookingIds = {};
  final Set<String> roomsWithActionableGap = {};

  _debugLog(
    'Continuity candidates before dedup: ${continuityCandidates.length}',
  );
  for (final c in continuityCandidates) {
    final ids = c.actions.map((a) => a.bookingId).toSet().toList();
    final overlap = ids.any((id) => usedBookingIds.contains(id));
    if (overlap) {
      _debugLog('  Skip duplicate bookingId in: $ids');
      continue;
    }
    for (final id in ids) {
      usedBookingIds.add(id);
    }
    if (c.roomId != null) {
      roomsWithActionableGap.add(c.roomId!);
    }
    suggestions.add(c);
  }
  _debugLog(
    'Actionable CONTINUITY suggestions after dedup: ${suggestions.where((s) => s.type == SuggestionType.continuity).length}',
  );

  // ── 2) SHORT_GAP only for rooms that have NO actionable continuity ─────────
  final gapsByRoom = <String, List<BookingGap>>{};
  for (final g in shortGaps) {
    if (roomsWithActionableGap.contains(g.roomId)) continue;
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
  _ScoredMove({required this.booking, required this.gap, required this.score});
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
  Map<String, RoomMeta>? roomMetadata,
) {
  final beforeTarget = _roomMetrics(bookings, gap.roomId);
  final afterTarget = _roomMetricsAfterMove(
    bookings,
    candidate,
    gap.roomId,
    candidate.checkInUtc,
    candidate.checkOutUtc,
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
        fromMeta!.type == toMeta!.type) {
      compatibility += 2;
    }
    if (fromMeta?.floor != null &&
        toMeta?.floor != null &&
        fromMeta!.floor == toMeta!.floor) {
      compatibility += 1;
    }
  }

  return targetImprovement - sourceDamage + compatibility;
}

bool _sameDates(GapBookingInput a, GapBookingInput b) {
  final au = _midnightUtc(a.checkInUtc);
  final bu = _midnightUtc(b.checkInUtc);
  if (!au.isAtSameMomentAs(bu)) return false;
  final ae = _midnightUtc(a.checkOutUtc);
  final be = _midnightUtc(b.checkOutUtc);
  return ae.isAtSameMomentAs(be);
}

/// Find a two-step chain: B1 (in R1) → gap, B2 (in R2) → R1. Same dates for B1 and B2.
/// Returns a suggestion with actionChain, or null if none found.
OptimizationSuggestion? _findTwoStepChain(
  List<GapBookingInput> windowBookings,
  BookingGap gap,
  Map<String, RoomMeta>? roomMetadata, {
  DateTime? redlineMidnight,
  Set<String>? checkedInBookingIds,
}) {
  final gapRoomId = gap.roomId;
  for (final b1 in windowBookings) {
    if (b1.roomId == gapRoomId) continue;
    if (redlineMidnight != null &&
        !_midnightUtc(b1.checkInUtc).isAfter(redlineMidnight)) continue;
    if (checkedInBookingIds != null &&
        checkedInBookingIds.contains(b1.bookingId)) continue;
    if (!_isContainedInGap(b1, gap)) continue;
    if (!_isMoveSafe(windowBookings, b1)) continue;
    if (!_fitsInTargetWithoutOverlap(windowBookings, b1, gap)) continue;

    final r1 = b1.roomId;
    final withoutB1 = windowBookings
        .where((b) => !(b.bookingId == b1.bookingId && b.roomId == b1.roomId))
        .toList();
    for (final b2 in windowBookings) {
      if (b2.roomId == r1 || b2.roomId == gapRoomId) continue;
      if (b2.bookingId == b1.bookingId) continue;
      if (redlineMidnight != null &&
          !_midnightUtc(b2.checkInUtc).isAfter(redlineMidnight)) {
        continue;
      }
      if (checkedInBookingIds != null &&
          checkedInBookingIds.contains(b2.bookingId)) {
        continue;
      }
      if (!_sameDates(b1, b2)) {
        continue;
      }
      if (!_isMoveSafe(windowBookings, b2)) {
        continue;
      }
      if (!_fitsInTargetWithDates(withoutB1, r1, b2.checkInUtc, b2.checkOutUtc)) {
        continue;
      }

      final action1 = MoveBookingAction(
        bookingId: b1.bookingId,
        fromRoomId: b1.roomId,
        toRoomId: gapRoomId,
        newCheckIn: b1.checkInUtc,
        newCheckOut: b1.checkOutUtc,
        requiresUserConfirm: false,
      );
      final action2 = MoveBookingAction(
        bookingId: b2.bookingId,
        fromRoomId: b2.roomId,
        toRoomId: r1,
        newCheckIn: b2.checkInUtc,
        newCheckOut: b2.checkOutUtc,
        requiresUserConfirm: false,
      );
      final beforeTarget = _roomMetrics(windowBookings, gapRoomId);
      final afterTarget = _roomMetricsAfterMove(
        windowBookings,
        b1,
        gapRoomId,
        b1.checkInUtc,
        b1.checkOutUtc,
      );
      final effects = <String>[
        'Room $gapRoomId gap count: ${beforeTarget.shortGapCount} → ${afterTarget.shortGapCount}',
        'Two moves: booking ${b1.bookingId} to Room $gapRoomId, then booking ${b2.bookingId} to Room $r1.',
      ];
      return OptimizationSuggestion(
        type: SuggestionType.continuity,
        roomId: gapRoomId,
        message:
            'Chain move to fill gap: (1) Move booking ${b1.bookingId} from Room $r1 to Room $gapRoomId, (2) Move booking ${b2.bookingId} from Room ${b2.roomId} to Room $r1. Same dates, same number of nights.',
        impactScore: _clamp(6 + gap.gapNights, 7, 10),
        relatedGapCount: 1,
        bookingId: b1.bookingId,
        fromRoomId: b1.roomId,
        toRoomId: gapRoomId,
        gapStart: gap.gapStart,
        gapEnd: gap.gapEnd,
        score: 10.0,
        reason:
            'Fills the ${gap.gapNights}-night gap in Room $gapRoomId by shifting two bookings (chess move).',
        effects: effects,
        action: null,
        actionChain: [action1, action2],
      );
    }
  }
  return null;
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

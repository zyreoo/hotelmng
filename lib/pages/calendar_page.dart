import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart'
    show DocumentSnapshot, DocumentChangeType, DocumentChange, QuerySnapshot;
import '../models/booking_model.dart';
import '../models/calendar_booking.dart';
import '../models/room_model.dart';
import '../services/firebase_service.dart';
import '../services/hotel_provider.dart';
import '../services/auth_provider.dart';
import '../utils/stayora_colors.dart';
import '../utils/currency_formatter.dart';
import '../utils/gap_detector.dart';
import '../utils/optimization_suggestions.dart';
import '../features/calendar/models/calendar_cell_data.dart';
import '../features/calendar/widgets/booking_details_form.dart';
import '../features/calendar/widgets/calendar_day_view_card.dart';
import '../widgets/loading_empty_states.dart';
import '../widgets/stayora_logo.dart';
import '../features/calendar/widgets/calendar_bottom_section.dart';
import 'add_booking_page.dart';
import 'room_management_page.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  static const double _headerHeight = 50.0;
  double get _dayLabelWidth =>
      MediaQuery.of(context).size.width >= 768 ? 100.0 : 80.0;
  double get _roomColumnWidth =>
      MediaQuery.of(context).size.width >= 768 ? 120.0 : 90.0;
  // Minimum 48 pt on mobile to meet touch-target guidelines.
  double get _dayRowHeight =>
      MediaQuery.of(context).size.width >= 768 ? 50.0 : 48.0;

  // Sliding window: bounded date range to avoid unbounded widget growth
  DateTime _earliestDate = DateTime.now();
  int _totalDaysLoaded = 30;
  static const int _loadMoreDays = 30;
  static const int _maxDaysLoaded = 180;
  bool _isLoadingMore = false;
  final List<DateTime> _cachedDates = [];
  double _lastScrollOffset = 0.0;

  // Real-time Firestore synchronization
  StreamSubscription<QuerySnapshot>? _bookingsSubscription;
  StreamSubscription<QuerySnapshot>? _waitingListSubscription;
  Timer? _debounceTimer;
  static const Duration _debounceDuration = Duration(milliseconds: 100);

  /// Bookings with status 'Waiting list' (over capacity / not on grid).
  final List<({String id, BookingModel booking})> _waitingListBookings = [];

  // Rooms loaded from Firestore (hotel-specific)
  List<String> _roomNames = [];

  /// Full room models keyed by room name — used for housekeeping dots.
  Map<String, RoomModel> _roomModelsMap = {};

  /// Room ID → current name, used to resolve selectedRoomIds in bookings.
  Map<String, String> _roomIdToNameMap = {};
  final FirebaseService _firebaseService = FirebaseService();
  bool _roomNamesLoaded = false;

  /// Room names to show on the calendar grid, capped by Settings > Total Rooms (max).
  List<String> get _displayedRoomNames {
    final maxRooms = HotelProvider.of(context).currentHotel?.totalRooms;
    if (maxRooms == null || maxRooms <= 0) return _roomNames;
    return _roomNames.take(maxRooms).toList();
  }

  // Sample bookings - each booking represents a night stay
  // Key: DateTime (the night), Value: Map of room -> booking info
  final Map<DateTime, Map<String, CalendarBooking>> _bookings = {};

  /// Full booking models by document ID. One entry per Firestore document.
  /// Used to resolve the full booking when editing any cell of a multi-room stay.
  final Map<String, BookingModel> _bookingModelsById = {};

  /// Last date used in date search; persisted so the dialog reopens with it.
  DateTime? _lastSearchedDate;

  // Selection state for drag-and-drop booking
  bool _roomsNextToEachOther = false;
  String? _selectionStartRoom;
  DateTime? _selectionStartDate;
  String? _selectionEndRoom;
  DateTime? _selectionEndDate;

  /// Hover state — in a [ValueNotifier] so only the affected cell rebuilds on
  /// mouse enter/exit instead of the entire page.
  final _hoverNotifier = ValueNotifier<_HoverState?>(null);

  /// Skeleton drag state — same ValueNotifier trick: only the overlay redraws.
  final _skeletonNotifier = ValueNotifier<_SkeletonState?>(null);

  /// Pre-computed per-(room, date) cell data. Rebuilt once after every booking
  /// change via [_rebuildCellCache], so [_buildRoomCell] never runs O(n) loops.
  final Map<DateTime, Map<String, CalendarCellData>> _cellDataCache = {};

  static List<String> get statusOptions => BookingModel.statusOptions;

  static Color _statusColor(String status) => StayoraColors.forStatus(status);

  static Color _advanceIndicatorColor(String advanceStatus) {
    switch (advanceStatus) {
      case 'paid':
        return StayoraColors.success;
      case 'waiting':
        return StayoraColors.warning;
      case 'not_required':
      default:
        return StayoraColors.muted;
    }
  }

  List<String> get paymentMethods => BookingModel.paymentMethods;
  bool _isSelecting = false;
  List<int> _preselectedRoomsIndex = [];
  final GlobalKey _gridKey = GlobalKey();
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _roomHeadersScrollController = ScrollController();
  final ScrollController _stickyDayLabelsScrollController = ScrollController();

  Future<void> _deleteBooking(
    String userId,
    String hotelId,
    String bookingId,
  ) async {
    await _firebaseService.deleteBooking(userId, hotelId, bookingId);
  }

  Future<void> _updateBooking(
    String userId,
    String hotelId,
    BookingModel booking,
  ) async {
    await _firebaseService.updateBooking(userId, hotelId, booking);
  }

  Future<void> _loadRooms() async {
    final hotelId = HotelProvider.of(context).hotelId;
    final userId = AuthScopeData.of(context).uid;
    if (hotelId == null || userId == null) return;
    try {
      final list = await _firebaseService.getRooms(userId, hotelId);
      if (mounted) {
        setState(() {
          _roomNames = list.map((r) => r.name).toList();
          _roomModelsMap = {for (final r in list) r.name: r};
          _roomIdToNameMap = {
            for (final r in list)
              if (r.id != null) r.id!: r.name,
          };
          _roomNamesLoaded = true;
        });
        _rebuildCellCache();
        _subscribeToBookings();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _roomNames = [];
          _roomModelsMap = {};
          _roomNamesLoaded = true;
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_roomNamesLoaded) {
      _loadRooms();
    }
  }

  /// Returns the current room names for a booking, resolving via document IDs
  /// when available so renaming a room is reflected in old bookings.
  List<String> _resolveRooms(BookingModel booking) =>
      booking.resolvedSelectedRooms(_roomIdToNameMap);

  /// Bookings that occupy a room (excludes Cancelled and Waiting list).
  List<BookingModel> get _occupancyBookings => _bookingModelsById.values
      .where((b) => b.status != 'Cancelled' && b.status != 'Waiting list')
      .toList();

  /// Gap inputs for optimization suggestions (one entry per room per booking).
  /// Uses UTC midnight for check-in/check-out so gap detection and candidate matching align.
  List<GapBookingInput> get _gapBookingInputsCalendar {
    final list = <GapBookingInput>[];
    for (final b in _occupancyBookings) {
      final roomIds = b.selectedRoomIds ?? b.selectedRooms ?? [];
      final checkInUtc = DateTime.utc(
        b.checkIn.year,
        b.checkIn.month,
        b.checkIn.day,
      );
      final checkOutUtc = DateTime.utc(
        b.checkOut.year,
        b.checkOut.month,
        b.checkOut.day,
      );
      for (final roomId in roomIds) {
        if (roomId.isEmpty) continue;
        list.add(
          GapBookingInput(
            bookingId: b.id ?? '',
            roomId: roomId,
            checkInUtc: checkInUtc,
            checkOutUtc: checkOutUtc,
          ),
        );
      }
    }
    return list;
  }

  /// Only suggests moves for gaps and bookings on or after today (redline); excludes checked-in bookings.
  List<OptimizationSuggestion> get _calendarOptimizationSuggestions {
    final now = DateTime.now();
    final redlineUtc = DateTime.utc(now.year, now.month, now.day);
    final checkedInIds = _occupancyBookings
        .where((b) => b.checkedInAt != null)
        .map((b) => b.id)
        .whereType<String>()
        .toSet();
    return generateOptimizationSuggestions(
      _gapBookingInputsCalendar,
      windowStart: now,
      windowDays: 30,
      nowUtc: () => DateTime.now().toUtc(),
      redlineUtc: redlineUtc,
      checkedInBookingIds: checkedInIds,
    );
  }

  /// User-friendly suggestion text: guest name and room names only (no raw IDs).
  String _suggestionDisplayMessage(OptimizationSuggestion s) {
    String text = s.message;
    for (final e in _roomIdToNameMap.entries) {
      text = text.replaceAll('Room ${e.key}', 'Room ${e.value}');
    }
    if (s.bookingId != null) {
      final booking = _bookingModelsById[s.bookingId!];
      if (booking != null && booking.userName.isNotEmpty) {
        text = text.replaceFirst(
          'booking ${s.bookingId!}',
          "${booking.userName}'s booking",
        );
      }
    }
    return text;
  }

  /// Effects lines with room IDs replaced by room names.
  List<String> _suggestionEffectsWithRoomNames(OptimizationSuggestion s) {
    return s.effects.map((e) => _textWithRoomNames(e)).toList();
  }

  String _textWithRoomNames(String text) {
    for (final entry in _roomIdToNameMap.entries) {
      text = text.replaceAll('Room ${entry.key}', 'Room ${entry.value}');
    }
    return text;
  }

  void _showSuggestionsBottomSheet() {
    final suggestions = _calendarOptimizationSuggestions;
    if (suggestions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No optimization suggestions right now.')),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.25,
        maxChildSize: 0.9,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline_rounded,
                        color: StayoraColors.warning,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Suggestions',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    itemCount: suggestions.length,
                    itemBuilder: (context, index) {
                      final s = suggestions[index];
                      final roomName = s.roomId != null
                          ? (_roomIdToNameMap[s.roomId!] ?? s.roomId!)
                          : null;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: Theme.of(
                                context,
                              ).colorScheme.outline.withOpacity(0.2),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _suggestionDisplayMessage(s),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Impact: ${s.impactScore}/10',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                if (s.reason != null &&
                                    s.reason!.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    _textWithRoomNames(s.reason!),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                                if (s.effects.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  ..._suggestionEffectsWithRoomNames(s).map(
                                    (e) => Padding(
                                      padding: const EdgeInsets.only(bottom: 2),
                                      child: Text(
                                        e,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant
                                              .withOpacity(0.9),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                if (s.isActionable && s.actions.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  TextButton.icon(
                                    onPressed: () async {
                                      Navigator.pop(ctx);
                                      final accepted = s.actions.length == 1
                                          ? await _showMovePreviewDialog(
                                              s.actions.first,
                                            )
                                          : await _showChainPreviewDialog(
                                              s.actions,
                                            );
                                      if (accepted == true && mounted) {
                                        await _applyMoveSuggestionChain(
                                          s.actions,
                                        );
                                      }
                                    },
                                    icon: const Icon(
                                      Icons.check_circle_outline_rounded,
                                      size: 18,
                                    ),
                                    label: Text(
                                      s.actions.length > 1
                                          ? 'Apply ${s.actions.length} moves'
                                          : 'Apply',
                                    ),
                                    style: TextButton.styleFrom(
                                      foregroundColor: StayoraLogo.stayoraBlue,
                                    ),
                                  ),
                                ] else if ((s.type == SuggestionType.shortGap ||
                                        s.type == SuggestionType.continuity) &&
                                    s.roomId != null &&
                                    roomName != null) ...[
                                  const SizedBox(height: 10),
                                  TextButton.icon(
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      _showFillGapSuggestion(
                                        s.roomId!,
                                        roomName,
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.auto_fix_high_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Suggest fill'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: StayoraLogo.stayoraBlue,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// True if [a] and [b] represent the same calendar day (UTC).
  static bool _sameDayUtc(DateTime a, DateTime b) {
    final ua = a.toUtc();
    final ub = b.toUtc();
    return ua.year == ub.year && ua.month == ub.month && ua.day == ub.day;
  }

  /// Finds a booking that has the same dates as [gap] but is in another room (not [gapRoomId]).
  /// Returns null if none found — we only suggest moving rooms, not changing nights.
  BookingModel? _findBookingMatchingGapDates(BookingGap gap, String gapRoomId) {
    for (final b in _occupancyBookings) {
      if (!_sameDayUtc(b.checkIn, gap.gapStart) ||
          !_sameDayUtc(b.checkOut, gap.gapEnd)) {
        continue;
      }
      final roomIds = b.selectedRoomIds ?? b.selectedRooms ?? [];
      if (roomIds.contains(gapRoomId)) continue;
      return b;
    }
    return null;
  }

  Future<void> _showFillGapSuggestion(String roomId, String roomName) async {
    final gapInputs = _gapBookingInputsCalendar;
    final gaps = detectGaps(
      gapInputs,
    ).where((g) => g.roomId == roomId).toList();
    if (gaps.isEmpty) return;
    final gap = gaps.first;
    final candidate = _findBookingMatchingGapDates(gap, roomId);
    if (candidate == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No booking with the same dates (${DateFormat('MMM d').format(gap.gapStart)}–${DateFormat('MMM d').format(gap.gapEnd)}) in another room to move into $roomName.',
          ),
        ),
      );
      return;
    }
    final dateFormat = DateFormat('MMM d, yyyy');
    final dateRange =
        '${dateFormat.format(candidate.checkIn)} – ${dateFormat.format(candidate.checkOut)}';
    final currentRoomNames = _resolveRooms(candidate);
    final currentRoomLabel = currentRoomNames.isEmpty
        ? 'another room'
        : currentRoomNames.join(', ');

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm room change'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'To fill the gap in $roomName:',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Move ${candidate.userName}\'s booking from $currentRoomLabel to $roomName. Dates stay the same: $dateRange.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Do you want to apply this change?',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final userId = AuthScopeData.of(context).uid;
    final hotelId = HotelProvider.of(context).hotelId;
    if (userId == null || hotelId == null) return;
    // Change only the room: same check-in/check-out, assign this booking to the gap room.
    final updated = candidate.copyWith(
      numberOfRooms: 1,
      selectedRooms: [roomName],
      selectedRoomIds: [roomId],
    );
    await _updateBooking(userId, hotelId, updated);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${candidate.userName}\'s booking moved to $roomName.'),
        ),
      );
    }
  }

  /// Shows a preview of the move (before → after). Returns true if user accepts.
  Future<bool?> _showMovePreviewDialog(MoveBookingAction action) async {
    final booking = _bookingModelsById[action.bookingId];
    if (booking == null) return false;
    final fromRoomName =
        _roomIdToNameMap[action.fromRoomId] ?? action.fromRoomId;
    final toRoomName = _roomIdToNameMap[action.toRoomId] ?? action.toRoomId;
    final dateFormat = DateFormat('MMM d, yyyy');
    final beforeRange =
        '${dateFormat.format(booking.checkIn)} – ${dateFormat.format(booking.checkOut)}';
    final datesChange = action.requiresUserConfirm;
    final afterRange = datesChange
        ? '${dateFormat.format(action.newCheckIn)} – ${dateFormat.format(action.newCheckOut)}'
        : beforeRange;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Preview change'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${booking.userName}\'s booking will move as shown below. Accept to apply.',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              _MovePreviewTimeline(
                fromRoomName: fromRoomName,
                toRoomName: toRoomName,
                beforeCheckIn: booking.checkIn,
                beforeCheckOut: booking.checkOut,
                afterCheckIn: action.newCheckIn,
                afterCheckOut: action.newCheckOut,
              ),
              const SizedBox(height: 12),
              _previewRow(
                ctx,
                label: 'Before',
                guest: booking.userName,
                room: fromRoomName,
                dates: beforeRange,
                isBefore: true,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.arrow_downward_rounded,
                      size: 20,
                      color: Theme.of(ctx).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'will become',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(ctx).colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              _previewRow(
                ctx,
                label: 'After',
                guest: booking.userName,
                room: toRoomName,
                dates: afterRange,
                isBefore: false,
              ),
              if (datesChange) ...[
                const SizedBox(height: 12),
                Text(
                  'Stay length will change to match the gap.',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'Accept to apply this change, or cancel.',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Don\'t accept'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }

  Widget _previewRow(
    BuildContext ctx, {
    required String label,
    required String guest,
    required String room,
    required String dates,
    required bool isBefore,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(
          ctx,
        ).colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(ctx).colorScheme.outline.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$guest\'s booking',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Theme.of(ctx).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Room $room • $dates',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(ctx).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Applies the move (room only; dates and number of nights stay the same).
  Future<void> _applyMoveSuggestion(MoveBookingAction action) async {
    final booking = _bookingModelsById[action.bookingId];
    if (booking == null) return;
    final toRoomName = _roomIdToNameMap[action.toRoomId] ?? action.toRoomId;
    final userId = AuthScopeData.of(context).uid;
    final hotelId = HotelProvider.of(context).hotelId;
    if (userId == null || hotelId == null) return;

    final updated = booking.copyWith(
      numberOfRooms: 1,
      selectedRooms: [toRoomName],
      selectedRoomIds: [action.toRoomId],
    );
    await _updateBooking(userId, hotelId, updated);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${booking.userName}\'s booking moved to $toRoomName.'),
        ),
      );
    }
  }

  /// Applies a chain of moves in order (e.g. B1→gap, then B2→freed slot).
  Future<void> _applyMoveSuggestionChain(
    List<MoveBookingAction> actions,
  ) async {
    for (final action in actions) {
      await _applyMoveSuggestion(action);
      if (!mounted) return;
    }
  }

  /// Preview for a chain of moves (Cursor-style: before | after calendar view). Returns true if user accepts.
  Future<bool?> _showChainPreviewDialog(List<MoveBookingAction> actions) async {
    for (final a in actions) {
      if (_bookingModelsById[a.bookingId] == null) return false;
    }
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Preview chain move'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'How the calendar will look before and after applying ${actions.length} moves.',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              _ChainPreviewCalendar(
                actions: actions,
                bookingModelsById: _bookingModelsById,
                roomIdToNameMap: _roomIdToNameMap,
              ),
              const SizedBox(height: 16),
              Text(
                'Accept to apply all moves, or cancel.',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Don\'t accept'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _earliestDate = DateTime.now();

    // Sync room headers scroll with horizontal scroll
    _horizontalScrollController.addListener(() {
      if (_roomHeadersScrollController.hasClients &&
          _horizontalScrollController.hasClients) {
        final mainOffset = _horizontalScrollController.offset;
        final headerOffset = _roomHeadersScrollController.offset;
        // Only jump if offsets differ significantly (avoid redundant jumps)
        if ((mainOffset - headerOffset).abs() > 0.1) {
          _roomHeadersScrollController.jumpTo(mainOffset);
        }
      }
    });

    // Sync sticky day labels scroll with main vertical scroll
    _verticalScrollController.addListener(() {
      if (_stickyDayLabelsScrollController.hasClients &&
          _verticalScrollController.hasClients) {
        final mainOffset = _verticalScrollController.offset;
        final stickyOffset = _stickyDayLabelsScrollController.offset;
        // Only jump if offsets differ significantly (avoid redundant jumps)
        if ((mainOffset - stickyOffset).abs() > 0.1) {
          _stickyDayLabelsScrollController.jumpTo(mainOffset);
        }
      }
      // Also check for loading more dates
      _onVerticalScroll();
    });

    // Ensure initial synchronization after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_verticalScrollController.hasClients &&
          _stickyDayLabelsScrollController.hasClients) {
        final mainOffset = _verticalScrollController.offset;
        final stickyOffset = _stickyDayLabelsScrollController.offset;
        if ((mainOffset - stickyOffset).abs() > 0.1) {
          _stickyDayLabelsScrollController.jumpTo(mainOffset);
        }
      }
      if (_horizontalScrollController.hasClients &&
          _roomHeadersScrollController.hasClients) {
        final mainOffset = _horizontalScrollController.offset;
        final headerOffset = _roomHeadersScrollController.offset;
        if ((mainOffset - headerOffset).abs() > 0.1) {
          _roomHeadersScrollController.jumpTo(mainOffset);
        }
      }

      // Subscribe to real-time bookings for the visible date range
      _subscribeToBookings();
    });
  }

  void _onVerticalScroll() {
    if (!_verticalScrollController.hasClients || _isLoadingMore) return;
    final currentOffset = _verticalScrollController.offset;
    final isScrollingUp = currentOffset < _lastScrollOffset;
    _lastScrollOffset = currentOffset;
    // Only load more past dates when the user is actively scrolling UP
    // and reaches near the top — not on downward scroll or initial render.
    if (isScrollingUp && currentOffset < 200) {
      _loadMoreDatesUp();
    }
  }

  void _loadMoreDatesUp() {
    if (_isLoadingMore || !mounted) return;

    setState(() {
      _isLoadingMore = true;
    });

    final currentOffset = _verticalScrollController.offset;
    final daysToAdd = _loadMoreDays;
    final newEarliestDate = _earliestDate.subtract(Duration(days: daysToAdd));

    if (!mounted) return;
    setState(() {
      _earliestDate = newEarliestDate;
      _totalDaysLoaded += daysToAdd;
      _isLoadingMore = false;
    });

    // Re-subscribe so we fetch bookings for the new range (including dates above today)
    _subscribeToBookings();

    // Adjust scroll position to maintain view after frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_verticalScrollController.hasClients) {
        // Use dayRowHeight for scroll offset
        final newOffset = currentOffset + (daysToAdd * _dayRowHeight);
        _verticalScrollController.jumpTo(newOffset);
        // Sticky day labels will be updated automatically by the listener
      }
    });
  }

  void _scrollToDate(DateTime targetDate) {
    if (!_verticalScrollController.hasClients) return;

    // Ensure the target date is loaded
    if (targetDate.isBefore(_earliestDate)) {
      final daysNeeded = _earliestDate.difference(targetDate).inDays;
      final daysToAdd = ((daysNeeded / _loadMoreDays).ceil() * _loadMoreDays);
      final newEarliestDate = _earliestDate.subtract(Duration(days: daysToAdd));

      setState(() {
        _earliestDate = newEarliestDate;
        _totalDaysLoaded += daysToAdd;
      });

      // Re-subscribe so bookings are loaded for the extended range
      _subscribeToBookings();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToDate(targetDate);
      });
      return;
    }

    // Extend forward if target is after loaded range
    final daysFromStart = targetDate.difference(_earliestDate).inDays;
    if (daysFromStart >= _totalDaysLoaded) {
      final extra = (daysFromStart - _totalDaysLoaded + 1).clamp(
        0,
        _maxDaysLoaded - _totalDaysLoaded,
      );
      if (extra > 0) {
        setState(() => _totalDaysLoaded += extra);
        _subscribeToBookings();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _scrollToDate(targetDate);
        });
        return;
      }
    }

    // Scroll to date
    if (daysFromStart >= 0 && daysFromStart < _totalDaysLoaded) {
      final targetOffset = daysFromStart * _dayRowHeight;
      _verticalScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _showDateSearchDialog() async {
    final initial = _lastSearchedDate ?? DateTime.now();
    DateTime date = initial;

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 320),
                decoration: BoxDecoration(
                  color: StayoraColors.surfaceLight,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(
                        context,
                      ).colorScheme.shadow.withOpacity(0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 24),
                    Text(
                      'Search date',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 17,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Go to date',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Material(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: date,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (picked != null) {
                              setModalState(() => date = picked);
                            }
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.calendar_today_rounded,
                                  size: 20,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  DateFormat('EEEE, MMM d, yyyy').format(date),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                ),
                                const Spacer(),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 22,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              style: TextButton.styleFrom(
                                foregroundColor: StayoraColors.blue,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                if (!mounted) return;
                                _lastSearchedDate = date;
                                _scrollToDate(date);
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: StayoraColors.blue,
                                foregroundColor: Theme.of(
                                  context,
                                ).colorScheme.onPrimary,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                elevation: 0,
                              ),
                              child: const Text('Search'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _bookingsSubscription?.cancel();
    _waitingListSubscription?.cancel();
    _hoverNotifier.dispose();
    _skeletonNotifier.dispose();
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    _roomHeadersScrollController.dispose();
    _stickyDayLabelsScrollController.dispose();
    super.dispose();
  }

  CalendarBooking? _getBooking(String room, DateTime date) {
    final nightDate = DateTime(date.year, date.month, date.day);
    return _bookings[nightDate]?[room];
  }

  /// Rebuilds the per-cell data cache from the current [_bookings] map and
  /// [_displayedRoomNames]. Call this after every booking change (debounced).
  void _rebuildCellCache() {
    final rooms = _displayedRoomNames;
    _cellDataCache.clear();

    for (final date in _dates) {
      final dateKey = DateTime(date.year, date.month, date.day);
      final prevKey = dateKey.subtract(const Duration(days: 1));
      final nextKey = dateKey.add(const Duration(days: 1));
      final rowCache = <String, CalendarCellData>{};

      for (int ri = 0; ri < rooms.length; ri++) {
        final room = rooms[ri];
        final booking = _getBooking(room, date);
        if (booking == null) {
          rowCache[room] = CalendarCellData.empty;
          continue;
        }
        final bid = booking.bookingId;
        final connLeft =
            ri > 0 && _getBooking(rooms[ri - 1], date)?.bookingId == bid;
        final connRight =
            ri < rooms.length - 1 &&
            _getBooking(rooms[ri + 1], date)?.bookingId == bid;
        final connTop = _getBooking(room, prevKey)?.bookingId == bid;
        final connBottom = _getBooking(room, nextKey)?.bookingId == bid;

        // First room index for this booking on this date.
        int firstRoomIdx = ri;
        while (firstRoomIdx > 0 &&
            _getBooking(rooms[firstRoomIdx - 1], date)?.bookingId == bid) {
          firstRoomIdx--;
        }
        int span = 0;
        for (int i = firstRoomIdx; i < rooms.length; i++) {
          if (_getBooking(rooms[i], date)?.bookingId == bid) {
            span++;
          } else {
            break;
          }
        }
        final midIdx = firstRoomIdx + (span ~/ 2);
        final isInfoCell =
            booking.isFirstNight &&
            (span == 1 ? ri == firstRoomIdx : ri == midIdx);

        rowCache[room] = CalendarCellData(
          booking: booking,
          isConnectedLeft: connLeft,
          isConnectedRight: connRight,
          isConnectedTop: connTop,
          isConnectedBottom: connBottom,
          isInfoCell: isInfoCell,
          centerInfoInBubble: span >= 2,
        );
      }
      _cellDataCache[dateKey] = rowCache;
    }
  }

  // Selection helper methods
  bool _isCellInSelection(String room, DateTime date) {
    if (!_isSelecting ||
        _selectionStartRoom == null ||
        _selectionStartDate == null) {
      return false;
    }

    final startRoomIndex = _displayedRoomNames.indexOf(_selectionStartRoom!);
    final endRoomIndex = _selectionEndRoom != null
        ? _displayedRoomNames.indexOf(_selectionEndRoom!)
        : startRoomIndex;
    final currentRoomIndex = _displayedRoomNames.indexOf(room);

    if (currentRoomIndex == -1 || startRoomIndex == -1) return false;

    final startDate = _selectionStartDate!;
    final endDate = _selectionEndDate ?? startDate;

    final minRoomIndex = startRoomIndex < endRoomIndex
        ? startRoomIndex
        : endRoomIndex;
    final maxRoomIndex = startRoomIndex > endRoomIndex
        ? startRoomIndex
        : endRoomIndex;
    // Normalize dates to midnight for comparison
    final startDateNormalized = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
    );
    final endDateNormalized = DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
    );
    final currentDate = DateTime(date.year, date.month, date.day);

    // Ensure minDate is before maxDate (handle upward selection)
    final minDate = startDateNormalized.isBefore(endDateNormalized)
        ? startDateNormalized
        : endDateNormalized;
    final maxDate = startDateNormalized.isAfter(endDateNormalized)
        ? startDateNormalized
        : endDateNormalized;

    final roomInRange =
        currentRoomIndex >= minRoomIndex && currentRoomIndex <= maxRoomIndex;

    // Check if current date is within the selected date range (inclusive)
    final dateInRange =
        (currentDate.isAtSameMomentAs(minDate) ||
            currentDate.isAtSameMomentAs(maxDate)) ||
        (currentDate.isAfter(minDate) && currentDate.isBefore(maxDate));

    return roomInRange && dateInRange;
  }

  void _startSelection(String room, DateTime date) {
    setState(() {
      _isSelecting = true;
      _roomsNextToEachOther = false;
      _selectionStartRoom = room;
      _selectionStartDate = date;
      _selectionEndRoom = room;
      _selectionEndDate = date;
    });
  }

  void _updateSelection(String room, DateTime date) {
    if (_isSelecting) {
      setState(() {
        _selectionEndRoom = room;
        _selectionEndDate = date;
      });
    }
  }

  /// Finds all bookings that occupy any cell in [selectedRooms] x [selectedDates]
  /// and moves them to Waiting list. Optionally exclude [excludeBookingId] (e.g. the booking being moved).
  Future<void> _moveBookingsInSelectionToWaitingList(
    List<String> selectedRooms,
    List<DateTime> selectedDates, {
    String? excludeBookingId,
  }) async {
    final userId = AuthScopeData.of(context).uid;
    final hotelId = HotelProvider.of(context).hotelId;
    if (userId == null || hotelId == null) return;

    final Set<String> bookingIds = {};
    for (final room in selectedRooms) {
      for (final date in selectedDates) {
        final night = DateTime(date.year, date.month, date.day);
        final booking = _getBooking(room, night);
        if (booking != null && booking.bookingId.isNotEmpty) {
          if (excludeBookingId == null ||
              booking.bookingId != excludeBookingId) {
            bookingIds.add(booking.bookingId);
          }
        }
      }
    }

    for (final id in bookingIds) {
      final model = _bookingModelsById[id];
      if (model == null ||
          model.status == 'Cancelled' ||
          model.status == 'Waiting list') {
        continue;
      }
      await _updateBooking(
        userId,
        hotelId,
        model.copyWith(status: 'Waiting list'),
      );
    }
  }

  /// Move a booking (from the grid) to the waiting list. No-op if already Waiting list or Cancelled.
  Future<void> _moveBookingToWaitingList(String bookingId) async {
    final userId = AuthScopeData.of(context).uid;
    final hotelId = HotelProvider.of(context).hotelId;
    if (userId == null || hotelId == null) return;

    final model = _bookingModelsById[bookingId];
    if (model == null ||
        model.status == 'Cancelled' ||
        model.status == 'Waiting list') {
      return;
    }

    final updated = model.copyWith(status: 'Waiting list');
    await _updateBooking(userId, hotelId, updated);

    // Remove from grid immediately so UI updates without waiting for Firestore snapshot
    for (final entry in _bookings.entries.toList()) {
      final roomMap = entry.value;
      for (final roomName in roomMap.keys.toList()) {
        if (roomMap[roomName]?.bookingId == bookingId) {
          roomMap.remove(roomName);
        }
      }
    }
    for (final nightDate in _bookings.keys.toList()) {
      if (_bookings[nightDate]!.isEmpty) {
        _bookings.remove(nightDate);
      }
    }
    if (mounted) setState(() {});

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${model.userName} moved to waiting list'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: StayoraColors.purple,
        ),
      );
    }
  }

  /// Returns the waiting-list booking for [bookingId], or null.
  BookingModel? _getWaitingListBookingById(String bookingId) {
    for (final e in _waitingListBookings) {
      if (e.id == bookingId) return e.booking;
    }
    return null;
  }

  /// Drop a booking onto the calendar at (room, date). Works for both waiting-list and grid bookings.
  /// Displaced bookings in that range are moved to the waiting list (excluding the one being placed).
  Future<void> _onDropWaitingListBooking(
    String bookingId,
    String room,
    DateTime date,
  ) async {
    final userId = AuthScopeData.of(context).uid;
    final hotelId = HotelProvider.of(context).hotelId;
    if (userId == null || hotelId == null) {
      return;
    }

    // Resolve booking: from waiting list or from grid (_bookingModelsById)
    BookingModel? booking;
    bool fromWaitingList = false;
    for (final e in _waitingListBookings) {
      if (e.id == bookingId) {
        booking = e.booking;
        fromWaitingList = true;
        break;
      }
    }
    booking ??= _bookingModelsById[bookingId];
    if (booking == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Booking not found'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final roomIndex = _displayedRoomNames.indexOf(room);
    if (roomIndex == -1) return;
    final n = booking.numberOfRooms;
    // Use as many contiguous rooms as fit from the drop cell (1 to n) so the user can place the booking anywhere.
    final roomCount = n.clamp(1, _displayedRoomNames.length - roomIndex);
    if (roomCount < 1) return;
    final targetRooms = _displayedRoomNames.sublist(
      roomIndex,
      roomIndex + roomCount,
    );
    final checkIn = DateTime(date.year, date.month, date.day);
    final checkOut = checkIn.add(Duration(days: booking.numberOfNights));

    // Build the placement update first.
    final targetRoomIds = <String>[];
    for (final name in targetRooms) {
      final id = _roomModelsMap[name]?.id;
      if (id != null && id.isNotEmpty) targetRoomIds.add(id);
    }
    final newStatus = fromWaitingList ? 'Confirmed' : booking.status;
    final updated = booking.copyWith(
      checkIn: checkIn,
      checkOut: checkOut,
      numberOfRooms: targetRooms.length,
      selectedRooms: targetRooms,
      selectedRoomIds: targetRoomIds.length == targetRooms.length
          ? targetRoomIds
          : [],
      status: newStatus,
    );

    // Save the dropped booking first. Only if that succeeds, move displaced bookings to waiting list.
    try {
      await _updateBooking(userId, hotelId, updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not place booking: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: StayoraColors.error,
          ),
        );
      }
      return;
    }

    // Placement saved: now move any existing bookings in that range to waiting list (exclude the one we placed).
    final selectedDates = <DateTime>[];
    for (
      var d = checkIn;
      d.isBefore(checkOut);
      d = d.add(const Duration(days: 1))
    ) {
      selectedDates.add(d);
    }
    await _moveBookingsInSelectionToWaitingList(
      targetRooms,
      selectedDates,
      excludeBookingId: bookingId,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${booking.userName} moved to ${targetRooms.join(", ")}',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: StayoraColors.success,
        ),
      );
    }
  }

  void _endSelection() {
    if (_isSelecting &&
        _selectionStartRoom != null &&
        _selectionStartDate != null) {
      final selectedRooms = _getSelectedRooms();
      final selectedDates = _getSelectedDates();

      if (selectedRooms.isNotEmpty && selectedDates.isNotEmpty) {
        _roomsNextToEachOther = _areSelectedRoomsNextToEachOther(selectedRooms);
        _preselectedRoomsIndex = selectedRooms
            .map((room) => _displayedRoomNames.indexOf(room))
            .where((index) => index != -1)
            .toList();
        // Move any existing bookings in the selected range to waiting list, then open dialog
        _moveBookingsInSelectionToWaitingList(
          selectedRooms,
          selectedDates,
        ).then((_) {
          if (!mounted) return;
          _showBookingDialog(
            selectedRooms,
            selectedDates,
            _roomsNextToEachOther,
            preselectedRoomIndexes: _preselectedRoomsIndex,
          );
        });
      }

      setState(() {
        _isSelecting = false;
        _selectionStartRoom = null;
        _selectionStartDate = null;
        _selectionEndRoom = null;
        _selectionEndDate = null;
        _roomsNextToEachOther = false;
        _preselectedRoomsIndex = [];
      });
    }
  }

  List<String> _getSelectedRooms() {
    if (_selectionStartRoom == null) return [];

    final startIndex = _displayedRoomNames.indexOf(_selectionStartRoom!);
    final endIndex = _selectionEndRoom != null
        ? _displayedRoomNames.indexOf(_selectionEndRoom!)
        : startIndex;

    final minIndex = startIndex < endIndex ? startIndex : endIndex;
    final maxIndex = startIndex > endIndex ? startIndex : endIndex;

    return _displayedRoomNames.sublist(minIndex, maxIndex + 1);
  }

  List<DateTime> _getSelectedDates() {
    if (_selectionStartDate == null) return [];

    final startDate = _selectionStartDate!;
    final endDate = _selectionEndDate ?? startDate;

    // Normalize dates to midnight and ensure min/max order
    final startNormalized = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
    );
    final endNormalized = DateTime(endDate.year, endDate.month, endDate.day);

    final minDate = startNormalized.isBefore(endNormalized)
        ? startNormalized
        : endNormalized;
    final maxDate = startNormalized.isAfter(endNormalized)
        ? startNormalized
        : endNormalized;

    final days = maxDate.difference(minDate).inDays + 1;
    return List.generate(days, (index) {
      return DateTime(
        minDate.year,
        minDate.month,
        minDate.day,
      ).add(Duration(days: index));
    });
  }

  bool _areSelectedRoomsNextToEachOther(List<String> rooms) {
    if (rooms.length < 2) return false;

    final indices = rooms
        .map((room) => _displayedRoomNames.indexOf(room))
        .toList();
    if (indices.any((index) => index == -1)) return false;

    indices.sort();
    for (var i = 1; i < indices.length; i++) {
      if (indices[i] - indices[i - 1] != 1) {
        return false;
      }
    }
    return true;
  }

  DateTime? _cachedEarliestDate;
  int? _cachedTotalDays;

  List<DateTime> get _dates {
    if (_cachedDates.isEmpty ||
        _cachedEarliestDate != _earliestDate ||
        _cachedTotalDays != _totalDaysLoaded) {
      _cachedEarliestDate = _earliestDate;
      _cachedTotalDays = _totalDaysLoaded;
      final base = DateTime(
        _earliestDate.year,
        _earliestDate.month,
        _earliestDate.day,
      );
      _cachedDates
        ..clear()
        ..addAll(
          List.generate(
            _totalDaysLoaded,
            (index) => base.add(Duration(days: index)),
          ),
        );
    }
    return _cachedDates;
  }

  Map<String, dynamic>? _getCellFromPosition(Offset position) {
    final scrollX = _horizontalScrollController.hasClients
        ? _horizontalScrollController.offset
        : 0.0;
    final scrollY = _verticalScrollController.hasClients
        ? _verticalScrollController.offset
        : 0.0;

    final adjustedX = position.dx + scrollX;
    if (adjustedX < _dayLabelWidth) return null;

    final roomIndex = ((adjustedX - _dayLabelWidth) / _roomColumnWidth).floor();
    if (roomIndex < 0 || roomIndex >= _displayedRoomNames.length) return null;

    // Position is already relative to the gesture detector which is below the header
    final localY = position.dy;
    if (localY < 0) return null;

    // Calculate day index using dayRowHeight
    final dayIndex = ((localY + scrollY) / _dayRowHeight).floor();
    if (dayIndex < 0 || dayIndex >= _dates.length) return null;

    return {'room': _displayedRoomNames[roomIndex], 'date': _dates[dayIndex]};
  }

  void _subscribeToBookings() {
    _bookingsSubscription?.cancel();

    final rangeStart = DateTime(
      _earliestDate.year,
      _earliestDate.month,
      _earliestDate.day,
    );
    final rangeEnd = rangeStart.add(Duration(days: _totalDaysLoaded));

    final userId = FirebaseAuth.instance.currentUser?.uid;
    final hotelId = HotelProvider.of(context).hotelId;
    if (hotelId == null || userId == null) return;

    _bookingsSubscription = _firebaseService
        .bookingsStreamForCalendar(userId, hotelId, rangeStart)
        .listen(
          (snapshot) {
            _processBookingChanges(snapshot.docChanges, rangeStart, rangeEnd);
          },
          onError: (error, stackTrace) {
            debugPrint('Firestore booking subscription error: $error');
            if (mounted) {
              final msg = error.toString().contains('permission-denied')
                  ? 'Calendar: sign in or check Firestore rules.'
                  : 'Calendar: could not load bookings.';
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(msg), backgroundColor: StayoraColors.error),
              );
            }
          },
          cancelOnError: false,
        );
    _subscribeToWaitingList();
  }

  void _subscribeToWaitingList() {
    _waitingListSubscription?.cancel();

    final userId = FirebaseAuth.instance.currentUser?.uid;
    final hotelId = HotelProvider.of(context).hotelId;
    if (hotelId == null || userId == null) return;

    _waitingListSubscription = _firebaseService
        .waitingListBookingsStream(userId, hotelId)
        .listen(
          (snapshot) {
            if (!mounted) return;
            final list = <({String id, BookingModel booking})>[];
            for (final doc in snapshot.docs) {
              final data = doc.data();
              list.add((
                id: doc.id,
                booking: BookingModel.fromFirestore(data, doc.id),
              ));
            }
            setState(() {
              _waitingListBookings
                ..clear()
                ..addAll(list);
            });
          },
          onError: (error, stackTrace) {
            debugPrint('Firestore waiting list subscription error: $error');
            if (mounted && error.toString().contains('permission-denied')) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Waiting list: sign in or check Firestore rules.'),
                  backgroundColor: StayoraColors.error,
                ),
              );
            }
          },
          cancelOnError: false,
        );
  }

  void _processBookingChanges(
    List<DocumentChange<Map<String, dynamic>>> changes,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) {
    bool needsUpdate = false;

    for (final change in changes) {
      final data = change.doc.data();
      if (data == null) continue;

      final bookingModel = BookingModel.fromFirestore(data, change.doc.id);

      final bookingStart = DateTime(
        bookingModel.checkIn.year,
        bookingModel.checkIn.month,
        bookingModel.checkIn.day,
      );
      final bookingEnd = DateTime(
        bookingModel.checkOut.year,
        bookingModel.checkOut.month,
        bookingModel.checkOut.day,
      );

      // Include only bookings that overlap visible range [rangeStart, rangeEnd)
      // Overlap: bookingStart < rangeEnd AND bookingEnd > rangeStart
      if (bookingStart.isAtSameMomentAs(rangeEnd) ||
          bookingStart.isAfter(rangeEnd) ||
          bookingEnd.isAtSameMomentAs(rangeStart) ||
          bookingEnd.isBefore(rangeStart)) {
        continue; // completely outside visible range
      }

      // Waiting list bookings are not drawn on the grid; they are shown in the waiting list section
      if (bookingModel.status == 'Waiting list') {
        final docId = change.doc.id;
        // Remove from grid so it doesn't stay visible when moved to waiting list
        for (final entry in _bookings.entries.toList()) {
          final roomMap = entry.value;
          for (final roomName in roomMap.keys.toList()) {
            if (roomMap[roomName]?.bookingId == docId) {
              roomMap.remove(roomName);
              needsUpdate = true;
            }
          }
        }
        for (final nightDate in _bookings.keys.toList()) {
          if (_bookings[nightDate]!.isEmpty) {
            _bookings.remove(nightDate);
          }
        }
        if (change.type == DocumentChangeType.removed) {
          _bookingModelsById.remove(docId);
        } else {
          _bookingModelsById[docId] = bookingModel;
        }
        needsUpdate = true;
        continue;
      }

      final rooms = _resolveRooms(bookingModel);
      if (rooms.isEmpty) continue;

      final docId = change.doc.id;

      if (change.type == DocumentChangeType.removed) {
        // Remove this booking from all cells
        for (final entry in _bookings.entries.toList()) {
          final nightDate = entry.key;
          final roomMap = entry.value;
          for (final roomName in roomMap.keys.toList()) {
            if (roomMap[roomName]?.bookingId == docId) {
              roomMap.remove(roomName);
              needsUpdate = true;
            }
          }
          if (roomMap.isEmpty) {
            _bookings.remove(nightDate);
          }
        }
        _bookingModelsById.remove(docId);
        continue;
      }

      // Added or modified: clear any previous placement of this booking (so moved bookings don't stay in old cells)
      for (final entry in _bookings.entries.toList()) {
        final roomMap = entry.value;
        for (final roomName in roomMap.keys.toList()) {
          if (roomMap[roomName]?.bookingId == docId) {
            roomMap.remove(roomName);
            needsUpdate = true;
          }
        }
      }
      for (final nightDate in _bookings.keys.toList()) {
        if (_bookings[nightDate]!.isEmpty) {
          _bookings.remove(nightDate);
        }
      }

      final totalNights = bookingModel.numberOfNights;

      for (final room in rooms) {
        if (!_roomNames.contains(room)) continue;

        for (int i = 0; i < totalNights; i++) {
          final nightDate = bookingStart.add(Duration(days: i));

          // Show only nights inside visible range: nightDate >= rangeStart AND nightDate < rangeEnd
          if (nightDate.isBefore(rangeStart) ||
              nightDate.isAtSameMomentAs(rangeEnd) ||
              nightDate.isAfter(rangeEnd)) {
            continue; // night outside visible range
          }

          // Add placement
          _bookings[nightDate] ??= {};
          _bookings[nightDate]![room] = CalendarBooking(
            bookingId: bookingModel.id ?? '',
            guestName: bookingModel.userName,
            color: StayoraColors.calendarColor(bookingModel.status),
            isFirstNight: i == 0,
            isLastNight: i == totalNights - 1,
            totalNights: totalNights,
            advancePaymentStatus: bookingModel.advancePaymentStatus,
            status: bookingModel.status,
            phone: bookingModel.userPhone,
          );
          needsUpdate = true;
        }
      }

      _bookingModelsById[docId] = bookingModel;
    }

    if (needsUpdate) {
      _debouncedSetState();
    }
  }

  void _debouncedSetState() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () {
      if (mounted) {
        setState(() {});
        _rebuildCellCache();
      }
    });
  }

  Future<void> _showDayViewDialog() async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: _lastSearchedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: isDark
                ? const ColorScheme.dark(primary: StayoraColors.blue)
                : const ColorScheme.light(primary: StayoraColors.blue),
          ),
          child: child!,
        );
      },
    );

    if (selectedDate == null) return;

    // Get bookings for the selected date
    final bookingsForDay = <BookingModel>[];
    for (final entry in _bookingModelsById.entries) {
      final booking = entry.value;
      final checkInDate = DateTime(
        booking.checkIn.year,
        booking.checkIn.month,
        booking.checkIn.day,
      );
      final checkOutDate = DateTime(
        booking.checkOut.year,
        booking.checkOut.month,
        booking.checkOut.day,
      );
      final targetDate = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
      );

      // Check if booking overlaps the selected date
      if (!targetDate.isBefore(checkInDate) &&
          targetDate.isBefore(checkOutDate)) {
        bookingsForDay.add(booking);
      }
    }

    if (!mounted) return;

    // Show dialog with bookings for that day
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF1C1C1E)
                : Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat(
                              'EEEE, MMM d, yyyy',
                            ).format(selectedDate),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${bookingsForDay.length} booking${bookingsForDay.length != 1 ? 's' : ''}',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Bookings list
              Expanded(
                child: bookingsForDay.isEmpty
                    ? const EmptyStateWidget(
                        icon: Icons.event_busy_rounded,
                        title: 'No bookings for this date',
                        subtitle: 'Select another date or add a new booking',
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: bookingsForDay.length,
                        itemBuilder: (context, index) {
                          final booking = bookingsForDay[index];
                          return CalendarDayViewCard(
                            booking: booking,
                            roomIdToName: _roomIdToNameMap,
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.of(context, rootNavigator: false).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      AddBookingPage(existingBooking: booking),
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 8),
                        Text(
                          'Calendar',
                          style: Theme.of(context).textTheme.headlineLarge
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 34,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Material(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            onTap: _showDateSearchDialog,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 12,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.search_rounded,
                                    size: 18,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    DateFormat('MMM d, yyyy').format(
                                      _lastSearchedDate ?? DateTime.now(),
                                    ),
                                    style: Theme.of(context).textTheme.bodyLarge
                                        ?.copyWith(
                                          color: Theme.of(context).colorScheme.onSurface,
                                        ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: _showDayViewDialog,
                            icon: const Icon(Icons.view_day_rounded, size: 24),
                            tooltip: 'Day View',
                            style: IconButton.styleFrom(
                              foregroundColor: StayoraLogo.stayoraBlue,
                              backgroundColor: Colors.transparent,
                            ),
                          ),
                          const SizedBox(width: 4),
                          TextButton.icon(
                            onPressed: () async {
                              await Navigator.of(
                                context,
                                rootNavigator: false,
                              ).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const RoomManagementPage(),
                                ),
                              );
                              _loadRooms();
                            },
                            icon: const Icon(
                              Icons.meeting_room_rounded,
                              size: 20,
                            ),
                            label: Text(
                              'Manage rooms',
                              overflow: TextOverflow.ellipsis,
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: StayoraLogo.stayoraBlue,
                              backgroundColor: Colors.transparent,
                            ),
                          ),
                          const SizedBox(width: 4),
                          TextButton.icon(
                            onPressed: _showSuggestionsBottomSheet,
                            icon: const Icon(
                              Icons.lightbulb_outline_rounded,
                              size: 20,
                            ),
                            label: const Text('Suggestions'),
                            style: TextButton.styleFrom(
                              foregroundColor: StayoraLogo.stayoraBlue,
                              backgroundColor: Colors.transparent,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: StayoraColors.blue.withOpacity(0.25),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.today_rounded),
                              onPressed: () {
                                _scrollToDate(DateTime.now());
                              },
                              style: IconButton.styleFrom(
                                backgroundColor: StayoraColors.blue,
                                foregroundColor: Theme.of(
                                  context,
                                ).colorScheme.onPrimary,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Calendar Grid or empty rooms state
            Expanded(
              child: !_roomNamesLoaded
                  ? const Center(child: CircularProgressIndicator())
                  : _displayedRoomNames.isEmpty
                  ? Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(
                              context,
                            ).colorScheme.shadow.withOpacity(0.08),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.meeting_room_rounded,
                              size: 64,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No rooms yet',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 48,
                              ),
                              child: Text(
                                'Add rooms to see the calendar and assign bookings to rooms.',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 24),
                            FilledButton.icon(
                              onPressed: () async {
                                await Navigator.of(
                                  context,
                                  rootNavigator: false,
                                ).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const RoomManagementPage(),
                                  ),
                                );
                                _loadRooms();
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('Manage rooms'),
                              style: FilledButton.styleFrom(
                                backgroundColor: StayoraColors.blue,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 24),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.shadow.withOpacity(0.08),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  // Main scrollable grid: vertical scroll outer,
                                  // horizontal inner, Column of rows so the grid
                                  // has intrinsic height and is always visible.
                                  Positioned.fill(
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                        top: _headerHeight,
                                      ),
                                      child: SizedBox.expand(
                                        child: Listener(
                                          key: _gridKey,
                                          behavior: HitTestBehavior.translucent,
                                          onPointerDown: (event) {
                                            final cell = _getCellFromPosition(
                                              event.localPosition,
                                            );
                                            if (cell != null) {
                                              if (_getBooking(
                                                    cell['room']!,
                                                    cell['date']!,
                                                  ) ==
                                                  null) {
                                                _startSelection(
                                                  cell['room']!,
                                                  cell['date']!,
                                                );
                                              }
                                            }
                                          },
                                          onPointerMove: (event) {
                                            if (_isSelecting) {
                                              final cell = _getCellFromPosition(
                                                event.localPosition,
                                              );
                                              if (cell != null) {
                                                _updateSelection(
                                                  cell['room']!,
                                                  cell['date']!,
                                                );
                                              }
                                            }
                                          },
                                          onPointerUp: (_) {
                                            if (_isSelecting) {
                                              _endSelection();
                                            }
                                          },
                                          onPointerCancel: (_) {
                                            if (_isSelecting) {
                                              setState(() {
                                                _isSelecting = false;
                                                _selectionStartRoom = null;
                                                _selectionStartDate = null;
                                                _selectionEndRoom = null;
                                                _selectionEndDate = null;
                                              });
                                            }
                                          },
                                          child: SingleChildScrollView(
                                            controller:
                                                _verticalScrollController,
                                            scrollDirection: Axis.vertical,
                                            padding: EdgeInsets.zero,
                                            child: SingleChildScrollView(
                                              controller:
                                                  _horizontalScrollController,
                                              scrollDirection: Axis.horizontal,
                                              padding: EdgeInsets.zero,
                                              child: Builder(
                                                builder: (context) {
                                                  final dateList = _dates;
                                                  return Container(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .surfaceContainerLowest,
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: dateList.map((
                                                        date,
                                                      ) {
                                                        final isToday =
                                                            isSameDay(
                                                              date,
                                                              DateTime.now(),
                                                            );
                                                        return RepaintBoundary(
                                                          child: _buildDayRow(
                                                            date,
                                                            isToday,
                                                          ),
                                                        );
                                                      }).toList(),
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                  // Sticky room headers at the top
                                  Positioned(
                                    top: 0,
                                    left: 0,
                                    right: 0,
                                    height: _headerHeight,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.surface,
                                        border: Border(
                                          bottom: BorderSide(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .outline
                                                .withOpacity(0.3),
                                            width: 1,
                                          ),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .shadow
                                                .withOpacity(0.05),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        children: [
                                          // Empty corner cell (fixed) — same as day column
                                          Container(
                                            width: _dayLabelWidth,
                                            height: _headerHeight,
                                            decoration: BoxDecoration(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .surface,
                                              border: Border(
                                                right: BorderSide(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .outline
                                                      .withOpacity(0.3),
                                                ),
                                              ),
                                            ),
                                            child: Center(
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    Icons.hotel_rounded,
                                                    size: 14,
                                                    color:
                                                        StayoraLogo.stayoraBlue,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    'Rooms',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 12,
                                                      color: StayoraLogo
                                                          .stayoraBlue,
                                                      letterSpacing: 0.2,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          // Room headers (scrollable horizontally)
                                          Expanded(
                                            child: SingleChildScrollView(
                                              controller:
                                                  _roomHeadersScrollController,
                                              scrollDirection: Axis.horizontal,
                                              physics:
                                                  const NeverScrollableScrollPhysics(),
                                              child: Row(
                                                children: _displayedRoomNames.map((
                                                  room,
                                                ) {
                                                  final roomModel =
                                                      _roomModelsMap[room];
                                                  final hkStatus =
                                                      roomModel
                                                          ?.housekeepingStatus ??
                                                      'clean';
                                                  final hkColor =
                                                      StayoraColors.housekeepingColor(
                                                        hkStatus,
                                                      );
                                                  final firstTag =
                                                      roomModel != null &&
                                                          roomModel
                                                              .tags
                                                              .isNotEmpty
                                                      ? roomModel.tags.first
                                                      : null;
                                                  final headerBg =
                                                      Theme.of(context)
                                                          .colorScheme
                                                          .surface;
                                                  return Container(
                                                    width: _roomColumnWidth,
                                                    height: 50,
                                                    decoration: BoxDecoration(
                                                      color: headerBg,
                                                      border: Border(
                                                        right: BorderSide(
                                                          color:
                                                              Theme.of(context)
                                                                  .colorScheme
                                                                  .outline
                                                                  .withOpacity(
                                                                    0.2,
                                                                  ),
                                                          width: 1,
                                                        ),
                                                      ),
                                                    ),
                                                    child: Center(
                                                      child: Column(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Text(
                                                            'Room $room',
                                                            style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize: 12,
                                                              color:
                                                                  Theme.of(
                                                                        context,
                                                                      )
                                                                      .colorScheme
                                                                      .onSurface,
                                                              letterSpacing:
                                                                  0.2,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            height: 2,
                                                          ),
                                                          Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              Container(
                                                                width: 6,
                                                                height: 6,
                                                                decoration: BoxDecoration(
                                                                  shape: BoxShape
                                                                      .circle,
                                                                  color:
                                                                      hkColor,
                                                                ),
                                                              ),
                                                              if (firstTag !=
                                                                  null) ...[
                                                                const SizedBox(
                                                                  width: 3,
                                                                ),
                                                                Text(
                                                                  '• $firstTag',
                                                                  style: TextStyle(
                                                                    fontSize: 9,
                                                                    color: Theme.of(
                                                                      context,
                                                                    ).colorScheme.onSurfaceVariant,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w500,
                                                                  ),
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                  maxLines: 1,
                                                                ),
                                                              ],
                                                            ],
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                                }).toList(),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  // Sticky day labels on the left
                                  Positioned(
                                    top: _headerHeight,
                                    left: 0,
                                    bottom: 0,
                                    width: _dayLabelWidth,
                                    child: Container(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.surface,
                                      child: ScrollConfiguration(
                                        behavior: ScrollConfiguration.of(
                                          context,
                                        ).copyWith(scrollbars: false),
                                        child: SingleChildScrollView(
                                          controller:
                                              _stickyDayLabelsScrollController,
                                          scrollDirection: Axis.vertical,
                                          physics:
                                              const NeverScrollableScrollPhysics(),
                                          child: Column(
                                            children: _dates.map((date) {
                                              final isToday = isSameDay(
                                                date,
                                                DateTime.now(),
                                              );
                                              return _buildStickyDayLabel(
                                                date,
                                                isToday,
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                  // Skeleton drag-drop overlay — lives in the
                                  // outer Stack so its Positioned coordinates
                                  // are already viewport-relative.
                                  // Uses ListenableBuilder so only the overlay
                                  // redraws on drag-move, not the whole page.
                                  ListenableBuilder(
                                    listenable: Listenable.merge([
                                      _skeletonNotifier,
                                      _verticalScrollController,
                                      _horizontalScrollController,
                                    ]),
                                    builder: (context, _) {
                                      final skeleton = _skeletonNotifier.value;
                                      if (skeleton == null) {
                                        return const SizedBox.shrink();
                                      }
                                      return _buildDragSkeletonOverlay(
                                        skeleton,
                                      );
                                    },
                                  ),

                                  // Red line overlay for today's date
                                  if (_dates.any(
                                    (date) => isSameDay(date, DateTime.now()),
                                  ))
                                    AnimatedBuilder(
                                      animation: _verticalScrollController,
                                      builder: (context, _) {
                                        final todayIndex = _dates.indexWhere(
                                          (date) =>
                                              isSameDay(date, DateTime.now()),
                                        );
                                        if (todayIndex == -1) {
                                          return const SizedBox.shrink();
                                        }

                                        final scrollOffset =
                                            _verticalScrollController.hasClients
                                            ? _verticalScrollController.offset
                                            : 0.0;
                                        // Position line on the top border of today's row (above the row, not inside)
                                        final lineY =
                                            _headerHeight +
                                            (todayIndex * _dayRowHeight) -
                                            scrollOffset;

                                        return Positioned(
                                          top: lineY,
                                          left:
                                              _dayLabelWidth, // Start after date column
                                          right: 0,
                                          height: 2,
                                          child: const ColoredBox(
                                            color: Colors.red,
                                          ),
                                        );
                                      },
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        CalendarBottomSection(
                          waitingListBookings: _waitingListBookings,
                          onDropOnSection: _moveBookingToWaitingList,
                          onClearSkeleton: () =>
                              _skeletonNotifier.value = null,
                          onShowDetails: _showBookingDetailsById,
                          statusColor: _statusColor,
                          advanceIndicatorColor: _advanceIndicatorColor,
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: StayoraColors.blue.withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: FloatingActionButton(
          heroTag: 'calendar_fab',
          onPressed: () {
            Navigator.of(context, rootNavigator: false)
                .push(
                  MaterialPageRoute(
                    builder: (context) => const AddBookingPage(),
                  ),
                )
                .then((bookingCreated) {
                  if (bookingCreated == true) {
                    _subscribeToBookings();
                  }
                });
          },
          backgroundColor: StayoraColors.blue,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            Icons.add_rounded,
            color: Theme.of(context).colorScheme.onPrimary,
            size: 28,
          ),
        ),
      ),
    );
  }

  void _showBookingDetailsById(BuildContext context, String bookingId) {
    final hotelId = HotelProvider.of(context).hotelId;
    final userId = AuthScopeData.of(context).uid;
    if (hotelId == null || userId == null) return;
    final nestedNavigator = Navigator.of(context, rootNavigator: false);
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.shadow.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _firebaseService.bookingDocStream(
              userId,
              hotelId,
              bookingId,
            ),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final doc = snapshot.data!;
              if (!doc.exists) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Booking removed',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Close'),
                        ),
                      ),
                    ],
                  ),
                );
              }
              final fullBooking = BookingModel.fromFirestore(
                doc.data()!,
                doc.id,
              );
              final currencyFormatterById = CurrencyFormatter.fromHotel(
                HotelProvider.of(context).currentHotel,
              );
              return BookingDetailsForm(
                key: ValueKey(fullBooking.id),
                fullBooking: fullBooking,
                room: '—',
                date: fullBooking.checkIn,
                bookingId: bookingId,
                statusOptions: statusOptions,
                getStatusColor: _statusColor,
                paymentMethods: paymentMethods,
                currencyFormatter: currencyFormatterById,
                buildDetailRow: _buildDetailRow,
                buildStatusRowWithStatus: _buildStatusRowWithStatus,
                roomIdToName: _roomIdToNameMap,
                onSave: (updated) async {
                  await _updateBooking(userId, hotelId, updated);
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                        content: Text('Booking updated'),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: StayoraColors.success,
                      ),
                    );
                  }
                },
                onDelete: () async {
                  final navigator = Navigator.of(dialogContext);
                  final messenger = ScaffoldMessenger.of(dialogContext);
                  final confirm = await _showDeleteConfirmation(dialogContext);
                  if (confirm != true) return;
                  if (!mounted) return;
                  try {
                    _showLoadingDialog(dialogContext);
                    await _deleteBooking(userId, hotelId, bookingId);
                    if (!mounted) return;
                    navigator.pop();
                    navigator.pop();
                  } catch (e) {
                    if (!mounted) return;
                    navigator.pop();
                    navigator.pop();
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('Failed to delete: $e'),
                        backgroundColor: Colors.red,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                onEditFull: () {
                  Navigator.pop(dialogContext);
                  nestedNavigator
                      .push(
                        MaterialPageRoute(
                          builder: (context) {
                            final resolved = fullBooking.resolvedSelectedRooms(
                              _roomIdToNameMap,
                            );
                            return AddBookingPage(
                              existingBooking: fullBooking,
                              preselectedRoom: resolved.isNotEmpty
                                  ? resolved.first
                                  : '—',
                              preselectedStartDate: fullBooking.checkIn,
                              preselectedEndDate: fullBooking.checkOut,
                              preselectedNumberOfRooms:
                                  fullBooking.numberOfRooms,
                            );
                          },
                        ),
                      )
                      .then((bookingCreated) {
                        if (bookingCreated == true) {
                          _subscribeToBookings();
                          _subscribeToWaitingList();
                        }
                      });
                },
                onClose: () => Navigator.pop(dialogContext),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Skeleton overlay showing where the dropped booking will land.
  /// Positioned relative to the viewport (accounting for scroll offsets) so it
  /// can live in the outer Stack rather than inside the scroll area.
  Widget _buildDragSkeletonOverlay(_SkeletonState skeleton) {
    final booking =
        _getWaitingListBookingById(skeleton.bookingId) ??
        _bookingModelsById[skeleton.bookingId];
    if (booking == null) return const SizedBox.shrink();

    final roomIndex = _displayedRoomNames.indexOf(skeleton.room);
    final dateIndex = _dates.indexWhere(
      (d) =>
          d.year == skeleton.date.year &&
          d.month == skeleton.date.month &&
          d.day == skeleton.date.day,
    );
    if (roomIndex < 0 || dateIndex < 0) return const SizedBox.shrink();

    final nRoomsEffective = booking.numberOfRooms.clamp(
      1,
      _displayedRoomNames.length - roomIndex,
    );
    final nNightsEffective = booking.numberOfNights.clamp(
      1,
      _dates.length - dateIndex,
    );
    final isValid = nRoomsEffective >= 1 && nNightsEffective >= 1;

    // Viewport-relative coordinates (scroll offsets subtracted so the overlay
    // follows the cell even while the grid scrolls under it).
    final scrollX = _horizontalScrollController.hasClients
        ? _horizontalScrollController.offset
        : 0.0;
    final scrollY = _verticalScrollController.hasClients
        ? _verticalScrollController.offset
        : 0.0;

    final left = _dayLabelWidth + roomIndex * _roomColumnWidth - scrollX;
    final top = _headerHeight + dateIndex * _dayRowHeight - scrollY;
    final width = nRoomsEffective * _roomColumnWidth;
    final height = nNightsEffective * _dayRowHeight;

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: (isValid ? StayoraColors.purple : StayoraColors.error)
                .withOpacity(0.35),
            border: Border.all(
              color: isValid ? StayoraColors.purple : StayoraColors.error,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              '${booking.userName}\n$nRoomsEffective room(s) · $nNightsEffective night(s)',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDayRow(DateTime date, bool isToday) {
    final scheme = Theme.of(context).colorScheme;
    final isWeekend =
        date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
    Color rowColor = scheme.surface;
    if (isToday) {
      rowColor = StayoraColors.blue.withOpacity(0.08);
    } else if (isWeekend) {
      rowColor = scheme.surfaceContainerLowest.withOpacity(0.5);
    }
    return Container(
      height: _dayRowHeight,
      decoration: BoxDecoration(color: rowColor),
      child: Row(
        children: [
          // Spacer for sticky day label column
          SizedBox(width: _dayLabelWidth),
          // Room cells — read pre-computed data from cache.
          Row(
            children: _displayedRoomNames.map((room) {
              final dateKey = DateTime(date.year, date.month, date.day);
              final cellData =
                  _cellDataCache[dateKey]?[room] ?? CalendarCellData.empty;
              return _buildRoomCell(room, date, cellData);
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildStickyDayLabel(DateTime date, bool isToday) {
    return SizedBox(
      height: _dayRowHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Right divider
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 1,
            child: Container(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
            ),
          ),

          // Background for the whole date row (filled, not rounded)
          Positioned.fill(
            child: Container(
              color: isToday
                  ? StayoraColors.blue.withOpacity(0.08)
                  : Theme.of(context).colorScheme.surface,
            ),
          ),

          // Date text
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: FittedBox(
                alignment: Alignment.centerLeft,
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('EEE').format(date),
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.0,
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('MMM d').format(date),
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.0,
                        fontWeight: isToday ? FontWeight.bold : FontWeight.w600,
                        color: isToday
                            ? StayoraLogo.stayoraBlue
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds a single room × date cell using pre-computed [cellData] from the
  /// cache. Hover and skeleton state are read via [ValueListenableBuilder] so
  /// only the affected cell — not the whole page — rebuilds on mouse events.
  Widget _buildRoomCell(String room, DateTime date, CalendarCellData cellData) {
    final booking = cellData.booking;
    final isSelected = _isCellInSelection(room, date);

    final scheme = Theme.of(context).colorScheme;
    final outlineColor = scheme.outline.withOpacity(0.3);
    final cellRightBorderColor = cellData.isConnectedRight
        ? Colors.transparent
        : outlineColor;
    final cellTopBorderColor = cellData.isConnectedTop
        ? Colors.transparent
        : outlineColor;
    final cellBottomBorderColor = cellData.isConnectedBottom
        ? Colors.transparent
        : outlineColor;

    return DragTarget<WaitingListDragPayload>(
      onWillAcceptWithDetails: (_) => true,
      // Update notifier (no setState) — only the skeleton overlay widget rebuilds.
      onMove: (details) => _skeletonNotifier.value = _SkeletonState(
        bookingId: details.data.bookingId,
        room: room,
        date: date,
      ),
      onLeave: (_) => _skeletonNotifier.value = null,
      onAcceptWithDetails: (details) {
        _onDropWaitingListBooking(details.data.bookingId, room, date);
        _skeletonNotifier.value = null;
      },
      builder: (context, candidateData, _) {
        final isHighlighted = candidateData.isNotEmpty;
        return MouseRegion(
          // Update notifier (no setState) — only the ValueListenableBuilder
          // inside each cell rebuilds when hover changes.
          onEnter: (_) =>
              _hoverNotifier.value = _HoverState(room: room, date: date),
          onExit: (_) => _hoverNotifier.value = null,
          child: GestureDetector(
            onTap: () {
              if (booking != null) {
                _showBookingDetails(context, room, date, booking);
              } else if (!_isSelecting) {
                _showBookingDialog([room], [date], false);
              }
            },
            child: ValueListenableBuilder<_HoverState?>(
              valueListenable: _hoverNotifier,
              builder: (context, hoverState, _) {
                final isHovered =
                    hoverState != null &&
                    hoverState.room == room &&
                    hoverState.date.year == date.year &&
                    hoverState.date.month == date.month &&
                    hoverState.date.day == date.day;
                return Container(
                  width: _roomColumnWidth,
                  height: _dayRowHeight,
                  decoration: BoxDecoration(
                    color: isHighlighted
                        ? StayoraColors.purple.withOpacity(0.25)
                        : isSelected
                        ? StayoraColors.blue.withOpacity(0.2)
                        : scheme.surface,
                    border: Border(
                      top: isSelected
                          ? BorderSide(
                              color: StayoraColors.blue.withOpacity(0.5),
                              width: 2,
                            )
                          : BorderSide(color: cellTopBorderColor, width: 1),
                      bottom: isSelected
                          ? BorderSide(
                              color: StayoraColors.blue.withOpacity(0.5),
                              width: 2,
                            )
                          : BorderSide(color: cellBottomBorderColor, width: 1),
                      left: isSelected
                          ? BorderSide(
                              color: StayoraColors.blue.withOpacity(0.5),
                              width: 2,
                            )
                          : BorderSide.none,
                      right: BorderSide(color: cellRightBorderColor, width: 1),
                    ),
                  ),
                  child: Stack(
                    children: [
                      if (booking != null)
                        LongPressDraggable<WaitingListDragPayload>(
                          data: WaitingListDragPayload(
                            bookingId: booking.bookingId,
                          ),
                          onDragStarted: () {},
                          onDragEnd: (_) => _skeletonNotifier.value = null,
                          feedback: _buildBookingCardContent(
                            context,
                            booking,
                            stripeColor: _statusColor(booking.status),
                            compact: true,
                            forFeedback: true,
                          ),
                          childWhenDragging: _buildGridBookingCard(
                            context,
                            room,
                            date,
                            booking,
                            isHovered: false,
                            isDragging: true,
                            isConnectedLeft: cellData.isConnectedLeft,
                            isConnectedRight: cellData.isConnectedRight,
                            isConnectedTop: cellData.isConnectedTop,
                            isConnectedBottom: cellData.isConnectedBottom,
                            showInfo: cellData.isInfoCell,
                            centerInfoInBubble: cellData.centerInfoInBubble,
                          ),
                          child: _buildGridBookingCard(
                            context,
                            room,
                            date,
                            booking,
                            isHovered: isHovered,
                            isDragging: false,
                            isConnectedLeft: cellData.isConnectedLeft,
                            isConnectedRight: cellData.isConnectedRight,
                            isConnectedTop: cellData.isConnectedTop,
                            isConnectedBottom: cellData.isConnectedBottom,
                            showInfo: cellData.isInfoCell,
                            centerInfoInBubble: cellData.centerInfoInBubble,
                          ),
                        ),
                      if (isSelected && booking == null)
                        Container(
                          width: double.infinity,
                          height: double.infinity,
                          decoration: BoxDecoration(
                            color: StayoraColors.blue.withOpacity(0.15),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// One grid cell's booking card: left stripe, surface, shadow, status, hover.
  /// Connected sides share no gap/border so the whole booking is one bubble.
  /// [showInfo]: show guest name, nights, phone, status in one cell (first night; 1 room = left, 2+ rooms = middle).
  /// [centerInfoInBubble]: when true (2+ rooms), center the info horizontally in the cell for top-middle of bubble.
  Widget _buildGridBookingCard(
    BuildContext context,
    String room,
    DateTime date,
    CalendarBooking booking, {
    required bool isHovered,
    required bool isDragging,
    bool isConnectedLeft = false,
    bool isConnectedRight = false,
    bool isConnectedTop = false,
    bool isConnectedBottom = false,
    bool showInfo = true,
    bool centerInfoInBubble = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final cardBg = isDark
        ? scheme.surfaceContainerHighest
        : scheme.surfaceContainerLowest;
    final cardBgResolved = isDragging ? cardBg.withOpacity(0.6) : cardBg;
    // Status color from legend: border goes around the whole bubble
    final statusColor = _statusColor(booking.status);
    const radius = 10.0;
    // One bubble: round only the four outer corners of the whole block
    final topLeft = (isConnectedTop || isConnectedLeft) ? 0.0 : radius;
    final topRight = (isConnectedTop || isConnectedRight) ? 0.0 : radius;
    final bottomLeft = (isConnectedBottom || isConnectedLeft) ? 0.0 : radius;
    final bottomRight = (isConnectedBottom || isConnectedRight) ? 0.0 : radius;

    return Container(
      width: double.infinity,
      height: double.infinity,
      margin: EdgeInsets.only(
        top: isConnectedTop ? 0 : 2,
        bottom: isConnectedBottom ? 0 : 2,
        left: isConnectedLeft ? 0 : 2,
        right: isConnectedRight ? 0 : 2,
      ),
      decoration: BoxDecoration(
        color: cardBgResolved,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(topLeft),
          topRight: Radius.circular(topRight),
          bottomLeft: Radius.circular(bottomLeft),
          bottomRight: Radius.circular(bottomRight),
        ),
        border: Border(
          top: isConnectedTop
              ? BorderSide.none
              : BorderSide(color: statusColor, width: 2),
          bottom: isConnectedBottom
              ? BorderSide.none
              : BorderSide(color: statusColor, width: 2),
          left: isConnectedLeft
              ? BorderSide.none
              : BorderSide(color: statusColor, width: 2),
          right: isConnectedRight
              ? BorderSide.none
              : BorderSide(color: statusColor, width: 2),
        ),
        boxShadow: [
          if (showInfo && !isDragging)
            BoxShadow(
              color: scheme.shadow.withOpacity(isDark ? 0.2 : 0.08),
              blurRadius: isHovered ? 8 : 4,
              offset: Offset(0, isHovered ? 3 : 2),
            ),
          if (isHovered && !isDragging)
            BoxShadow(
              color: statusColor.withOpacity(0.35),
              blurRadius: 8,
              spreadRadius: 0,
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(topLeft),
          topRight: Radius.circular(topRight),
          bottomLeft: Radius.circular(bottomLeft),
          bottomRight: Radius.circular(bottomRight),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Content — only in the single "first" cell of the booking (color line is the border around bubble)
            Expanded(
              child: showInfo
                  ? Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                            left: 6,
                            right: 8,
                            top: 2,
                            bottom: 2,
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: centerInfoInBubble
                                ? Alignment.center
                                : Alignment.centerLeft,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: centerInfoInBubble
                                  ? CrossAxisAlignment.center
                                  : CrossAxisAlignment.start,
                              children: [
                                // Line 1 — Primary: guest name
                                Text(
                                  booking.guestName,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: scheme.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                // Line 2 — Secondary: nights • status
                                Text(
                                  '${booking.totalNights} night${booking.totalNights != 1 ? 's' : ''} • ${booking.status}',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                // Line 3 — Phone (easy to see at a glance)
                                if (booking.phone.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 1),
                                    child: Text(
                                      booking.phone,
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: scheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w400,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        // Status dot — top-right
                        Positioned(
                          top: 4,
                          right: 6,
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _statusColor(booking.status),
                              border: Border.all(color: cardBg, width: 1),
                            ),
                          ),
                        ),
                        // Advance payment dot — next to status when relevant
                        if (booking.advancePaymentStatus != 'not_required')
                          Positioned(
                            top: 4,
                            right: 14,
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _advanceIndicatorColor(
                                  booking.advancePaymentStatus,
                                ),
                                border: Border.all(color: cardBg, width: 1),
                              ),
                            ),
                          ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  /// Compact card for drag feedback (stripe + name + nights).
  Widget _buildBookingCardContent(
    BuildContext context,
    CalendarBooking booking, {
    required Color stripeColor,
    bool compact = true,
    bool forFeedback = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outline.withOpacity(0.2), width: 1),
        ),
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: stripeColor,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(4),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    booking.guestName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: scheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (booking.totalNights > 1) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${booking.totalNights} nights',
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBookingDetails(
    BuildContext context,
    String room,
    DateTime date,
    CalendarBooking booking,
  ) {
    final hotelId = HotelProvider.of(context).hotelId;
    final userId = AuthScopeData.of(context).uid;
    if (hotelId == null || userId == null) return;
    final bookingId = booking.bookingId;
    final nestedNavigator = Navigator.of(context, rootNavigator: false);
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.shadow.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _firebaseService.bookingDocStream(
              userId,
              hotelId,
              bookingId,
            ),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final doc = snapshot.data!;
              if (!doc.exists) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Booking removed',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Close'),
                        ),
                      ),
                    ],
                  ),
                );
              }
              final fullBooking = BookingModel.fromFirestore(
                doc.data()!,
                doc.id,
              );
              final currencyFormatter = CurrencyFormatter.fromHotel(
                HotelProvider.of(context).currentHotel,
              );
              return BookingDetailsForm(
                key: ValueKey(fullBooking.id),
                fullBooking: fullBooking,
                room: room,
                date: date,
                bookingId: bookingId,
                statusOptions: statusOptions,
                getStatusColor: _statusColor,
                paymentMethods: paymentMethods,
                currencyFormatter: currencyFormatter,
                buildDetailRow: _buildDetailRow,
                buildStatusRowWithStatus: _buildStatusRowWithStatus,
                roomIdToName: _roomIdToNameMap,
                onSave: (updated) async {
                  await _updateBooking(userId, hotelId, updated);
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                        content: Text('Booking updated'),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: StayoraColors.success,
                      ),
                    );
                  }
                },
                onDelete: () async {
                  final navigator = Navigator.of(dialogContext);
                  final messenger = ScaffoldMessenger.of(dialogContext);
                  final confirm = await _showDeleteConfirmation(dialogContext);
                  if (confirm != true) return;
                  if (!mounted) return;
                  try {
                    _showLoadingDialog(dialogContext);
                    await _deleteBooking(userId, hotelId, bookingId);
                    if (!mounted) return;
                    navigator.pop();
                    navigator.pop();
                  } catch (e) {
                    if (!mounted) return;
                    navigator.pop();
                    navigator.pop();
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('Failed to delete: $e'),
                        backgroundColor: Colors.red,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                onEditFull: () {
                  Navigator.pop(dialogContext);
                  nestedNavigator
                      .push(
                        MaterialPageRoute(
                          builder: (context) => AddBookingPage(
                            existingBooking: fullBooking,
                            preselectedRoom: room,
                            preselectedStartDate: fullBooking.checkIn,
                            preselectedEndDate: fullBooking.checkOut,
                            preselectedNumberOfRooms: fullBooking.numberOfRooms,
                          ),
                        ),
                      )
                      .then((bookingCreated) {
                        if (bookingCreated == true) {
                          _subscribeToBookings();
                        }
                      });
                },
                onClose: () => Navigator.pop(dialogContext),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: StayoraColors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: StayoraColors.blue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRowWithStatus(String status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.info_outline_rounded, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Status',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withOpacity(0.4)),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showDeleteConfirmation(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.shadow.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_rounded,
                  color: Colors.red,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Delete Booking?',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 17,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'This will permanently delete the booking. This action cannot be undone.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                        child: const Text('Delete'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(
                            ctx,
                          ).colorScheme.inverseSurface,
                          foregroundColor: Theme.of(
                            ctx,
                          ).colorScheme.onInverseSurface,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showLoadingDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.shadow.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(StayoraColors.blue),
              ),
              SizedBox(height: 16),
              Text(
                'Please wait...',
                style: TextStyle(fontSize: 15, color: Colors.black87),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBookingDialog(
    List<String> rooms,
    List<DateTime> dates,
    bool roomsNextToEachOther, {
    List<int>? preselectedRoomIndexes,
  }) {
    final startDate = dates.first;
    final endDate = dates.last.add(
      const Duration(days: 1),
    ); // Check-out is the day after last night

    // Navigate to Add Booking page with preselected values (nested navigator so nav bar stays)
    Navigator.of(context, rootNavigator: false)
        .push(
          MaterialPageRoute(
            builder: (context) => AddBookingPage(
              preselectedRoom: rooms.length == 1 ? rooms.first : null,
              preselectedStartDate: startDate,
              preselectedEndDate: endDate,
              preselectedNumberOfRooms: rooms.length,
              preselectedRoomsNextToEachOther: roomsNextToEachOther,
              preselectedRoomsIndex: preselectedRoomIndexes,
            ),
          ),
        )
        .then((bookingCreated) {
          if (bookingCreated == true) {
            // Refresh the calendar if booking was created
            setState(() {});
          }
        });
  }

  bool isSameDay(DateTime a, DateTime b) {
    // Normalize both dates to midnight for accurate comparison
    final dateA = DateTime(a.year, a.month, a.day);
    final dateB = DateTime(b.year, b.month, b.day);
    return dateA.isAtSameMomentAs(dateB);
  }
}

/// Cursor-style before | after mini calendar for a chain of moves.
class _ChainPreviewCalendar extends StatelessWidget {
  const _ChainPreviewCalendar({
    required this.actions,
    required this.bookingModelsById,
    required this.roomIdToNameMap,
  });

  final List<MoveBookingAction> actions;
  final Map<String, BookingModel> bookingModelsById;
  final Map<String, String> roomIdToNameMap;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    const double cellWidth = 22.0;
    const double rowHeight = 32.0;
    const double roomLabelWidth = 64.0;

    DateTime rangeStart = _day(actions.first.newCheckIn);
    DateTime rangeEnd = _day(actions.first.newCheckOut);
    for (final a in actions) {
      final b = bookingModelsById[a.bookingId];
      if (b == null) continue;
      final s = _day(b.checkIn);
      final e = _day(b.checkOut);
      if (s.isBefore(rangeStart)) rangeStart = s;
      if (e.isAfter(rangeEnd)) rangeEnd = e;
    }
    final totalDays = rangeEnd.difference(rangeStart).inDays.clamp(2, 14);

    final affectedRoomIds = <String>{};
    for (final a in actions) {
      affectedRoomIds.add(a.fromRoomId);
      affectedRoomIds.add(a.toRoomId);
    }
    final roomOrder = affectedRoomIds.toList()..sort();

    // Before: fromRoomId has the booking
    final before = <String, List<_Slot>>{};
    for (final a in actions) {
      final b = bookingModelsById[a.bookingId];
      if (b == null) continue;
      before
          .putIfAbsent(a.fromRoomId, () => [])
          .add(
            _Slot(
              guestName: b.userName,
              checkIn: b.checkIn,
              checkOut: b.checkOut,
            ),
          );
    }
    for (final rid in roomOrder) {
      before.putIfAbsent(rid, () => []);
    }

    // After: toRoomId has the booking
    final after = <String, List<_Slot>>{};
    for (final a in actions) {
      final b = bookingModelsById[a.bookingId];
      if (b == null) continue;
      after
          .putIfAbsent(a.toRoomId, () => [])
          .add(
            _Slot(
              guestName: b.userName,
              checkIn: a.newCheckIn,
              checkOut: a.newCheckOut,
            ),
          );
    }
    for (final rid in roomOrder) {
      after.putIfAbsent(rid, () => []);
    }

    final colorScheme = Theme.of(context).colorScheme;
    final barColor = StayoraColors.blue.withOpacity(0.85);
    final emptyColor = colorScheme.surfaceContainerHighest.withOpacity(0.4);
    final timelineWidth = totalDays * cellWidth;

    Widget buildPanel(
      String title,
      Map<String, List<_Slot>> state,
      bool isAfter,
    ) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isAfter
              ? colorScheme.primaryContainer.withOpacity(0.08)
              : colorScheme.surfaceContainerHighest.withOpacity(0.25),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outline.withOpacity(0.2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: roomLabelWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 18,
                        child: Text(
                          '',
                          style: TextStyle(
                            fontSize: 9,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      ...roomOrder.map((rid) {
                        final name = roomIdToNameMap[rid] ?? rid;
                        return SizedBox(
                          height: rowHeight,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              name,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: colorScheme.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    width: timelineWidth,
                    child: Column(
                      children: [
                        SizedBox(
                          height: 18,
                          child: Row(
                            children: List.generate(totalDays, (i) {
                              final d = rangeStart.add(Duration(days: i));
                              return SizedBox(
                                width: cellWidth,
                                child: Center(
                                  child: Text(
                                    '${d.day}',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                        ...roomOrder.map((rid) {
                          final slots = state[rid] ?? [];
                          return SizedBox(
                            height: rowHeight,
                            child: _roomTimelineRow(
                              context,
                              cellWidth: cellWidth,
                              totalDays: totalDays,
                              rangeStart: rangeStart,
                              slots: slots,
                              barColor: barColor,
                              emptyColor: emptyColor,
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: buildPanel('Before', before, false)),
        Container(
          width: 2,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          color: colorScheme.outline.withOpacity(0.35),
        ),
        Expanded(child: buildPanel('After', after, true)),
      ],
    );
  }

  Widget _roomTimelineRow(
    BuildContext context, {
    required double cellWidth,
    required int totalDays,
    required DateTime rangeStart,
    required List<_Slot> slots,
    required Color barColor,
    required Color emptyColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Row(
          children: List.generate(
            totalDays,
            (i) => Container(
              width: cellWidth - 0.5,
              decoration: BoxDecoration(
                color: emptyColor,
                border: Border(
                  right: BorderSide(
                    color: colorScheme.outline.withOpacity(0.15),
                  ),
                ),
              ),
            ),
          ),
        ),
        for (final slot in slots) ...[
          () {
            final s = _day(slot.checkIn);
            final e = _day(slot.checkOut);
            final startCol = s
                .difference(rangeStart)
                .inDays
                .clamp(0, totalDays - 1);
            final endCol = e.difference(rangeStart).inDays.clamp(1, totalDays);
            if (endCol <= startCol) return const SizedBox.shrink();
            return Positioned(
              left: startCol * cellWidth + 1.5,
              top: 3,
              bottom: 3,
              width: (endCol - startCol) * cellWidth - 3,
              child: Container(
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: StayoraColors.blue, width: 1),
                ),
                child: Center(
                  child: Text(
                    slot.guestName,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            );
          }(),
        ],
      ],
    );
  }
}

/// Hover (room, date) for per-cell hover highlight without full page rebuild.
class _HoverState {
  const _HoverState({required this.room, required this.date});
  final String room;
  final DateTime date;
}

/// Drag-over state for waiting-list → grid drop preview.
class _SkeletonState {
  const _SkeletonState({
    required this.bookingId,
    required this.room,
    required this.date,
  });
  final String bookingId;
  final String room;
  final DateTime date;
}

class _Slot {
  const _Slot({
    required this.guestName,
    required this.checkIn,
    required this.checkOut,
  });
  final String guestName;
  final DateTime checkIn;
  final DateTime checkOut;
}

/// Mini timeline showing a booking moving from one room row to another (before → after).
class _MovePreviewTimeline extends StatelessWidget {
  const _MovePreviewTimeline({
    required this.fromRoomName,
    required this.toRoomName,
    required this.beforeCheckIn,
    required this.beforeCheckOut,
    required this.afterCheckIn,
    required this.afterCheckOut,
  });

  final String fromRoomName;
  final String toRoomName;
  final DateTime beforeCheckIn;
  final DateTime beforeCheckOut;
  final DateTime afterCheckIn;
  final DateTime afterCheckOut;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    const double cellWidth = 28.0;
    const double rowHeight = 36.0;

    final bStart = _day(beforeCheckIn);
    final bEnd = _day(beforeCheckOut);
    final aStart = _day(afterCheckIn);
    final aEnd = _day(afterCheckOut);
    final rangeStart = bStart.isBefore(aStart) ? bStart : aStart;
    final rangeEnd = bEnd.isAfter(aEnd) ? bEnd : aEnd;
    final totalDays = rangeEnd.difference(rangeStart).inDays.clamp(2, 14);

    final beforeStartCol = bStart
        .difference(rangeStart)
        .inDays
        .clamp(0, totalDays - 1);
    final beforeEndCol = bEnd.difference(rangeStart).inDays.clamp(1, totalDays);
    final afterStartCol = aStart
        .difference(rangeStart)
        .inDays
        .clamp(0, totalDays - 1);
    final afterEndCol = aEnd.difference(rangeStart).inDays.clamp(1, totalDays);

    final colorScheme = Theme.of(context).colorScheme;
    final barColor = StayoraColors.blue.withOpacity(0.85);
    final emptyColor = colorScheme.surfaceContainerHighest.withOpacity(0.4);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outline.withOpacity(0.25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How the booking moves',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          // Day labels row
          SizedBox(
            height: 22,
            child: Row(
              children: [
                SizedBox(
                  width: 72,
                  child: Text(
                    '',
                    style: TextStyle(
                      fontSize: 10,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Row(
                  children: List.generate(totalDays, (i) {
                    final d = rangeStart.add(Duration(days: i));
                    return SizedBox(
                      width: cellWidth,
                      child: Center(
                        child: Text(
                          '${d.day}',
                          style: TextStyle(
                            fontSize: 10,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Before row: booking in "from" room
          _timelineRow(
            context,
            label: 'From',
            roomName: fromRoomName,
            cellWidth: cellWidth,
            rowHeight: rowHeight,
            totalDays: totalDays,
            barStartCol: beforeStartCol,
            barEndCol: beforeEndCol,
            barColor: barColor,
            emptyColor: emptyColor,
          ),
          const SizedBox(height: 6),
          // After row: booking in "to" room
          _timelineRow(
            context,
            label: 'To',
            roomName: toRoomName,
            cellWidth: cellWidth,
            rowHeight: rowHeight,
            totalDays: totalDays,
            barStartCol: afterStartCol,
            barEndCol: afterEndCol,
            barColor: barColor,
            emptyColor: emptyColor,
          ),
        ],
      ),
    );
  }

  Widget _timelineRow(
    BuildContext context, {
    required String label,
    required String roomName,
    required double cellWidth,
    required double rowHeight,
    required int totalDays,
    required int barStartCol,
    required int barEndCol,
    required Color barColor,
    required Color emptyColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final timelineWidth = totalDays * cellWidth;

    return SizedBox(
      height: rowHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 72,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    roomName,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: timelineWidth,
              height: rowHeight,
              child: Stack(
                children: [
                  // Grid cells
                  Row(
                    children: List.generate(
                      totalDays,
                      (i) => Container(
                        width: cellWidth - 0.5,
                        decoration: BoxDecoration(
                          color: emptyColor,
                          border: Border(
                            right: BorderSide(
                              color: colorScheme.outline.withOpacity(0.2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Booking bar
                  Positioned(
                    left: barStartCol * cellWidth + 2,
                    top: 4,
                    bottom: 4,
                    width: (barEndCol - barStartCol) * cellWidth - 4,
                    child: Container(
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: StayoraColors.blue, width: 1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/booking_model.dart';
import '../models/room_model.dart';
import '../services/firebase_service.dart';
import '../services/hotel_provider.dart';
import '../services/auth_provider.dart';
import '../utils/stayora_colors.dart';
import '../utils/currency_formatter.dart';
import '../utils/money_input_formatter.dart';
import '../widgets/loading_empty_states.dart';
import '../widgets/stayora_logo.dart';
import 'add_booking_page.dart';
import 'room_management_page.dart';

/// Payload when dragging a booking from the waiting list onto the calendar.
class _WaitingListDragPayload {
  const _WaitingListDragPayload({required this.bookingId});
  final String bookingId;
}

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
  final Map<DateTime, Map<String, Booking>> _bookings = {};

  /// Full booking models by document ID. One entry per Firestore document.
  /// Used to resolve the full booking when editing any cell of a multi-room stay.
  final Map<String, BookingModel> _bookingModelsById = {};

  /// Last date used in date search; persisted so the dialog reopens with it.
  DateTime? _lastSearchedDate;

  // Selection state for drag-and-drop booking
  int _numberOfSelectedRooms = 0;
  bool _roomsNextToEachOther = false;
  String? _selectionStartRoom;
  DateTime? _selectionStartDate;
  String? _selectionEndRoom;
  DateTime? _selectionEndDate;

  /// When dragging a waiting-list booking over the grid, show a skeleton at this cell.
  String? _skeletonWaitingListBookingId;
  String? _skeletonRoom;
  DateTime? _skeletonDate;

  static const List<String> statusOptions = [
    'Confirmed',
    'Pending',
    'Cancelled',
    'Paid',
    'Unpaid',
    'Waiting list',
  ];

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

  int amountOfMoneyPaid = 0;
  List<String> paymentMethods = ['Cash', 'Card', 'Bank Transfer', 'Other'];
  bool _isSelecting = false;
  List<int> _preselectedRoomsIndex = [];
  final GlobalKey _gridKey = GlobalKey();
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _roomHeadersScrollController = ScrollController();
  final ScrollController _stickyDayLabelsScrollController = ScrollController();

  Future<void> _deleteBooking(
      String userId, String hotelId, String bookingId) async {
    await _firebaseService.deleteBooking(userId, hotelId, bookingId);
  }

  Future<void> _updateBooking(
      String userId, String hotelId, BookingModel booking) async {
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
    // Capture oldEarliestDate BEFORE updating it
    final oldEarliestDate = _earliestDate;
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
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  DateFormat('EEEE, MMM d, yyyy').format(date),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                                const Spacer(),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 22,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                                foregroundColor: Theme.of(context).colorScheme.onPrimary,
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
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    _roomHeadersScrollController.dispose();
    _stickyDayLabelsScrollController.dispose();
    super.dispose();
  }

  void _addBooking(
    String room,
    DateTime startDate,
    int nights,
    String guestName,
    Color color,
  ) {
    for (int i = 0; i < nights; i++) {
      final nightDate = DateTime(
        startDate.year,
        startDate.month,
        startDate.day,
      ).add(Duration(days: i));
      _bookings[nightDate] ??= {};
      _bookings[nightDate]![room] = Booking(
        bookingId: '',
        guestName: guestName,
        color: color,
        isFirstNight: i == 0,
        isLastNight: i == nights - 1,
        totalNights: nights,
      );
    }
  }

  Booking? _getBooking(String room, DateTime date) {
    final nightDate = DateTime(date.year, date.month, date.day);
    return _bookings[nightDate]?[room];
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
      // starting on a single room
      _numberOfSelectedRooms = 1;
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

        // update how many rooms are currently spanned horizontally
        if (_selectionStartRoom != null) {
          final startIndex = _displayedRoomNames.indexOf(_selectionStartRoom!);
          final endIndex = _displayedRoomNames.indexOf(_selectionEndRoom!);
          if (startIndex != -1 && endIndex != -1) {
            final minIndex = startIndex < endIndex ? startIndex : endIndex;
            final maxIndex = startIndex > endIndex ? startIndex : endIndex;
            _numberOfSelectedRooms = maxIndex - minIndex + 1;
          }
        }
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
          if (excludeBookingId == null || booking.bookingId != excludeBookingId) {
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
    if (userId == null || hotelId == null) return;

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
    if (roomIndex + n > _displayedRoomNames.length) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Not enough contiguous rooms: need $n from "$room"',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    final targetRooms = _displayedRoomNames.sublist(roomIndex, roomIndex + n);
    final checkIn = DateTime(date.year, date.month, date.day);
    final checkOut = checkIn.add(Duration(days: booking.numberOfNights));

    // Move any existing bookings in target range to waiting list (exclude the one we're placing)
    final selectedDates = <DateTime>[];
    for (var d = checkIn; d.isBefore(checkOut); d = d.add(const Duration(days: 1))) {
      selectedDates.add(d);
    }
    await _moveBookingsInSelectionToWaitingList(
      targetRooms,
      selectedDates,
      excludeBookingId: bookingId,
    );

    final newStatus = fromWaitingList ? 'Confirmed' : booking.status;
    final updated = booking.copyWith(
      checkIn: checkIn,
      checkOut: checkOut,
      selectedRooms: targetRooms,
      status: newStatus,
    );
    await _updateBooking(userId, hotelId, updated);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${booking.userName} moved to ${targetRooms.join(", ")}'),
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
        _moveBookingsInSelectionToWaitingList(selectedRooms, selectedDates)
            .then((_) {
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

    final indices = rooms.map((room) => _displayedRoomNames.indexOf(room)).toList();
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
        ..addAll(List.generate(
          _totalDaysLoaded,
          (index) => base.add(Duration(days: index)),
        ));
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

    final hotelId = HotelProvider.of(context).hotelId;
    final userId = AuthScopeData.of(context).uid;
    if (hotelId == null || userId == null) return;

    // Real-time query: users/{userId}/hotels/{hotelId}/bookings
    _bookingsSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('hotels')
        .doc(hotelId)
        .collection('bookings')
        .where('checkOut', isGreaterThan: rangeStart.toIso8601String())
        .snapshots()
        .listen(
          (snapshot) {
            _processBookingChanges(snapshot.docChanges, rangeStart, rangeEnd);
          },
          onError: (error) {
            debugPrint('Firestore booking subscription error: $error');
          },
        );
    _subscribeToWaitingList();
  }

  void _subscribeToWaitingList() {
    _waitingListSubscription?.cancel();

    final hotelId = HotelProvider.of(context).hotelId;
    final userId = AuthScopeData.of(context).uid;
    if (hotelId == null || userId == null) return;

    _waitingListSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('hotels')
        .doc(hotelId)
        .collection('bookings')
        .where('status', isEqualTo: 'Waiting list')
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      final list = <({String id, BookingModel booking})>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        list.add((id: doc.id, booking: BookingModel.fromFirestore(data, doc.id)));
      }
      setState(() {
        _waitingListBookings
          ..clear()
          ..addAll(list);
      });
    }, onError: (error) {
      debugPrint('Firestore waiting list subscription error: $error');
    });
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
          _bookings[nightDate]![room] = Booking(
            bookingId: bookingModel.id ?? '',
            guestName: bookingModel.userName,
            color: StayoraColors.calendarColor(bookingModel.status),
            isFirstNight: i == 0,
            isLastNight: i == totalNights - 1,
            totalNights: totalNights,
            advancePaymentStatus: bookingModel.advancePaymentStatus,
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
      if (!targetDate.isBefore(checkInDate) && targetDate.isBefore(checkOutDate)) {
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
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
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
                            DateFormat('EEEE, MMM d, yyyy').format(selectedDate),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${bookingsForDay.length} booking${bookingsForDay.length != 1 ? 's' : ''}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                child                    : bookingsForDay.isEmpty
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
                          return _DayViewBookingCard(
                            booking: booking,
                            roomIdToName: _roomIdToNameMap,
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.of(context, rootNavigator: false).push(
                                MaterialPageRoute(
                                  builder: (_) => AddBookingPage(existingBooking: booking),
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
                        InkWell(
                          onTap: _showDateSearchDialog,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 4,
                              horizontal: 2,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.search_rounded,
                                  size: 18,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    DateFormat(
                                      'MMM d, yyyy',
                                    ).format(_lastSearchedDate ?? DateTime.now()),
                                    style: Theme.of(context).textTheme.bodyLarge
                                        ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
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
                              await Navigator.of(context, rootNavigator: false).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const RoomManagementPage(),
                                ),
                              );
                              _loadRooms();
                            },
                            icon: const Icon(Icons.meeting_room_rounded, size: 20),
                            label: Text(
                              'Manage rooms',
                              overflow: TextOverflow.ellipsis,
                            ),
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
                                foregroundColor: Theme.of(context).colorScheme.onPrimary,
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
                                color: Theme.of(context).colorScheme.shadow.withOpacity(0.08),
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
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No rooms yet',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 8),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 48),
                                  child: Text(
                                    'Add rooms to see the calendar and assign bookings to rooms.',
                                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                FilledButton.icon(
                                  onPressed: () async {
                                    await Navigator.of(context, rootNavigator: false).push(
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
                          children: [
                            Expanded(
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 24),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Theme.of(context).colorScheme.shadow.withOpacity(0.08),
                                      blurRadius: 16,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Stack(
                    children: [
                      // Main scrollable grid
                      Positioned.fill(
                        child: Padding(
                          padding: EdgeInsets.only(top: _headerHeight),
                          child: GestureDetector(
                            key: _gridKey,
                            onPanStart: (details) {
                              final cell = _getCellFromPosition(
                                details.localPosition,
                              );
                              if (cell != null) {
                                // Only start selection on empty cells
                                if (_getBooking(cell['room']!, cell['date']!) ==
                                    null) {
                                  _startSelection(cell['room']!, cell['date']!);
                                }
                              }
                            },
                            onPanUpdate: (details) {
                              if (_isSelecting) {
                                final cell = _getCellFromPosition(
                                  details.localPosition,
                                );
                                if (cell != null) {
                                  // Allow selection to continue even over booked cells
                                  _updateSelection(
                                    cell['room']!,
                                    cell['date']!,
                                  );
                                }
                              }
                            },
                            onPanEnd: (details) {
                              if (_isSelecting) {
                                _endSelection();
                              }
                            },
                            onPanCancel: () {
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
                              controller: _verticalScrollController,
                              scrollDirection: Axis.vertical,
                              padding: EdgeInsets.zero,
                              child: SingleChildScrollView(
                                controller: _horizontalScrollController,
                                scrollDirection: Axis.horizontal,
                                padding: EdgeInsets.zero,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Column(
                                      children: _dates.map((date) {
                                        final isToday = isSameDay(
                                          date,
                                          DateTime.now(),
                                        );
                                        return _buildDayRow(date, isToday);
                                      }).toList(),
                                    ),
                                    // Skeleton overlay when dragging a waiting-list (or grid) booking over the calendar
                                    if (_skeletonWaitingListBookingId != null &&
                                        _skeletonRoom != null &&
                                        _skeletonDate != null)
                                      _buildDragSkeletonOverlay(),
                                  ],
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
                            color: Theme.of(context).colorScheme.surface,
                            border: Border(
                              bottom: BorderSide(
                                color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Theme.of(context).colorScheme.shadow.withOpacity(0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              // Empty corner cell (fixed)
                              Container(
                                width: _dayLabelWidth,
                                height: _headerHeight,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                  border: Border(
                                    right: BorderSide(
                                      color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                                    ),
                                  ),
                                ),
                                child: Center(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.hotel_rounded,
                                        size: 14,
                                        color: StayoraLogo.stayoraBlue,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Rooms',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                          color: StayoraLogo.stayoraBlue,
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
                                  controller: _roomHeadersScrollController,
                                  scrollDirection: Axis.horizontal,
                                  physics: const NeverScrollableScrollPhysics(),
                                  child: Row(
                                    children: _displayedRoomNames.map((room) {
                                      final roomModel = _roomModelsMap[room];
                                      final hkStatus = roomModel?.housekeepingStatus ?? 'clean';
                                      final hkColor = StayoraColors.housekeepingColor(hkStatus);
                                      final firstTag = roomModel != null && roomModel.tags.isNotEmpty
                                          ? roomModel.tags.first
                                          : null;
                                      return Container(
                                        width: _roomColumnWidth,
                                        height: 50,
                                        decoration: BoxDecoration(
                                          border: Border(
                                            right: BorderSide(
                                              color: Theme.of(context).colorScheme.surface,
                                              width: 1,
                                            ),
                                          ),
                                        ),
                                        child: Center(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                'Room $room',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                  color: Theme.of(context).colorScheme.onSurface,
                                                  letterSpacing: 0.3,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Container(
                                                    width: 7,
                                                    height: 7,
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      color: hkColor,
                                                    ),
                                                  ),
                                                  if (firstTag != null) ...[
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      firstTag,
                                                      style: TextStyle(
                                                        fontSize: 9,
                                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
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
                          color: Theme.of(context).colorScheme.surface,
                          child: ScrollConfiguration(
                            behavior: ScrollConfiguration.of(
                              context,
                            ).copyWith(scrollbars: false),
                            child: SingleChildScrollView(
                              controller: _stickyDayLabelsScrollController,
                              scrollDirection: Axis.vertical,
                              physics: const NeverScrollableScrollPhysics(),
                              child: Column(
                                children: _dates.map((date) {
                                  final isToday = isSameDay(
                                    date,
                                    DateTime.now(),
                                  );
                                  return _buildStickyDayLabel(date, isToday);
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Red line overlay for today's date
                      if (_dates.any((date) => isSameDay(date, DateTime.now())))
                        AnimatedBuilder(
                          animation: _verticalScrollController,
                          builder: (context, _) {
                            final todayIndex = _dates.indexWhere(
                              (date) => isSameDay(date, DateTime.now()),
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
                              left: _dayLabelWidth, // Start after date column
                              right: 0,
                              height: 2,
                              child: const ColoredBox(color: Colors.red),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
                            // Waiting list then legend
                            _buildWaitingListSection(),
                            const SizedBox(height: 16),
                            _buildLegendSection(),
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
            Navigator.of(context, rootNavigator: false).push(
              MaterialPageRoute(builder: (context) => const AddBookingPage()),
            ).then((bookingCreated) {
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
          child: Icon(Icons.add_rounded, color: Theme.of(context).colorScheme.onPrimary, size: 28),
        ),
      ),
    );
  }

  Widget _buildLegendSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Status Legend',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _LegendItem(
                    color: _statusColor('Confirmed'),
                    label: 'Confirmed',
                  ),
                  _LegendItem(
                    color: _statusColor('Pending'),
                    label: 'Pending',
                  ),
                  _LegendItem(
                    color: _statusColor('Paid'),
                    label: 'Paid',
                  ),
                  _LegendItem(
                    color: _statusColor('Unpaid'),
                    label: 'Unpaid',
                  ),
                  _LegendItem(
                    color: _statusColor('Cancelled'),
                    label: 'Cancelled',
                  ),
                  _LegendItem(
                    color: _statusColor('Waiting list'),
                    label: 'Waiting list',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWaitingListSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: DragTarget<_WaitingListDragPayload>(
        onWillAcceptWithDetails: (details) => true,
        onAcceptWithDetails: (details) {
          _moveBookingToWaitingList(details.data.bookingId);
        },
        builder: (context, candidateData, rejectedData) {
          final isHighlighted = candidateData.isNotEmpty;
          return Card(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: isHighlighted
                  ? const BorderSide(color: StayoraColors.purple, width: 2)
                  : BorderSide.none,
            ),
            color: isHighlighted
                ? StayoraColors.purple.withOpacity(0.08)
                : null,
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            leading: Icon(
              Icons.list_alt_rounded,
              color: _waitingListBookings.isEmpty
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : StayoraColors.purple,
              size: 24,
            ),
            title: Text(
              'Waiting list',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            trailing: Text(
              '${_waitingListBookings.length}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _waitingListBookings.isEmpty
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : StayoraColors.purple,
              ),
            ),
            children: [
              if (_waitingListBookings.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Text(
                    'No reservations on the waiting list. Bookings saved as "Waiting list" (e.g. over capacity) appear here.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                      child: Text(
                        'Long-press an item and drag it to a calendar cell to place it. Any booking there will move to the waiting list.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.3,
                        ),
                      ),
                    ),
                    ..._waitingListBookings.map((e) {
                  final b = e.booking;
                  final payload = _WaitingListDragPayload(bookingId: e.id);
                  return LongPressDraggable<_WaitingListDragPayload>(
                    data: payload,
                    onDragEnd: (_) {
                      setState(() {
                        _skeletonWaitingListBookingId = null;
                        _skeletonRoom = null;
                        _skeletonDate = null;
                      });
                    },
                    feedback: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(12),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.person_rounded,
                                color: _statusColor('Waiting list'),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  b.userName,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${b.numberOfRooms} room(s)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    childWhenDragging: Opacity(
                      opacity: 0.5,
                      child: ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          backgroundColor:
                              _statusColor('Waiting list').withOpacity(0.2),
                          child: Icon(
                            Icons.person_rounded,
                            size: 20,
                            color: _statusColor('Waiting list'),
                          ),
                        ),
                        title: Text(
                          b.userName,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text(
                          '${DateFormat('MMM d', 'en').format(b.checkIn)} – ${DateFormat('MMM d', 'en').format(b.checkOut)} · ${b.numberOfRooms} room(s)',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          color: StayoraColors.blue,
                          size: 20,
                        ),
                      ),
                    ),
                    child: ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        backgroundColor:
                            _statusColor('Waiting list').withOpacity(0.2),
                        child: Icon(
                          Icons.person_rounded,
                          size: 20,
                          color: _statusColor('Waiting list'),
                        ),
                      ),
                      title: Text(
                        b.userName,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text(
                        '${DateFormat('MMM d', 'en').format(b.checkIn)} – ${DateFormat('MMM d', 'en').format(b.checkOut)} · ${b.numberOfRooms} room(s)',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right_rounded,
                        color: StayoraColors.blue,
                        size: 20,
                      ),
                      onTap: () => _showBookingDetailsById(context, e.id),
                    ),
                  );
                }),
                  ],
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
  },
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
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(userId)
                .collection('hotels')
                .doc(hotelId)
                .collection('bookings')
                .doc(bookingId)
                .snapshots(),
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
              return _BookingDetailsForm(
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
                  nestedNavigator.push(
                    MaterialPageRoute(
                        builder: (context) {
                          final resolved = fullBooking.resolvedSelectedRooms(_roomIdToNameMap);
                          return AddBookingPage(
                            existingBooking: fullBooking,
                            preselectedRoom: resolved.isNotEmpty ? resolved.first : '—',
                            preselectedStartDate: fullBooking.checkIn,
                            preselectedEndDate: fullBooking.checkOut,
                            preselectedNumberOfRooms: fullBooking.numberOfRooms,
                          );
                        },
                    ),
                  ).then((bookingCreated) {
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

  /// Skeleton overlay showing the size of the booking being dragged (rooms × nights).
  Widget _buildDragSkeletonOverlay() {
    final booking = _getWaitingListBookingById(_skeletonWaitingListBookingId!) ??
        _bookingModelsById[_skeletonWaitingListBookingId!];
    if (booking == null) return const SizedBox.shrink();

    final roomIndex = _displayedRoomNames.indexOf(_skeletonRoom!);
    final dateIndex = _dates.indexWhere(
      (d) =>
          d.year == _skeletonDate!.year &&
          d.month == _skeletonDate!.month &&
          d.day == _skeletonDate!.day,
    );
    if (roomIndex < 0 || dateIndex < 0) return const SizedBox.shrink();

    final nRooms = booking.numberOfRooms;
    final nNights = booking.numberOfNights;
    final roomEnd = roomIndex + nRooms;
    final dateEnd = dateIndex + nNights;
    final fitsRooms = roomEnd <= _displayedRoomNames.length;
    final fitsDates = dateEnd <= _dates.length;
    final isValid = fitsRooms && fitsDates;

    final left = _dayLabelWidth + roomIndex * _roomColumnWidth;
    final top = dateIndex * _dayRowHeight;
    final width = nRooms * _roomColumnWidth;
    final height = nNights * _dayRowHeight;

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: (isValid
                    ? StayoraColors.purple
                    : StayoraColors.error)
                .withOpacity(0.35),
            border: Border.all(
              color: isValid
                  ? StayoraColors.purple
                  : StayoraColors.error,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              '${booking.userName}\n$nRooms room(s) · $nNights night(s)',
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
    return Container(
      height: _dayRowHeight, // Row height stays the same, gap is between rows
      decoration: BoxDecoration(
        color: isToday
            ? StayoraColors.blue.withOpacity(0.05)
            : Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outline.withOpacity(0.3), width: 1),
          bottom: BorderSide(color: Theme.of(context).colorScheme.outline.withOpacity(0.3), width: 1),
        ),
      ),
      child: Row(
        children: [
          // Spacer for sticky day label column
          SizedBox(width: _dayLabelWidth),
          // Room cells
          Row(
            children: _displayedRoomNames.map((room) {
              final booking = _getBooking(room, date);
              return _buildRoomCell(room, date, booking);
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
            child: Container(color: Theme.of(context).colorScheme.outline.withOpacity(0.3)),
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

  Widget _buildRoomCell(String room, DateTime date, Booking? booking) {
    final isSelected = _isCellInSelection(room, date);

    return DragTarget<_WaitingListDragPayload>(
      onWillAcceptWithDetails: (details) => true,
      onMove: (details) {
        setState(() {
          _skeletonWaitingListBookingId = details.data.bookingId;
          _skeletonRoom = room;
          _skeletonDate = date;
        });
      },
      onLeave: (_) {
        setState(() {
          _skeletonWaitingListBookingId = null;
          _skeletonRoom = null;
          _skeletonDate = null;
        });
      },
      onAcceptWithDetails: (details) {
        _onDropWaitingListBooking(details.data.bookingId, room, date);
        setState(() {
          _skeletonWaitingListBookingId = null;
          _skeletonRoom = null;
          _skeletonDate = null;
        });
      },
      builder: (context, candidateData, rejectedData) {
        final isHighlighted = candidateData.isNotEmpty;
        return GestureDetector(
          onTap: () {
            if (booking != null) {
              _showBookingDetails(context, room, date, booking);
            } else if (!_isSelecting) {
              _showBookingDialog([room], [date], false);
            }
          },
          child: Container(
        width: _roomColumnWidth,
        height: _dayRowHeight,
        decoration: BoxDecoration(
          color: isHighlighted
              ? StayoraColors.purple.withOpacity(0.25)
              : isSelected
                  ? StayoraColors.blue.withOpacity(0.2)
                  : Theme.of(context).colorScheme.surface,
          border: Border(
            right: BorderSide(color: Theme.of(context).colorScheme.outline.withOpacity(0.3), width: 1),
            top: isSelected
                ? BorderSide(
                    color: StayoraColors.blue.withOpacity(0.5),
                    width: 2,
                  )
                : BorderSide.none,
            bottom: isSelected
                ? BorderSide(
                    color: StayoraColors.blue.withOpacity(0.5),
                    width: 2,
                  )
                : BorderSide.none,
            left: isSelected
                ? BorderSide(
                    color: StayoraColors.blue.withOpacity(0.5),
                    width: 2,
                  )
                : BorderSide.none,
          ),
        ),
        child: Stack(
          children: [
            // Booking display (long-press to drag to another cell)
            if (booking != null)
              LongPressDraggable<_WaitingListDragPayload>(
                data: _WaitingListDragPayload(bookingId: booking.bookingId),
                onDragEnd: (_) {
                  setState(() {
                    _skeletonWaitingListBookingId = null;
                    _skeletonRoom = null;
                    _skeletonDate = null;
                  });
                },
                feedback: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: booking.color,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          booking.guestName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (booking.totalNights > 1) ...[
                          const SizedBox(width: 6),
                          Text(
                            '${booking.totalNights} nights',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                childWhenDragging: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: double.infinity,
                      height: double.infinity,
                      decoration: BoxDecoration(
                        color: booking.color.withOpacity(0.4),
                        borderRadius: BorderRadius.horizontal(
                          left: booking.isFirstNight
                              ? const Radius.circular(8)
                              : Radius.zero,
                          right: booking.isLastNight
                              ? const Radius.circular(8)
                              : Radius.zero,
                        ),
                      ),
                    ),
                  ],
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: double.infinity,
                      height: double.infinity,
                      decoration: BoxDecoration(
                        color: booking.color,
                        borderRadius: BorderRadius.horizontal(
                          left: booking.isFirstNight
                              ? const Radius.circular(8)
                              : Radius.zero,
                          right: booking.isLastNight
                              ? const Radius.circular(8)
                              : Radius.zero,
                        ),
                        boxShadow: booking.isFirstNight
                            ? [
                                BoxShadow(
                                  color: Theme.of(context).colorScheme.shadow.withOpacity(0.1),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: booking.isFirstNight
                          ? Padding(
                              padding: const EdgeInsets.only(
                                left: 10,
                                right: 8,
                                top: 6,
                                bottom: 6,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    booking.guestName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (booking.totalNights > 1)
                                    Text(
                                      '${booking.totalNights} nights',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.9),
                                        fontSize: 9,
                                      ),
                                    ),
                                ],
                              ),
                            )
                          : const SizedBox(),
                    ),
                    // Advance payment dot — top-right of the first night cell
                    if (booking.isFirstNight &&
                        booking.advancePaymentStatus != 'not_required')
                      Positioned(
                        top: 5,
                        right: 5,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _advanceIndicatorColor(
                              booking.advancePaymentStatus,
                            ),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.7),
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            // Selection overlay
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
      ),
    );
      },
    );
  }

  void _showBookingDetails(
    BuildContext context,
    String room,
    DateTime date,
    Booking booking,
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
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(userId)
                .collection('hotels')
                .doc(hotelId)
                .collection('bookings')
                .doc(bookingId)
                .snapshots(),
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
              return _BookingDetailsForm(
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
                  nestedNavigator.push(
                    MaterialPageRoute(
                      builder: (context) => AddBookingPage(
                        existingBooking: fullBooking,
                        preselectedRoom: room,
                        preselectedStartDate: fullBooking.checkIn,
                        preselectedEndDate: fullBooking.checkOut,
                        preselectedNumberOfRooms: fullBooking.numberOfRooms,
                      ),
                    ),
                  ).then((bookingCreated) {
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
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                  style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                          foregroundColor: Theme.of(context).colorScheme.onPrimary,
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
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: TextButton.styleFrom(
                          foregroundColor: StayoraColors.blue,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
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
    Navigator.of(context, rootNavigator: false).push(
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
    ).then((bookingCreated) {
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

class _BookingDetailsForm extends StatefulWidget {
  final BookingModel fullBooking;
  final String room;
  final DateTime date;
  final String bookingId;
  final List<String> statusOptions;
  final Color Function(String) getStatusColor;
  final List<String> paymentMethods;
  final CurrencyFormatter currencyFormatter;
  final Widget Function(IconData, String, String) buildDetailRow;
  final Widget Function(String) buildStatusRowWithStatus;
  final Future<void> Function(BookingModel) onSave;
  final Future<void> Function() onDelete;
  final VoidCallback onEditFull;
  final VoidCallback onClose;
  /// Passed from the calendar state so room names are always current.
  final Map<String, String> roomIdToName;

  const _BookingDetailsForm({
    super.key,
    required this.fullBooking,
    required this.room,
    required this.date,
    required this.bookingId,
    required this.statusOptions,
    required this.getStatusColor,
    required this.paymentMethods,
    required this.currencyFormatter,
    required this.buildDetailRow,
    required this.buildStatusRowWithStatus,
    required this.onSave,
    required this.onDelete,
    required this.onEditFull,
    required this.onClose,
    this.roomIdToName = const {},
  });

  @override
  State<_BookingDetailsForm> createState() => _BookingDetailsFormState();
}

class _BookingDetailsFormState extends State<_BookingDetailsForm> {
  late String _status;
  late TextEditingController _amountController;
  late TextEditingController _advanceAmountController;
  late String _paymentMethod;
  late String _advancePaymentMethod;
  late String _advanceStatus; // not_required, pending, received
  late TextEditingController _notesController;

  /// Initial values when the dialog opened (or last synced from Firestore).
  /// Used to detect unsaved changes.
  late String _initialStatus;
  late int _initialAmount;
  late int _initialAdvanceAmount;
  late String _initialPaymentMethod;
  late String _initialAdvancePaymentMethod;
  late String _initialAdvanceStatus;
  late String _initialNotes;

  @override
  void initState() {
    super.initState();
    _syncFromBooking(widget.fullBooking);
  }

  void _syncFromBooking(BookingModel b) {
    _status = widget.statusOptions.contains(b.status)
        ? b.status
        : widget.statusOptions.first;
    _amountController = TextEditingController(
      text: CurrencyFormatter.formatStoredAmountForInput(b.amountOfMoneyPaid),
    );
    _advanceAmountController = TextEditingController(
      text: CurrencyFormatter.formatStoredAmountForInput(b.advanceAmountPaid),
    );
    _paymentMethod = widget.paymentMethods.contains(b.paymentMethod)
        ? b.paymentMethod
        : widget.paymentMethods.first;
    _advancePaymentMethod =
        (b.advancePaymentMethod != null && b.advancePaymentMethod!.isNotEmpty)
        ? b.advancePaymentMethod!
        : widget.paymentMethods.first;
    _advanceStatus =
        (b.advanceStatus != null &&
            BookingModel.advanceStatusOptions.contains(b.advanceStatus))
        ? b.advanceStatus!
        : (b.advancePercent != null && b.advancePercent! > 0
              ? (b.advanceAmountPaid >= b.advanceAmountRequired
                    ? 'received'
                    : 'pending')
              : 'not_required');
    _notesController = TextEditingController(text: b.notes ?? '');

    _initialStatus = _status;
    _initialAmount = b.amountOfMoneyPaid;
    _initialAdvanceAmount = b.advanceAmountPaid;
    _initialPaymentMethod = _paymentMethod;
    _initialAdvancePaymentMethod = _advancePaymentMethod;
    _initialAdvanceStatus = _advanceStatus;
    _initialNotes = b.notes ?? '';
  }

  /// True if any editable field differs from the initial/saved state.
  bool get _hasChanges {
    final currentAmount =
        CurrencyFormatter.parseMoneyStringToCents(_amountController.text.trim());
    final currentAdvance = CurrencyFormatter.parseMoneyStringToCents(
        _advanceAmountController.text.trim());
    final currentNotes = _notesController.text.trim();
    return _status != _initialStatus ||
        currentAmount != _initialAmount ||
        currentAdvance != _initialAdvanceAmount ||
        _paymentMethod != _initialPaymentMethod ||
        _advancePaymentMethod != _initialAdvancePaymentMethod ||
        _advanceStatus != _initialAdvanceStatus ||
        currentNotes != _initialNotes;
  }

  Future<void> _handleClose() async {
    if (!_hasChanges) {
      widget.onClose();
      return;
    }
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.shadow.withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 28),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Unsaved Changes',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 20,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'You have unsaved changes. Do you want to save before closing?',
                  style: TextStyle(
                    fontSize: 15,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              // Buttons - Apple style: full width, stacked, rounded
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => Navigator.pop(context, 'save'),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              color: StayoraColors.success,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Center(
                              child: Text(
                                'Save and Close',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => Navigator.pop(context, 'discard'),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.5)),
                            ),
                            child: const Center(
                              child: Text(
                                'Discard Changes',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: StayoraColors.error,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => Navigator.pop(context, 'cancel'),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: const Center(
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: StayoraColors.blue,
                                ),
                              ),
                            ),
                          ),
                        ),
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
    if (!mounted) return;
    switch (result) {
      case 'save':
        final amount =
            CurrencyFormatter.parseMoneyStringToCents(_amountController.text.trim());
        final advanceAmount = CurrencyFormatter.parseMoneyStringToCents(
            _advanceAmountController.text.trim());
        final updated = widget.fullBooking.copyWith(
          status: _status,
          amountOfMoneyPaid: amount,
          paymentMethod: _paymentMethod,
          advanceAmountPaid: advanceAmount,
          advancePaymentMethod: _advancePaymentMethod,
          advanceStatus: _advanceStatus,
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          // preserve check-in/out timestamps set via the quick buttons
          checkedInAt: widget.fullBooking.checkedInAt,
          checkedOutAt: widget.fullBooking.checkedOutAt,
        );
        await widget.onSave(updated);
        if (!mounted) return;
        widget.onClose();
        break;
      case 'discard':
        widget.onClose();
        break;
      case 'cancel':
      default:
        break;
    }
  }

  @override
  void didUpdateWidget(covariant _BookingDetailsForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fullBooking.id != widget.fullBooking.id ||
        oldWidget.fullBooking.status != widget.fullBooking.status ||
        oldWidget.fullBooking.amountOfMoneyPaid !=
            widget.fullBooking.amountOfMoneyPaid ||
        oldWidget.fullBooking.paymentMethod !=
            widget.fullBooking.paymentMethod ||
        oldWidget.fullBooking.advanceAmountPaid !=
            widget.fullBooking.advanceAmountPaid ||
        oldWidget.fullBooking.advancePaymentMethod !=
            widget.fullBooking.advancePaymentMethod ||
        oldWidget.fullBooking.advanceStatus !=
            widget.fullBooking.advanceStatus ||
        oldWidget.fullBooking.notes != widget.fullBooking.notes) {
      _amountController.dispose();
      _advanceAmountController.dispose();
      _notesController.dispose();
      _syncFromBooking(widget.fullBooking);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _advanceAmountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.fullBooking;
    final totalNights = b.numberOfNights;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 24),
          Text(
            'Booking Details',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 17,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                widget.buildDetailRow(
                  Icons.person_rounded,
                  'Guest',
                  b.userName,
                ),
                const SizedBox(height: 12),
                widget.buildDetailRow(
                  Icons.hotel_rounded,
                  () {
                    final resolved = b.resolvedSelectedRooms(widget.roomIdToName);
                    return resolved.length > 1 ? 'Rooms' : 'Room';
                  }(),
                  () {
                    final resolved = b.resolvedSelectedRooms(widget.roomIdToName);
                    return resolved.isNotEmpty ? resolved.join(', ') : widget.room;
                  }(),
                ),
                const SizedBox(height: 12),
                widget.buildDetailRow(
                  Icons.calendar_today_rounded,
                  'Date',
                  DateFormat('MMM d, yyyy').format(widget.date),
                ),
                const SizedBox(height: 12),
                widget.buildDetailRow(
                  Icons.nightlight_round,
                  'Duration',
                  '$totalNights ${totalNights == 1 ? 'night' : 'nights'}',
                ),
                const SizedBox(height: 16),
                // ── Check-in / Check-out ─────────────────────────────────
                Text(
                  'Check-in / Check-out',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: b.checkedInAt == null
                          ? OutlinedButton.icon(
                              onPressed: () async {
                                final updated = b.copyWith(
                                  checkedInAt: DateTime.now(),
                                );
                                await widget.onSave(updated);
                              },
                              icon: const Icon(Icons.login_rounded, size: 16),
                              label: const Text('Check In'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: StayoraColors.teal,
                                side: const BorderSide(color: StayoraColors.teal),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                            )
                          : Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: StayoraColors.teal.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: StayoraColors.teal.withOpacity(0.4),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    size: 14,
                                    color: StayoraColors.teal,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'In: ${DateFormat('MMM d, HH:mm').format(b.checkedInAt!)}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: StayoraColors.teal,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: b.checkedOutAt == null
                          ? OutlinedButton.icon(
                              onPressed: b.checkedInAt == null
                                  ? null
                                  : () async {
                                      final updated = b.copyWith(
                                        checkedOutAt: DateTime.now(),
                                      );
                                      await widget.onSave(updated);
                                    },
                              icon: const Icon(Icons.logout_rounded, size: 16),
                              label: const Text('Check Out'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: StayoraColors.warning,
                                side: BorderSide(
                                  color: b.checkedInAt == null
                                      ? Theme.of(context).colorScheme.outline.withOpacity(0.4)
                                      : StayoraColors.warning,
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                            )
                          : Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: StayoraColors.warning.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: StayoraColors.warning.withOpacity(0.4),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    size: 14,
                                    color: StayoraColors.warning,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Out: ${DateFormat('MMM d, HH:mm').format(b.checkedOutAt!)}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: StayoraColors.warning,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Price card — compact, formatted currency
                _PriceCard(
                  booking: b,
                  currencyFormatter: widget.currencyFormatter,
                ),
                const SizedBox(height: 16),
                // Advance payment section
                ...() {
                  final advStatus = b.advancePaymentStatus;
                  final cf = widget.currencyFormatter;
                  if (advStatus == 'not_required') {
                    return [
                      _SectionCard(
                        title: 'Advance payment',
                        child: Text(
                          'No advance required',
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ];
                  }
                  return [
                    _SectionCard(
                      title: 'Advance payment',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (b.advancePercent != null && b.advancePercent! > 0)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                '${b.advancePercent}% of total — required ${cf.format(b.advanceAmountRequired)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ),
                          TextFormField(
                            controller: _advanceAmountController,
                            inputFormatters: [
                              MoneyInputFormatter(),
                            ],
                            decoration: InputDecoration(
                              labelText: 'Advance paid',
                              hintText: '0.00',
                              filled: true,
                              fillColor:
                                  Theme.of(context).colorScheme.surface,
                              prefixIcon: const Icon(
                                Icons.payments_rounded,
                                size: 18,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            value: widget.paymentMethods
                                    .contains(_advancePaymentMethod)
                                ? _advancePaymentMethod
                                : widget.paymentMethods.first,
                            decoration: InputDecoration(
                              labelText: 'Advance payment method',
                              filled: true,
                              fillColor:
                                  Theme.of(context).colorScheme.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                            items: widget.paymentMethods
                                .map(
                                  (m) => DropdownMenuItem(
                                    value: m,
                                    child: Text(m),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() {
                              _advancePaymentMethod =
                                  v ?? widget.paymentMethods.first;
                            }),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Advance received?',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              ChoiceChip(
                                label: const Text('Pending'),
                                selected: _advanceStatus == 'pending',
                                onSelected: (v) =>
                                    setState(() => _advanceStatus = 'pending'),
                                selectedColor:
                                    StayoraColors.warning.withOpacity(0.3),
                              ),
                              ChoiceChip(
                                label: const Text('Received'),
                                selected: _advanceStatus == 'received',
                                onSelected: (v) =>
                                    setState(() => _advanceStatus = 'received'),
                                selectedColor:
                                    StayoraColors.success.withOpacity(0.3),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Builder(
                            builder: (context) {
                              final advancePaid =
                                  CurrencyFormatter.parseMoneyStringToCents(
                                _advanceAmountController.text.trim(),
                              );
                              final remaining = (b.calculatedTotal - advancePaid)
                                  .clamp(0, b.calculatedTotal);
                              return Row(
                                children: [
                                  Icon(
                                    Icons.account_balance_wallet_rounded,
                                    size: 16,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Remaining: ${cf.format(remaining)}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: remaining > 0
                                            ? StayoraColors.warning
                                            : Theme.of(context)
                                                .colorScheme
                                                .onSurface,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ];
                }(),
                const SizedBox(height: 16),
                // Payment, status & notes — one card
                _SectionCard(
                  title: 'Payment & notes',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<String>(
                        value: _status,
                        decoration: InputDecoration(
                          labelText: 'Status',
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        items: widget.statusOptions
                            .map(
                              (s) => DropdownMenuItem(
                                value: s,
                                child: Text(
                                  s,
                                  style: TextStyle(
                                    color: widget.getStatusColor(s),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _status = v ?? _status),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _amountController,
                        inputFormatters: [MoneyInputFormatter()],
                        decoration: InputDecoration(
                          labelText: 'Amount paid',
                          hintText: '0.00',
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surface,
                          prefixIcon: const Icon(
                            Icons.payments_rounded,
                            size: 20,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: widget.paymentMethods.contains(_paymentMethod)
                            ? _paymentMethod
                            : widget.paymentMethods.first,
                        decoration: InputDecoration(
                          labelText: 'Payment method',
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        items: widget.paymentMethods
                            .map(
                              (m) => DropdownMenuItem(
                                value: m,
                                child: Text(m),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(
                          () => _paymentMethod =
                              v ?? widget.paymentMethods.first,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _notesController,
                        decoration: InputDecoration(
                          labelText: 'Notes',
                          hintText: 'Optional notes…',
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surface,
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        maxLines: 2,
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      final amount = CurrencyFormatter.parseMoneyStringToCents(
                        _amountController.text.trim(),
                      );
                      final advanceAmount =
                          CurrencyFormatter.parseMoneyStringToCents(
                        _advanceAmountController.text.trim(),
                      );
                      final updated = b.copyWith(
                        status: _status,
                        amountOfMoneyPaid: amount,
                        paymentMethod: _paymentMethod,
                        advanceAmountPaid: advanceAmount,
                        advancePaymentMethod: _advancePaymentMethod,
                        advanceStatus: _advanceStatus,
                        notes: _notesController.text.trim().isEmpty
                            ? null
                            : _notesController.text.trim(),
                      );
                      await widget.onSave(updated);
                    },
                    label: const Text('Save changes'),
                    style: FilledButton.styleFrom(
                      backgroundColor: StayoraColors.success,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: widget.onEditFull,
                    style: FilledButton.styleFrom(
                      backgroundColor: StayoraColors.blue,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Edit full booking (dates, rooms, guest)',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async => await widget.onDelete(),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Delete Booking'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _handleClose,
                    style: TextButton.styleFrom(
                      foregroundColor: StayoraColors.blue,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class Booking {
  final String bookingId;
  final String guestName;
  final Color color;
  final bool isFirstNight;
  final bool isLastNight;
  final int totalNights;

  /// Advance payment status: not_required, waiting, paid.
  final String advancePaymentStatus;

  Booking({
    required this.bookingId,
    required this.guestName,
    required this.color,
    required this.isFirstNight,
    required this.isLastNight,
    required this.totalNights,
    this.advancePaymentStatus = 'not_required',
  });
}

/// Section wrapper for the popup: title + padded content.
class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// Compact price breakdown card with formatted currency (no raw 120000).
class _PriceCard extends StatelessWidget {
  final BookingModel booking;
  final CurrencyFormatter currencyFormatter;

  const _PriceCard({
    required this.booking,
    required this.currencyFormatter,
  });

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final hasRoom = (b.pricePerNight ?? 0) > 0;
    final hasServices =
        b.selectedServices != null && b.selectedServices!.isNotEmpty;
    final theme = Theme.of(context);

    if (!hasRoom && !hasServices) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outline.withOpacity(0.2),
          ),
        ),
        child: Text(
          'No price set',
          style: TextStyle(
            fontSize: 13,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasRoom)
            _priceRow(
              context,
              '${b.numberOfNights} night${b.numberOfNights == 1 ? '' : 's'} × ${b.numberOfRooms} room${b.numberOfRooms == 1 ? '' : 's'} × ${currencyFormatter.formatCompact(b.pricePerNight!)}',
              currencyFormatter.formatCompact(b.roomSubtotal),
              isSub: true,
            ),
          if (hasServices) ...[
            if (hasRoom) const SizedBox(height: 8),
            ...b.selectedServices!.map(
              (s) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _priceRow(
                  context,
                  '${s.name} × ${s.quantity}',
                  currencyFormatter.formatCompact(s.lineTotal),
                  isSub: true,
                ),
              ),
            ),
            const SizedBox(height: 6),
            _priceRow(
              context,
              'Services',
              currencyFormatter.formatCompact(b.servicesSubtotal),
              isSub: true,
            ),
            const SizedBox(height: 8),
          ],
          const Divider(height: 1),
          const SizedBox(height: 8),
          _priceRow(
            context,
            'Total',
            currencyFormatter.format(b.calculatedTotal),
            isSub: false,
          ),
        ],
      ),
    );
  }

  Widget _priceRow(
    BuildContext context,
    String label,
    String value, {
    required bool isSub,
  }) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: isSub ? 13 : 14,
              fontWeight: isSub ? FontWeight.w500 : FontWeight.w600,
              color: isSub
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.onSurface,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: TextStyle(
            fontSize: isSub ? 13 : 15,
            fontWeight: isSub ? FontWeight.w500 : FontWeight.bold,
            color: isSub
                ? theme.colorScheme.onSurface
                : StayoraColors.blue,
          ),
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: color,
              width: 2,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _DayViewBookingCard extends StatelessWidget {
  final BookingModel booking;
  final VoidCallback onTap;
  final Map<String, String> roomIdToName;

  const _DayViewBookingCard({
    required this.booking,
    required this.onTap,
    this.roomIdToName = const {},
  });

  Color _getStatusColor(BuildContext context, String status) {
    switch (status) {
      case 'Confirmed':
        return StayoraColors.success;
      case 'Pending':
        return StayoraColors.warning;
      case 'Cancelled':
        return StayoraColors.error;
      case 'Paid':
        return StayoraColors.blue;
      case 'Unpaid':
        return StayoraColors.muted;
      case 'Waiting list':
        return StayoraColors.purple;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor(context, booking.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      booking.userName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      booking.status,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.phone_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    booking.userPhone,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${DateFormat('MMM d').format(booking.checkIn)} - ${DateFormat('MMM d, yyyy').format(booking.checkOut)}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Icon(
                    Icons.nights_stay_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${booking.numberOfNights} night${booking.numberOfNights != 1 ? 's' : ''}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              Builder(builder: (context) {
                final rooms = booking.resolvedSelectedRooms(roomIdToName);
                if (rooms.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.bed_rounded,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            rooms.join(', '),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

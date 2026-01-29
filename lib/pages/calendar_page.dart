import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/booking_model.dart';
import 'add_booking_page.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  static const double _headerHeight = 50.0;
  static const double _dayLabelWidth = 100.0;

  final double _roomColumnWidth = 120.0;
  final double _dayRowHeight = 50.0;

  // Sliding window: bounded date range to avoid unbounded widget growth
  DateTime _earliestDate = DateTime.now();
  int _totalDaysLoaded = 30;
  static const int _loadMoreDays = 30;
  static const int _maxDaysLoaded = 180;
  bool _isLoadingMore = false;
  List<DateTime> _cachedDates = [];

  // Real-time Firestore synchronization
  StreamSubscription<QuerySnapshot>? _bookingsSubscription;
  Timer? _debounceTimer;
  static const Duration _debounceDuration = Duration(milliseconds: 100);

  // Sample rooms
  final List<String> _rooms = [
    '101',
    '102',
    '103',
    '104',
    '105',
    '201',
    '202',
    '203',
    '204',
    '205',
    '301',
    '302',
    '303',
    '304',
    '305',
  ];

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
  bool _isSelecting = false;
  List<int> _preselectedRoomsIndex = [];
  final GlobalKey _gridKey = GlobalKey();
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _roomHeadersScrollController = ScrollController();
  final ScrollController _stickyDayLabelsScrollController = ScrollController();

  Future<void> _deleteBooking(String bookingId) async {
    await FirebaseFirestore.instance
        .collection('bookings')
        .doc(bookingId)
        .delete();
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
    // If scrolled near the top (within 200px), load more dates
    if (_verticalScrollController.offset < 200 &&
        _verticalScrollController.hasClients &&
        !_isLoadingMore) {
      _loadMoreDatesUp();
    }
  }

  void _loadMoreDatesUp() {
    if (_isLoadingMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    final currentOffset = _verticalScrollController.offset;
    final daysToAdd = _loadMoreDays;
    // Capture oldEarliestDate BEFORE updating it
    final oldEarliestDate = _earliestDate;
    final newEarliestDate = _earliestDate.subtract(Duration(days: daysToAdd));

    setState(() {
      _earliestDate = newEarliestDate;
      _totalDaysLoaded += daysToAdd;
      _isLoadingMore = false;
    });

    // Re-subscribe so we fetch bookings for the new range (including dates above today)
    _subscribeToBookings();

    // Adjust scroll position to maintain view after frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
    final initial = _lastSearchedDate ?? _earliestDate;
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
                  color: const Color(0xFFF2F2F7),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
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
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Go to date',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Material(
                        color: Colors.white,
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
                                  color: Colors.grey.shade600,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  DateFormat('EEEE, MMM d, yyyy').format(date),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black87,
                                  ),
                                ),
                                const Spacer(),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 22,
                                  color: Colors.grey.shade400,
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
                                foregroundColor: const Color(0xFF007AFF),
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
                                backgroundColor: const Color(0xFF007AFF),
                                foregroundColor: Colors.white,
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

    final startRoomIndex = _rooms.indexOf(_selectionStartRoom!);
    final endRoomIndex = _selectionEndRoom != null
        ? _rooms.indexOf(_selectionEndRoom!)
        : startRoomIndex;
    final currentRoomIndex = _rooms.indexOf(room);

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
          final startIndex = _rooms.indexOf(_selectionStartRoom!);
          final endIndex = _rooms.indexOf(_selectionEndRoom!);
          if (startIndex != -1 && endIndex != -1) {
            final minIndex = startIndex < endIndex ? startIndex : endIndex;
            final maxIndex = startIndex > endIndex ? startIndex : endIndex;
            _numberOfSelectedRooms = maxIndex - minIndex + 1;
          }
        }
      });
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
            .map((room) => _rooms.indexOf(room))
            .where((index) => index != -1)
            .toList();
        _showBookingDialog(
          selectedRooms,
          selectedDates,
          _roomsNextToEachOther,
          preselectedRoomIndexes: _preselectedRoomsIndex,
        );
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

    final startIndex = _rooms.indexOf(_selectionStartRoom!);
    final endIndex = _selectionEndRoom != null
        ? _rooms.indexOf(_selectionEndRoom!)
        : startIndex;

    final minIndex = startIndex < endIndex ? startIndex : endIndex;
    final maxIndex = startIndex > endIndex ? startIndex : endIndex;

    return _rooms.sublist(minIndex, maxIndex + 1);
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

    final indices = rooms.map((room) => _rooms.indexOf(room)).toList();
    if (indices.any((index) => index == -1)) return false;

    indices.sort();
    for (var i = 1; i < indices.length; i++) {
      if (indices[i] - indices[i - 1] != 1) {
        return false;
      }
    }
    return true;
  }

  List<DateTime> get _dates {
    return List.generate(_totalDaysLoaded, (index) {
      return DateTime(
        _earliestDate.year,
        _earliestDate.month,
        _earliestDate.day,
      ).add(Duration(days: index));
    });
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
    if (roomIndex < 0 || roomIndex >= _rooms.length) return null;

    // Position is already relative to the gesture detector which is below the header
    final localY = position.dy;
    if (localY < 0) return null;

    // Calculate day index using dayRowHeight
    final dayIndex = ((localY + scrollY) / _dayRowHeight).floor();
    if (dayIndex < 0 || dayIndex >= _dates.length) return null;

    return {'room': _rooms[roomIndex], 'date': _dates[dayIndex]};
  }

  void _subscribeToBookings() {
    _bookingsSubscription?.cancel();

    final rangeStart = DateTime(
      _earliestDate.year,
      _earliestDate.month,
      _earliestDate.day,
    );
    final rangeEnd = rangeStart.add(Duration(days: _totalDaysLoaded));

    // Real-time query: only bookings overlapping [rangeStart, rangeEnd)
    _bookingsSubscription = FirebaseFirestore.instance
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

      final rooms = bookingModel.selectedRooms;
      if (rooms == null || rooms.isEmpty) continue;

      final totalNights = bookingModel.numberOfNights;

      for (final room in rooms) {
        if (!_rooms.contains(room)) continue;

        for (int i = 0; i < totalNights; i++) {
          final nightDate = bookingStart.add(Duration(days: i));

          // Show only nights inside visible range: nightDate >= rangeStart AND nightDate < rangeEnd
          if (nightDate.isBefore(rangeStart) ||
              nightDate.isAtSameMomentAs(rangeEnd) ||
              nightDate.isAfter(rangeEnd)) {
            continue; // night outside visible range
          }

          if (change.type == DocumentChangeType.removed) {
            // Remove booking
            _bookings[nightDate]?.remove(room);
            if (_bookings[nightDate]?.isEmpty ?? false) {
              _bookings.remove(nightDate);
            }
            needsUpdate = true;
          } else {
            // Added or modified
            _bookings[nightDate] ??= {};
            _bookings[nightDate]![room] = Booking(
              bookingId: bookingModel.id ?? '',
              guestName: bookingModel.userName,
              color: Colors.blueAccent,
              isFirstNight: i == 0,
              isLastNight: i == totalNights - 1,
              totalNights: totalNights,
            );
            needsUpdate = true;
          }
        }
      }

      // Keep full booking model for edit: one entry per document
      final docId = change.doc.id;
      if (change.type == DocumentChangeType.removed) {
        _bookingModelsById.remove(docId);
      } else {
        _bookingModelsById[docId] = bookingModel;
      }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Text(
                        'Calendar',
                        style: Theme.of(context).textTheme.headlineLarge
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 34,
                            ),
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
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.search_rounded,
                                size: 18,
                                color: Colors.grey.shade600,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                DateFormat(
                                  'MMM d, yyyy',
                                ).format(_lastSearchedDate ?? _earliestDate),
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF007AFF).withOpacity(0.25),
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
                            backgroundColor: const Color(0xFF007AFF),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Calendar Grid
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
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
                                _updateSelection(cell['room']!, cell['date']!);
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
                              child: Column(
                                children: _dates.map((date) {
                                  final isToday = isSameDay(
                                    date,
                                    DateTime.now(),
                                  );
                                  return _buildDayRow(date, isToday);
                                }).toList(),
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
                          color: const Color(0xFFF9F9F9),
                          border: Border(
                            bottom: BorderSide(
                              color: Colors.grey.shade300,
                              width: 1,
                            ),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
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
                                color: const Color(0xFFEFEFF4),
                                border: Border(
                                  right: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                              ),
                              child: Center(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.hotel_rounded,
                                      size: 14,
                                      color: Color(0xFF007AFF),
                                    ),
                                    const SizedBox(width: 4),
                                    const Text(
                                      'Rooms',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        color: Color(0xFF007AFF),
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
                                  children: _rooms.map((room) {
                                    return Container(
                                      width: _roomColumnWidth,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        border: Border(
                                          right: BorderSide(
                                            color: Colors.white,
                                            width: 1,
                                          ),
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          'Room $room',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                            color: Colors.black87,
                                            letterSpacing: 0.3,
                                          ),
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
                        color: Colors.white,
                        child: ScrollConfiguration(
                          behavior: ScrollConfiguration.of(context).copyWith(
                            scrollbars: false,
                          ),
                          child: SingleChildScrollView(
                            controller: _stickyDayLabelsScrollController,
                            scrollDirection: Axis.vertical,
                            physics: const NeverScrollableScrollPhysics(),
                            child: Column(
                              children: _dates.map((date) {
                                final isToday = isSameDay(date, DateTime.now());
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
                          if (todayIndex == -1) return const SizedBox.shrink();

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
            const SizedBox(height: 24),
          ],
        ),
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF007AFF).withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: FloatingActionButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AddBookingPage()),
            ).then((bookingCreated) {
              if (bookingCreated == true) {
                _subscribeToBookings();
              }
            });
          },
          backgroundColor: const Color(0xFF007AFF),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
        ),
      ),
    );
  }

  Widget _buildDayRow(DateTime date, bool isToday) {
    return Container(
      height: _dayRowHeight, // Row height stays the same, gap is between rows
      decoration: BoxDecoration(
        color: isToday
            ? const Color(0xFF007AFF).withOpacity(0.05)
            : Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey.shade200, width: 1),
          bottom: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Spacer for sticky day label column
          SizedBox(width: _dayLabelWidth),
          // Room cells
          Row(
            children: _rooms.map((room) {
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
            child: Container(color: Colors.grey.shade200),
          ),

          // Background for the whole date row (filled, not rounded)
          Positioned.fill(
            child: Container(
              color: isToday
                  ? const Color(0xFF007AFF).withOpacity(0.08)
                  : Colors.white,
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
                        color: Colors.grey.shade600,
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
                            ? const Color(0xFF007AFF)
                            : Colors.black87,
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

    return GestureDetector(
      onTap: () {
        if (booking != null) {
          _showBookingDetails(context, room, date, booking);
        } else if (!_isSelecting) {
          // Single tap on empty cell - show quick booking dialog for one cell
          _showBookingDialog([room], [date], false);
        }
      },
      child: Container(
        width: _roomColumnWidth,
        height: _dayRowHeight,
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF007AFF).withOpacity(0.2)
              : Colors.white,
          border: Border(
            right: BorderSide(color: Colors.grey.shade200, width: 1),
            top: isSelected
                ? BorderSide(
                    color: const Color(0xFF007AFF).withOpacity(0.5),
                    width: 2,
                  )
                : BorderSide.none,
            bottom: isSelected
                ? BorderSide(
                    color: const Color(0xFF007AFF).withOpacity(0.5),
                    width: 2,
                  )
                : BorderSide.none,
            left: isSelected
                ? BorderSide(
                    color: const Color(0xFF007AFF).withOpacity(0.5),
                    width: 2,
                  )
                : BorderSide.none,
          ),
        ),
        child: Stack(
          children: [
            // Booking display
            if (booking != null)
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
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: booking.isFirstNight
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
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
            // Selection overlay
            if (isSelected && booking == null)
              Container(
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF).withOpacity(0.15),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showBookingDetails(
    BuildContext context,
    String room,
    DateTime date,
    Booking booking,
  ) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 340),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
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
                'Booking Details',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 17,
                      color: Colors.black,
                    ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _buildDetailRow(
                      Icons.person_rounded,
                      'Guest',
                      booking.guestName,
                    ),
                    const SizedBox(height: 12),
                    _buildDetailRow(
                      Icons.hotel_rounded,
                      'Room',
                      room,
                    ),
                    const SizedBox(height: 12),
                    _buildDetailRow(
                      Icons.calendar_today_rounded,
                      'Date',
                      DateFormat('MMM d, yyyy').format(date),
                    ),
                    const SizedBox(height: 12),
                    _buildDetailRow(
                      Icons.nightlight_round,
                      'Duration',
                      '${booking.totalNights} ${booking.totalNights == 1 ? 'night' : 'nights'}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    // Edit Button
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          final fullBooking =
                              _bookingModelsById[booking.bookingId];
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => AddBookingPage(
                                existingBooking: fullBooking,
                                preselectedRoom:
                                    fullBooking == null ? room : null,
                                preselectedStartDate:
                                    fullBooking?.checkIn ?? date,
                                preselectedEndDate: fullBooking?.checkOut ??
                                    date.add(
                                      Duration(days: booking.totalNights),
                                    ),
                                preselectedNumberOfRooms:
                                    fullBooking?.numberOfRooms ??
                                        booking.totalNights,
                              ),
                            ),
                          ).then((bookingCreated) {
                            if (bookingCreated == true) {
                              _subscribeToBookings();
                            }
                          });
                        },
                        icon: const Icon(Icons.edit_rounded, size: 18),
                        label: const Text('Edit Booking'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF007AFF),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Delete Button
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          final confirm = await _showDeleteConfirmation(context);
                          if (confirm != true) return;

                          try {
                            _showLoadingDialog(context);
                            await _deleteBooking(booking.bookingId);
                            if (mounted) Navigator.pop(context);
                          } catch (e) {
                            if (mounted) Navigator.pop(context);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to delete: $e'),
                                backgroundColor: Colors.red,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
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
                    // Close Button
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF007AFF),
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
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF007AFF).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 20,
              color: const Color(0xFF007AFF),
            ),
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
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
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
            color: const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
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
                      color: Colors.black,
                    ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'This will permanently delete the booking. This action cannot be undone.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
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
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF007AFF),
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
            color: const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF007AFF)),
              ),
              SizedBox(height: 16),
              Text(
                'Please wait...',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.black87,
                ),
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

    // Navigate to Add Booking page with preselected values
    Navigator.push(
      context,
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

class Booking {
  final String bookingId;
  final String guestName;
  final Color color;
  final bool isFirstNight;
  final bool isLastNight;
  final int totalNights;

  Booking({
    required this.bookingId,
    required this.guestName,
    required this.color,
    required this.isFirstNight,
    required this.isLastNight,
    required this.totalNights,
  });
}

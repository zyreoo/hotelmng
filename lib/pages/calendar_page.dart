import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

  // For infinite scroll
  DateTime _earliestDate = DateTime.now();
  int _totalDaysLoaded = 30;
  static const int _loadMoreDays = 30; // Load 30 more days when scrolling up
  bool _isLoadingMore = false;

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

  // Selection state for drag-and-drop booking
  String? _selectionStartRoom;
  DateTime? _selectionStartDate;
  String? _selectionEndRoom;
  DateTime? _selectionEndDate;
  bool _isSelecting = false;
  final GlobalKey _gridKey = GlobalKey();
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _roomHeadersScrollController = ScrollController();
  final ScrollController _stickyDayLabelsScrollController = ScrollController();

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

    // Adjust scroll position to maintain view after frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_verticalScrollController.hasClients) {
        // Use dayRowHeight for scroll offset
        final newOffset = currentOffset + (daysToAdd * _dayRowHeight);
        _verticalScrollController.jumpTo(newOffset);
        // Sticky day labels will be updated automatically by the listener
      }
    });

    // Load bookings for new dates - use the OLD earliestDate captured before update
    _loadBookingsForDateRange(newEarliestDate, oldEarliestDate);
  }

  void _loadBookingsForDateRange(DateTime startDate, DateTime endDate) {
    // TODO: Implement loading bookings from your data source (Firebase, etc.)
    // This is a placeholder - implement based on your actual data loading mechanism
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

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToDate(targetDate);
      });
      return;
    }

    // Calculate scroll position
    final daysFromStart = targetDate.difference(_earliestDate).inDays;
    if (daysFromStart >= 0 && daysFromStart < _totalDaysLoaded) {
      final targetOffset = daysFromStart * _dayRowHeight;
      _verticalScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  void dispose() {
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
      _isSelecting = true;
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

  void _endSelection() {
    if (_isSelecting &&
        _selectionStartRoom != null &&
        _selectionStartDate != null) {
      final selectedRooms = _getSelectedRooms();
      final selectedDates = _getSelectedDates();

      if (selectedRooms.isNotEmpty && selectedDates.isNotEmpty) {
        _showBookingDialog(selectedRooms, selectedDates);
      }

      setState(() {
        _isSelecting = false;
        _selectionStartRoom = null;
        _selectionStartDate = null;
        _selectionEndRoom = null;
        _selectionEndDate = null;
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
                      Text(
                        '${DateFormat('MMM d').format(_earliestDate)} - ${DateFormat('MMM d, yyyy').format(_dates.last)}',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () {
                          _scrollToDate(
                            _earliestDate.subtract(const Duration(days: 7)),
                          );
                        },
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF007AFF),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () {
                          _scrollToDate(
                            _earliestDate.add(const Duration(days: 7)),
                          );
                        },
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF007AFF),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.today),
                        onPressed: () {
                          _scrollToDate(DateTime.now());
                        },
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF007AFF),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Calendar Grid
            Expanded(
              child: Card(
                margin: const EdgeInsets.symmetric(horizontal: 24),
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
                          color: Colors.grey.shade50,
                          border: Border(
                            bottom: BorderSide(
                              color: Colors.grey.shade200,
                              width: 1,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            // Empty corner cell (fixed)
                            Container(
                              width: _dayLabelWidth,
                              height: _headerHeight,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                border: Border(
                                  right: BorderSide(
                                    color: Colors.grey.shade200,
                                  ),
                                ),
                              ),
                              child: const Center(
                                child: Text(
                                  'Rooms',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                    color: Color(0xFF007AFF),
                                  ),
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
                                            color: Colors.grey.shade200,
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
                        color: Colors.transparent,
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
                          // Position line inside the row (slightly below top, e.g., 8px down)
                          const lineOffsetInRow = 8.0; // Offset from top of row
                          final lineY =
                              _headerHeight +
                              (todayIndex * _dayRowHeight) +
                              lineOffsetInRow -
                              scrollOffset;

                          return Positioned(
                            top: lineY,
                            left: _dayLabelWidth, // Start after date column
                            right: 0,
                            height: 2,
                            child: Container(color: Colors.red),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddBookingPage()),
          ).then((bookingCreated) {
            if (bookingCreated == true) {
              // Refresh the calendar if booking was created
              setState(() {});
            }
          });
        },
        backgroundColor: const Color(0xFF007AFF),
        child: const Icon(Icons.add, color: Colors.white),
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

          // Pill positioned at the top of the row
          Positioned(
            top: 0,
            left: 8,
            right: 6,
            height: 34, // Fixed height for the pill
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white, // "cuts" the gridline
                borderRadius: BorderRadius.circular(10),
              ),
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
                          fontWeight: isToday
                              ? FontWeight.bold
                              : FontWeight.w600,
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
          _showBookingDialog([room], [date]);
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
                        ? const Radius.circular(4)
                        : Radius.zero,
                    right: booking.isLastNight
                        ? const Radius.circular(4)
                        : Radius.zero,
                  ),
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
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Room $room'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Guest: ${booking.guestName}'),
            const SizedBox(height: 8),
            Text('Duration: ${booking.totalNights} nights'),
            const SizedBox(height: 8),
            Text('Date: ${DateFormat('MMM d, yyyy').format(date)}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Delete booking logic
            },
            child: const Text(
              'Cancel Booking',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _showBookingDialog(List<String> rooms, List<DateTime> dates) {
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
  final String guestName;
  final Color color;
  final bool isFirstNight;
  final bool isLastNight;
  final int totalNights;

  Booking({
    required this.guestName,
    required this.color,
    required this.isFirstNight,
    required this.isLastNight,
    required this.totalNights,
  });
}

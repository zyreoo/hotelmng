import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'add_booking_page.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _startDate = DateTime.now();
  final int _daysToShow = 30; // Show 30 days
  final double _roomColumnWidth = 120.0;
  final double _dayRowHeight = 60.0;

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

  @override
  void initState() {
    super.initState();
    _initializeSampleBookings();
  }

  @override
  void dispose() {
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  void _initializeSampleBookings() {
    final now = DateTime.now();

    // Add some sample bookings
    _addBooking('101', now, 3, 'John Smith', const Color(0xFF007AFF));
    _addBooking(
      '102',
      now.add(const Duration(days: 2)),
      2,
      'Sarah Johnson',
      const Color(0xFF34C759),
    );
    _addBooking(
      '201',
      now.add(const Duration(days: 1)),
      4,
      'Mike Chen',
      const Color(0xFFFF9500),
    );
    _addBooking('203', now, 1, 'Emily Davis', const Color(0xFF5856D6));
    _addBooking(
      '301',
      now.add(const Duration(days: 5)),
      2,
      'David Wilson',
      const Color(0xFFFF2D55),
    );
    _addBooking(
      '104',
      now.add(const Duration(days: 3)),
      3,
      'Lisa Anderson',
      const Color(0xFF5AC8FA),
    );
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

    final minRoomIndex =
        startRoomIndex < endRoomIndex ? startRoomIndex : endRoomIndex;
    final maxRoomIndex =
        startRoomIndex > endRoomIndex ? startRoomIndex : endRoomIndex;
    
    // Normalize dates to midnight for comparison
    final minDate = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
    );
    final maxDate = DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
    );
    final currentDate = DateTime(
      date.year,
      date.month,
      date.day,
    );

    final roomInRange =
        currentRoomIndex >= minRoomIndex && currentRoomIndex <= maxRoomIndex;
    
    // Check if current date is within the selected date range
    final dateInRange = (currentDate.isAtSameMomentAs(minDate) ||
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

    final minDate = startDate.isBefore(endDate) ? startDate : endDate;
    final maxDate = startDate.isAfter(endDate) ? startDate : endDate;

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
    return List.generate(_daysToShow, (index) {
      return DateTime(
        _startDate.year,
        _startDate.month,
        _startDate.day,
      ).add(Duration(days: index));
    });
  }

  Map<String, dynamic>? _getCellFromPosition(Offset position) {
    // Account for scroll offsets
    final scrollX = _horizontalScrollController.hasClients
        ? _horizontalScrollController.offset
        : 0.0;
    final scrollY = _verticalScrollController.hasClients
        ? _verticalScrollController.offset
        : 0.0;

    // Account for the day label column (100px)
    final adjustedX = position.dx + scrollX;
    if (adjustedX < 100) {
      return null; // Clicked on day label column
    }

    // Calculate which room column
    final roomX = adjustedX - 100;
    final roomIndex = (roomX / _roomColumnWidth).floor();
    
    if (roomIndex < 0 || roomIndex >= _rooms.length) {
      return null;
    }

    // Calculate which day row
    final adjustedY = position.dy + scrollY;
    final dayIndex = (adjustedY / _dayRowHeight).floor();
    
    if (dayIndex < 0 || dayIndex >= _dates.length) {
      return null;
    }

    return {
      'room': _rooms[roomIndex],
      'date': _dates[dayIndex],
    };
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
                        '${DateFormat('MMM d').format(_startDate)} - ${DateFormat('MMM d, yyyy').format(_dates.last)}',
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
                          setState(() {
                            _startDate = _startDate.subtract(
                              const Duration(days: 7),
                            );
                          });
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
                          setState(() {
                            _startDate = _startDate.add(
                              const Duration(days: 7),
                            );
                          });
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
                          setState(() {
                            _startDate = DateTime.now();
                          });
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
                child: Column(
                  children: [
                    // Room headers row (sticky)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        border: Border(
                          bottom: BorderSide(color: Colors.grey.shade200, width: 1),
                        ),
                      ),
                      child: Row(
                        children: [
                          // Empty corner cell
                          Container(
                            width: 100,
                            height: 50,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              border: Border(
                                right: BorderSide(color: Colors.grey.shade200),
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
                          // Room headers
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
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

                    // Days and bookings grid
                    Expanded(
                      child: GestureDetector(
                        key: _gridKey,
                        onPanStart: (details) {
                          final cell = _getCellFromPosition(details.localPosition);
                          if (cell != null && _getBooking(cell['room']!, cell['date']!) == null) {
                            _startSelection(cell['room']!, cell['date']!);
                          }
                        },
                        onPanUpdate: (details) {
                          if (_isSelecting) {
                            final cell = _getCellFromPosition(details.localPosition);
                            if (cell != null && _getBooking(cell['room']!, cell['date']!) == null) {
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
                          child: SingleChildScrollView(
                            controller: _horizontalScrollController,
                            scrollDirection: Axis.horizontal,
                            child: Column(
                              children: _dates.map((date) {
                                final isToday = isSameDay(date, DateTime.now());
                                return _buildDayRow(date, isToday);
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
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
            MaterialPageRoute(
              builder: (context) => const AddBookingPage(),
            ),
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
      height: _dayRowHeight,
      decoration: BoxDecoration(
        color: isToday
            ? const Color(0xFF007AFF).withOpacity(0.05)
            : Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Day label (sticky)
          Container(
            width: 100,
            decoration: BoxDecoration(
              color: isToday
                  ? const Color(0xFF007AFF).withOpacity(0.1)
                  : Colors.grey.shade50,
              border: Border(
                right: BorderSide(color: Colors.grey.shade200, width: 1),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('EEE').format(date),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    DateFormat('MMM d').format(date),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isToday ? FontWeight.bold : FontWeight.w600,
                      color: isToday ? const Color(0xFF007AFF) : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ),
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
                    color: const Color(0xFF007AFF).withOpacity(0.5), width: 2)
                : BorderSide.none,
            bottom: isSelected
                ? BorderSide(
                    color: const Color(0xFF007AFF).withOpacity(0.5), width: 2)
                : BorderSide.none,
            left: isSelected
                ? BorderSide(
                    color: const Color(0xFF007AFF).withOpacity(0.5), width: 2)
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
    final endDate = dates.last.add(const Duration(days: 1)); // Check-out is the day after last night

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
    return a.year == b.year && a.month == b.month && a.day == b.day;
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

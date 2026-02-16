import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/booking_model.dart';
import '../services/firebase_service.dart';
import '../services/hotel_provider.dart';
import '../services/auth_provider.dart';
import '../utils/currency_formatter.dart';
import 'add_booking_page.dart';

class BookingsListPage extends StatefulWidget {
  const BookingsListPage({super.key});

  @override
  State<BookingsListPage> createState() => _BookingsListPageState();
}

class _BookingsListPageState extends State<BookingsListPage> {
  final FirebaseService _firebaseService = FirebaseService();
  final _searchController = TextEditingController();
  
  List<BookingModel> _allBookings = [];
  List<BookingModel> _filteredBookings = [];
  bool _loading = true;
  String? _error;
  
  String _selectedStatus = 'All';
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  
  static final List<String> _statusOptions = [
    'All',
    ...BookingModel.statusOptions,
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterBookings);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final hotelId = HotelProvider.of(context).hotelId;
    final userId = AuthScopeData.of(context).uid;
    if (hotelId != null && userId != null) _loadBookings(userId, hotelId);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadBookings(String userId, String hotelId) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final now = DateTime.now();
      final start = now.subtract(const Duration(days: 180));
      final end = now.add(const Duration(days: 365));
      final list = await _firebaseService.getBookings(
        userId,
        hotelId,
        startDate: start,
        endDate: end,
      );
      if (mounted) {
        setState(() {
          _allBookings = list;
          _filteredBookings = list;
          _loading = false;
        });
        _filterBookings();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _allBookings = [];
          _filteredBookings = [];
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  void _filterBookings() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      _filteredBookings = _allBookings.where((booking) {
        // Search filter
        final matchesSearch = query.isEmpty ||
            booking.userName.toLowerCase().contains(query) ||
            booking.userPhone.contains(query) ||
            (booking.userEmail?.toLowerCase().contains(query) ?? false);

        // Status filter
        final matchesStatus =
            _selectedStatus == 'All' || booking.status == _selectedStatus;

        // Date range filter
        bool matchesDateRange = true;
        if (_filterStartDate != null || _filterEndDate != null) {
          final checkIn = DateTime(
            booking.checkIn.year,
            booking.checkIn.month,
            booking.checkIn.day,
          );
          if (_filterStartDate != null && checkIn.isBefore(_filterStartDate!)) {
            matchesDateRange = false;
          }
          if (_filterEndDate != null && checkIn.isAfter(_filterEndDate!)) {
            matchesDateRange = false;
          }
        }

        return matchesSearch && matchesStatus && matchesDateRange;
      }).toList();

      // Sort by check-in date (most recent first)
      _filteredBookings.sort((a, b) => b.checkIn.compareTo(a.checkIn));
    });
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: _filterStartDate != null && _filterEndDate != null
          ? DateTimeRange(start: _filterStartDate!, end: _filterEndDate!)
          : null,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: const Color(0xFF007AFF),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.grey.shade900,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _filterStartDate = picked.start;
        _filterEndDate = picked.end;
      });
      _filterBookings();
    }
  }

  void _clearDateFilter() {
    setState(() {
      _filterStartDate = null;
      _filterEndDate = null;
    });
    _filterBookings();
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Confirmed':
        return const Color(0xFF34C759);
      case 'Pending':
        return const Color(0xFFFF9500);
      case 'Cancelled':
        return const Color(0xFFFF3B30);
      case 'Paid':
        return const Color(0xFF007AFF);
      case 'Unpaid':
        return const Color(0xFF8E8E93);
      case 'Waiting list':
        return const Color(0xFFAF52DE);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hotel = HotelProvider.of(context).currentHotel;
    final currencyFormatter = CurrencyFormatter.fromHotel(hotel);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Text(
                    'Bookings',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 34,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_filteredBookings.length} ${_filteredBookings.length == 1 ? 'booking' : 'bookings'}',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                  ),
                ],
              ),
            ),

            // Search & Filters
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                children: [
                  // Search bar
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search by name, phone, or email...',
                        hintStyle: TextStyle(color: Colors.grey.shade400),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: Colors.grey.shade400,
                        ),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(
                                  Icons.clear_rounded,
                                  color: Colors.grey.shade400,
                                ),
                                onPressed: () {
                                  _searchController.clear();
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Filter chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        // Status filter
                        _FilterChip(
                          label: _selectedStatus,
                          icon: Icons.filter_list_rounded,
                          onTap: () => _showStatusFilter(),
                        ),
                        const SizedBox(width: 8),

                        // Date range filter
                        _FilterChip(
                          label: _filterStartDate != null && _filterEndDate != null
                              ? '${DateFormat('MMM d').format(_filterStartDate!)} - ${DateFormat('MMM d').format(_filterEndDate!)}'
                              : 'Date range',
                          icon: Icons.calendar_today_rounded,
                          onTap: _selectDateRange,
                          onClear: _filterStartDate != null || _filterEndDate != null
                              ? _clearDateFilter
                              : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Bookings list
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _error!,
                              style: const TextStyle(color: Color(0xFFFF3B30)),
                            ),
                          ),
                        )
                      : _filteredBookings.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.search_off_rounded,
                                    size: 64,
                                    color: Colors.grey.shade300,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No bookings found',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Try adjusting your filters',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade400,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: () async {
                                final hotelId = HotelProvider.of(context).hotelId;
                                final userId = AuthScopeData.of(context).uid;
                                if (hotelId != null && userId != null) {
                                  await _loadBookings(userId, hotelId);
                                }
                              },
                              child: ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 8,
                                ),
                                itemCount: _filteredBookings.length,
                                itemBuilder: (context, index) {
                                  final booking = _filteredBookings[index];
                                  return _BookingCard(
                                    booking: booking,
                                    currencyFormatter: currencyFormatter,
                                    statusColor: _getStatusColor(booking.status),
                                    onTap: () => _openBooking(booking),
                                  );
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  void _showStatusFilter() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Filter by status',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ..._statusOptions.map((status) {
                  final isSelected = status == _selectedStatus;
                  return ListTile(
                    leading: Icon(
                      isSelected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: isSelected
                          ? const Color(0xFF007AFF)
                          : Colors.grey.shade400,
                    ),
                    title: Text(
                      status,
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected
                            ? const Color(0xFF007AFF)
                            : Colors.grey.shade900,
                      ),
                    ),
                    onTap: () {
                      setState(() => _selectedStatus = status);
                      _filterBookings();
                      Navigator.pop(context);
                    },
                  );
                }).toList(),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openBooking(BookingModel booking) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddBookingPage(existingBooking: booking),
      ),
    );
    // Reload bookings after editing
    final hotelId = HotelProvider.of(context).hotelId;
    final userId = AuthScopeData.of(context).uid;
    if (hotelId != null && userId != null) {
      _loadBookings(userId, hotelId);
    }
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _FilterChip({
    required this.label,
    required this.icon,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.grey.shade300,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: const Color(0xFF007AFF)),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF007AFF),
              ),
            ),
            if (onClear != null) ...[
              const SizedBox(width: 6),
              InkWell(
                onTap: onClear,
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  final BookingModel booking;
  final CurrencyFormatter currencyFormatter;
  final Color statusColor;
  final VoidCallback onTap;

  const _BookingCard({
    required this.booking,
    required this.currencyFormatter,
    required this.statusColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            booking.userName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            booking.userPhone,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        booking.status,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _InfoRow(
                        icon: Icons.calendar_today_rounded,
                        label: 'Check-in',
                        value: DateFormat('MMM d, y').format(booking.checkIn),
                      ),
                    ),
                    Expanded(
                      child: _InfoRow(
                        icon: Icons.calendar_today_rounded,
                        label: 'Check-out',
                        value: DateFormat('MMM d, y').format(booking.checkOut),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _InfoRow(
                        icon: Icons.bed_rounded,
                        label: 'Rooms',
                        value: '${booking.numberOfRooms}',
                      ),
                    ),
                    Expanded(
                      child: _InfoRow(
                        icon: Icons.people_rounded,
                        label: 'Guests',
                        value: '${booking.numberOfGuests}',
                      ),
                    ),
                  ],
                ),
                if (booking.amountOfMoneyPaid > 0) ...[
                  const SizedBox(height: 8),
                  _InfoRow(
                    icon: Icons.payments_rounded,
                    label: 'Paid',
                    value: currencyFormatter.formatCompact(
                      booking.amountOfMoneyPaid,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: Colors.grey.shade400,
        ),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

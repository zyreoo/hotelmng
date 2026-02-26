import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/booking_model.dart';
import '../services/firebase_service.dart';
import '../services/hotel_provider.dart';
import '../services/auth_provider.dart';
import '../utils/currency_formatter.dart';
import '../utils/stayora_colors.dart';
import '../widgets/app_notification.dart';
import '../widgets/loading_empty_states.dart';
import '../widgets/stayora_logo.dart';
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
  dynamic _bookingsSubscription;
  String? _subscribedUserId;
  String? _subscribedHotelId;
  
  String _selectedStatus = 'All';
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  String _sortBy = 'date'; // date, name, status, amount
  bool _sortAscending = false; // false = newest / highest first

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
    if (hotelId == null || userId == null) return;
    // Re-subscribe only when hotel or user changes.
    if (userId == _subscribedUserId && hotelId == _subscribedHotelId) return;
    _subscribedUserId = userId;
    _subscribedHotelId = hotelId;
    _bookingsSubscription?.cancel();
    final checkInAfter = DateTime.now().subtract(const Duration(days: 365));
    setState(() {
      _loading = true;
      _error = null;
    });
    _bookingsSubscription = _firebaseService
        .bookingsStream(userId, hotelId, checkInOnOrAfter: checkInAfter)
        .listen(
      (snapshot) {
        final list = snapshot.docs
            .map((doc) => BookingModel.fromFirestore(doc.data(), doc.id))
            .toList();
        if (mounted) {
          setState(() {
            _allBookings = list;
            _filteredBookings = list;
            _loading = false;
            _error = null;
          });
          _filterBookings();
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _allBookings = [];
            _filteredBookings = [];
            _loading = false;
            _error = e.toString();
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _bookingsSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadBookings(String userId, String hotelId) async {
    // Force a re-subscribe by clearing the cached IDs.
    _subscribedUserId = null;
    _subscribedHotelId = null;
    didChangeDependencies();
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

      // Sort
      final mult = _sortAscending ? 1 : -1;
      switch (_sortBy) {
        case 'date':
          _filteredBookings.sort((a, b) => mult * a.checkIn.compareTo(b.checkIn));
          break;
        case 'name':
          _filteredBookings.sort((a, b) => mult * a.userName.toLowerCase().compareTo(b.userName.toLowerCase()));
          break;
        case 'status':
          _filteredBookings.sort((a, b) => mult * a.status.compareTo(b.status));
          break;
        case 'amount':
          _filteredBookings.sort((a, b) => mult * a.amountOfMoneyPaid.compareTo(b.amountOfMoneyPaid));
          break;
        default:
          _filteredBookings.sort((a, b) => mult * a.checkIn.compareTo(b.checkIn));
      }
    });
  }

  Future<void> _updateBookingStatus(BookingModel booking, String newStatus) async {
    final userId = AuthScopeData.of(context).uid;
    final hotelId = HotelProvider.of(context).hotelId;
    if (userId == null || hotelId == null || booking.id == null) return;
    try {
      final updated = booking.copyWith(status: newStatus);
      await _firebaseService.updateBooking(userId, hotelId, updated);
      if (mounted) {
        showAppNotification(context, 'Status updated to $newStatus', type: AppNotificationType.success);
        await _loadBookings(userId, hotelId);
      }
    } catch (e) {
      if (mounted) {
        showAppNotification(context, 'Failed to update: $e', type: AppNotificationType.error);
      }
    }
  }

  void _showSortOptions() {
    final options = [
      ('date', 'Check-in date'),
      ('name', 'Guest name'),
      ('status', 'Status'),
      ('amount', 'Amount'),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha:0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Sort by',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _sortAscending = !_sortAscending;
                            _filterBookings();
                          });
                          Navigator.pop(context);
                        },
                        child: Text(_sortAscending ? 'Oldest first' : 'Newest first'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                ...options.map((opt) {
                  final (value, label) = opt;
                  final isSelected = _sortBy == value;
                  return ListTile(
                    leading: Icon(
                      isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                      color: isSelected ? StayoraLogo.stayoraBlue : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    title: Text(label),
                    onTap: () {
                      setState(() {
                        _sortBy = value;
                        _filterBookings();
                      });
                      Navigator.pop(context);
                    },
                  );
                }),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
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
        return child!;
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

  Color _getStatusColor(String status) => StayoraColors.forStatus(status);

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
                              ? Theme.of(context).colorScheme.onSurfaceVariant
                              : Theme.of(context).colorScheme.onSurfaceVariant,
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
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.shadow.withValues(alpha:0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search by name, phone, or email...',
                        hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(
                                  Icons.clear_rounded,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                        const SizedBox(width: 8),
                        // Sort
                        _FilterChip(
                          label: _sortBy == 'date'
                              ? 'Date'
                              : _sortBy == 'name'
                                  ? 'Name'
                                  : _sortBy == 'status'
                                      ? 'Status'
                                      : 'Amount',
                          icon: _sortAscending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                          onTap: _showSortOptions,
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
                  ? SkeletonListLoader(
                      itemCount: 8,
                      itemHeight: 140,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    )
                  : _error != null
                      ? ErrorStateWidget(
                          message: _error!,
                          onRetry: () {
                            final hotelId = HotelProvider.of(context).hotelId;
                            final userId = AuthScopeData.of(context).uid;
                            if (hotelId != null && userId != null) {
                              _loadBookings(userId, hotelId);
                            }
                          },
                        )
                      : _filteredBookings.isEmpty
                          ? const EmptyStateWidget(
                              icon: Icons.event_busy_rounded,
                              title: 'No bookings found',
                              subtitle: 'Try adjusting your filters or add a new booking',
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
                                    onStatusChange: (newStatus) => _updateBookingStatus(booking, newStatus),
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
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha:0.5),
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
                          ? StayoraColors.blue
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    title: Text(
                      status,
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected
                            ? StayoraColors.blue
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    onTap: () {
                      setState(() => _selectedStatus = status);
                      _filterBookings();
                      Navigator.pop(context);
                    },
                  );
                }),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openBooking(BookingModel booking) async {
    await Navigator.of(context, rootNavigator: false).push(
      MaterialPageRoute(
        builder: (context) => AddBookingPage(existingBooking: booking),
      ),
    );
    if (!mounted) return;
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
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha:0.5),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.shadow.withValues(alpha:0.03),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: StayoraColors.blue),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: StayoraColors.blue,
              ),
            ),
            if (onClear != null) ...[
              const SizedBox(width: 6),
              InkWell(
                onTap: onClear,
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Status chip that opens a menu via showMenu (avoids PopupMenuButton during hit-test).
class _StatusChipWithMenu extends StatelessWidget {
  final String label;
  final Color statusColor;
  final ValueChanged<String> onSelected;

  const _StatusChipWithMenu({
    required this.label,
    required this.statusColor,
    required this.onSelected,
  });

  Future<void> _showMenu(BuildContext context) async {
    // Defer menu open to avoid mouse_tracker assertion (!_debugDuringDeviceUpdate).
    await Future.delayed(const Duration(milliseconds: 100));
    if (!context.mounted) return;
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null || !context.mounted) return;
    final overlay = Navigator.of(context).overlay;
    if (overlay == null || !context.mounted) return;
    final RenderBox overlayBox = overlay.context.findRenderObject() as RenderBox;
    final position = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    final size = MediaQuery.sizeOf(context);
    final top = position.dy + box.size.height;
    final relativeRect = RelativeRect.fromLTRB(
      position.dx,
      top,
      size.width - position.dx,
      size.height - top,
    );
    final value = await showMenu<String>(
      context: context,
      position: relativeRect,
      items: BookingModel.statusOptions
          .map((status) => PopupMenuItem<String>(
                value: status,
                child: Text(status),
              ))
          .toList(),
    );
    if (value != null && context.mounted) {
      onSelected(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showMenu(context),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha:0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.arrow_drop_down_rounded, size: 18, color: statusColor),
            ],
          ),
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
  final ValueChanged<String>? onStatusChange;

  const _BookingCard({
    required this.booking,
    required this.currencyFormatter,
    required this.statusColor,
    required this.onTap,
    this.onStatusChange,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha:isDark ? 0.2 : 0.05),
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
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onStatusChange != null)
                      _StatusChipWithMenu(
                        label: booking.status,
                        statusColor: statusColor,
                        onSelected: onStatusChange!,
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha:0.1),
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
                    icon: currencyFormatter.currencyIcon,
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
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
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

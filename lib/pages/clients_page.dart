import 'package:flutter/material.dart';
import '../models/booking_model.dart';
import '../services/auth_provider.dart';
import '../services/hotel_provider.dart';
import '../services/firebase_service.dart';
import '../widgets/loading_empty_states.dart';
import '../utils/currency_formatter.dart';
import 'add_booking_page.dart';
import 'package:intl/intl.dart';

class ClientsPage extends StatefulWidget {
  const ClientsPage({super.key});

  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  List<BookingModel> _allBookings = [];
  List<_ClientData> _clients = [];
  List<_ClientData> _filteredClients = [];
  bool _loading = true;
  String? _error;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadData();
    });
  }

  Future<void> _loadData() async {
    final userId = AuthScopeData.of(context).uid;
    final hotelId = HotelProvider.of(context).hotelId;

    if (userId == null || hotelId == null) {
      setState(() {
        _loading = false;
        _error = 'User or hotel not found';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final bookings = await FirebaseService().getBookings(userId, hotelId);
      if (!mounted) return;
      _allBookings = bookings;
      _buildClientsList();
      setState(() {
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load clients: $e';
      });
    }
  }

  void _buildClientsList() {
    // Group bookings by client (using phone as unique identifier)
    final Map<String, List<BookingModel>> clientBookings = {};
    
    for (final booking in _allBookings) {
      final key = booking.userPhone;
      if (!clientBookings.containsKey(key)) {
        clientBookings[key] = [];
      }
      clientBookings[key]!.add(booking);
    }

    // Build client data
    _clients = clientBookings.entries.map((entry) {
      final bookings = entry.value;
      bookings.sort((a, b) => b.checkIn.compareTo(a.checkIn)); // Most recent first
      final totalSpent = bookings.fold<int>(
        0,
        (sum, b) => sum + b.amountOfMoneyPaid,
      );
      final totalBookings = bookings.length;
      final lastBooking = bookings.first;

      return _ClientData(
        name: lastBooking.userName,
        phone: lastBooking.userPhone,
        email: lastBooking.userEmail ?? '',
        totalBookings: totalBookings,
        totalSpent: totalSpent,
        lastCheckIn: lastBooking.checkIn,
        bookings: bookings,
      );
    }).toList();

    // Sort by last check-in (most recent first)
    _clients.sort((a, b) => b.lastCheckIn.compareTo(a.lastCheckIn));
    _applySearch();
  }

  void _applySearch() {
    if (_searchQuery.isEmpty) {
      _filteredClients = _clients;
    } else {
      final query = _searchQuery.toLowerCase();
      _filteredClients = _clients.where((client) {
        return client.name.toLowerCase().contains(query) ||
            client.phone.toLowerCase().contains(query) ||
            client.email.toLowerCase().contains(query);
      }).toList();
    }
  }

  Future<void> _updateBookingStatus(BookingModel booking, String newStatus) async {
    final userId = AuthScopeData.of(context).uid;
    final hotelId = HotelProvider.of(context).hotelId;
    if (userId == null || hotelId == null || booking.id == null) return;
    try {
      final updated = booking.copyWith(status: newStatus);
      await FirebaseService().updateBooking(userId, hotelId, updated);
      if (mounted) {
        await _loadData();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status updated to $newStatus'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF34C759),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFFF3B30),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hotel = HotelProvider.of(context).currentHotel;
    final currencyFormatter = CurrencyFormatter.fromHotel(hotel);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Text(
                    'Clients',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 34,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_clients.length} total clients',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 16),
                  // Search bar
                  TextField(
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                        _applySearch();
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Search by name, phone, or email',
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Clients list
            Expanded(
              child: _loading
                  ? SkeletonListLoader(
                      itemCount: 6,
                      itemHeight: 100,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    )
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
                      : _filteredClients.isEmpty
                          ? EmptyStateWidget(
                              icon: Icons.people_outline_rounded,
                              title: _searchQuery.isEmpty
                                  ? 'No clients yet'
                                  : 'No clients found',
                              subtitle: _searchQuery.isEmpty
                                  ? 'Add your first booking to see clients here'
                                  : 'Try a different search',
                            )
                          : RefreshIndicator(
                              onRefresh: _loadData,
                              child: ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                itemCount: _filteredClients.length,
                                itemBuilder: (context, index) {
                                  final client = _filteredClients[index];
                                  return _ClientCard(
                                    client: client,
                                    currencyFormatter: currencyFormatter,
                                    onTap: () => _showClientDetails(client),
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

  void _showClientDetails(_ClientData client) {
    final hotel = HotelProvider.of(context).currentHotel;
    final currencyFormatter = CurrencyFormatter.fromHotel(hotel);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: const Color(0xFF007AFF).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child: Center(
                            child: Text(
                              client.name.isNotEmpty ? client.name[0].toUpperCase() : '?',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF007AFF),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                client.name,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                client.phone,
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
                    if (client.email.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            Icons.email_outlined,
                            size: 16,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            client.email,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    // Stats
                    Row(
                      children: [
                        Expanded(
                          child: _StatBox(
                            label: 'Bookings',
                            value: '${client.totalBookings}',
                            isDark: isDark,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatBox(
                            label: 'Total Spent',
                            value: currencyFormatter.formatCompact(client.totalSpent),
                            isDark: isDark,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Bookings list
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: client.bookings.length,
                  itemBuilder: (context, index) {
                    final booking = client.bookings[index];
                    return _BookingListItem(
                      booking: booking,
                      currencyFormatter: currencyFormatter,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AddBookingPage(existingBooking: booking),
                          ),
                        ).then((_) => _loadData());
                      },
                      onStatusChange: (newStatus) async {
                        await _updateBookingStatus(booking, newStatus);
                        if (context.mounted) Navigator.pop(context);
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
}

class _ClientData {
  final String name;
  final String phone;
  final String email;
  final int totalBookings;
  final int totalSpent;
  final DateTime lastCheckIn;
  final List<BookingModel> bookings;

  _ClientData({
    required this.name,
    required this.phone,
    required this.email,
    required this.totalBookings,
    required this.totalSpent,
    required this.lastCheckIn,
    required this.bookings,
  });
}

class _ClientCard extends StatelessWidget {
  final _ClientData client;
  final CurrencyFormatter currencyFormatter;
  final VoidCallback onTap;

  const _ClientCard({
    required this.client,
    required this.currencyFormatter,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Center(
                  child: Text(
                    client.name.isNotEmpty ? client.name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF007AFF),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      client.name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      client.phone,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${client.totalBookings} booking${client.totalBookings != 1 ? 's' : ''} · ${currencyFormatter.formatCompact(client.totalSpent)}',
                      style: TextStyle(
                        color: const Color(0xFF007AFF),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;

  const _StatBox({
    required this.label,
    required this.value,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// Status chip that opens menu via showMenu to avoid hit-test assertion.
class _ClientBookingStatusChip extends StatelessWidget {
  final String status;
  final Color Function(String) getStatusColor;
  final ValueChanged<String> onSelected;

  const _ClientBookingStatusChip({
    required this.status,
    required this.getStatusColor,
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
    final size = MediaQuery.of(context).size;
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
          .map((s) => PopupMenuItem<String>(value: s, child: Text(s)))
          .toList(),
    );
    if (value != null && context.mounted) onSelected(value);
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = getStatusColor(status);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showMenu(context),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                status,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_down_rounded, size: 16, color: statusColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookingListItem extends StatelessWidget {
  final BookingModel booking;
  final CurrencyFormatter currencyFormatter;
  final VoidCallback onTap;
  final ValueChanged<String>? onStatusChange;

  const _BookingListItem({
    required this.booking,
    required this.currencyFormatter,
    required this.onTap,
    this.onStatusChange,
  });

  String _getStatusLabel(String status) {
    return status;
  }

  Color _getStatusColor(BuildContext context, String status) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    switch (status) {
      case 'Pending':
        return const Color(0xFFFF9500);
      case 'Confirmed':
        return const Color(0xFF007AFF);
      case 'Checked In':
        return const Color(0xFF34C759);
      case 'Checked Out':
        return muted;
      case 'Cancelled':
        return const Color(0xFFFF3B30);
      default:
        return muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
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
                      DateFormat('MMM d, yyyy').format(booking.checkIn),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (onStatusChange != null)
                    _ClientBookingStatusChip(
                      status: booking.status,
                      getStatusColor: (status) => _getStatusColor(context, status),
                      onSelected: onStatusChange!,
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getStatusColor(context, booking.status).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _getStatusLabel(booking.status),
                        style: TextStyle(
                          color: _getStatusColor(context, booking.status),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${DateFormat('MMM d').format(booking.checkIn)} - ${DateFormat('MMM d').format(booking.checkOut)}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Icon(
                    Icons.bed_rounded,
                    size: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${booking.numberOfRooms} room${booking.numberOfRooms != 1 ? 's' : ''}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                currencyFormatter.formatCompact(booking.amountOfMoneyPaid),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF007AFF),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

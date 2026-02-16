import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/booking_model.dart';
import '../services/firebase_service.dart';
import '../services/hotel_provider.dart';
import '../services/auth_provider.dart';
import '../utils/currency_formatter.dart';
import '../utils/money_input_formatter.dart';
import '../widgets/loading_empty_states.dart';
import 'add_booking_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final FirebaseService _firebaseService = FirebaseService();
  List<BookingModel> _bookings = [];
  bool _loading = true;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final hotelId = HotelProvider.of(context).hotelId;
    final userId = AuthScopeData.of(context).uid;
    if (hotelId != null && userId != null) _loadBookings(userId, hotelId);
  }

  Future<void> _loadBookings(String userId, String hotelId) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Wide range so we get all bookings overlapping "today" and this month
      final now = DateTime.now();
      final start = now.subtract(const Duration(days: 120));
      final end = now.add(const Duration(days: 60));
      final list = await _firebaseService.getBookings(
        userId,
        hotelId,
        startDate: start,
        endDate: end,
      );
      if (mounted) {
        setState(() {
          _bookings = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _bookings = [];
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  /// Bookings that are not cancelled.
  List<BookingModel> get _activeBookings =>
      _bookings.where((b) => b.status != 'Cancelled').toList();

  /// Bookings that actually occupy a room (excludes Cancelled and Waiting list).
  List<BookingModel> get _bookingsForOccupancy =>
      _bookings.where((b) =>
          b.status != 'Cancelled' && b.status != 'Waiting list').toList();

  /// True if [date] is >= checkIn (start of day) and < checkOut (start of day).
  bool _bookingOverlapsDate(BookingModel b, DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final checkIn = DateTime(b.checkIn.year, b.checkIn.month, b.checkIn.day);
    final checkOut = DateTime(
      b.checkOut.year,
      b.checkOut.month,
      b.checkOut.day,
    );
    return !d.isBefore(checkIn) && d.isBefore(checkOut);
  }

  /// Room-nights occupied on [date] (only counts bookings that occupy a room).
  int _occupiedRoomNightsOn(DateTime date) {
    return _bookingsForOccupancy
        .where((b) => _bookingOverlapsDate(b, date))
        .fold<int>(0, (sum, b) => sum + b.numberOfRooms);
  }

  /// Rooms occupied today.
  int get _occupiedToday => _occupiedRoomNightsOn(DateTime.now());

  /// Occupancy percentage today (0-100).
  int _occupancyPercentage(int totalRooms) {
    if (totalRooms <= 0) return 0;
    final occupied = _occupiedToday;
    return ((occupied / totalRooms) * 100).round();
  }

  /// Check-ins today (count of bookings where checkIn is today).
  int get _checkInsToday {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _activeBookings.where((b) {
      final ci = DateTime(b.checkIn.year, b.checkIn.month, b.checkIn.day);
      return ci == today;
    }).length;
  }

  /// Bookings checking in today.
  List<BookingModel> get _checkInsTodayList {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _activeBookings.where((b) {
      final ci = DateTime(b.checkIn.year, b.checkIn.month, b.checkIn.day);
      return ci == today;
    }).toList();
  }

  /// Bookings checking out today.
  List<BookingModel> get _checkOutsTodayList {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _activeBookings.where((b) {
      final co = DateTime(b.checkOut.year, b.checkOut.month, b.checkOut.day);
      return co == today;
    }).toList();
  }

  /// Bookings with advance payment pending (future check-in, advance required but not received).
  List<BookingModel> get _advancesPendingList {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _activeBookings.where((b) {
      final ci = DateTime(b.checkIn.year, b.checkIn.month, b.checkIn.day);
      final isFuture = !ci.isBefore(today);
      final hasAdvanceRequired =
          b.advancePercent != null && b.advancePercent! > 0;
      final notReceived = b.advancePaymentStatus != 'paid';
      return isFuture && hasAdvanceRequired && notReceived;
    }).toList();
  }

  /// Total revenue: sum of "amount paid" for all non-cancelled bookings (in loaded range).
  int get _revenueTotal =>
      _activeBookings.fold<int>(0, (sum, b) => sum + b.amountOfMoneyPaid);

  /// Revenue this month: sum of "amount paid" for bookings whose check-in is in the current month.
  int get _revenueThisMonth {
    final now = DateTime.now();
    return _activeBookings
        .where(
          (b) => b.checkIn.year == now.year && b.checkIn.month == now.month,
        )
        .fold<int>(0, (sum, b) => sum + b.amountOfMoneyPaid);
  }

  /// Last 7 days: room-nights per day (index 0 = oldest).
  List<int> get _weeklyOccupancyRoomNights {
    final now = DateTime.now();
    return List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      return _occupiedRoomNightsOn(d);
    });
  }

  /// Max Y for weekly chart: at least 1 or totalRooms so scale is meaningful.
  double _weeklyChartMaxY(int totalRooms) {
    final list = _weeklyOccupancyRoomNights;
    if (list.isEmpty) return (totalRooms > 0 ? totalRooms : 10).toDouble();
    final m = list.reduce((a, b) => a > b ? a : b);
    final cap = totalRooms > 0 ? totalRooms : 10;
    return (m > cap ? m : cap).toDouble();
  }

  /// First and last day of the weekly range (last 7 days).
  DateTime get _weeklyStartDate =>
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)
          .subtract(const Duration(days: 6));
  DateTime get _weeklyEndDate => DateTime.now();

  Future<void> _showMarkAdvanceReceivedSheet(BookingModel booking) async {
    final userId = AuthScopeData.of(context).uid;
    final hotelId = HotelProvider.of(context).hotelId;
    if (userId == null || hotelId == null || booking.id == null) return;

    final amountController = TextEditingController(
      text: CurrencyFormatter.formatCentsForInput(booking.advanceAmountRequired),
    );
    String paymentMethod = booking.advancePaymentMethod ?? BookingModel.paymentMethods.first;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Mark advance received',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                booking.userName,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [MoneyInputFormatter()],
                decoration: InputDecoration(
                  labelText: 'Amount received',
                  hintText: 'e.g. 50.00',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: paymentMethod,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                items: BookingModel.paymentMethods
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (v) => paymentMethod = v ?? paymentMethod,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF34C759),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Mark received'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (result == true) {
      final amountCents = CurrencyFormatter.parseMoneyStringToCents(
        amountController.text.trim().isEmpty ? '0' : amountController.text.trim(),
      );
      final updated = booking.copyWith(
        advanceStatus: 'received',
        advanceAmountPaid: amountCents,
        advancePaymentMethod: paymentMethod,
      );
      try {
        await _firebaseService.updateBooking(userId, hotelId, updated);
        if (mounted) {
          await _loadBookings(userId, hotelId);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Advance marked as received'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFF34C759),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      }
    }
  }

  Widget _buildWeeklyOccupancyCard({
    required List<int> weekDays,
    required double maxY,
    int? totalRooms,
  }) {
    final start = _weeklyStartDate;
    final end = _weeklyEndDate;
    final dateRangeStr =
        '${DateFormat('d MMM').format(start)} – ${DateFormat('d MMM').format(end)}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Weekly occupancy',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Last 7 days · Room-nights per day · $dateRangeStr',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxY,
                  minY: 0,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i >= 0 && i < 7) {
                            final d = DateTime.now()
                                .subtract(Duration(days: 6 - i));
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                DateFormat('d/M').format(d),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: maxY > 10 ? (maxY / 5).ceilToDouble() : 1,
                        getTitlesWidget: (value, meta) {
                          final v = value.toInt();
                          if (v != value || v < 0) return const SizedBox.shrink();
                          return Text(
                            v.toString(),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(7, (i) {
                    final y = weekDays[i].toDouble();
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: y,
                          fromY: 0,
                          color: const Color(0xFF007AFF),
                          width: 20,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ],
                      showingTooltipIndicators: [],
                    );
                  }),
                ),
                duration: const Duration(milliseconds: 300),
              ),
            ),
            if (totalRooms != null && totalRooms > 0) ...[
              const SizedBox(height: 8),
              Text(
                'Capacity: $totalRooms rooms',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hotelId = HotelProvider.of(context).hotelId;
    final userId = AuthScopeData.of(context).uid;
    
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            if (hotelId != null && userId != null) {
              await _loadBookings(userId, hotelId);
            }
          },
          child: CustomScrollView(
            slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      'Dashboard',
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(fontWeight: FontWeight.bold, fontSize: 34),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Overview of your hotel',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.symmetric(
                horizontal: MediaQuery.of(context).size.width >= 768 ? 24 : 16,
              ),
              sliver: _loading
                  ? SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SkeletonListLoader(
                          itemCount: 5,
                          itemHeight: 140,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    )
                  : _error != null
                  ? SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Color(0xFFFF3B30)),
                        ),
                      ),
                    )
                  : _bookings.isEmpty
                  ? SliverFillRemaining(
                      child: EmptyStateWidget(
                        icon: Icons.event_available_rounded,
                        title: 'No bookings yet',
                        subtitle: 'Add your first booking to see your dashboard',
                      ),
                    )
                  : SliverToBoxAdapter(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final isMobile = constraints.maxWidth < 600;
                          final weekDays = _weeklyOccupancyRoomNights;
                          final hotel = HotelProvider.of(context).currentHotel;
                          final currencyFormatter = CurrencyFormatter.fromHotel(
                            hotel,
                          );

                          return Column(
                            children: [
                              // Reminders Section
                              if (_checkInsTodayList.isNotEmpty ||
                                  _checkOutsTodayList.isNotEmpty ||
                                  _advancesPendingList.isNotEmpty) ...[
                                _RemindersCard(
                                  checkInsToday: _checkInsTodayList,
                                  checkOutsToday: _checkOutsTodayList,
                                  advancesPending: _advancesPendingList,
                                  currencyFormatter: currencyFormatter,
                                  onBookingTap: (booking) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => AddBookingPage(
                                          existingBooking: booking,
                                        ),
                                      ),
                                    ).then((_) {
                                      final hotelId = HotelProvider.of(
                                        context,
                                      ).hotelId;
                                      final userId = AuthScopeData.of(
                                        context,
                                      ).uid;
                                      if (hotelId != null && userId != null) {
                                        _loadBookings(userId, hotelId);
                                      }
                                    });
                                  },
                                  onMarkAdvanceReceived: _showMarkAdvanceReceivedSheet,
                                ),
                                const SizedBox(height: 24),
                              ],

                              // Stats Cards Grid
                              if (isMobile) ...[
                                _StatCard(
                                  title: 'Occupied today',
                                  value: '$_occupiedToday / ${hotel?.totalRooms ?? 0}',
                                  icon: Icons.bed_rounded,
                                  color: const Color(0xFF34C759),
                                  trend: 'rooms',
                                ),
                                const SizedBox(height: 12),
                                _StatCard(
                                  title: 'Occupancy rate',
                                  value: '${_occupancyPercentage(hotel?.totalRooms ?? 10)}%',
                                  icon: Icons.pie_chart_rounded,
                                  color: const Color(0xFF007AFF),
                                  trend: 'today',
                                ),
                                const SizedBox(height: 12),
                                _StatCard(
                                  title: 'Check-ins today',
                                  value: '$_checkInsToday',
                                  icon: Icons.login_rounded,
                                  color: const Color(0xFFFF9500),
                                  trend: 'bookings',
                                ),
                                const SizedBox(height: 12),
                                _StatCard(
                                  title: 'Revenue this month',
                                  value: currencyFormatter.formatCompact(
                                    _revenueThisMonth,
                                  ),
                                  icon: Icons.attach_money_rounded,
                                  color: const Color(0xFF5856D6),
                                  trend:
                                      'sum of amount paid (check-in this month)',
                                ),
                                const SizedBox(height: 12),
                                _StatCard(
                                  title: 'Total revenue',
                                  value: currencyFormatter.formatCompact(
                                    _revenueTotal,
                                  ),
                                  icon: Icons.account_balance_wallet_rounded,
                                  color: const Color(0xFF007AFF),
                                  trend: 'sum of amount paid (all bookings)',
                                ),
                              ] else ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: _StatCard(
                                        title: 'Occupied today',
                                        value: '$_occupiedToday / ${hotel?.totalRooms ?? 0}',
                                        icon: Icons.bed_rounded,
                                        color: const Color(0xFF34C759),
                                        trend: 'rooms',
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: _StatCard(
                                        title: 'Occupancy rate',
                                        value: '${_occupancyPercentage(hotel?.totalRooms ?? 10)}%',
                                        icon: Icons.pie_chart_rounded,
                                        color: const Color(0xFF007AFF),
                                        trend: 'today',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _StatCard(
                                        title: 'Check-ins today',
                                        value: '$_checkInsToday',
                                        icon: Icons.login_rounded,
                                        color: const Color(0xFFFF9500),
                                        trend: 'bookings',
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Container(),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _StatCard(
                                        title: 'Revenue this month',
                                        value: currencyFormatter.formatCompact(
                                          _revenueThisMonth,
                                        ),
                                        icon: Icons.attach_money_rounded,
                                        color: const Color(0xFF5856D6),
                                        trend:
                                            'sum of amount paid (check-in this month)',
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: _StatCard(
                                        title: 'Total revenue',
                                        value: currencyFormatter.formatCompact(
                                          _revenueTotal,
                                        ),
                                        icon: Icons
                                            .account_balance_wallet_rounded,
                                        color: const Color(0xFF007AFF),
                                        trend:
                                            'sum of amount paid (all bookings)',
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 24),

                              // Weekly occupancy (room-nights per day)
                              _buildWeeklyOccupancyCard(
                                weekDays: weekDays,
                                maxY: _weeklyChartMaxY(hotel?.totalRooms ?? 10),
                                totalRooms: hotel?.totalRooms,
                              ),
                              const SizedBox(height: 24),
                            ],
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String trend;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.trend,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SizedBox(
                  width: 36,
                  height: 36,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    trend,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _RemindersCard extends StatelessWidget {
  final List<BookingModel> checkInsToday;
  final List<BookingModel> checkOutsToday;
  final List<BookingModel> advancesPending;
  final CurrencyFormatter currencyFormatter;
  final Function(BookingModel) onBookingTap;
  final Future<void> Function(BookingModel)? onMarkAdvanceReceived;

  const _RemindersCard({
    required this.checkInsToday,
    required this.checkOutsToday,
    required this.advancesPending,
    required this.currencyFormatter,
    required this.onBookingTap,
    this.onMarkAdvanceReceived,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9500).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.notifications_active_rounded,
                    color: Color(0xFFFF9500),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Today\'s Reminders',
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Check-ins today
            if (checkInsToday.isNotEmpty) ...[
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 20,
                    decoration: BoxDecoration(
                      color: const Color(0xFF34C759),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Check-ins today (${checkInsToday.length})',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...checkInsToday.take(3).map((booking) {
                return _ReminderItem(
                  booking: booking,
                  currencyFormatter: currencyFormatter,
                  onTap: () => onBookingTap(booking),
                  subtitle:
                      '${booking.numberOfRooms} room(s) · ${booking.numberOfGuests} guest(s)',
                );
              }),
              if (checkInsToday.length > 3) ...[
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    '+ ${checkInsToday.length - 3} more',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],

            // Divider between sections
            if (checkInsToday.isNotEmpty && (checkOutsToday.isNotEmpty || advancesPending.isNotEmpty)) ...[
              const SizedBox(height: 20),
              Divider(height: 1, color: Theme.of(context).dividerColor),
              const SizedBox(height: 20),
            ],

            // Check-outs today
            if (checkOutsToday.isNotEmpty) ...[
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 20,
                    decoration: BoxDecoration(
                      color: const Color(0xFF007AFF),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Check-outs today (${checkOutsToday.length})',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...checkOutsToday.take(3).map((booking) {
                return _ReminderItem(
                  booking: booking,
                  currencyFormatter: currencyFormatter,
                  onTap: () => onBookingTap(booking),
                  subtitle:
                      '${booking.numberOfRooms} room(s) · ${booking.numberOfGuests} guest(s)',
                );
              }),
              if (checkOutsToday.length > 3) ...[
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    '+ ${checkOutsToday.length - 3} more',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],

            // Divider between sections
            if (checkOutsToday.isNotEmpty && advancesPending.isNotEmpty) ...[
              const SizedBox(height: 20),
              Divider(height: 1, color: Theme.of(context).dividerColor),
              const SizedBox(height: 20),
            ],

            // Advances pending
            if (advancesPending.isNotEmpty) ...[
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 20,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9500),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Advance payments pending (${advancesPending.length})',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...advancesPending.take(3).map((booking) {
                return _ReminderItem(
                  booking: booking,
                  currencyFormatter: currencyFormatter,
                  onTap: () => onBookingTap(booking),
                  subtitle:
                      'Due: ${currencyFormatter.formatCompact(booking.advanceAmountRequired)} · Check-in ${DateFormat('MMM d').format(booking.checkIn)}',
                  showWarning: true,
                  onMarkAdvanceReceived: onMarkAdvanceReceived != null
                      ? () => onMarkAdvanceReceived!(booking)
                      : null,
                );
              }),
              if (advancesPending.length > 3) ...[
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    '+ ${advancesPending.length - 3} more',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _ReminderItem extends StatelessWidget {
  final BookingModel booking;
  final CurrencyFormatter currencyFormatter;
  final VoidCallback onTap;
  final String subtitle;
  final bool showWarning;
  final VoidCallback? onMarkAdvanceReceived;

  const _ReminderItem({
    required this.booking,
    required this.currencyFormatter,
    required this.onTap,
    required this.subtitle,
    this.showWarning = false,
    this.onMarkAdvanceReceived,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: showWarning
            ? const Color(0xFFFF9500).withOpacity(0.05)
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: showWarning
              ? const Color(0xFFFF9500).withOpacity(0.2)
              : colorScheme.outline.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        booking.userName,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              if (showWarning && onMarkAdvanceReceived != null) ...[
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: TextButton(
                    onPressed: onMarkAdvanceReceived,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF34C759),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Mark received'),
                  ),
                ),
              ],
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

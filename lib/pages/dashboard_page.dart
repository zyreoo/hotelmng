import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/booking_model.dart';
import '../services/firebase_service.dart';
import '../services/hotel_provider.dart';
import '../services/auth_provider.dart';
import '../utils/currency_formatter.dart';
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

  /// Room-nights occupied on [date].
  int _occupiedRoomNightsOn(DateTime date) {
    return _activeBookings
        .where((b) => _bookingOverlapsDate(b, date))
        .fold<int>(0, (sum, b) => sum + b.numberOfRooms);
  }

  /// Rooms occupied today.
  int get _occupiedToday => _occupiedRoomNightsOn(DateTime.now());

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

  /// Bookings with advance payment pending (future check-in, advance required but not received).
  List<BookingModel> get _advancesPendingList {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _activeBookings.where((b) {
      final ci = DateTime(b.checkIn.year, b.checkIn.month, b.checkIn.day);
      final isFuture = !ci.isBefore(today);
      final hasAdvanceRequired = b.advancePercent != null && b.advancePercent! > 0;
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

  /// Average occupancy % for the week if we had total rooms; we don't, so show max room-nights for scale.
  int get _weeklyMaxRoomNights {
    final list = _weeklyOccupancyRoomNights;
    if (list.isEmpty) return 10;
    final m = list.reduce((a, b) => a > b ? a : b);
    return m > 0 ? m : 10;
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
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
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
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
                  ? const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(48),
                        child: Center(child: CircularProgressIndicator()),
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
                  : SliverToBoxAdapter(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final isMobile = constraints.maxWidth < 600;
                          final weekDays = _weeklyOccupancyRoomNights;
                          final maxY = _weeklyMaxRoomNights.toDouble();
                          final hotel = HotelProvider.of(context).currentHotel;
                          final currencyFormatter = CurrencyFormatter.fromHotel(hotel);

                          return Column(
                            children: [
                              // Reminders Section
                              if (_checkInsTodayList.isNotEmpty || _advancesPendingList.isNotEmpty) ...[
                                _RemindersCard(
                                  checkInsToday: _checkInsTodayList,
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
                                      // Reload after editing
                                      final hotelId = HotelProvider.of(context).hotelId;
                                      final userId = AuthScopeData.of(context).uid;
                                      if (hotelId != null && userId != null) {
                                        _loadBookings(userId, hotelId);
                                      }
                                    });
                                  },
                                ),
                                const SizedBox(height: 24),
                              ],

                              // Stats Cards Grid
                              if (isMobile) ...[
                                _StatCard(
                                  title: 'Occupied today',
                                  value: '$_occupiedToday',
                                  icon: Icons.bed_rounded,
                                  color: const Color(0xFF34C759),
                                  trend: 'rooms',
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
                                  value: currencyFormatter.formatCompact(_revenueThisMonth),
                                  icon: Icons.attach_money_rounded,
                                  color: const Color(0xFF5856D6),
                                  trend:
                                      'sum of amount paid (check-in this month)',
                                ),
                                const SizedBox(height: 12),
                                _StatCard(
                                  title: 'Total revenue',
                                  value: currencyFormatter.formatCompact(_revenueTotal),
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
                                        value: '$_occupiedToday',
                                        icon: Icons.bed_rounded,
                                        color: const Color(0xFF34C759),
                                        trend: 'rooms',
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: _StatCard(
                                        title: 'Check-ins today',
                                        value: '$_checkInsToday',
                                        icon: Icons.login_rounded,
                                        color: const Color(0xFFFF9500),
                                        trend: 'bookings',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _StatCard(
                                        title: 'Revenue this month',
                                        value: currencyFormatter.formatCompact(_revenueThisMonth),
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
                                        value: currencyFormatter.formatCompact(_revenueTotal),
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
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'Weekly occupancy',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleLarge
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(
                                                0xFF007AFF,
                                              ).withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              'Room-nights',
                                              style: TextStyle(
                                                color: Colors.grey.shade600,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 24),
                                      SizedBox(
                                        height: 200,
                                        child: LineChart(
                                          LineChartData(
                                            gridData: FlGridData(
                                              show: true,
                                              drawVerticalLine: false,
                                              getDrawingHorizontalLine:
                                                  (value) {
                                                    return FlLine(
                                                      color:
                                                          Colors.grey.shade200,
                                                      strokeWidth: 1,
                                                    );
                                                  },
                                            ),
                                            titlesData: FlTitlesData(
                                              show: true,
                                              rightTitles: const AxisTitles(
                                                sideTitles: SideTitles(
                                                  showTitles: false,
                                                ),
                                              ),
                                              topTitles: const AxisTitles(
                                                sideTitles: SideTitles(
                                                  showTitles: false,
                                                ),
                                              ),
                                              bottomTitles: AxisTitles(
                                                sideTitles: SideTitles(
                                                  showTitles: true,
                                                  reservedSize: 30,
                                                  getTitlesWidget: (value, meta) {
                                                    final now = DateTime.now();
                                                    final d = now.subtract(
                                                      Duration(
                                                        days: 6 - value.toInt(),
                                                      ),
                                                    );
                                                    const days = [
                                                      'Mon',
                                                      'Tue',
                                                      'Wed',
                                                      'Thu',
                                                      'Fri',
                                                      'Sat',
                                                      'Sun',
                                                    ];
                                                    final i =
                                                        d.weekday; // 1=Mon
                                                    if (value.toInt() >= 0 &&
                                                        value.toInt() < 7) {
                                                      return Padding(
                                                        padding:
                                                            const EdgeInsets.only(
                                                              top: 8.0,
                                                            ),
                                                        child: Text(
                                                          days[i - 1],
                                                          style: TextStyle(
                                                            color: Colors
                                                                .grey
                                                                .shade600,
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                    return const Text('');
                                                  },
                                                ),
                                              ),
                                              leftTitles: AxisTitles(
                                                sideTitles: SideTitles(
                                                  showTitles: true,
                                                  reservedSize: 32,
                                                  getTitlesWidget:
                                                      (value, meta) {
                                                        return Text(
                                                          value
                                                              .toInt()
                                                              .toString(),
                                                          style: TextStyle(
                                                            color: Colors
                                                                .grey
                                                                .shade600,
                                                            fontSize: 12,
                                                          ),
                                                        );
                                                      },
                                                ),
                                              ),
                                            ),
                                            borderData: FlBorderData(
                                              show: false,
                                            ),
                                            minX: 0,
                                            maxX: 6,
                                            minY: 0,
                                            maxY: maxY,
                                            lineBarsData: [
                                              LineChartBarData(
                                                spots: List.generate(
                                                  7,
                                                  (i) => FlSpot(
                                                    i.toDouble(),
                                                    weekDays[i].toDouble(),
                                                  ),
                                                ),
                                                isCurved: true,
                                                color: const Color(0xFF007AFF),
                                                barWidth: 3,
                                                isStrokeCapRound: true,
                                                dotData: FlDotData(
                                                  show: true,
                                                  getDotPainter:
                                                      (
                                                        spot,
                                                        percent,
                                                        barData,
                                                        index,
                                                      ) {
                                                        return FlDotCirclePainter(
                                                          radius: 4,
                                                          color: Colors.white,
                                                          strokeWidth: 2,
                                                          strokeColor:
                                                              const Color(
                                                                0xFF007AFF,
                                                              ),
                                                        );
                                                      },
                                                ),
                                                belowBarData: BarAreaData(
                                                  show: true,
                                                  color: const Color(
                                                    0xFF007AFF,
                                                  ).withOpacity(0.1),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
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
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                Text(
                  trend,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
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
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

class _RemindersCard extends StatelessWidget {
  final List<BookingModel> checkInsToday;
  final List<BookingModel> advancesPending;
  final CurrencyFormatter currencyFormatter;
  final Function(BookingModel) onBookingTap;

  const _RemindersCard({
    required this.checkInsToday,
    required this.advancesPending,
    required this.currencyFormatter,
    required this.onBookingTap,
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
                Text(
                  'Today\'s Reminders',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
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
                  Text(
                    'Check-ins today (${checkInsToday.length})',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade900,
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
                  subtitle: '${booking.numberOfRooms} room(s) · ${booking.numberOfGuests} guest(s)',
                );
              }),
              if (checkInsToday.length > 3) ...[
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    '+ ${checkInsToday.length - 3} more',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],

            // Divider between sections
            if (checkInsToday.isNotEmpty && advancesPending.isNotEmpty) ...[
              const SizedBox(height: 20),
              Divider(height: 1, color: Colors.grey.shade200),
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
                  Text(
                    'Advance payments pending (${advancesPending.length})',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade900,
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
                  subtitle: 'Due: ${currencyFormatter.formatCompact(booking.advanceAmountRequired)} · Check-in ${DateFormat('MMM d').format(booking.checkIn)}',
                  showWarning: true,
                );
              }),
              if (advancesPending.length > 3) ...[
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    '+ ${advancesPending.length - 3} more',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
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

  const _ReminderItem({
    required this.booking,
    required this.currencyFormatter,
    required this.onTap,
    required this.subtitle,
    this.showWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: showWarning
            ? const Color(0xFFFF9500).withOpacity(0.05)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: showWarning
              ? const Color(0xFFFF9500).withOpacity(0.2)
              : Colors.grey.shade200,
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        booking.userName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.grey.shade400,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

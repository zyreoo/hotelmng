import 'package:flutter/material.dart';
import '../services/auth_provider.dart';
import '../services/hotel_provider.dart';
import '../widgets/stayora_logo.dart';
import '../pages/login_page.dart';
import '../pages/hotel_setup_page.dart';
import '../pages/dashboard_page.dart';
import '../pages/calendar_page.dart';
import '../pages/bookings_list_page.dart';
import '../pages/clients_page.dart';
import '../pages/employees_page.dart';
import '../pages/schedule.dart';
import '../pages/add_booking_page.dart';
import '../pages/settings_page.dart';
import '../pages/room_management_page.dart';
import '../pages/services_page.dart';
import '../pages/housekeeping_page.dart';
import '../pages/tasks_page.dart';

/// Wraps [child] with [HotelProvider] only when the user is logged in.
class WrapHotelWhenLoggedIn extends StatelessWidget {
  const WrapHotelWhenLoggedIn({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final auth = AuthScopeData.of(context);
    if (auth.authChecked && auth.user != null) {
      return HotelProvider(child: child);
    }
    return child;
  }
}

/// Shows a loading spinner until auth is resolved, then routes to login or the app.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthScopeData.of(context);
    if (!auth.authChecked) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (auth.user == null) return const LoginPage();
    return const _HotelGate();
  }
}

class _HotelGate extends StatelessWidget {
  const _HotelGate();

  @override
  Widget build(BuildContext context) {
    final hotel = HotelProvider.of(context).currentHotel;
    if (hotel == null) return const HotelSetupPage();
    return const MainNavigationScreen();
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;

  final List<GlobalKey<NavigatorState>> _navigatorKeys =
      List.generate(13, (_) => GlobalKey<NavigatorState>());

  /// Titles for pages reachable from the More menu (indices 4–12).
  static const List<String> _menuPageTitles = [
    'Clients',
    'Calendar',
    'Employees',
    'Shifts',
    'Settings',
    'Rooms',
    'Services',
    'Housekeeping',
    'Tasks',
  ];

  List<Widget> _buildPageList(bool isDesktop) {
    final onMoreSelect = (int index) => setState(() => _selectedIndex = index);
    final raw = <Widget>[
      const DashboardPage(),
      const AddBookingPage(),
      const BookingsListPage(),
      _MoreMenuPage(onSelect: onMoreSelect),
      const ClientsPage(),
      const CalendarPage(),
      const EmployeesPage(),
      const SchedulePage(),
      const SettingsPage(),
      const RoomManagementPage(),
      const ServicesPage(),
      const HousekeepingPage(),
      const TasksPage(),
    ];
    if (isDesktop) return raw;
    // On mobile, wrap menu pages (4–12) with an AppBar that has a back arrow to More.
    return List.generate(13, (i) {
      if (i >= 4 && i <= 12) {
        return _MobileBackToMenuWrapper(
          title: _menuPageTitles[i - 4],
          onBack: () => setState(() => _selectedIndex = 3),
          child: raw[i],
        );
      }
      return raw[i];
    });
  }

  static const List<_NavItem> _navItems = [
    _NavItem(Icons.dashboard_rounded, 'Dashboard'),
    _NavItem(Icons.add_circle_outline_rounded, 'Add Booking'),
    _NavItem(Icons.list_alt_rounded, 'Bookings'),
    _NavItem(Icons.calendar_month_rounded, 'Calendar'),
    _NavItem(Icons.person_rounded, 'Clients'),
    _NavItem(Icons.people_rounded, 'Employees'),
    _NavItem(Icons.schedule_rounded, 'Shifts'),
    _NavItem(Icons.task_alt_rounded, 'Tasks'),
    _NavItem(Icons.settings_rounded, 'Settings'),
    _NavItem(Icons.meeting_room_rounded, 'Rooms'),
    _NavItem(Icons.room_service_rounded, 'Services'),
    _NavItem(Icons.cleaning_services_rounded, 'Housekeeping'),
  ];

  static const List<int> _navIndexToPageIndex = [0, 1, 2, 5, 4, 6, 7, 12, 8, 9, 10, 11];

  static const List<_NavItem> _mobileNavItems = [
    _NavItem(Icons.dashboard_rounded, 'Dashboard'),
    _NavItem(Icons.add_circle_outline_rounded, 'Add Booking'),
    _NavItem(Icons.list_alt_rounded, 'Bookings'),
    _NavItem(Icons.menu_rounded, 'More'),
  ];

  int _mobileBarIndexToPageIndex(int barIndex) =>
      barIndex <= 2 ? barIndex : 3;

  int _pageIndexToMobileBarIndex(int pageIndex) =>
      pageIndex <= 2 ? pageIndex : 3;


  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 768;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    final pageList = _buildPageList(isDesktop);
    final tabStack = IndexedStack(
      index: _selectedIndex,
      children: List.generate(13, (i) {
        return Navigator(
          key: _navigatorKeys[i],
          initialRoute: '/',
          onGenerateRoute: (settings) {
            if (settings.name == '/') {
              return MaterialPageRoute<void>(builder: (_) => pageList[i]);
            }
            return null;
          },
        );
      }),
    );

    return Scaffold(
      body: isDesktop
          ? Row(
              children: [
                _DesktopSidebar(
                  navItems: _navItems,
                  navIndexToPageIndex: _navIndexToPageIndex,
                  selectedIndex: _selectedIndex,
                  isDark: isDark,
                  colorScheme: colorScheme,
                  onSelect: (i) => setState(() => _selectedIndex = i),
                ),
                Expanded(child: tabStack),
              ],
            )
          : tabStack,
      drawer: isDesktop ? null : const Drawer(child: _SignOutDrawer()),
      bottomNavigationBar: isDesktop
          ? null
          // iOS-style: thin hairline top border, no shadow, no pill indicator.
          : DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: isDark
                        ? Colors.white.withOpacity(0.12)
                        : Colors.black.withOpacity(0.10),
                    width: 0.5,
                  ),
                ),
              ),
              child: NavigationBar(
                selectedIndex: _pageIndexToMobileBarIndex(_selectedIndex),
                onDestinationSelected: (i) => setState(
                  () => _selectedIndex = _mobileBarIndexToPageIndex(i),
                ),
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                destinations: _mobileNavItems
                    .map((item) => NavigationDestination(
                          icon: Icon(item.icon),
                          label: item.label,
                        ))
                    .toList(),
              ),
            ),
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.navItems,
    required this.navIndexToPageIndex,
    required this.selectedIndex,
    required this.isDark,
    required this.colorScheme,
    required this.onSelect,
  });

  final List<_NavItem> navItems;
  final List<int> navIndexToPageIndex;
  final int selectedIndex;
  final bool isDark;
  final ColorScheme colorScheme;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(isDark ? 0.3 : 0.05),
            blurRadius: 10,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 4),
              child: StayoraLogo(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            Builder(builder: (context) {
              final hotel = HotelProvider.of(context).currentHotel;
              if (hotel == null) return const SizedBox(height: 12);
              return Padding(
                padding: const EdgeInsets.fromLTRB(24, 2, 24, 12),
                child: Row(
                  children: [
                    Icon(Icons.hotel_rounded,
                        size: 13, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        hotel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: navItems.length,
                itemBuilder: (context, index) {
                  final pageIndex = navIndexToPageIndex[index];
                  return _SidebarNavItem(
                    item: navItems[index],
                    isSelected: selectedIndex == pageIndex,
                    isDark: isDark,
                    colorScheme: colorScheme,
                    onTap: () => onSelect(pageIndex),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: _SignOutTile(),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarNavItem extends StatelessWidget {
  const _SidebarNavItem({
    required this.item,
    required this.isSelected,
    required this.isDark,
    required this.colorScheme,
    required this.onTap,
  });

  final _NavItem item;
  final bool isSelected;
  final bool isDark;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const blue = StayoraLogo.stayoraBlue;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? blue.withOpacity(isDark ? 0.2 : 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              item.icon,
              color: isSelected ? blue : colorScheme.onSurfaceVariant,
              size: 24,
            ),
            const SizedBox(width: 12),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? blue : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Apple Settings-style "More" screen.
///
/// Layout mirrors iOS Settings.app:
///  • page background: #F2F2F7 (light) / pure black (dark)
///  • groups: white (light) / #1C1C1E (dark) rounded-12 cards
///  • each row: 32×32 colored rounded-square icon + label + chevron
///  • inset hairline divider between rows (starts after the icon)
class _MoreMenuPage extends StatelessWidget {
  const _MoreMenuPage({required this.onSelect});
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = AuthScopeData.of(context);
    final hotel = HotelProvider.of(context).currentHotel;

    const bookingNavItems = <_MoreItem>[
      _MoreItem(Icons.calendar_month_rounded, 'Calendar',          5, Color(0xFFFF3B30)),
      _MoreItem(Icons.person_rounded,         'Clients',           4, Color(0xFF34C759)),
      _MoreItem(Icons.people_rounded,         'Employees',         6, Color(0xFFFF9500)),
      _MoreItem(Icons.schedule_rounded,       'Shifts',            7, Color(0xFFAF52DE)),
      _MoreItem(Icons.task_alt_rounded,       'Tasks',            12, Color(0xFF5AC8FA)),
    ];

    const hotelNavItems = <_MoreItem>[
      _MoreItem(Icons.meeting_room_rounded,        'Rooms',        9,  Color(0xFF007AFF)),
      _MoreItem(Icons.room_service_rounded,        'Services',    10,  Color(0xFF30B0C7)),
      _MoreItem(Icons.cleaning_services_rounded,   'Housekeeping',11,  Color(0xFF64D2FF)),
    ];

    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFF2F2F7),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // ── Large iOS-style title + hotel name ───────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Text(
                'More',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            if (hotel != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Row(
                  children: [
                    Icon(Icons.hotel_rounded,
                        size: 14, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(
                      hotel.name,
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              )
            else
              const SizedBox(height: 16),

            // ── Booking & People group ────────────────────────────────
            _IosGroupCard(
              isDark: isDark,
              children: [
                for (int i = 0; i < bookingNavItems.length; i++) ...[
                  _IosMenuRow(
                    item: bookingNavItems[i],
                    colorScheme: colorScheme,
                    onTap: () => onSelect(bookingNavItems[i].pageIndex),
                  ),
                  if (i < bookingNavItems.length - 1)
                    _IosInsetDivider(isDark: isDark),
                ],
              ],
            ),

            const SizedBox(height: 12),

            // ── Hotel management group ────────────────────────────────
            _IosGroupCard(
              isDark: isDark,
              children: [
                for (int i = 0; i < hotelNavItems.length; i++) ...[
                  _IosMenuRow(
                    item: hotelNavItems[i],
                    colorScheme: colorScheme,
                    onTap: () => onSelect(hotelNavItems[i].pageIndex),
                  ),
                  if (i < hotelNavItems.length - 1)
                    _IosInsetDivider(isDark: isDark),
                ],
              ],
            ),

            const SizedBox(height: 12),

            // ── Settings group ───────────────────────────────────────
            _IosGroupCard(
              isDark: isDark,
              children: [
                _IosMenuRow(
                  item: const _MoreItem(
                    Icons.settings_rounded,
                    'Settings',
                    8,
                    Color(0xFF8E8E93),
                  ),
                  colorScheme: colorScheme,
                  onTap: () => onSelect(8),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Sign out group ───────────────────────────────────────
            _IosGroupCard(
              isDark: isDark,
              children: [
                InkWell(
                  onTap: () async => auth.signOut(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF3B30),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.logout_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Text(
                          'Sign Out',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                            color: Color(0xFFFF3B30),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ── iOS grouped card ─────────────────────────────────────────────────────────

/// Data class for a More-menu row.
class _MoreItem {
  final IconData icon;
  final String label;
  final int pageIndex;
  final Color iconColor;
  const _MoreItem(this.icon, this.label, this.pageIndex, this.iconColor);
}

/// White / dark rounded-12 card that wraps a list of rows (iOS grouped style).
class _IosGroupCard extends StatelessWidget {
  const _IosGroupCard({required this.isDark, required this.children});

  final bool isDark;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ColoredBox(
          color: bg,
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}

/// One row inside a [_IosGroupCard]: coloured icon badge · title · chevron.
class _IosMenuRow extends StatelessWidget {
  const _IosMenuRow({
    required this.item,
    required this.colorScheme,
    required this.onTap,
  });

  final _MoreItem item;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            // Coloured rounded-square icon badge (like iOS Settings)
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: item.iconColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(item.icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: colorScheme.onSurfaceVariant.withOpacity(0.45),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

/// Inset hairline separator that starts after the icon badge (iOS-style).
class _IosInsetDivider extends StatelessWidget {
  const _IosInsetDivider({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 0.5,
      thickness: 0.5,
      // 16 (h-padding) + 32 (icon) + 14 (gap) = 62
      indent: 62,
      endIndent: 0,
      color: isDark
          ? Colors.white.withOpacity(0.12)
          : Colors.black.withOpacity(0.10),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem(this.icon, this.label);
}

class _SignOutTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final auth = AuthScopeData.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(Icons.logout_rounded,
          color: colorScheme.onSurfaceVariant, size: 24),
      title: Text(
        'Sign out',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      onTap: () async => auth.signOut(),
    );
  }
}

class _SignOutDrawer extends StatelessWidget {
  const _SignOutDrawer();

  @override
  Widget build(BuildContext context) {
    final auth = AuthScopeData.of(context);
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: StayoraLogo(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout_rounded),
            title: const Text('Sign out'),
            onTap: () async {
              Navigator.of(context).pop();
              await auth.signOut();
            },
          ),
        ],
      ),
    );
  }
}

/// On mobile, wraps a page (opened from the More menu) in a [Scaffold] with an
/// [AppBar] that has a back arrow returning to the More menu.
class _MobileBackToMenuWrapper extends StatelessWidget {
  const _MobileBackToMenuWrapper({
    required this.title,
    required this.onBack,
    required this.child,
  });

  final String title;
  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: onBack,
          tooltip: 'Back to More',
          style: IconButton.styleFrom(
            foregroundColor: colorScheme.primary,
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      body: child,
    );
  }
}

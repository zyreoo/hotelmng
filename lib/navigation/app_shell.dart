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
      List.generate(9, (_) => GlobalKey<NavigatorState>());

  List<Widget> get _pages {
    final onMoreSelect = (int index) => setState(() => _selectedIndex = index);
    return [
      const DashboardPage(),
      const AddBookingPage(),
      const BookingsListPage(),
      _MoreMenuPage(onSelect: onMoreSelect),
      const ClientsPage(),
      const CalendarPage(),
      const EmployeesPage(),
      const SchedulePage(),
      const SettingsPage(),
    ];
  }

  static const List<_NavItem> _navItems = [
    _NavItem(Icons.dashboard_rounded, 'Dashboard'),
    _NavItem(Icons.add_circle_outline_rounded, 'Add Booking'),
    _NavItem(Icons.list_alt_rounded, 'Bookings'),
    _NavItem(Icons.calendar_month_rounded, 'Calendar'),
    _NavItem(Icons.person_rounded, 'Clients'),
    _NavItem(Icons.people_rounded, 'Employees'),
    _NavItem(Icons.schedule_rounded, 'Shifts'),
    _NavItem(Icons.settings_rounded, 'Settings'),
  ];

  static const List<int> _navIndexToPageIndex = [0, 1, 2, 5, 4, 6, 7, 8];

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

    final tabStack = IndexedStack(
      index: _selectedIndex,
      children: List.generate(9, (i) {
        return Navigator(
          key: _navigatorKeys[i],
          initialRoute: '/',
          onGenerateRoute: (settings) {
            if (settings.name == '/') {
              return MaterialPageRoute<void>(builder: (_) => _pages[i]);
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
          : NavigationBar(
              selectedIndex: _pageIndexToMobileBarIndex(_selectedIndex),
              onDestinationSelected: (i) =>
                  setState(() => _selectedIndex = _mobileBarIndexToPageIndex(i)),
              labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
              destinations: _mobileNavItems
                  .map((item) => NavigationDestination(
                        icon: Icon(item.icon),
                        label: item.label,
                      ))
                  .toList(),
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
              padding: const EdgeInsets.all(24.0),
              child: StayoraLogo(fontSize: 22, fontWeight: FontWeight.bold),
            ),
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

class _MoreMenuPage extends StatelessWidget {
  const _MoreMenuPage({required this.onSelect});
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final items = [
      const _NavItem(Icons.calendar_month_rounded, 'Calendar', 5),
      const _NavItem(Icons.person_rounded, 'Clients', 4),
      const _NavItem(Icons.people_rounded, 'Employees', 6),
      const _NavItem(Icons.schedule_rounded, 'Shifts', 7),
      const _NavItem(Icons.settings_rounded, 'Settings', 8),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('More'),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: items
              .map((item) => ListTile(
                    leading: Icon(item.icon,
                        color: StayoraLogo.stayoraBlue, size: 24),
                    title: Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    trailing: Icon(Icons.chevron_right_rounded,
                        color: colorScheme.onSurfaceVariant, size: 24),
                    onTap: () => onSelect(item.pageIndex),
                  ))
              .toList(),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final int pageIndex;
  const _NavItem(this.icon, this.label, [this.pageIndex = -1]);
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

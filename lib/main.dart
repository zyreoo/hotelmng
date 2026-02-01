import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'services/auth_provider.dart';
import 'services/hotel_provider.dart';
import 'pages/login_page.dart';
import 'pages/hotel_setup_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/calendar_page.dart';
import 'pages/employees_page.dart';
import 'pages/add_booking_page.dart';
import 'pages/schedule.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase with generated options
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('Firebase initialized successfully');
  } catch (e) {
    // Firebase not configured yet - app will still run
    debugPrint('Firebase not initialized: $e');
  }

  runApp(const HotelManagementApp());
}

class HotelManagementApp extends StatelessWidget {
  const HotelManagementApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthProvider(
      child: _WrapHotelWhenLoggedIn(
        child: MaterialApp(
          title: 'Hotel Management',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            scaffoldBackgroundColor: const Color(0xFFF5F5F7),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF007AFF),
              brightness: Brightness.light,
            ),
            cardTheme: const CardThemeData(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
              color: Colors.white,
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFFF5F5F7),
              elevation: 0,
              centerTitle: false,
            ),
          ),
          home: const _AuthGate(),
        ),
      ),
    );
  }
}

/// When user is logged in, wraps [child] (MaterialApp) with [HotelProvider] so
/// all routes (including pushed pages like AddEmployeePage) have access to it.
class _WrapHotelWhenLoggedIn extends StatelessWidget {
  const _WrapHotelWhenLoggedIn({required this.child});
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

/// Shows login when not signed in; when signed in, shows hotel gate or main app.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = AuthScopeData.of(context);
    if (!auth.authChecked) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F5F7),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (auth.user == null) {
      return const LoginPage();
    }
    return const _HotelGate();
  }
}

/// Shows hotel setup when no hotel is selected; otherwise shows main app.
class _HotelGate extends StatelessWidget {
  const _HotelGate();

  @override
  Widget build(BuildContext context) {
    final scope = HotelProvider.of(context);
    final hotel = scope.currentHotel;
    if (hotel == null) {
      return const HotelSetupPage();
    }
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

  final List<Widget> _pages = const [
    DashboardPage(),
    AddBookingPage(),
    CalendarPage(),
    EmployeesPage(),
    SchedulePage(),
  ];

  final List<_NavItem> _navItems = const [
    _NavItem(Icons.dashboard_rounded, 'Dashboard'),
    _NavItem(Icons.add_circle_outline_rounded, 'Add Booking'),
    _NavItem(Icons.calendar_month_rounded, 'Calendar'),
    _NavItem(Icons.people_rounded, 'Employees'),
    _NavItem(Icons.schedule_rounded, 'Schedule'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 768;

    return Scaffold(
      body: isDesktop
          ? Row(
              children: [
                // Left Sidebar Navigation (Desktop)
                Container(
                  width: 240,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(2, 0),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // App Logo/Title
                        Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF007AFF),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.hotel_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Hotel Management',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        const SizedBox(height: 8),

                        // Navigation Items
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            itemCount: _navItems.length,
                            itemBuilder: (context, index) {
                              return _buildNavItem(_navItems[index], index);
                            },
                          ),
                        ),
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: _SignOutTile(),
                        ),
                      ],
                    ),
                  ),
                ),

                // Main Content Area
                Expanded(child: _pages[_selectedIndex]),
              ],
            )
          : _pages[_selectedIndex], // Mobile: full screen
      drawer: isDesktop ? null : const Drawer(child: _SignOutDrawer()),
      // Bottom Navigation Bar (Mobile)
      bottomNavigationBar: isDesktop
          ? null
          : Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: List.generate(
                      _navItems.length,
                      (index) => _buildBottomNavItem(_navItems[index], index),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildNavItem(_NavItem item, int index) {
    final isSelected = _selectedIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedIndex = index),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF007AFF).withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              item.icon,
              color: isSelected
                  ? const Color(0xFF007AFF)
                  : Colors.grey.shade600,
              size: 24,
            ),
            const SizedBox(width: 12),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected
                    ? const Color(0xFF007AFF)
                    : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavItem(_NavItem item, int index) {
    final isSelected = _selectedIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedIndex = index),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              item.icon,
              color: isSelected
                  ? const Color(0xFF007AFF)
                  : Colors.grey.shade600,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected
                    ? const Color(0xFF007AFF)
                    : Colors.grey.shade600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
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
    return ListTile(
      leading: Icon(Icons.logout_rounded, color: Colors.grey.shade600, size: 24),
      title: Text(
        'Sign out',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: Colors.grey.shade700,
        ),
      ),
      onTap: () async {
        await auth.signOut();
      },
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
            child: Text(
              'Account',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
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

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'firebase_options.dart';
import 'services/auth_provider.dart';
import 'services/hotel_provider.dart';
import 'services/theme_provider.dart';
import 'pages/login_page.dart';
import 'pages/hotel_setup_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/calendar_page.dart';
import 'pages/bookings_list_page.dart';
import 'pages/employees_page.dart';
import 'pages/add_booking_page.dart';
import 'pages/settings_page.dart';

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

  // Required for DateFormat with locale (e.g. calendar waiting list, date pickers)
  await initializeDateFormatting('en');

  runApp(const HotelManagementApp());
}

class HotelManagementApp extends StatelessWidget {
  const HotelManagementApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthProvider(
      child: ThemeProvider(
        child: _WrapHotelWhenLoggedIn(
          child: _MaterialAppWithTheme(),
        ),
      ),
    );
  }
}

class _MaterialAppWithTheme extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final themeMode = ThemeProvider.of(context).themeMode;

    return MaterialApp(
      title: 'Hotel Management',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      home: const _AuthGate(),
    );
  }

  ThemeData _buildLightTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF007AFF),
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFFF5F5F7),
      
      // Cards with frosted glass effect
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        color: Colors.white,
        shadowColor: Colors.black.withOpacity(0.05),
      ),
      
      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFFF5F5F7),
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
      ),
      
      // Navigation Bar (Material 3)
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: colorScheme.primary.withOpacity(0.12),
        labelTextStyle: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
            );
          }
          return const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
          );
        }),
        iconTheme: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return IconThemeData(color: colorScheme.primary);
          }
          return IconThemeData(color: Colors.grey.shade600);
        }),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 65,
      ),
      
      // Divider
      dividerTheme: DividerThemeData(
        color: Colors.grey.shade200,
        thickness: 1,
        space: 1,
      ),
      
      // Text theme with proper contrast
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          color: Colors.black87,
        ),
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0A84FF),
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFF000000),
      
      // Cards with elevated surface
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        color: const Color(0xFF1C1C1E),
        shadowColor: Colors.black.withOpacity(0.3),
      ),
      
      // AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF000000),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      
      // Navigation Bar (Material 3) - elevated surface
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF1C1C1E),
        indicatorColor: colorScheme.primary.withOpacity(0.2),
        labelTextStyle: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            );
          }
          return TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade400,
          );
        }),
        iconTheme: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return IconThemeData(color: colorScheme.primary);
          }
          return IconThemeData(color: Colors.grey.shade500);
        }),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 65,
      ),
      
      // Divider with better contrast
      dividerTheme: const DividerThemeData(
        color: Color(0xFF2C2C2E),
        thickness: 1,
        space: 1,
      ),
      
      // Text theme with proper contrast for dark mode
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          color: Color(0xFFE5E5E7),
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
    BookingsListPage(),
    CalendarPage(),
    EmployeesPage(),
    SettingsPage(),
  ];

  final List<_NavItem> _navItems = const [
    _NavItem(Icons.dashboard_rounded, 'Dashboard'),
    _NavItem(Icons.add_circle_outline_rounded, 'Add Booking'),
    _NavItem(Icons.list_alt_rounded, 'Bookings'),
    _NavItem(Icons.calendar_month_rounded, 'Calendar'),
    _NavItem(Icons.people_rounded, 'Employees'),
    _NavItem(Icons.settings_rounded, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 768;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: isDesktop
          ? Row(
              children: [
                // Left Sidebar Navigation (Desktop)
                Container(
                  width: 240,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
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
                                  color: colorScheme.primary,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.hotel_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Hotel Management',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black,
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
      // Bottom Navigation Bar (Mobile) - Using Material 3 NavigationBar
      bottomNavigationBar: isDesktop
          ? null
          : NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) {
                setState(() => _selectedIndex = index);
              },
              destinations: _navItems.map((item) {
                return NavigationDestination(
                  icon: Icon(item.icon),
                  label: item.label,
                );
              }).toList(),
            ),
    );
  }

  Widget _buildNavItem(_NavItem item, int index) {
    final isSelected = _selectedIndex == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    
    return InkWell(
      onTap: () => setState(() => _selectedIndex = index),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primary.withOpacity(isDark ? 0.2 : 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              item.icon,
              color: isSelected
                  ? colorScheme.primary
                  : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
              size: 24,
            ),
            const SizedBox(width: 12),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected
                    ? colorScheme.primary
                    : (isDark ? Colors.grey.shade300 : Colors.grey.shade700),
              ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return ListTile(
      leading: Icon(
        Icons.logout_rounded,
        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
        size: 24,
      ),
      title: Text(
        'Sign out',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
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

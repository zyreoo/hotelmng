import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'firebase_options.dart';
import 'services/auth_provider.dart';
import 'services/hotel_provider.dart';
import 'services/theme_provider.dart';
import 'widgets/stayora_logo.dart';
import 'pages/login_page.dart';
import 'pages/hotel_setup_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/calendar_page.dart';
import 'pages/bookings_list_page.dart';
import 'pages/clients_page.dart';
import 'pages/employees_page.dart';
import 'pages/schedule.dart';
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
      title: 'STAYORA',
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
    final base = GoogleFonts.interTextTheme();
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFFF5F5F7),
      textTheme: base.copyWith(
        displayLarge: base.displayLarge?.copyWith(fontWeight: FontWeight.bold),
        displayMedium: base.displayMedium?.copyWith(fontWeight: FontWeight.bold),
        displaySmall: base.displaySmall?.copyWith(fontWeight: FontWeight.bold),
        headlineLarge: base.headlineLarge?.copyWith(
          fontSize: 34,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
        headlineMedium: base.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
        headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
        titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        titleSmall: base.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        bodyLarge: base.bodyLarge?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
        bodyMedium: base.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        bodySmall: base.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        labelMedium: base.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        labelSmall: base.labelSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
      
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
      
      // Navigation Bar (Material 3) - use Stayora blue for selected state
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: StayoraLogo.stayoraBlue.withOpacity(0.12),
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
            return const IconThemeData(color: StayoraLogo.stayoraBlue);
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
      
    );
  }

  ThemeData _buildDarkTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF007AFF),
      brightness: Brightness.dark,
      surface: const Color(0xFF1C1C1E),
    );
    final base = GoogleFonts.interTextTheme(ThemeData.dark().textTheme);
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFF000000),
      textTheme: base.copyWith(
        displayLarge: base.displayLarge?.copyWith(fontWeight: FontWeight.bold),
        displayMedium: base.displayMedium?.copyWith(fontWeight: FontWeight.bold),
        displaySmall: base.displaySmall?.copyWith(fontWeight: FontWeight.bold),
        headlineLarge: base.headlineLarge?.copyWith(
          fontSize: 34,
          fontWeight: FontWeight.bold,
          color: colorScheme.onSurface,
        ),
        headlineMedium: base.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
        headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
        titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        titleSmall: base.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        bodyLarge: base.bodyLarge?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
        bodyMedium: base.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
        bodySmall: base.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurfaceVariant,
        ),
        labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        labelMedium: base.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        labelSmall: base.labelSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
      
      // Cards - use surface so they're clearly visible
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        color: colorScheme.surface,
        shadowColor: Colors.black.withOpacity(0.3),
      ),
      
      // AppBar - black background, white text
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFF000000),
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.bold,
          color: colorScheme.onSurface,
        ),
        iconTheme: IconThemeData(color: colorScheme.onSurface),
      ),
      
      // Input fields - dark fill, white/light text
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF2C2C2E),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withOpacity(0.7)),
      ),
      
      // Navigation Bar (Material 3) - elevated surface, Stayora blue for selected
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: StayoraLogo.stayoraBlue.withOpacity(0.2),
        labelTextStyle: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            );
          }
          return TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: colorScheme.onSurfaceVariant,
          );
        }),
        iconTheme: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return const IconThemeData(color: StayoraLogo.stayoraBlue);
          }
          return IconThemeData(color: colorScheme.onSurfaceVariant);
        }),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 65,
      ),
      
      // Divider
      dividerTheme: DividerThemeData(
        color: colorScheme.outline.withOpacity(0.3),
        thickness: 1,
        space: 1,
      ),
      
      // ListTile / list items
      listTileTheme: ListTileThemeData(
        textColor: colorScheme.onSurface,
        iconColor: colorScheme.onSurfaceVariant,
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
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
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

  /// Desktop: 8 pages. Mobile: 9 pages (Dashboard, Add Booking, Bookings, More menu, Clients, Calendar, Employees, Schedule, Settings).
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

  /// Full nav items for desktop sidebar (8 items), ordered by importance: core actions first, then calendar/clients, then staff, then settings.
  final List<_NavItem> _navItems = const [
    _NavItem(Icons.dashboard_rounded, 'Dashboard'),
    _NavItem(Icons.add_circle_outline_rounded, 'Add Booking'),
    _NavItem(Icons.list_alt_rounded, 'Bookings'),
    _NavItem(Icons.calendar_month_rounded, 'Calendar'),
    _NavItem(Icons.person_rounded, 'Clients'),
    _NavItem(Icons.people_rounded, 'Employees'),
    _NavItem(Icons.schedule_rounded, 'Shifts'),
    _NavItem(Icons.settings_rounded, 'Settings'),
  ];

  /// Page index for each sidebar item (matches reordered nav: 0,1,2 = Dashboard, Add Booking, Bookings; then Calendar=5, Clients=4, Employees=6, Shifts=7, Settings=8).
  static const List<int> _navIndexToPageIndex = [0, 1, 2, 5, 4, 6, 7, 8];

  /// Mobile bottom bar: 4 items (Dashboard, Add Booking, Bookings, More).
  static const List<_NavItem> _mobileNavItems = [
    _NavItem(Icons.dashboard_rounded, 'Dashboard'),
    _NavItem(Icons.add_circle_outline_rounded, 'Add Booking'),
    _NavItem(Icons.list_alt_rounded, 'Bookings'),
    _NavItem(Icons.menu_rounded, 'More'),
  ];

  /// Map mobile bar index (0–3) to page index (0–8). Bar 3 = More menu (page 3); from More we go to 4–8.
  int _mobileBarIndexToPageIndex(int barIndex) {
    if (barIndex <= 2) return barIndex;
    return 3; // More
  }

  int _pageIndexToMobileBarIndex(int pageIndex) {
    if (pageIndex <= 2) return pageIndex;
    return 3; // Any of 3–8 shows More selected
  }

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
                        // App Logo/Title
                        Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: StayoraLogo(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Divider(height: 1),
                        const SizedBox(height: 8),

                        // Navigation Items (8 items → page indices via _navIndexToPageIndex)
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            itemCount: _navItems.length,
                            itemBuilder: (context, index) {
                              final pageIndex = _navIndexToPageIndex[index];
                              return _buildNavItem(_navItems[index], pageIndex);
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
      // Bottom Navigation Bar (Mobile) - 4 items: Dashboard, Add Booking, Bookings, More
      bottomNavigationBar: isDesktop
          ? null
          : NavigationBar(
              selectedIndex: _pageIndexToMobileBarIndex(_selectedIndex),
              onDestinationSelected: (barIndex) {
                setState(() => _selectedIndex = _mobileBarIndexToPageIndex(barIndex));
              },
              labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
              destinations: _mobileNavItems.map((item) {
                return NavigationDestination(
                  icon: Icon(item.icon),
                  label: item.label,
                );
              }).toList(),
            ),
    );
  }

  Widget _buildNavItem(_NavItem item, int pageIndex) {
    final isSelected = _selectedIndex == pageIndex;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final stayoraBlue = StayoraLogo.stayoraBlue;

    return InkWell(
      onTap: () => setState(() => _selectedIndex = pageIndex),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? stayoraBlue.withOpacity(isDark ? 0.2 : 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              item.icon,
              color: isSelected
                  ? stayoraBlue
                  : colorScheme.onSurfaceVariant,
              size: 24,
            ),
            const SizedBox(width: 12),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected
                    ? stayoraBlue
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

}

/// Mobile-only "More" page: list of secondary nav items (Clients, Calendar, Employees, Shifts, Settings).
class _MoreMenuPage extends StatelessWidget {
  const _MoreMenuPage({required this.onSelect});
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final items = [
      _NavItem(Icons.calendar_month_rounded, 'Calendar', 5),
      _NavItem(Icons.person_rounded, 'Clients', 4),
      _NavItem(Icons.people_rounded, 'Employees', 6),
      _NavItem(Icons.schedule_rounded, 'Shifts', 7),
      _NavItem(Icons.settings_rounded, 'Settings', 8),
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
          children: items.map((item) {
            return ListTile(
              leading: Icon(item.icon, color: StayoraLogo.stayoraBlue, size: 24),
              title: Text(
                item.label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface,
                ),
              ),
              trailing: Icon(Icons.chevron_right_rounded, color: colorScheme.onSurfaceVariant, size: 24),
              onTap: () => onSelect(item.pageIndex),
            );
          }).toList(),
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
      leading: Icon(
        Icons.logout_rounded,
        color: colorScheme.onSurfaceVariant,
        size: 24,
      ),
      title: Text(
        'Sign out',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: colorScheme.onSurfaceVariant,
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
            child: StayoraLogo(
              fontSize: 20,
              fontWeight: FontWeight.bold,
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

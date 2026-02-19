import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'firebase_options.dart';
import 'navigation/app_shell.dart';
import 'services/auth_provider.dart';
import 'services/theme_provider.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('Firebase initialized successfully');
  } catch (e) {
    debugPrint('Firebase not initialized: $e');
  }

  await initializeDateFormatting('en');

  runApp(const HotelManagementApp());
}

class HotelManagementApp extends StatelessWidget {
  const HotelManagementApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthProvider(
      child: ThemeProvider(
        child: WrapHotelWhenLoggedIn(
          child: _AppRoot(),
        ),
      ),
    );
  }
}

class _AppRoot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final themeMode = ThemeProvider.of(context).themeMode;
    return MaterialApp(
      title: 'STAYORA',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const AuthGate(),
    );
  }
}

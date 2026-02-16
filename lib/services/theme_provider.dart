import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _keyThemeMode = 'theme_mode';

class ThemeProvider extends StatefulWidget {
  final Widget child;

  const ThemeProvider({super.key, required this.child});

  static ThemeScopeData of(BuildContext context) {
    final data = context.dependOnInheritedWidgetOfExactType<ThemeScopeData>();
    assert(
      data != null,
      'ThemeProvider not found. Wrap app with ThemeProvider.',
    );
    return data!;
  }

  @override
  State<ThemeProvider> createState() => _ThemeProviderState();
}

class _ThemeProviderState extends State<ThemeProvider> {
  ThemeMode _themeMode = ThemeMode.system;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    if (!_loaded) {
      _loaded = true;
      try {
        final prefs = await SharedPreferences.getInstance();
        final themeString = prefs.getString(_keyThemeMode);
        if (themeString != null && mounted) {
          setState(() {
            _themeMode = ThemeMode.values.firstWhere(
              (mode) => mode.name == themeString,
              orElse: () => ThemeMode.system,
            );
          });
        }
      } catch (_) {
        // SharedPreferences can fail, continue with system default
      }
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyThemeMode, mode.name);
    } catch (_) {
      // Persistence failed; theme is still set in memory for this session
    }
  }

  @override
  Widget build(BuildContext context) {
    return ThemeScopeData(
      themeMode: _themeMode,
      setThemeMode: setThemeMode,
      child: widget.child,
    );
  }
}

class ThemeScopeData extends InheritedWidget {
  final ThemeMode themeMode;
  final Future<void> Function(ThemeMode) setThemeMode;

  const ThemeScopeData({
    super.key,
    required this.themeMode,
    required this.setThemeMode,
    required super.child,
  });

  @override
  bool updateShouldNotify(ThemeScopeData oldWidget) {
    return themeMode != oldWidget.themeMode;
  }
}

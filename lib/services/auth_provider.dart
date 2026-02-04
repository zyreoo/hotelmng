import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the current auth user and provides sign-in, sign-up, sign-out.
/// Wrap the app with [AuthProvider]; use [AuthScopeData.of] to access.
class AuthProvider extends StatefulWidget {
  final Widget child;

  const AuthProvider({super.key, required this.child});

  @override
  State<AuthProvider> createState() => _AuthProviderState();
}

class _AuthProviderState extends State<AuthProvider> {
  User? _user;
  bool _authChecked = false;

  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (mounted) {
        setState(() {
          _user = user;
          _authChecked = true;
        });
      }
    });
  }

  Future<void> signIn(String email, String password) async {
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signUp(String email, String password) async {
    await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signOut() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyCurrentHotelId);
      await prefs.remove(_keyCurrentUserId);
    } catch (_) {}
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return AuthScopeData(
      user: _user,
      authChecked: _authChecked,
      signIn: signIn,
      signUp: signUp,
      signOut: signOut,
      child: widget.child,
    );
  }
}

const String _keyCurrentHotelId = 'current_hotel_id';
const String _keyCurrentUserId = 'current_user_id';

class AuthScopeData extends InheritedWidget {
  final User? user;
  final bool authChecked;
  final Future<void> Function(String email, String password) signIn;
  final Future<void> Function(String email, String password) signUp;
  final Future<void> Function() signOut;

  const AuthScopeData({
    super.key,
    required this.user,
    required this.authChecked,
    required this.signIn,
    required this.signUp,
    required this.signOut,
    required super.child,
  });

  static AuthScopeData of(BuildContext context) {
    final data = context.dependOnInheritedWidgetOfExactType<AuthScopeData>();
    assert(data != null, 'AuthProvider not found. Wrap app with AuthProvider.');
    return data!;
  }

  String? get uid => user?.uid;
  String? get email => user?.email;

  @override
  bool updateShouldNotify(AuthScopeData oldWidget) {
    return user?.uid != oldWidget.user?.uid ||
        authChecked != oldWidget.authChecked;
  }
}

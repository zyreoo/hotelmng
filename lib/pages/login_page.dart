import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_provider.dart';
import '../utils/stayora_colors.dart';
import '../widgets/stayora_logo.dart';
import '../widgets/app_notification.dart';
import 'sign_up_page.dart';

/// App brand blue for primary buttons (matches StayoraLogo).
const Color _stayoraBlue = StayoraColors.blue;

/// Email/password login. Links to sign-up.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter email and password');
      return;
    }
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      final auth = AuthScopeData.of(context);
      await auth.signIn(email, password);
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _messageForAuthError(e);
        });
      }
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    final emailController = TextEditingController();
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
                'Reset Password',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your email and we\'ll send you a link to reset your password.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Email',
                  hintText: 'Enter your email',
                  prefixIcon: const Icon(
                    Icons.email_outlined,
                    color: _stayoraBlue,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
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
                      onPressed: () {
                        if (emailController.text.trim().isNotEmpty) {
                          Navigator.pop(context, true);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Send Link'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (result == true && emailController.text.trim().isNotEmpty) {
      try {
        await FirebaseAuth.instance.sendPasswordResetEmail(
          email: emailController.text.trim(),
        );
        if (mounted) {
          showAppNotification(context, 'Password reset link sent! Check your email.', type: AppNotificationType.success);
        }
      } catch (e) {
        if (mounted) {
          showAppNotification(context, _messageForAuthError(e), type: AppNotificationType.error);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const StayoraLogo(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Sign in with your account',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      hintText: 'you@example.com',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                      prefixIcon: const Icon(Icons.email_outlined),
                    ),
                    onSubmitted: (_) => _signIn(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      hintText: '••••••••',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () =>
                            setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    onSubmitted: (_) => _signIn(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: StayoraColors.error,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _loading ? null : _signIn,
                      style: FilledButton.styleFrom(
                        backgroundColor: _stayoraBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _loading
                          ? SizedBox(
                              height: 22,
                              width: 22,
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Sign in'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _loading ? null : _showForgotPasswordDialog,
                    child: Text(
                      'Forgot password?',
                      style: const TextStyle(
                        color: _stayoraBlue,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const SignUpPage(),
                              ),
                            );
                          },
                    child: Text(
                      'Create an account',
                      style: const TextStyle(color: _stayoraBlue),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _messageForAuthError(dynamic e) {
  if (e is FirebaseAuthException) {
    switch (e.code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Invalid email or password.';
      case 'invalid-email':
        return 'Invalid email address.';
      case 'operation-not-allowed':
        return 'Email sign-in is not enabled. Enable "Email/Password" in Firebase Console → Authentication → Sign-in method.';
      case 'network-request-failed':
        return 'Network error. Check your connection.';
      case 'too-many-requests':
        return 'Too many attempts. Try again later.';
      default:
        return e.message ?? 'Sign in failed (${e.code}).';
    }
  }
  final s = e.toString().toLowerCase();
  if (s.contains('user-not-found') || s.contains('wrong-password')) return 'Invalid email or password.';
  if (s.contains('invalid-email')) return 'Invalid email address.';
  if (s.contains('operation-not-allowed')) return 'Email sign-in is not enabled. Enable "Email/Password" in Firebase Console.';
  if (s.contains('network')) return 'Network error. Check your connection.';
  return 'Sign in failed. Try again.';
}

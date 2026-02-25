import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/stayora_colors.dart';

/// Type of notification for styling (success = green, error = red, info = neutral).
enum AppNotificationType {
  success,
  error,
  info,
}

/// Data for a single notification.
class AppNotificationData {
  const AppNotificationData({
    required this.message,
    this.type = AppNotificationType.info,
  });
  final String message;
  final AppNotificationType type;
}

/// Clean Apple-style toast: top-center, below safe area, rounded, soft shadow, auto-dismiss.
class AppNotificationWidget extends StatelessWidget {
  const AppNotificationWidget({
    super.key,
    required this.data,
    required this.onDismiss,
  });

  final AppNotificationData data;
  final VoidCallback onDismiss;

  static const double _horizontalPadding = 20;
  static const double _verticalPadding = 14;
  static const double _iconSize = 20;
  static const double _radius = 12;
  static const double _elevation = 8;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final (Color bg, Color fg, IconData icon) = _styleFor(data.type, isDark, theme);

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 12, left: 16, right: 16),
          child: Align(
            alignment: Alignment.topRight,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, (value - 1) * 80),
                  child: Opacity(
                    opacity: value,
                    child: child,
                  ),
                );
              },
              child: Material(
                elevation: _elevation,
                shadowColor: theme.colorScheme.shadow.withOpacity(0.2),
                borderRadius: BorderRadius.circular(_radius),
                color: bg,
                child: InkWell(
                  onTap: onDismiss,
                  borderRadius: BorderRadius.circular(_radius),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: _horizontalPadding,
                      vertical: _verticalPadding,
                    ),
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          size: _iconSize,
                          color: fg,
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            data.message,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: fg,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  (Color, Color, IconData) _styleFor(AppNotificationType type, bool isDark, ThemeData theme) {
    switch (type) {
      case AppNotificationType.success:
        return (
          isDark ? StayoraColors.success.withOpacity(0.25) : StayoraColors.success.withOpacity(0.12),
          isDark ? const Color(0xFF30D158) : const Color(0xFF248A3D),
          Icons.check_circle_rounded,
        );
      case AppNotificationType.error:
        return (
          isDark ? StayoraColors.error.withOpacity(0.25) : StayoraColors.error.withOpacity(0.12),
          isDark ? const Color(0xFFFF453A) : const Color(0xFFD70015),
          Icons.error_outline_rounded,
        );
      case AppNotificationType.info:
        return (
          theme.colorScheme.surfaceContainerHigh,
          theme.colorScheme.onSurface,
          Icons.info_outline_rounded,
        );
    }
  }
}

/// Provides [show] to descendants and hosts the overlay.
class AppNotificationScope extends StatefulWidget {
  const AppNotificationScope({super.key, required this.child});
  final Widget child;

  static AppNotificationScopeData of(BuildContext context) {
    final inherited = context.dependOnInheritedWidgetOfExactType<_AppNotificationScopeInherited>();
    assert(inherited != null, 'AppNotificationScope not found. Wrap with AppNotificationScope.');
    return AppNotificationScopeData(show: inherited!.show);
  }

  @override
  State<AppNotificationScope> createState() => _AppNotificationScopeState();
}

class _AppNotificationScopeState extends State<AppNotificationScope> {
  final ValueNotifier<AppNotificationData?> _notifier = ValueNotifier<AppNotificationData?>(null);
  Timer? _timer;

  void show(String message, {AppNotificationType type = AppNotificationType.info}) {
    _timer?.cancel();
    _notifier.value = AppNotificationData(message: message, type: type);
    _timer = Timer(const Duration(seconds: 3), () {
      _notifier.value = null;
      _timer = null;
    });
  }

  void _dismiss() {
    _timer?.cancel();
    _timer = null;
    _notifier.value = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _notifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AppNotificationScopeInherited(
      show: show,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          widget.child,
          ValueListenableBuilder<AppNotificationData?>(
            valueListenable: _notifier,
            builder: (context, data, _) {
              if (data == null) return const SizedBox.shrink();
              return AppNotificationOverlay(
                data: data,
                onDismiss: _dismiss,
              );
            },
          ),
        ],
      ),
    );
  }
}

class AppNotificationScopeData {
  AppNotificationScopeData({required this.show});
  final void Function(String message, {AppNotificationType type}) show;
}

/// Shows a notification from anywhere. Uses [AppNotificationScope] when available, otherwise falls back to SnackBar.
void showAppNotification(
  BuildContext context,
  String message, {
  AppNotificationType type = AppNotificationType.info,
}) {
  try {
    AppNotificationScope.of(context).show(message, type: type);
  } catch (_) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: type == AppNotificationType.error ? StayoraColors.error : null,
      ),
    );
  }
}

class _AppNotificationScopeInherited extends InheritedWidget {
  const _AppNotificationScopeInherited({
    required this.show,
    required super.child,
  });
  final void Function(String message, {AppNotificationType type}) show;

  @override
  bool updateShouldNotify(_AppNotificationScopeInherited oldWidget) =>
      show != oldWidget.show;
}

/// Overlay that paints the notification on top (used inside [AppNotificationScope]).
class AppNotificationOverlay extends StatelessWidget {
  const AppNotificationOverlay({
    super.key,
    required this.data,
    required this.onDismiss,
  });
  final AppNotificationData data;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final (Color bg, Color fg, IconData icon) = _styleFor(context, data.type, isDark);

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 12, left: 16, right: 16),
          child: Align(
            alignment: Alignment.topRight,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, (value - 1) * 80),
                  child: Opacity(opacity: value, child: child),
                );
              },
              child: Material(
                elevation: 8,
                shadowColor: theme.colorScheme.shadow.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                color: bg,
                child: InkWell(
                  onTap: onDismiss,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 20, color: fg),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            data.message,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: fg,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  (Color, Color, IconData) _styleFor(BuildContext context, AppNotificationType type, bool isDark) {
    final theme = Theme.of(context);
    switch (type) {
      case AppNotificationType.success:
        return (
          isDark ? StayoraColors.success.withOpacity(0.25) : StayoraColors.success.withOpacity(0.12),
          isDark ? const Color(0xFF30D158) : const Color(0xFF248A3D),
          Icons.check_circle_rounded,
        );
      case AppNotificationType.error:
        return (
          isDark ? StayoraColors.error.withOpacity(0.25) : StayoraColors.error.withOpacity(0.12),
          isDark ? const Color(0xFFFF453A) : const Color(0xFFD70015),
          Icons.error_outline_rounded,
        );
      case AppNotificationType.info:
        return (
          theme.colorScheme.surfaceContainerHigh,
          theme.colorScheme.onSurface,
          Icons.info_outline_rounded,
        );
    }
  }
}

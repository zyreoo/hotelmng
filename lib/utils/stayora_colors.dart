import 'package:flutter/material.dart';

/// Centralised colour palette for Stayora.
///
/// Use these constants instead of raw hex values so that future
/// theme or accessibility tweaks only need to happen in one place.
abstract class StayoraColors {
  // ── Brand ───────────────────────────────────────────────────────
  static const Color blue = Color(0xFF007AFF);   // primary / info

  // ── Semantic ─────────────────────────────────────────────────────
  static const Color success  = Color(0xFF34C759); // Confirmed / Paid / green
  static const Color warning  = Color(0xFFFF9500); // Pending / orange
  static const Color error    = Color(0xFFFF3B30); // Cancelled / destructive
  static const Color purple   = Color(0xFFAF52DE); // Waiting list
  static const Color muted    = Color(0xFF8E8E93); // Unpaid / inactive grey

  // ── Accent ───────────────────────────────────────────────────────
  /// Teal – used for check-in status, "clean" housekeeping, positive states.
  static const Color teal = Color(0xFF00C7BE);

  // ── Surface tints ────────────────────────────────────────────────
  /// Light card / dialog background (replaces raw 0xFFF2F2F7).
  static const Color surfaceLight = Color(0xFFF2F2F7);

  // ── Calendar booking fills (calmer than status colours) ──────────
  /// Softer, desaturated hues for calendar cell backgrounds so the grid
  /// doesn't feel like a traffic-light. White text remains legible on all.
  static Color calendarColor(String status) {
    switch (status) {
      case 'Confirmed':
        return const Color(0xFF3D82D6); // medium blue
      case 'Pending':
        return const Color(0xFFC97C2A); // warm amber
      case 'Cancelled':
        return const Color(0xFFB84444); // muted rose-red
      case 'Paid':
        return const Color(0xFF5754C4); // indigo
      case 'Unpaid':
        return const Color(0xFF7A7A8A); // slate
      case 'Waiting list':
        return purple;
      default:
        return muted;
    }
  }

  // ── Distinct booking colors (PMS-style: same booking → same color) ─
  /// Muted palette for dark theme: left stripe and accents.
  static const List<Color> bookingPaletteDark = [
    Color(0xFF5B8DEE), // blue
    Color(0xFF4DBDB6), // teal
    Color(0xFF9B7DD9), // purple
    Color(0xFFE5A84A), // amber
    Color(0xFFE07A9E), // pink
    Color(0xFF7B7FDC), // indigo
    Color(0xFF8BC34A), // lime
  ];

  /// Muted palette for light theme.
  static const List<Color> bookingPaletteLight = [
    Color(0xFF3D75D4),
    Color(0xFF2DA89F),
    Color(0xFF7B5FC4),
    Color(0xFFC98E2E),
    Color(0xFFC45A7D),
    Color(0xFF5C5FBF),
    Color(0xFF6B9E2E),
  ];

  /// Returns a distinct color for a booking. Same [bookingId] → same color across rooms/nights.
  static Color bookingColorById(String bookingId, {required bool isDark}) {
    if (bookingId.isEmpty) return muted;
    final palette = isDark ? bookingPaletteDark : bookingPaletteLight;
    final index = bookingId.hashCode.abs() % palette.length;
    return palette[index];
  }

  // ── Housekeeping status → colour ─────────────────────────────────
  static Color housekeepingColor(String status) {
    switch (status) {
      case 'clean':
        return teal;
      case 'cleaning':
        return warning;
      case 'dirty':
        return error;
      case 'out_of_order':
        return muted;
      default:
        return teal;
    }
  }

  // ── Booking status → colour map ──────────────────────────────────
  static Color forStatus(String status) {
    switch (status) {
      case 'Confirmed':
        return success;
      case 'Pending':
        return warning;
      case 'Cancelled':
        return error;
      case 'Paid':
        return blue;
      case 'Unpaid':
        return muted;
      case 'Waiting list':
        return purple;
      default:
        return muted;
    }
  }
}

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

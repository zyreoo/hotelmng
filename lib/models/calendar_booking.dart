import 'package:flutter/material.dart';

/// Lightweight display model for a single night-cell on the calendar grid.
/// Holds only what the grid widget needs to render the cell — not the full
/// Firestore document (use [BookingModel] for that).
class CalendarBooking {
  final String bookingId;
  final String guestName;
  final Color color;
  final bool isFirstNight;
  final bool isLastNight;
  final int totalNights;

  /// Advance payment status: not_required, waiting, paid.
  final String advancePaymentStatus;

  const CalendarBooking({
    required this.bookingId,
    required this.guestName,
    required this.color,
    required this.isFirstNight,
    required this.isLastNight,
    required this.totalNights,
    this.advancePaymentStatus = 'not_required',
  });
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/hotel_model.dart';

/// Utility for formatting currency amounts consistently throughout the app.
class CurrencyFormatter {
  final String currencyCode;
  final String currencySymbol;

  CurrencyFormatter({required this.currencyCode, required this.currencySymbol});

  /// Icon to use for this currency everywhere in the app (inputs, list tiles, stats).
  /// Matches the configured currency: EUR → euro, USD → dollar, others (e.g. RON) → generic payments.
  IconData get currencyIcon {
    switch (currencyCode.toUpperCase()) {
      case 'EUR':
        return Icons.euro_rounded;
      case 'USD':
        return Icons.attach_money_rounded;
      default:
        return Icons.payments_rounded;
    }
  }

  /// Create formatter from hotel model.
  factory CurrencyFormatter.fromHotel(HotelModel? hotel) {
    return CurrencyFormatter(
      currencyCode: hotel?.currencyCode ?? 'EUR',
      currencySymbol: hotel?.currencySymbol ?? '€',
    );
  }

  /// Format amount (stored as cents/smallest unit) to display string.
  /// Example: 10000 → "€100.00"
  String format(int amountInCents) {
    final value = amountInCents / 100.0;
    final formatter = NumberFormat.currency(
      locale: 'en_US',
      symbol: currencySymbol,
      decimalDigits: 2,
    );
    return formatter.format(value);
  }

  /// Format amount as compact (no decimals if whole number).
  /// Example: 10000 → "€100", 10050 → "€100.50"
  String formatCompact(int amountInCents) {
    final value = amountInCents / 100.0;
    if (value == value.roundToDouble()) {
      // Whole number, no decimals
      final formatter = NumberFormat.currency(
        locale: 'en_US',
        symbol: currencySymbol,
        decimalDigits: 0,
      );
      return formatter.format(value);
    } else {
      return format(amountInCents);
    }
  }

  /// Format without currency symbol (just the number).
  /// Example: 10000 → "100.00"
  String formatWithoutSymbol(int amountInCents) {
    final value = amountInCents / 100.0;
    final formatter = NumberFormat('#,##0.00', 'en_US');
    return formatter.format(value);
  }

  // ─── Money input (for text fields) ─────────────────────────────────────

  /// Parse user input to cents. Accepts both comma and period as decimal separator.
  /// Examples: "20" → 2000, "20.5" or "20,5" → 2050, "2.80" or "2,80" → 280.
  static int parseMoneyStringToCents(String s) {
    if (s.trim().isEmpty) return 0;
    final normalized = s.trim().replaceAll(',', '.');
    final value = double.tryParse(normalized);
    if (value == null || value.isNegative) return 0;
    return (value * 100).round();
  }

  /// Format cents for display in an input field (always two decimals).
  /// Examples: 2000 → "20.00", 2050 → "20.50", 0 → "".
  static String formatCentsForInput(int cents) {
    if (cents <= 0) return '';
    final value = cents / 100.0;
    if (value == value.roundToDouble()) {
      return '${value.toInt()}.00';
    }
    return value.toStringAsFixed(2);
  }

  /// Format value from DB for input field. Handles legacy whole-number values:
  /// if value is in 1..999 (likely whole units), treat as euros and show "X.00".
  static String formatStoredAmountForInput(int value) {
    if (value <= 0) return '';
    if (value < 1000) {
      return formatCentsForInput(value * 100);
    }
    return formatCentsForInput(value);
  }
}

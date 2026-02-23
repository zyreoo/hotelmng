import '../../../models/calendar_booking.dart';

/// Pre-computed data for a single room×date cell so [_buildRoomCell] doesn't
/// recompute connections and info-cell flags on every build.
class CalendarCellData {
  const CalendarCellData({
    required this.booking,
    required this.isConnectedLeft,
    required this.isConnectedRight,
    required this.isConnectedTop,
    required this.isConnectedBottom,
    required this.isInfoCell,
    required this.centerInfoInBubble,
  });

  /// Empty cell (no booking).
  static const CalendarCellData empty = CalendarCellData(
    booking: null,
    isConnectedLeft: false,
    isConnectedRight: false,
    isConnectedTop: false,
    isConnectedBottom: false,
    isInfoCell: false,
    centerInfoInBubble: false,
  );

  final CalendarBooking? booking;
  final bool isConnectedLeft;
  final bool isConnectedRight;
  final bool isConnectedTop;
  final bool isConnectedBottom;
  final bool isInfoCell;
  final bool centerInfoInBubble;
}

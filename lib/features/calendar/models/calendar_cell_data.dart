import '../../../models/calendar_booking.dart';

class CalendarCellData {
  const CalendarCellData({
    required this.booking,
    required this.isConnectedLeft,
    required this.isConnectedRight,
    required this.isConnectedTop,
    required this.isConnectedBottom,
    required this.isInfoCell,
    required this.centerInfoInBubble,
    this.roomSpan = 1,
  });

  static const CalendarCellData empty = CalendarCellData(
    booking: null,
    isConnectedLeft: false,
    isConnectedRight: false,
    isConnectedTop: false,
    isConnectedBottom: false,
    isInfoCell: false,
    centerInfoInBubble: false,
    roomSpan: 1,
  );

  final CalendarBooking? booking;
  final bool isConnectedLeft;
  final bool isConnectedRight;
  final bool isConnectedTop;
  final bool isConnectedBottom;
  final bool isInfoCell;
  final bool centerInfoInBubble;
  final int roomSpan;
}

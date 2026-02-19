/// Named route constants for use with [Navigator.pushNamed].
///
/// Usage: `Navigator.pushNamed(context, AppRoutes.addBooking)`
abstract final class AppRoutes {
  static const String dashboard    = '/dashboard';
  static const String addBooking   = '/booking/add';
  static const String editBooking  = '/booking/edit';
  static const String bookingsList = '/bookings';
  static const String calendar     = '/calendar';
  static const String clients      = '/clients';
  static const String employees    = '/employees';
  static const String schedule     = '/schedule';
  static const String settings     = '/settings';
  static const String rooms        = '/rooms';
  static const String hotelSetup   = '/hotel-setup';
  static const String login        = '/login';
}

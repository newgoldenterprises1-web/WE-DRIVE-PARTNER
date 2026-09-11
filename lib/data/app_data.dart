import '../models/booking.dart';

class AppData {
  static bool isPremiumPartner = false;

  static final List<Booking> bookings = <Booking>[];
  static final List<Booking> premiumBookings = <Booking>[];

  static bool get premiumFeatureVisible => isPremiumPartner;
  static set premiumFeatureVisible(bool value) => isPremiumPartner = value;
}

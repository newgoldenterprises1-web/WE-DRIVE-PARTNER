import '../models/booking.dart';

class AppData {
  static bool isPremiumPartner = false;

  // Development-only session flag. It never gets written to Firestore.
  static bool testPartnerActivated = false;

  static final List<Booking> bookings = <Booking>[];
  static final List<Booking> premiumBookings = <Booking>[];

  static bool get premiumFeatureVisible => isPremiumPartner;
  static set premiumFeatureVisible(bool value) => isPremiumPartner = value;
}

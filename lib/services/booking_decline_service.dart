import 'package:firebase_auth/firebase_auth.dart';

import 'booking_status_service.dart';

class BookingDeclineService {
  const BookingDeclineService._();

  static Future<bool> declineBooking(String bookingId) async {
    final user = FirebaseAuth.instance.currentUser;
    final normalizedId = bookingId.trim();
    if (user == null || normalizedId.isEmpty) return false;

    return BookingStatusService.updateStatus(
      bookingId: normalizedId,
      nextStatus: 'CANCELLED',
    );
  }
}

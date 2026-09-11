import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'booking_status_service.dart';

class BookingDeclineService {
  const BookingDeclineService._();

  static Future<bool> declineBooking(String bookingId) async {
    final user = FirebaseAuth.instance.currentUser;
    final normalizedId = bookingId.trim();
    if (user == null || normalizedId.isEmpty) return false;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('bookings')
          .doc(normalizedId)
          .get();
      if (!snapshot.exists) return false;

      final data = snapshot.data() ?? <String, dynamic>{};
      final status = (data['status'] ?? '').toString().toUpperCase();
      final partnerId = (data['partnerId'] ?? '').toString().trim();

      if (status != 'REQUESTED' && status != 'SEARCHING') return false;
      if (partnerId.isNotEmpty && partnerId != user.uid) return false;

      return BookingStatusService.updateStatus(
        bookingId: normalizedId,
        nextStatus: 'CANCELLED',
      );
    } catch (_) {
      return false;
    }
  }
}

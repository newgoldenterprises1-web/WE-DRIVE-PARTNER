import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'booking_expiry_service.dart';

class BookingAssignmentService {
  const BookingAssignmentService._();

  static bool _isPremiumBooking(Map<String, dynamic> data) {
    return data['isPremiumBooking'] == true;
  }

  static Future<bool> acceptBooking(String bookingId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || bookingId.trim().isEmpty) return false;

    final firestore = FirebaseFirestore.instance;
    final ref = firestore.collection('bookings').doc(bookingId.trim());
    final partnerRef = firestore.collection('partners').doc(user.uid);

    try {
      await firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(ref);
        final partnerSnapshot = await transaction.get(partnerRef);

        if (!snapshot.exists) throw StateError('missing');

        final partnerData = partnerSnapshot.data() ?? <String, dynamic>{};
        if (partnerData['accountStatus'] != 'ACTIVE') throw StateError('inactive');
        if (partnerData['isOnline'] != true) throw StateError('offline');

        final data = snapshot.data() ?? <String, dynamic>{};
        final status = (data['status'] ?? 'SEARCHING').toString().toUpperCase();
        final partnerId = (data['partnerId'] ?? '').toString().trim();

        if (partnerId.isNotEmpty && partnerId != user.uid) throw StateError('assigned');
        if (status != 'REQUESTED' && status != 'SEARCHING') throw StateError('unavailable');
        if (BookingExpiryService.isExpired(data)) throw StateError('expired');

        if (_isPremiumBooking(data) && partnerData['isPremium'] != true) {
          throw StateError('premium_required');
        }

        transaction.set(ref, {
          'status': 'ACCEPTED',
          'partnerId': user.uid,
          'acceptedBy': user.uid,
          'acceptedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
      return true;
    } catch (_) {
      // A stale booking is allowed to be cleaned up without ever being accepted.
      await BookingExpiryService.expireIfStale(bookingId);
      return false;
    }
  }
}

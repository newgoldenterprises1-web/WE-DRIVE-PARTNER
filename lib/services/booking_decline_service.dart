import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BookingDeclineService {
  const BookingDeclineService._();

  static Future<bool> declineBooking(String bookingId) async {
    final user = FirebaseAuth.instance.currentUser;
    final normalizedId = bookingId.trim();
    if (user == null || normalizedId.isEmpty) return false;

    final firestore = FirebaseFirestore.instance;
    final ref = firestore.collection('bookings').doc(normalizedId);

    try {
      await firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(ref);
        if (!snapshot.exists) throw StateError('missing');

        final data = snapshot.data() ?? <String, dynamic>{};
        final status = (data['status'] ?? '').toString().toUpperCase();
        final partnerId = (data['partnerId'] ?? '').toString().trim();

        if (status != 'REQUESTED' && status != 'SEARCHING') {
          throw StateError('unavailable');
        }
        if (partnerId.isNotEmpty && partnerId != user.uid) {
          throw StateError('assigned');
        }

        transaction.set(
          ref,
          {
            'status': 'CANCELLED',
            'cancelledBy': user.uid,
            'cancelledAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}

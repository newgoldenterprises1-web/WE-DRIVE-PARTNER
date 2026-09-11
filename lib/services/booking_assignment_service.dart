import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BookingAssignmentService {
  const BookingAssignmentService._();

  static Future<bool> acceptBooking(String bookingId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || bookingId.trim().isEmpty) return false;

    final ref = FirebaseFirestore.instance.collection('bookings').doc(bookingId.trim());

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(ref);
        if (!snapshot.exists) throw StateError('missing');

        final data = snapshot.data() ?? <String, dynamic>{};
        final status = (data['status'] ?? 'SEARCHING').toString().toUpperCase();
        final partnerId = (data['partnerId'] ?? '').toString().trim();

        if (partnerId.isNotEmpty && partnerId != user.uid) {
          throw StateError('assigned');
        }
        if (status != 'REQUESTED' && status != 'SEARCHING') {
          throw StateError('unavailable');
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
      return false;
    }
  }
}

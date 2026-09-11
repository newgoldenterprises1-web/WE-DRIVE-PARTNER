import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BookingStatusService {
  const BookingStatusService._();

  static const Map<String, Set<String>> allowedTransitions = {
    'REQUESTED': {'ACCEPTED', 'CANCELLED'},
    'SEARCHING': {'ACCEPTED', 'CANCELLED'},
    'ACCEPTED': {'ARRIVING', 'CANCELLED'},
    'ARRIVING': {'ARRIVED', 'CANCELLED'},
    'ARRIVED': {'TRIP_STARTED', 'CANCELLED'},
    'TRIP_STARTED': {'COMPLETED'},
    'COMPLETED': <String>{},
    'CANCELLED': <String>{},
  };

  static Future<bool> updateStatus({
    required String bookingId,
    required String nextStatus,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final normalizedId = bookingId.trim();
    final target = nextStatus.trim().toUpperCase();

    if (user == null || normalizedId.isEmpty || target.isEmpty) {
      return false;
    }

    final firestore = FirebaseFirestore.instance;
    final ref = firestore.collection('bookings').doc(normalizedId);
    final partnerRef = firestore.collection('partners').doc(user.uid);

    try {
      await firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(ref);
        final partnerSnapshot = target == 'ACCEPTED'
            ? await transaction.get(partnerRef)
            : null;

        if (!snapshot.exists) {
          throw StateError('missing');
        }

        final data = snapshot.data() ?? <String, dynamic>{};
        final current = (data['status'] ?? 'SEARCHING').toString().toUpperCase();
        final partnerId = (data['partnerId'] ?? '').toString().trim();

        if (!_canTransition(current, target)) {
          throw StateError('invalid_transition');
        }

        if (target == 'ACCEPTED') {
          final partnerData = partnerSnapshot?.data() ?? <String, dynamic>{};
          if (partnerData['isOnline'] != true) {
            throw StateError('offline');
          }

          if (partnerId.isNotEmpty && partnerId != user.uid) {
            throw StateError('assigned');
          }

          transaction.set(ref, {
            'status': 'ACCEPTED',
            'partnerId': user.uid,
            'acceptedBy': user.uid,
            'acceptedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          return;
        }

        if (partnerId != user.uid) {
          throw StateError('not_owner');
        }

        transaction.set(ref, {
          'status': target,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });

      return true;
    } catch (_) {
      return false;
    }
  }

  static bool canTransition(String currentStatus, String nextStatus) {
    return _canTransition(
      currentStatus.trim().toUpperCase(),
      nextStatus.trim().toUpperCase(),
    );
  }

  static bool _canTransition(String currentStatus, String nextStatus) {
    final allowed = allowedTransitions[currentStatus];
    return allowed != null && allowed.contains(nextStatus);
  }
}

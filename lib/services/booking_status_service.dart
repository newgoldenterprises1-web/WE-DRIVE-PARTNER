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

  static Future<bool> updateStatus({required String bookingId, required String nextStatus}) async {
    final user = FirebaseAuth.instance.currentUser;
    final normalizedId = bookingId.trim();
    final target = nextStatus.trim().toUpperCase();
    if (user == null || normalizedId.isEmpty || target.isEmpty) return false;

    final firestore = FirebaseFirestore.instance;
    final ref = firestore.collection('bookings').doc(normalizedId);
    final partnerRef = firestore.collection('partners').doc(user.uid);

    try {
      await firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(ref);
        final partnerSnapshot = await transaction.get(partnerRef);
        if (!snapshot.exists) throw StateError('missing');

        final partnerData = partnerSnapshot.data() ?? <String, dynamic>{};
        final data = snapshot.data() ?? <String, dynamic>{};
        final current = (data['status'] ?? 'SEARCHING').toString().toUpperCase();
        final partnerId = (data['partnerId'] ?? '').toString().trim();
        final isPremiumBooking = data['isPremiumBooking'] == true;
        final isPremiumPartner = partnerData['isPremium'] == true;

        if (!_canTransition(current, target)) throw StateError('invalid_transition');

        if (target == 'ACCEPTED') {
          final accountStatus = partnerData['accountStatus'];
          if (accountStatus != null && accountStatus != 'ACTIVE') throw StateError('inactive');
          if (partnerData['isOnline'] != true) throw StateError('offline');
          if (partnerId.isNotEmpty && partnerId != user.uid) throw StateError('assigned');
          if (isPremiumBooking && !isPremiumPartner) throw StateError('premium_required');

          transaction.set(ref, {
            'status': 'ACCEPTED',
            'partnerId': user.uid,
            'acceptedBy': user.uid,
            'acceptedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          return;
        }

        if (partnerId != user.uid && target != 'CANCELLED') throw StateError('not_owner');
        if (target == 'CANCELLED' && partnerId.isNotEmpty && partnerId != user.uid) throw StateError('not_owner');

        final update = <String, dynamic>{'status': target, 'updatedAt': FieldValue.serverTimestamp()};
        switch (target) {
          case 'ARRIVING': update['arrivingAt'] = FieldValue.serverTimestamp(); break;
          case 'ARRIVED': update['arrivedAt'] = FieldValue.serverTimestamp(); break;
          case 'TRIP_STARTED': update['tripStartedAt'] = FieldValue.serverTimestamp(); break;
          case 'COMPLETED': update['completedAt'] = FieldValue.serverTimestamp(); break;
          case 'CANCELLED':
            update['cancelledBy'] = user.uid;
            update['cancelledAt'] = FieldValue.serverTimestamp();
            break;
        }
        transaction.set(ref, update, SetOptions(merge: true));
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool canTransition(String currentStatus, String nextStatus) => _canTransition(currentStatus.trim().toUpperCase(), nextStatus.trim().toUpperCase());

  static bool _canTransition(String currentStatus, String nextStatus) {
    final allowed = allowedTransitions[currentStatus];
    return allowed != null && allowed.contains(nextStatus);
  }
}

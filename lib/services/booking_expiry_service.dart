import 'package:cloud_firestore/cloud_firestore.dart';

class BookingExpiryService {
  BookingExpiryService._();

  static const Duration requestTimeout = Duration(minutes: 15);

  static bool isExpired(Map<String, dynamic> data, {DateTime? now}) {
    final status = (data['status'] ?? '').toString().trim().toUpperCase();
    if (status != 'REQUESTED' && status != 'SEARCHING') return false;

    final partnerId = (data['partnerId'] ?? '').toString().trim();
    if (partnerId.isNotEmpty) return false;

    final createdAt = data['createdAt'];
    if (createdAt is! Timestamp) return false;

    final referenceNow = now ?? DateTime.now();
    return referenceNow.difference(createdAt.toDate()) >= requestTimeout;
  }

  static Future<bool> expireIfStale(String bookingId) async {
    final normalizedId = bookingId.trim();
    if (normalizedId.isEmpty) return false;

    final firestore = FirebaseFirestore.instance;
    final ref = firestore.collection('bookings').doc(normalizedId);

    try {
      return await firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(ref);
        if (!snapshot.exists) return false;

        final data = snapshot.data() ?? <String, dynamic>{};
        if (!isExpired(data)) return false;

        transaction.set(
          ref,
          {
            'status': 'CANCELLED',
            'cancelledBy': 'SYSTEM_TIMEOUT',
            'cancelledReason': 'REQUEST_TIMEOUT',
            'cancelledAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        return true;
      });
    } catch (_) {
      return false;
    }
  }
}

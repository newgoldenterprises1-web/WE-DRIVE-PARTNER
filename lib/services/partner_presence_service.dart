import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

class PartnerPresenceService {
  PartnerPresenceService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static DocumentReference<Map<String, dynamic>>? _partnerRef() {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) return null;
    return _firestore.collection('partners').doc(uid);
  }

  static Future<bool?> getOnlineStatus() async {
    final ref = _partnerRef();
    if (ref == null) return null;

    try {
      final snapshot = await ref.get();
      if (!snapshot.exists) return false;
      return snapshot.data()?['isOnline'] == true;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> setOnline(bool online, {Position? position}) async {
    final ref = _partnerRef();
    if (ref == null) return false;

    try {
      final data = <String, dynamic>{
        'isOnline': online,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastSeenAt': FieldValue.serverTimestamp(),
      };

      if (position != null) {
        data['location'] = GeoPoint(position.latitude, position.longitude);
        data['latitude'] = position.latitude;
        data['longitude'] = position.longitude;
      }

      await ref.set(data, SetOptions(merge: true));
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> refreshLocation(Position position) async {
    final ref = _partnerRef();
    if (ref == null) return false;

    try {
      await ref.set({
        'isOnline': true,
        'location': GeoPoint(position.latitude, position.longitude),
        'latitude': position.latitude,
        'longitude': position.longitude,
        'lastSeenAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setOfflineBestEffort() async {
    final ref = _partnerRef();
    if (ref == null) return;

    try {
      await ref.set({
        'isOnline': false,
        'lastSeenAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Do not block app shutdown/navigation because presence is best-effort.
    }
  }
}

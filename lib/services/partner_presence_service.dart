import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

import 'location_service.dart';

class PartnerPresenceService {
  PartnerPresenceService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static Timer? _locationTimer;
  static bool _locationUpdateInFlight = false;

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

      final isOnline = snapshot.data()?['isOnline'] == true;
      if (isOnline) {
        _startLocationTracking();
      } else {
        _stopLocationTracking();
      }
      return isOnline;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> setOnline(bool online, {Position? position}) async {
    final ref = _partnerRef();
    if (ref == null) return false;

    try {
      Position? resolvedPosition = position;
      if (online && resolvedPosition == null) {
        resolvedPosition = await LocationService.getCurrentPosition();
      }

      final data = <String, dynamic>{
        'isOnline': online,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastSeenAt': FieldValue.serverTimestamp(),
      };

      if (resolvedPosition != null) {
        data['location'] = GeoPoint(
          resolvedPosition.latitude,
          resolvedPosition.longitude,
        );
        data['latitude'] = resolvedPosition.latitude;
        data['longitude'] = resolvedPosition.longitude;
      }

      await ref.set(data, SetOptions(merge: true));

      if (online) {
        _startLocationTracking();
      } else {
        _stopLocationTracking();
      }

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

  static void _startLocationTracking() {
    if (_locationTimer?.isActive == true) return;

    _updateLocationNow();
    _locationTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _updateLocationNow(),
    );
  }

  static void _stopLocationTracking() {
    _locationTimer?.cancel();
    _locationTimer = null;
  }

  static Future<void> _updateLocationNow() async {
    if (_locationUpdateInFlight) return;
    final ref = _partnerRef();
    if (ref == null) return;

    _locationUpdateInFlight = true;
    try {
      final isOnline = await getOnlineStatusWithoutStartingTracking();
      if (isOnline != true) {
        _stopLocationTracking();
        return;
      }

      final position = await LocationService.getCurrentPosition();
      if (position == null) return;

      await refreshLocation(position);
    } catch (_) {
      // Location updates are best-effort. The partner remains online if a
      // transient GPS/network failure occurs; the next tick will retry.
    } finally {
      _locationUpdateInFlight = false;
    }
  }

  static Future<bool?> getOnlineStatusWithoutStartingTracking() async {
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

  static Future<void> setOfflineBestEffort() async {
    final ref = _partnerRef();
    _stopLocationTracking();
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

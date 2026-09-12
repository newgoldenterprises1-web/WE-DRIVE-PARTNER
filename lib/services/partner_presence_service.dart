import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

import '../data/app_data.dart';
import 'location_service.dart';

class PartnerPresenceService {
  PartnerPresenceService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static Timer? _locationTimer;
  static bool _locationUpdateInFlight = false;
  static bool _testOnline = false;
  static const Duration stalePresenceWindow = Duration(minutes: 5);

  static DocumentReference<Map<String, dynamic>>? _partnerRef() {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) return null;
    return _firestore.collection('partners').doc(uid);
  }

  static String _dateKey([DateTime? date]) {
    final value = date ?? DateTime.now();
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  static void _restorePartnerPlan(Map<String, dynamic> data) {
    AppData.isPremiumPartner = data['isPremium'] == true;
  }

  static Future<bool?> getOnlineStatus() async {
    final ref = _partnerRef();
    if (ref == null) return null;

    // Development-only session simulation. No Firestore write is performed.
    if (AppData.testPartnerActivated) return _testOnline;

    try {
      final snapshot = await ref.get();
      if (!snapshot.exists) return false;
      final data = snapshot.data() ?? <String, dynamic>{};
      _restorePartnerPlan(data);
      if (data['accountStatus'] != 'ACTIVE') {
        _stopLocationTracking();
        return false;
      }
      final isOnline = data['isOnline'] == true;
      if (!isOnline) {
        _stopLocationTracking();
        return false;
      }
      final lastSeen = data['lastSeenAt'];
      if (lastSeen is Timestamp && DateTime.now().difference(lastSeen.toDate()) > stalePresenceWindow) {
        await setOfflineBestEffort();
        return false;
      }
      _startLocationTracking();
      return true;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> setOnline(bool online, {Position? position}) async {
    final ref = _partnerRef();
    if (ref == null) return false;

    // Development-only session simulation. Security rules remain unchanged.
    if (AppData.testPartnerActivated) {
      _testOnline = online;
      return true;
    }

    try {
      final current = await ref.get();
      final currentData = current.data() ?? <String, dynamic>{};
      _restorePartnerPlan(currentData);
      if (online && currentData['accountStatus'] != 'ACTIVE') return false;

      Position? resolvedPosition = position;
      if (online && resolvedPosition == null) {
        resolvedPosition = await LocationService.getCurrentPosition();
        if (resolvedPosition == null) return false;
      }

      final data = <String, dynamic>{
        'isOnline': online,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastSeenAt': FieldValue.serverTimestamp(),
      };
      if (online) {
        final todayKey = _dateKey();
        final currentDateKey = (currentData['onlineDateKey'] ?? '').toString();
        if (currentDateKey != todayKey) {
          data['onlineMinutesToday'] = 0;
          data['onlineDateKey'] = todayKey;
        }
        data['onlineStartedAt'] = FieldValue.serverTimestamp();
      } else {
        final started = currentData['onlineStartedAt'];
        var minutes = currentData['onlineMinutesToday'] is num ? (currentData['onlineMinutesToday'] as num).toInt() : 0;
        if (started is Timestamp) {
          final elapsed = DateTime.now().difference(started.toDate()).inMinutes;
          if (elapsed > 0) minutes += elapsed;
        }
        data['onlineMinutesToday'] = minutes;
        data['onlineDateKey'] = _dateKey();
        data['onlineStartedAt'] = FieldValue.delete();
      }

      if (resolvedPosition != null) {
        data['location'] = GeoPoint(resolvedPosition.latitude, resolvedPosition.longitude);
        data['latitude'] = resolvedPosition.latitude;
        data['longitude'] = resolvedPosition.longitude;
      }

      await ref.set(data, SetOptions(merge: true));
      if (online) _startLocationTracking(); else _stopLocationTracking();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> refreshLocation(Position position) async {
    final ref = _partnerRef();
    if (ref == null) return false;
    if (AppData.testPartnerActivated) return _testOnline;

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
    _locationTimer = Timer.periodic(const Duration(seconds: 60), (_) => _updateLocationNow());
  }

  static void _stopLocationTracking() {
    _locationTimer?.cancel();
    _locationTimer = null;
  }

  static Future<void> _updateLocationNow() async {
    if (_locationUpdateInFlight) return;
    if (AppData.testPartnerActivated) return;
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
      if (position != null) await refreshLocation(position);
    } catch (_) {
    } finally {
      _locationUpdateInFlight = false;
    }
  }

  static Future<bool?> getOnlineStatusWithoutStartingTracking() async {
    final ref = _partnerRef();
    if (ref == null) return null;
    if (AppData.testPartnerActivated) return _testOnline;

    try {
      final snapshot = await ref.get();
      if (!snapshot.exists) return false;
      final data = snapshot.data() ?? <String, dynamic>{};
      _restorePartnerPlan(data);
      return data['accountStatus'] == 'ACTIVE' && data['isOnline'] == true;
    } catch (_) {
      return null;
    }
  }

  static Future<void> setOfflineBestEffort() async {
    _stopLocationTracking();
    if (AppData.testPartnerActivated) {
      _testOnline = false;
      return;
    }

    final ref = _partnerRef();
    if (ref == null) return;
    try {
      final current = await ref.get();
      final currentData = current.data() ?? <String, dynamic>{};
      _restorePartnerPlan(currentData);
      final started = currentData['onlineStartedAt'];
      var minutes = currentData['onlineMinutesToday'] is num ? (currentData['onlineMinutesToday'] as num).toInt() : 0;
      if (started is Timestamp) {
        final elapsed = DateTime.now().difference(started.toDate()).inMinutes;
        if (elapsed > 0) minutes += elapsed;
      }
      await ref.set({
        'isOnline': false,
        'onlineMinutesToday': minutes,
        'onlineDateKey': _dateKey(),
        'onlineStartedAt': FieldValue.delete(),
        'lastSeenAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
    }
  }
}

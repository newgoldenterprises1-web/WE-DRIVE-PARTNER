import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

/// Production partner presence/location service.
///
/// The UI stays unchanged. Location is pushed to Firebase immediately from
/// the device's last known fix when available, then refreshed with a
/// high-accuracy live stream.
class PartnerPresenceService {
  PartnerPresenceService._();
  static final PartnerPresenceService instance = PartnerPresenceService._();

  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-south1');

  StreamSubscription<Position>? _positionSubscription;
  bool _running = false;

  Future<void> setOnline(bool online) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Partner session is not available.');
    }

    if (online) {
      await _ensureLocationPermission();
      await _functions.httpsCallable('setDriverPresence').call({
        'online': true,
      });
      await startLiveLocation();
    } else {
      await stopLiveLocation();
      await _functions.httpsCallable('setDriverPresence').call({
        'online': false,
      });
    }
  }

  Future<void> startLiveLocation() async {
    if (_running) return;
    await _ensureLocationPermission();

    // Do not wait for a fresh GPS fix before starting. Android can often
    // provide a cached fix immediately, which makes the partner location
    // available to Firebase much faster.
    final lastKnown = await Geolocator.getLastKnownPosition();
    if (lastKnown != null) {
      await _sendPosition(lastKnown);
    }

    // Then request a fresh high-accuracy position. This corrects the cached
    // location as soon as the device gets a newer GPS/Wi-Fi/cell fix.
    try {
      final current = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
        timeLimit: const Duration(seconds: 8),
      );
      await _sendPosition(current);
    } catch (_) {
      // A cached position may already have been sent. Keep the live stream
      // running rather than blocking the partner from going online.
    }

    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _running = true;
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen((position) async {
      await _sendPosition(position);
    });
  }

  Future<void> _sendPosition(Position position) async {
    try {
      await _functions.httpsCallable('updateDriverLocation').call({
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'heading': position.heading,
        'speed': position.speed,
      });
    } catch (_) {
      // A transient network failure must not crash the partner app.
    }
  }

  Future<void> stopLiveLocation() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _running = false;
  }

  Future<void> dispose() => stopLiveLocation();

  Future<void> _ensureLocationPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Please turn on device location services.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('Location permission is required while you are online.');
    }
  }
}

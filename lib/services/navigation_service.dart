import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

class NavigationService {
  const NavigationService._();

  static Future<bool> openDrivingNavigation(String destination) async {
    final trimmed = destination.trim();
    if (trimmed.isEmpty) return false;

    // Use the device's cached location immediately when available. This avoids
    // making Google Maps wait unnecessarily for another GPS lookup just to
    // determine the driver's starting point.
    String? origin;
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        origin = '${lastKnown.latitude},${lastKnown.longitude}';
      }
    } catch (_) {}

    final query = <String, String>{
      'api': '1',
      'destination': trimmed,
      'travelmode': 'driving',
      'dir_action': 'navigate',
      if (origin != null) 'origin': origin,
    };

    final uri = Uri.https('www.google.com', '/maps/dir/', query);

    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error, stackTrace) {
      debugPrint('Google Maps launch failed: $error\n$stackTrace');
      return false;
    }
  }
}

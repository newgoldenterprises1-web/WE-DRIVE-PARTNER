import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'location_service.dart';

class NavigationService {
  const NavigationService._();

  static Future<bool> openDrivingNavigation(String destination) async {
    final trimmed = destination.trim();
    if (trimmed.isEmpty) return false;

    // Request/verify current location permission before asking Google Maps
    // to start turn-by-turn navigation from the driver's current position.
    final locationReady = await LocationService.ensurePermission();
    if (!locationReady) return false;

    final encoded = Uri.encodeComponent(trimmed);
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=$encoded'
      '&travelmode=driving'
      '&dir_action=navigate',
    );

    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error, stackTrace) {
      debugPrint('Navigation launch failed: $error\n$stackTrace');
      return false;
    }
  }
}

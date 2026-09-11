import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

class NavigationService {
  const NavigationService._();

  static Future<bool> openDrivingNavigation(String destination) async {
    final trimmed = destination.trim();
    if (trimmed.isEmpty) return false;

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

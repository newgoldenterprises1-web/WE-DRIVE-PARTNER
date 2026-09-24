import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:cloud_functions/cloud_functions.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final CloudFunctions _functions = FirebaseFunctions.instanceFor(region: 'asia-south1');
  bool _initialized = false;

  Future<void> initialize() async {
    if (!_initialized) {
      _initialized = true;

      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        announcement: false,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
      );

      _messaging.onTokenRefresh.listen((token) async {
        await _register(token);
      });

      FirebaseMessaging.onMessage.listen((message) async {
        try {
          await SystemSound.play(SystemSoundType.alert);
          await HapticFeedback.heavyImpact();
        } catch (_) {}
      });
    }

    await _registerCurrentToken();
  }

  Future<void> _registerCurrentToken() async {
    final token = await _messaging.getToken();
    if (token != null) await _register(token);
  }

  Future<void> _register(String token) async {
    try {
      await _functions.httpsCallable('registerDriverFcmToken').call({
        'token': token,
      });
    } catch (_) {
      // Authentication may not be ready during cold start. HomeScreen calls
      // initialize again after the partner session is available.
    }
  }
}

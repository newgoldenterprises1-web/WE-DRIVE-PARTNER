import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

@pragma('vm:entry-point')
Future<void> weDriveFirebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-south1');
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<User?>? _authSubscription;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    FirebaseMessaging.onBackgroundMessage(
      weDriveFirebaseMessagingBackgroundHandler,
    );

    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    await _registerToken();

    _tokenSubscription = _messaging.onTokenRefresh.listen((token) {
      _registerToken(token);
    });

    _authSubscription =
        FirebaseAuth.instance.authStateChanges().listen((_) {
      _registerToken();
    });
  }

  Future<void> _registerToken([String? token]) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final value = (token ?? await _messaging.getToken() ?? '').trim();
    if (value.isEmpty) return;

    try {
      await _functions.httpsCallable('registerFcmToken').call({
        'token': value,
      });
    } catch (_) {
      // Role claims may still be refreshing immediately after login.
      // Token refresh/auth changes will retry registration.
    }
  }

  Future<void> dispose() async {
    await _tokenSubscription?.cancel();
    await _authSubscription?.cancel();
    _tokenSubscription = null;
    _authSubscription = null;
  }
}

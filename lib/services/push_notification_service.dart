import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

@pragma('vm:entry-point')
Future<void> weDriveFirebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-south1');

  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;

  bool _initialized = false;
  RemoteMessage? _pendingOpenedMessage;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    FirebaseMessaging.onBackgroundMessage(
      weDriveFirebaseMessagingBackgroundHandler,
    );

    await _messaging.setAutoInitEnabled(true);

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

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((_) {
      _registerToken();
    });

    _foregroundSubscription = FirebaseMessaging.onMessage.listen(
      _showForegroundNotification,
    );

    _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      _handleNotificationOpen,
    );

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _pendingOpenedMessage = initialMessage;
    }
  }

  Future<void> _registerToken([String? token]) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      await currentUser.getIdToken(true);
    } catch (_) {
      // Token refresh is best-effort. The callable remains authoritative.
    }

    final value = (token ?? await _messaging.getToken() ?? '').trim();
    if (value.isEmpty) return;

    try {
      await _functions.httpsCallable('registerFcmToken').call({
        'token': value,
      });
    } catch (_) {
      // A later auth/token refresh will retry registration.
    }
  }

  void _showForegroundNotification(RemoteMessage message) {
    final notification = message.notification;
    final title = notification?.title ?? message.data['title']?.toString();
    final body = notification?.body ?? message.data['body']?.toString();

    if ((title == null || title.trim().isEmpty) &&
        (body == null || body.trim().isEmpty)) {
      return;
    }

    final messenger = scaffoldMessengerKey.currentState;
    if (messenger == null) return;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null && title.trim().isNotEmpty)
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              if (body != null && body.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(body),
              ],
            ],
          ),
        ),
      );
  }

  void flushPendingNotification() {
    final message = _pendingOpenedMessage;
    _pendingOpenedMessage = null;
    if (message != null) {
      _handleNotificationOpen(message);
    }
  }

  void _handleNotificationOpen(RemoteMessage message) {
    final status = message.data['status']?.toString().toUpperCase();
    final bookingId = message.data['bookingId']?.toString();

    if (status == 'REQUESTED' || status == 'SEARCHING') {
      scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('New ride request available in Bookings.'),
        ),
      );
      return;
    }

    if (bookingId != null && bookingId.isNotEmpty) {
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('Booking update received: $bookingId'),
        ),
      );
    }
  }

  Future<void> setRideRequestsSubscription(bool enabled) async {
    try {
      if (enabled) {
        await _messaging.subscribeToTopic('ride_requests');
      } else {
        await _messaging.unsubscribeFromTopic('ride_requests');
      }
    } catch (_) {
      // Topic subscriptions are best-effort.
    }
  }

  Future<void> dispose() async {
    await _tokenSubscription?.cancel();
    await _authSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();

    _tokenSubscription = null;
    _authSubscription = null;
    _foregroundSubscription = null;
    _openedSubscription = null;
  }
}

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Notification payloads are displayed by Firebase Messaging automatically
  // when the app is in the background/terminated. Data is intentionally kept
  // lightweight here so background delivery remains reliable.
}

class NotificationService {
  NotificationService._();

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static GlobalKey<NavigatorState>? _navigatorKey;
  static StreamSubscription<String>? _tokenSubscription;
  static StreamSubscription<User?>? _authSubscription;
  static StreamSubscription<RemoteMessage>? _foregroundSubscription;
  static bool _initialized = false;

  static Future<void> initialize(GlobalKey<NavigatorState> navigatorKey) async {
    if (_initialized) return;
    _initialized = true;
    _navigatorKey = navigatorKey;

    if (kIsWeb) return;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      debugPrint('Notification permission: ${settings.authorizationStatus}');
    } catch (error, stackTrace) {
      debugPrint('Notification permission request failed: $error\n$stackTrace');
    }

    try {
      final token = await _messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await _saveToken(token);
      }
    } catch (error, stackTrace) {
      debugPrint('FCM token fetch failed: $error\n$stackTrace');
    }

    _tokenSubscription = _messaging.onTokenRefresh.listen((token) async {
      if (token.trim().isEmpty) return;
      await _saveToken(token.trim());
    });

    _authSubscription = _auth.authStateChanges().listen((_) async {
      try {
        final token = await _messaging.getToken();
        if (token != null && token.isNotEmpty) {
          await _saveToken(token);
        }
      } catch (error, stackTrace) {
        debugPrint('FCM token refresh after auth change failed: $error\n$stackTrace');
      }
    });

    _foregroundSubscription = FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
  }

  static Future<void> dispose() async {
    await _tokenSubscription?.cancel();
    await _authSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    _tokenSubscription = null;
    _authSubscription = null;
    _foregroundSubscription = null;
    _initialized = false;
  }

  static Future<void> _saveToken(String token) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _firestore.collection('partners').doc(user.uid).set(
        {
          'fcmToken': token,
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (error, stackTrace) {
      debugPrint('FCM token save failed: $error\n$stackTrace');
    }
  }

  static void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    final title = notification?.title ?? message.data['title']?.toString() ?? 'WE DRIVE';
    final body = notification?.body ?? message.data['body']?.toString() ?? 'You have a new partner update.';

    final state = _navigatorKey?.currentState;
    if (state == null) return;

    final messenger = ScaffoldMessenger.maybeOf(state.context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text('$title\n$body'),
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        action: message.data['bookingId'] != null
            ? SnackBarAction(
                label: 'VIEW',
                onPressed: () {},
              )
            : null,
      ),
    );
  }
}

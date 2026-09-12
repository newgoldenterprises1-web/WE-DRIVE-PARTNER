import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:razorpay_flutter/razorpay_flutter.dart';

class RazorpayPaymentService {
  RazorpayPaymentService._();

  static final RazorpayPaymentService instance = RazorpayPaymentService._();

  // Development mode: simulates a successful payment locally. It does not
  // charge money or write payment/activation state to Firestore.
  // Set to false only after the server-side Razorpay Test/Live order and
  // verification endpoints are configured.
  static const bool testMode = true;

  // Session-only development activation. This is deliberately kept in memory
  // so Test Mode can open the partner UI without weakening Firestore rules.
  static bool testOnboardingActivated = false;

  static const String _functionBaseUrl =
      'https://asia-south1-we-drive-4315a.cloudfunctions.net';

  Razorpay? _razorpay;
  Completer<bool>? _paymentCompleter;
  String? _activeOrderId;
  String? _activePlan;

  bool get isTestMode => testMode;

  Future<bool> payPlan({required String plan}) async {
    final normalizedPlan = plan.trim().toUpperCase();
    if (normalizedPlan != 'ONBOARDING' && normalizedPlan != 'PREMIUM') {
      return false;
    }
    if (_paymentCompleter != null) return false;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    if (testMode) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (normalizedPlan == 'ONBOARDING') {
        testOnboardingActivated = true;
      }
      return true;
    }

    final token = await user.getIdToken();
    if (token == null || token.isEmpty) return false;

    try {
      final order = await _createOrder(token, normalizedPlan);
      final keyId = (order['keyId'] ?? '').toString();
      final orderId = (order['orderId'] ?? '').toString();
      final amount = order['amount'];
      final currency = (order['currency'] ?? 'INR').toString();
      if (keyId.isEmpty || orderId.isEmpty || amount is! num) return false;

      _activeOrderId = orderId;
      _activePlan = normalizedPlan;
      final completer = Completer<bool>();
      _paymentCompleter = completer;

      final razorpay = Razorpay();
      _razorpay = razorpay;
      razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handleSuccess);
      razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handleFailure);
      razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleWallet);

      razorpay.open({
        'key': keyId,
        'amount': amount,
        'currency': currency,
        'order_id': orderId,
        'name': 'WE DRIVE',
        'description': normalizedPlan == 'PREMIUM'
            ? 'Premium Chauffeur Upgrade'
            : 'WE DRIVE Partner Onboarding',
        'prefill': {
          'name': user.displayName ?? '',
          'email': user.email ?? '',
          'contact': user.phoneNumber ?? '',
        },
        'theme': {'color': '#0D223F'},
      });

      final result = await completer.future;
      _disposeRazorpay();
      return result;
    } catch (error, stackTrace) {
      debugPrint('Razorpay payment failed: $error\n$stackTrace');
      _disposeRazorpay();
      return false;
    }
  }

  Future<Map<String, dynamic>> _createOrder(String token, String plan) async {
    final response = await http.post(
      Uri.parse('$_functionBaseUrl/createPaymentOrder'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'plan': plan}),
    );

    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        (data['error'] ?? 'Unable to create payment order').toString(),
      );
    }
    return data;
  }

  Future<void> _handleSuccess(PaymentSuccessResponse response) async {
    final completer = _paymentCompleter;
    final orderId = _activeOrderId;
    final plan = _activePlan;
    if (completer == null || orderId == null || plan == null) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw StateError('Please sign in again.');
      final token = await user.getIdToken();
      if (token == null || token.isEmpty) {
        throw StateError('Missing authentication token.');
      }

      final paymentId = (response.paymentId ?? '').trim();
      final returnedOrderId = (response.orderId ?? '').trim();
      final signature = (response.signature ?? '').trim();
      if (paymentId.isEmpty || signature.isEmpty || returnedOrderId != orderId) {
        throw StateError('Payment verification data is incomplete.');
      }

      final httpResponse = await http.post(
        Uri.parse('$_functionBaseUrl/verifyPayment'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'plan': plan,
          'orderId': orderId,
          'paymentId': paymentId,
          'signature': signature,
        }),
      );
      final data = _decode(httpResponse);
      if (httpResponse.statusCode < 200 ||
          httpResponse.statusCode >= 300 ||
          data['ok'] != true) {
        throw StateError(
          (data['error'] ?? 'Payment verification failed').toString(),
        );
      }

      if (!completer.isCompleted) completer.complete(true);
    } catch (error, stackTrace) {
      debugPrint('Payment verification failed: $error\n$stackTrace');
      if (!completer.isCompleted) completer.complete(false);
    }
  }

  void _handleFailure(PaymentFailureResponse response) {
    debugPrint(
      'Razorpay checkout error: ${response.code} ${response.message}',
    );
    final completer = _paymentCompleter;
    if (completer != null && !completer.isCompleted) completer.complete(false);
  }

  void _handleWallet(ExternalWalletResponse response) {
    debugPrint('Razorpay external wallet: ${response.walletName}');
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.body.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  void _disposeRazorpay() {
    _razorpay?.clear();
    _razorpay = null;
    _paymentCompleter = null;
    _activeOrderId = null;
    _activePlan = null;
  }
}

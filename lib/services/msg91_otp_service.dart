import 'dart:convert';
import 'dart:developer' as developer;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:sendotp_flutter_sdk/sendotp_flutter_sdk.dart';

class Msg91OtpService {
  Msg91OtpService._();

  static final Msg91OtpService instance = Msg91OtpService._();

  static const String widgetId = '36696d6a754f383834373433';
  static const String authToken = String.fromEnvironment('MSG91_AUTH_TOKEN');
  static const String apiBaseUrl = String.fromEnvironment('WE_DRIVE_API_BASE_URL');

  bool _initialized = false;

  bool get isConfigured => authToken.trim().isNotEmpty && apiBaseUrl.trim().isNotEmpty;

  void initialize() {
    _ensureConfigured();
    if (_initialized) return;

    final token = authToken.trim();
    OTPWidget.initializeWidget(widgetId, token);
    _initialized = true;
    developer.log('MSG91 OTP widget initialized: $widgetId', name: 'WE_DRIVE_OTP');
  }

  Future<Map<String, dynamic>> sendOtp(String phoneNumber) async {
    initialize();

    final identifier = phoneNumber.trim();
    if (!RegExp(r'^\d{12}$').hasMatch(identifier)) {
      throw StateError('Invalid OTP mobile identifier. Expected country code + 10 digit mobile number.');
    }

    try {
      final response = await OTPWidget.sendOTP({'identifier': identifier});
      final result = _asMap(response);
      developer.log('MSG91 Send OTP response received: $result', name: 'WE_DRIVE_OTP');
      return result;
    } catch (e, stackTrace) {
      developer.log('MSG91 Send OTP failed: $e', name: 'WE_DRIVE_OTP', error: e, stackTrace: stackTrace);
      throw StateError(_friendlyMsg91Error(e));
    }
  }

  Future<Map<String, dynamic>> verifyOtp({
    required String requestId,
    required String otp,
    required String phoneNumber,
  }) async {
    initialize();

    final response = await OTPWidget.verifyOTP({
      'reqId': requestId,
      'otp': otp,
    });

    final result = _asMap(response);
    final accessToken = _extractAccessToken(result);
    if (accessToken.isEmpty) {
      throw StateError('MSG91 verification succeeded but no access token was returned.');
    }

    final uri = Uri.parse('$apiBaseUrl/api/auth/driver/msg91');
    final httpResponse = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'accessToken': accessToken,
        'phoneNumber': phoneNumber,
      }),
    ).timeout(const Duration(seconds: 20));

    final data = _decodeHttpResponse(httpResponse);
    final customToken = data['customToken'];
    if (customToken is! String || customToken.isEmpty) {
      throw StateError('Authentication server did not return a Firebase custom token.');
    }

    await FirebaseAuth.instance.signInWithCustomToken(customToken);
    return data;
  }

  Future<Map<String, dynamic>> retryViaWhatsApp(String requestId) async {
    initialize();
    try {
      final response = await OTPWidget.retryOTP({
        'reqId': requestId,
        'retryChannel': 12,
      });
      return _asMap(response);
    } catch (e, stackTrace) {
      developer.log('MSG91 WhatsApp retry failed: $e', name: 'WE_DRIVE_OTP', error: e, stackTrace: stackTrace);
      throw StateError(_friendlyMsg91Error(e));
    }
  }

  Future<Map<String, dynamic>> retryViaSms(String requestId) async {
    initialize();
    try {
      final response = await OTPWidget.retryOTP({
        'reqId': requestId,
        'retryChannel': 11,
      });
      return _asMap(response);
    } catch (e, stackTrace) {
      developer.log('MSG91 SMS retry failed: $e', name: 'WE_DRIVE_OTP', error: e, stackTrace: stackTrace);
      throw StateError(_friendlyMsg91Error(e));
    }
  }

  void _ensureConfigured() {
    if (authToken.trim().isEmpty || apiBaseUrl.trim().isEmpty) {
      throw StateError(
        'OTP backend is not configured. Build with --dart-define=MSG91_AUTH_TOKEN=YOUR_TOKEN '
        '--dart-define=WE_DRIVE_API_BASE_URL=https://YOUR-BACKEND-URL',
      );
    }
  }

  Map<String, dynamic> _decodeHttpResponse(http.Response response) {
    Map<String, dynamic> data = {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) data = Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Keep the generic HTTP error below.
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(data['error']?.toString() ?? 'Authentication server error (${response.statusCode}).');
    }
    return data;
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    throw StateError('Unexpected MSG91 response: $value');
  }

  String _extractAccessToken(Map<String, dynamic> data) {
    final candidates = <dynamic>[
      data['access-token'],
      data['accessToken'],
      data['token'],
      data['data'] is Map ? data['data']['access-token'] : null,
      data['data'] is Map ? data['data']['accessToken'] : null,
      data['data'] is Map ? data['data']['token'] : null,
    ];

    for (final candidate in candidates) {
      if (candidate is String && candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }
    return '';
  }

  String _friendlyMsg91Error(Object error) {
    final message = error.toString().replaceFirst('StateError: ', '').trim();
    if (message.isEmpty) return 'MSG91 could not send the OTP. Please try again.';
    return message;
  }
}

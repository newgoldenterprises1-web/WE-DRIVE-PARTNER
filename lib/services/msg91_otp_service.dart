import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class Msg91OtpService {
  Msg91OtpService._();

  static final Msg91OtpService instance = Msg91OtpService._();

  static const String apiBaseUrl = String.fromEnvironment(
    'WE_DRIVE_API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8080',
  );

  bool get isConfigured => apiBaseUrl.trim().isNotEmpty;

  void initialize() {}

  Future<Map<String, dynamic>> sendOtp(String phoneNumber) async {
    final response = await _post('/api/auth/driver/msg91/send', {
      'phoneNumber': phoneNumber,
    });
    final reqId = response['reqId'];
    if (reqId is! String || reqId.trim().isEmpty) {
      throw StateError('OTP server did not return a request ID.');
    }
    return response;
  }

  Future<Map<String, dynamic>> verifyOtp({
    required String requestId,
    required String otp,
    required String phoneNumber,
  }) async {
    final data = await _post('/api/auth/driver/msg91/verify', {
      'reqId': requestId,
      'otp': otp,
      'phoneNumber': phoneNumber,
    });

    final customToken = data['customToken'];
    if (customToken is! String || customToken.isEmpty) {
      throw StateError('Authentication server did not return a Firebase custom token.');
    }

    await FirebaseAuth.instance.signInWithCustomToken(customToken);
    return data;
  }

  Future<Map<String, dynamic>> retryViaWhatsApp(String requestId) async {
    return _post('/api/auth/driver/msg91/retry', {
      'reqId': requestId,
      'retryChannel': 12,
    });
  }

  Future<Map<String, dynamic>> retryViaSms(String requestId) async {
    return _post('/api/auth/driver/msg91/retry', {
      'reqId': requestId,
      'retryChannel': 11,
    });
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    if (apiBaseUrl.trim().isEmpty) {
      throw StateError('WE DRIVE authentication server is not configured.');
    }

    final uri = Uri.parse('${apiBaseUrl.replaceFirst(RegExp(r'/$'), '')}$path');
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 25));

      Map<String, dynamic> data = {};
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) data = Map<String, dynamic>.from(decoded);
      } catch (_) {}

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(data['error']?.toString() ?? 'Authentication server error (${response.statusCode}).');
      }
      return data;
    } on StateError {
      rethrow;
    } catch (e) {
      throw StateError('Could not reach WE DRIVE authentication server. $e');
    }
  }
}

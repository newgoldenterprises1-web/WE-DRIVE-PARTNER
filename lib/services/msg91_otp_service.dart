import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:sendotp_flutter_sdk/sendotp_flutter_sdk.dart';

class Msg91OtpService {
  Msg91OtpService._();

  static final Msg91OtpService instance = Msg91OtpService._();

  // This is the actual MSG91 Widget ID from the configured widget's
  // Client Side Integration page. It is not the human-readable widget name.
  static const String widgetId = String.fromEnvironment(
    'MSG91_WIDGET_ID',
    defaultValue: '36696d6a754f383834373433',
  );

  // Keep the widget token out of GitHub. Supply it locally with:
  // --dart-define=MSG91_WIDGET_AUTH_TOKEN=YOUR_TOKEN
  static const String widgetAuthToken = String.fromEnvironment(
    'MSG91_WIDGET_AUTH_TOKEN',
    defaultValue: '',
  );

  static const String apiBaseUrl = String.fromEnvironment(
    'WE_DRIVE_API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8080',
  );

  bool _initialized = false;

  bool get isConfigured =>
      apiBaseUrl.trim().isNotEmpty &&
      widgetId.trim().isNotEmpty &&
      widgetAuthToken.trim().isNotEmpty;

  void initialize() {
    _ensureInitialized();
  }

  void _ensureInitialized() {
    if (_initialized) return;
    if (widgetId.trim().isEmpty) {
      throw StateError('MSG91 Widget ID is not configured.');
    }
    if (widgetAuthToken.trim().isEmpty || widgetAuthToken.startsWith('YOUR_')) {
      throw StateError('MSG91 Widget Auth Token is not configured.');
    }

    OTPWidget.initializeWidget(widgetId.trim(), widgetAuthToken.trim());
    _initialized = true;
  }

  String _normalizeIdentifier(String phoneNumber) {
    final digits = phoneNumber.replaceAll(RegExp(r'\D'), '');
    final local = digits.startsWith('91') && digits.length == 12
        ? digits.substring(2)
        : digits;

    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(local)) {
      throw StateError('Use a valid Indian mobile number.');
    }

    // MSG91 SDK expects the country code without the + sign.
    return '91$local';
  }

  Map<String, dynamic> _asMap(Map<String, dynamic>? response) {
    return response == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(response);
  }

  String _extractRequestId(Map<String, dynamic> data) {
    for (final value in [
      data['reqId'],
      data['reqid'],
      data['requestId'],
      data['request_id'],
      data['message'],
      data['data'] is Map ? (data['data'] as Map)['reqId'] : null,
      data['data'] is Map ? (data['data'] as Map)['requestId'] : null,
    ]) {
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  String _extractAccessToken(Map<String, dynamic> data) {
    for (final value in [
      data['access-token'],
      data['accessToken'],
      data['token'],
      data['data'] is Map ? (data['data'] as Map)['access-token'] : null,
      data['data'] is Map ? (data['data'] as Map)['accessToken'] : null,
      data['data'] is Map ? (data['data'] as Map)['token'] : null,
    ]) {
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  Future<Map<String, dynamic>> sendOtp(String phoneNumber) async {
    _ensureInitialized();

    final identifier = _normalizeIdentifier(phoneNumber);
    final response = _asMap(
      await OTPWidget.sendOTP({'identifier': identifier}),
    );

    final type = response['type']?.toString().toLowerCase();
    if (type != null && type.isNotEmpty && type != 'success') {
      throw StateError(
        response['message']?.toString() ?? 'MSG91 could not send the OTP.',
      );
    }

    final reqId = _extractRequestId(response);
    if (reqId.isEmpty && _extractAccessToken(response).isEmpty) {
      throw StateError('MSG91 did not return a request ID.');
    }

    return <String, dynamic>{
      ...response,
      'reqId': reqId,
      'phoneNumber': '+$identifier',
      'channel': 'sms',
    };
  }

  Future<Map<String, dynamic>> verifyOtp({
    required String requestId,
    required String otp,
    required String phoneNumber,
  }) async {
    _ensureInitialized();

    final cleanOtp = otp.trim();
    if (!RegExp(r'^\d{4,8}$').hasMatch(cleanOtp)) {
      throw StateError('Enter a valid OTP.');
    }

    final response = _asMap(
      await OTPWidget.verifyOTP({
        'reqId': requestId.trim(),
        'otp': cleanOtp,
      }),
    );

    final type = response['type']?.toString().toLowerCase();
    if (type != null && type.isNotEmpty && type != 'success') {
      throw StateError(
        response['message']?.toString() ?? 'MSG91 OTP verification failed.',
      );
    }

    final accessToken = _extractAccessToken(response);
    if (accessToken.isEmpty) {
      throw StateError('MSG91 verification succeeded but no access token was returned.');
    }

    // MSG91 access-token verification stays on the backend. The backend
    // validates the token with MSG91 and returns a Firebase custom token.
    final data = await _post('/api/auth/driver/msg91', {
      'accessToken': accessToken,
      'phoneNumber': phoneNumber,
    });

    final customToken = data['customToken'];
    if (customToken is! String || customToken.trim().isEmpty) {
      throw StateError(
        'Authentication server did not return a Firebase custom token.',
      );
    }

    await FirebaseAuth.instance.signInWithCustomToken(customToken);
    return data;
  }

  Future<Map<String, dynamic>> retryViaWhatsApp(String requestId) async {
    _ensureInitialized();
    return _retry(requestId, 12);
  }

  Future<Map<String, dynamic>> retryViaSms(String requestId) async {
    _ensureInitialized();
    return _retry(requestId, 11);
  }

  Future<Map<String, dynamic>> _retry(String requestId, int retryChannel) async {
    final id = requestId.trim();
    if (id.isEmpty) throw StateError('MSG91 request ID is required.');

    final response = _asMap(
      await OTPWidget.retryOTP({
        'reqId': id,
        'retryChannel': retryChannel,
      }),
    );

    final type = response['type']?.toString().toLowerCase();
    if (type != null && type.isNotEmpty && type != 'success') {
      throw StateError(
        response['message']?.toString() ?? 'MSG91 could not resend the OTP.',
      );
    }

    return <String, dynamic>{
      ...response,
      'reqId': _extractRequestId(response).isEmpty
          ? id
          : _extractRequestId(response),
      'channel': retryChannel == 11 ? 'sms' : 'whatsapp',
    };
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    if (apiBaseUrl.trim().isEmpty) {
      throw StateError('WE DRIVE authentication server is not configured.');
    }

    final uri = Uri.parse(
      '${apiBaseUrl.replaceFirst(RegExp(r'/$'), '')}$path',
    );

    try {
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 25));

      Map<String, dynamic> data = {};
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          data = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          data['error']?.toString() ??
              'Authentication server error (${response.statusCode}).',
        );
      }
      return data;
    } on StateError {
      rethrow;
    } catch (e) {
      throw StateError('Could not reach WE DRIVE authentication server. $e');
    }
  }
}

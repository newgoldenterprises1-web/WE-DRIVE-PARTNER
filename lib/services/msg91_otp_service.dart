import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

/// Authentication service used by the existing partner login UI.
///
/// The class name is kept for compatibility with the current screen, but the
/// OTP provider is now Firebase Phone Authentication. No WE DRIVE backend is
/// required to send or verify the SMS OTP.
class Msg91OtpService {
  Msg91OtpService._();

  static final Msg91OtpService instance = Msg91OtpService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _verificationId;
  int? _resendToken;
  String? _phoneNumber;

  bool get isConfigured => true;

  void initialize() {}

  String _normalizePhone(String phoneNumber) {
    final digits = phoneNumber.replaceAll(RegExp(r'\D'), '');
    final local = digits.startsWith('91') && digits.length == 12
        ? digits.substring(2)
        : digits;

    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(local)) {
      throw StateError('Please enter a valid 10-digit Indian mobile number.');
    }

    return '+91$local';
  }

  String _firebaseError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-phone-number':
        return 'Invalid mobile number.';
      case 'too-many-requests':
        return 'Too many OTP requests. Please wait and try again later.';
      case 'quota-exceeded':
        return 'Firebase SMS quota has been exceeded. Please try again later.';
      case 'operation-not-allowed':
        return 'Firebase Phone Authentication is not enabled for this app.';
      case 'app-not-authorized':
        return 'This Android app is not authorized in Firebase. Check SHA-1/SHA-256.';
      case 'captcha-check-failed':
        return 'Firebase app verification failed. Please try again.';
      case 'network-request-failed':
        return 'Network error. Please check the phone internet connection.';
      default:
        return e.message?.trim().isNotEmpty == true
            ? e.message!.trim()
            : 'Firebase could not send the OTP (${e.code}).';
    }
  }

  Future<Map<String, dynamic>> sendOtp(String phoneNumber) async {
    final normalized = _normalizePhone(phoneNumber);
    _phoneNumber = normalized;

    final completer = Completer<Map<String, dynamic>>();

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: normalized,
        timeout: const Duration(seconds: 60),
        forceResendingToken: _resendToken,
        verificationCompleted: (PhoneAuthCredential credential) async {
          try {
            await _auth.signInWithCredential(credential);
          } catch (_) {
            // Manual OTP entry can still complete the sign-in.
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          if (!completer.isCompleted) {
            completer.completeError(StateError(_firebaseError(e)));
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId;
          _resendToken = resendToken;
          if (!completer.isCompleted) {
            completer.complete(<String, dynamic>{
              'reqId': verificationId,
              'phoneNumber': normalized,
              'channel': 'sms',
            });
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } on FirebaseAuthException catch (e) {
      if (!completer.isCompleted) {
        completer.completeError(StateError(_firebaseError(e)));
      }
    } catch (e) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Could not start Firebase OTP: $e'));
      }
    }

    return completer.future;
  }

  Future<Map<String, dynamic>> verifyOtp({
    required String requestId,
    required String otp,
    required String phoneNumber,
  }) async {
    final cleanOtp = otp.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(cleanOtp)) {
      throw StateError('Please enter the 6-digit OTP sent by SMS.');
    }

    final verificationId = requestId.trim().isNotEmpty
        ? requestId.trim()
        : _verificationId;

    if (verificationId == null || verificationId.isEmpty) {
      throw StateError('OTP session expired. Please request a new OTP.');
    }

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: cleanOtp,
      );

      final result = await _auth.signInWithCredential(credential);
      final user = result.user;

      if (user == null) {
        throw StateError('Firebase sign-in did not create a user session.');
      }

      return <String, dynamic>{
        'success': true,
        'uid': user.uid,
        'phoneNumber': user.phoneNumber ?? _phoneNumber ?? phoneNumber,
        'channel': 'sms',
      };
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'invalid-verification-code':
          throw StateError('Incorrect OTP. Please check the SMS and try again.');
        case 'session-expired':
          throw StateError('OTP expired. Please request a new OTP.');
        case 'credential-already-in-use':
          throw StateError('This mobile number is already linked to another account.');
        default:
          throw StateError(_firebaseError(e));
      }
    }
  }

  Future<Map<String, dynamic>> retryViaSms(String requestId) async {
    final phone = _phoneNumber;
    if (phone == null || phone.isEmpty) {
      throw StateError('Please request the OTP again.');
    }
    return sendOtp(phone);
  }

  /// Kept only so the existing UI remains source-compatible.
  /// Firebase Phone Auth sends the verification code by SMS.
  Future<Map<String, dynamic>> retryViaWhatsApp(String requestId) async {
    return retryViaSms(requestId);
  }
}

import 'package:firebase_auth/firebase_auth.dart';

class PhoneAuthService {
  PhoneAuthService._();

  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static Future<void> verifyAndSignIn({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(UserCredential credential) onVerified,
    required void Function(FirebaseAuthException error) onError,
    void Function(String verificationId)? onCodeAutoRetrievalTimeout,
  }) async {
    final phone = phoneNumber.trim();
    if (phone.isEmpty) {
      onError(FirebaseAuthException(code: 'invalid-phone-number'));
      return;
    }
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          try {
            final result = await _auth.signInWithCredential(credential);
            onVerified(result);
          } on FirebaseAuthException catch (error) {
            onError(error);
          }
        },
        verificationFailed: onError,
        codeSent: onCodeSent,
        codeAutoRetrievalTimeout: onCodeAutoRetrievalTimeout ?? (_) {},
      );
    } on FirebaseAuthException catch (error) {
      onError(error);
    }
  }

  static Future<void> verifyAndLinkPhone({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(UserCredential credential) onVerified,
    required void Function(FirebaseAuthException error) onError,
    void Function(String verificationId)? onCodeAutoRetrievalTimeout,
  }) async {
    final currentUser = _auth.currentUser;
    final phone = phoneNumber.trim();
    if (currentUser == null || phone.isEmpty) {
      onError(FirebaseAuthException(code: 'invalid-state'));
      return;
    }
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          try {
            final result = await currentUser.linkWithCredential(credential);
            onVerified(result);
          } on FirebaseAuthException catch (error) {
            onError(error);
          }
        },
        verificationFailed: onError,
        codeSent: onCodeSent,
        codeAutoRetrievalTimeout: onCodeAutoRetrievalTimeout ?? (_) {},
      );
    } on FirebaseAuthException catch (error) {
      onError(error);
    }
  }

  static Future<UserCredential> signInWithSmsCode({required String verificationId, required String smsCode}) {
    final credential = PhoneAuthProvider.credential(verificationId: verificationId, smsCode: smsCode.trim());
    return _auth.signInWithCredential(credential);
  }

  static Future<UserCredential> linkPhoneWithSmsCode({required String verificationId, required String smsCode}) async {
    final user = _auth.currentUser;
    if (user == null) throw FirebaseAuthException(code: 'invalid-state');
    final credential = PhoneAuthProvider.credential(verificationId: verificationId, smsCode: smsCode.trim());
    return user.linkWithCredential(credential);
  }
}

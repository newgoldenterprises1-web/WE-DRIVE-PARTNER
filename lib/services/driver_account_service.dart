import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Bootstraps every Firebase Phone Auth session into a WE DRIVE driver account.
/// The server assigns the driver role, creates the partner profile, and the
/// client then force-refreshes its ID token so Firestore/Storage rules see it.
class DriverAccountService {
  DriverAccountService._();

  static final DriverAccountService instance = DriverAccountService._();

  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-south1');

  Future<void> ensureDriverAccount({String? name}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Partner session is not available.');
    }

    final callable = _functions.httpsCallable('ensureDriverAccount');
    await callable.call(<String, dynamic>{
      'name': (name ?? '').trim(),
      'phoneNumber': user.phoneNumber,
    });

    await user.getIdToken(true);
    await user.reload();
    await user.getIdToken(true);
  }
}

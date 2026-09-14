import 'package:cloud_functions/cloud_functions.dart';

class PayoutService {
  PayoutService._();
  static final PayoutService instance = PayoutService._();

  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'asia-south1');

  Future<String> setFrequency(String frequency) async {
    final result = await _functions.httpsCallable('setPayoutPreference').call({
      'frequency': frequency.toLowerCase(),
    });
    return String(result.data['frequency'] ?? frequency).toLowerCase();
  }

  Future<Map<String, dynamic>> withdraw() async {
    final result = await _functions.httpsCallable('requestPayout').call();
    return Map<String, dynamic>.from(result.data as Map);
  }
}

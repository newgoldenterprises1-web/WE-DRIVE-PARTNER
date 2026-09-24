import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../profile/verification_screen.dart';
import '../../theme/app_theme.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  late final Razorpay _razorpay;
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'asia-south1');
  bool paying = false;
  String? pendingOrderId;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  Future<void> _startPayment() async {
    if (paying) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _show('Please complete mobile verification first.', isError: true);
      return;
    }

    setState(() => paying = true);
    try {
      final result = await _functions.httpsCallable('createPartnerRegistrationOrder').call();
      final data = Map<String, dynamic>.from(result.data as Map);

      if (data['alreadyPaid'] == true) {
        if (!mounted) return;
        setState(() => paying = false);
        _openVerification();
        return;
      }

      pendingOrderId = data['orderId']?.toString();

      _razorpay.open({
        'key': data['keyId'],
        'amount': data['amount'],
        'currency': data['currency'] ?? 'INR',
        'order_id': data['orderId'],
        'name': 'WeDrive247',
        'description': 'Partner registration and verification',
        'prefill': {
          if (user.phoneNumber != null) 'contact': user.phoneNumber!.replaceFirst('+91', ''),
        },
        'theme': {'color': '#173B6D'},
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => paying = false);
      _show(e.toString().replaceFirst('Exception: ', ''), isError: true);
    }
  }

  Future<void> _onPaymentSuccess(PaymentSuccessResponse response) async {
    final orderId = response.orderId ?? pendingOrderId;
    final paymentId = response.paymentId;
    final signature = response.signature;

    if (orderId == null || paymentId == null || signature == null) {
      if (mounted) setState(() => paying = false);
      _show('Payment returned incomplete verification details.', isError: true);
      return;
    }

    try {
      await _functions.httpsCallable('verifyPartnerRegistrationPayment').call({
        'orderId': orderId,
        'paymentId': paymentId,
        'signature': signature,
      });
      if (!mounted) return;
      setState(() => paying = false);
      _show('Payment verified. Your documents can now be submitted.');
      _openVerification();
    } catch (e) {
      if (!mounted) return;
      setState(() => paying = false);
      _show('Payment verification failed: ' + e.toString().replaceFirst('Exception: ', ''), isError: true);
    }
  }

  void _onPaymentError(PaymentFailureResponse response) {
    if (!mounted) return;
    setState(() => paying = false);
    _show(response.message ?? 'Payment was not completed.', isError: true);
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    if (!mounted) return;
    setState(() => paying = false);
    _show('External wallet selected: ' + (response.walletName ?? 'wallet'));
  }

  void _openVerification() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const VerificationScreen()),
      (_) => false,
    );
  }

  void _show(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.gold.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(Icons.verified_user_rounded, color: AppColors.gold, size: 54),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Partner Onboarding Fee',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.navy, fontSize: 24, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              const Text(
                'Complete your registration by paying the one-time verification & uniform fee.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 32),
              AppCard(
                child: Column(
                  children: const [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('Background Verification (BGV)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      Text('₹199', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ]),
                    SizedBox(height: 12),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('Official WeDrive247 T-Shirt', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      Text('₹100', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ]),
                    Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1)),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('Total Payable', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.navy)),
                      Text('₹299', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.navy)),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: paying ? null : _startPayment,
                child: paying
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                    : const Text('PAY ₹299 & SUBMIT', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.5)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../data/app_data.dart';
import '../../services/partner_plan_service.dart';
import '../../services/razorpay_payment_service.dart';
import '../../theme/app_theme.dart';
import '../home/home_screen.dart';

class OnboardingPaymentScreen extends StatefulWidget {
  const OnboardingPaymentScreen({super.key});

  @override
  State<OnboardingPaymentScreen> createState() => _OnboardingPaymentScreenState();
}

class _OnboardingPaymentScreenState extends State<OnboardingPaymentScreen> {
  bool processing = false;

  Future<void> _pay() async {
    if (processing) return;
    if (FirebaseAuth.instance.currentUser == null) return;

    setState(() => processing = true);
    final success = await RazorpayPaymentService.instance.payPlan(plan: 'ONBOARDING');
    if (!mounted) return;

    if (success) {
      if (RazorpayPaymentService.testMode && AppData.testPartnerActivated) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('₹299 dummy payment completed. Test activation enabled for this app session.'),
            backgroundColor: AppColors.navy,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (_) => false,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('₹299 payment completed.'),
            backgroundColor: AppColors.navy,
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Onboarding payment was not completed.'),
          backgroundColor: Colors.orange,
        ),
      );
    }

    if (mounted) setState(() => processing = false);
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: AppColors.navy,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.verified_user_rounded, color: AppColors.gold, size: 42),
                      SizedBox(height: 14),
                      Text(
                        'Complete Partner Onboarding',
                        style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Pay the one-time onboarding fee to activate your WE DRIVE Partner account.',
                        style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AppCard(
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          Text('Onboarding fee', style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w800)),
                          Text('₹299', style: TextStyle(color: AppColors.gold, fontSize: 24, fontWeight: FontWeight.w900)),
                        ],
                      ),
                      const Divider(height: 28),
                      const _Benefit(icon: Icons.badge_rounded, text: 'Partner account verification'),
                      const _Benefit(icon: Icons.directions_car_rounded, text: 'Access to regular ride requests after activation'),
                      const _Benefit(icon: Icons.workspace_premium_rounded, text: 'Premium Drive upgrade remains separate at ₹699'),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    onPressed: processing ? null : _pay,
                    child: processing
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('PAY ₹299 & CONTINUE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Development mode: this payment is simulated safely. No real money is charged. Test activation lasts only for this app session; no Firestore payment or live account activation is performed.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.4),
                ),
                const SizedBox(height: 18),
                TextButton(
                  onPressed: _signOut,
                  child: const Text('SIGN OUT', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy)),
                ),
                const SizedBox(height: 6),
                Text(
                  'Partner plan: ${PartnerPlanService.standardPlanName}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted, fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Icon(icon, color: AppColors.navy, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../home/home_screen.dart';
import 'login_screen.dart';
import 'onboarding_payment_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _controller.forward();
    _checkAuthAndNavigate();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _checkAuthAndNavigate() async {
    try {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;

      final user = FirebaseAuth.instance.currentUser;
      Widget targetScreen = const LoginScreen();

      if (user != null) {
        try {
          final snapshot = await FirebaseFirestore.instance.collection('partners').doc(user.uid).get();
          final data = snapshot.data() ?? <String, dynamic>{};
          final paymentStatus = (data['onboardingPaymentStatus'] ?? 'PENDING').toString().toUpperCase();
          final accountStatus = (data['accountStatus'] ?? '').toString().toUpperCase();

          if (paymentStatus == 'PAID' && accountStatus != 'PENDING_ONBOARDING_FEE') {
            targetScreen = const HomeScreen();
          } else {
            targetScreen = const OnboardingPaymentScreen();
          }
        } catch (_) {
          targetScreen = const OnboardingPaymentScreen();
        }
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => targetScreen));
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.navyDark, AppColors.navy, Color(0xFF0F172A)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('WE DRIVE', style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: 3)),
                    const SizedBox(height: 8),
                    const Text('Your Car. Your Comfort. Our Chauffeur.', style: TextStyle(color: AppColors.gold, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                    const SizedBox(height: 56),
                    const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 2.5)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../home/home_screen.dart';

class OtpScreen extends StatefulWidget {
  final String phone;

  const OtpScreen({
    super.key,
    required this.phone,
  });

  @override
  State<OtpScreen> createState() {
    return _OtpScreenState();
  }
}

class _OtpScreenState extends State<OtpScreen> {
  final otpController = TextEditingController();
  Timer? timer;
  int seconds = 30;

  @override
  void initState() {
    super.initState();
    startTimer();
  }

  void startTimer() {
    timer?.cancel();
    setState(() {
      seconds = 30;
    });

    timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (seconds == 0) {
        timer.cancel();
        return;
      }

      setState(() {
        seconds--;
      });
    });
  }

  void verifyOtp() {
    if (otpController.text.trim().length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter the 6-digit OTP.'),
        ),
      );
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => const HomeScreen(),
      ),
      (route) => false,
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify OTP'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(26),
        children: [
          const SizedBox(height: 20),
          const Icon(
            Icons.verified_user_rounded,
            color: AppColors.gold,
            size: 48,
          ),
          const SizedBox(height: 20),
          const Text(
            'Enter verification code',
            style: TextStyle(
              color: AppColors.navy,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'OTP sent to +91 ${widget.phone}',
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 26),
          TextField(
            controller: otpController,
            maxLength: 6,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: 6,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: '••••••',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 18),
          AppPrimaryButton(
            label: 'VERIFY OTP',
            onPressed: verifyOtp,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: seconds == 0 ? startTimer : null,
            child: Text(
              seconds == 0 ? 'RESEND OTP' : 'Resend OTP in $seconds s',
            ),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'Demo OTP: 123456',
              style: TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

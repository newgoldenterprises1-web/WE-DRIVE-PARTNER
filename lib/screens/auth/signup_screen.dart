import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'otp_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() {
    return _SignupScreenState();
  }
}

class _SignupScreenState extends State<SignupScreen> {
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final emailController = TextEditingController();
  final cityController = TextEditingController();
  final experienceController = TextEditingController();

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    cityController.dispose();
    experienceController.dispose();
    super.dispose();
  }

  void continueSignup() {
    if (nameController.text.trim().isEmpty ||
        phoneController.text.trim().length != 10 ||
        emailController.text.trim().isEmpty ||
        cityController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete all required fields.'),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => OtpScreen(
          phone: phoneController.text.trim(),
        ),
      ),
    );
  }

  Widget field(
    String label,
    TextEditingController controller,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Become a Partner'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Join WE DRIVE',
            style: TextStyle(
              color: AppColors.navy,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Create your partner profile.',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 24),
          field('Full name', nameController, Icons.person_outline),
          field('Mobile number', phoneController, Icons.phone_outlined),
          field('Email address', emailController, Icons.mail_outline),
          field('City', cityController, Icons.location_on_outlined),
          field(
            'Driving experience',
            experienceController,
            Icons.drive_eta_outlined,
          ),
          const SizedBox(height: 8),
          AppPrimaryButton(
            label: 'CONTINUE',
            onPressed: continueSignup,
          ),
        ],
      ),
    );
  }
}

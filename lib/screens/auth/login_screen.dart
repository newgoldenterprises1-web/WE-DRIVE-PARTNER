import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../services/msg91_otp_service.dart';
import '../../theme/app_theme.dart';
import '../home/home_screen.dart';
import 'payment_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool isSignUp = false;
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  bool isLoading = false;
  String? requestId;
  final _otpService = Msg91OtpService.instance;
  final _functions = FirebaseFunctions.instanceFor(region: 'asia-south1');

  @override
  void initState() {
    super.initState();
    _otpService.initialize();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  String _phoneForMsg91() {
    final digits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 10 || !RegExp(r'^[6-9]').hasMatch(digits)) return '';
    return '91$digits';
  }

  String _extractRequestId(Map<String, dynamic> response) {
    final candidates = <dynamic>[
      response['reqId'],
      response['reqid'],
      response['requestId'],
      response['request_id'],
      response['message'],
      response['data'] is Map ? response['data']['reqId'] : null,
      response['data'] is Map ? response['data']['requestId'] : null,
      response['data'] is Map ? response['data']['message'] : null,
    ];
    for (final candidate in candidates) {
      if (candidate is String && candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }
    return '';
  }

  Future<void> handleSendOtp() async {
    final phone = _phoneForMsg91();
    if (phone.isEmpty) {
      showMessage('Please enter a valid 10-digit Indian mobile number.');
      return;
    }
    if (isSignUp && _nameController.text.trim().isEmpty) {
      showMessage('Please enter your full name for registration.');
      return;
    }

    setState(() => isLoading = true);
    try {
      final response = await _otpService.sendOtp(phone);
      final id = _extractRequestId(response);
      if (id.isEmpty) throw StateError('Firebase did not return an OTP session.');
      requestId = id;
      if (!mounted) return;
      setState(() => isLoading = false);
      await _showOtpDialog(phone);
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      showMessage(e.toString().replaceFirst('StateError: ', ''));
    }
  }

  Future<void> _ensureDriverAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Firebase session was not created. Please verify OTP again.');
    }

    await _functions.httpsCallable('ensureDriverAccount').call({
      'phoneNumber': user.phoneNumber,
      'name': _nameController.text.trim(),
    });

    // The callable sets the driver custom claim. Refresh the ID token so the
    // same login session can immediately use driver-only Firestore/Storage rules.
    await user.getIdToken(true);
  }

  Future<void> _showOtpDialog(String phone) async {
    final otpController = TextEditingController();
    bool verifying = false;
    bool retrying = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> verify() async {
            final otp = otpController.text.trim();
            if (otp.length != 6) {
              showMessage('Please enter the 6-digit OTP sent by SMS.');
              return;
            }
            final id = requestId;
            if (id == null || id.isEmpty) {
              showMessage('OTP session expired. Please request a new OTP.');
              return;
            }
            setDialogState(() => verifying = true);
            try {
              await _otpService.verifyOtp(
                requestId: id,
                otp: otp,
                phoneNumber: phone,
              );

              // Create/sync the partner profile and grant the driver role before
              // opening Home. This makes all driver-only buttons actually work.
              await _ensureDriverAccount();

              if (!mounted) return;
              Navigator.of(dialogContext).pop();
              final target = isSignUp ? const PaymentScreen() : const HomeScreen();
              Navigator.of(this.context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => target), (_) => false,
              );
            } catch (e) {
              setDialogState(() => verifying = false);
              showMessage(e.toString().replaceFirst('StateError: ', ''));
            }
          }

          Future<void> retrySms() async {
            final id = requestId;
            if (id == null || id.isEmpty) return;
            setDialogState(() => retrying = true);
            try {
              final response = await _otpService.retryViaSms(id);
              final newId = _extractRequestId(response);
              if (newId.isNotEmpty) requestId = newId;
              showMessage('A new OTP has been sent by SMS.');
            } catch (e) {
              showMessage(e.toString().replaceFirst('StateError: ', ''));
            } finally {
              setDialogState(() => retrying = false);
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text(
              'Verify your number',
              style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.navy),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'We sent a verification code to your mobile number by SMS.',
                  style: TextStyle(color: AppColors.muted, height: 1.35),
                ),
                const SizedBox(height: 6),
                Text(
                  '+$phone',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    labelText: 'OTP',
                    counterText: '',
                    prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.navy),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 8),
                if (retrying)
                  const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: retrySms,
                      child: const Text('Resend SMS'),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: verifying ? null : () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: verifying ? null : verify,
                child: verifying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('VERIFY & CONTINUE'),
              ),
            ],
          );
        },
      ),
    );
    otpController.dispose();
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
                Center(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.navy,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.navy.withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.local_taxi_rounded, color: AppColors.gold, size: 42),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'WE DRIVE',
                        style: TextStyle(
                          color: AppColors.navy,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Partner Portal • Hyderabad',
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F9FC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => isSignUp = false),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: !isSignUp ? AppColors.navy : Colors.transparent,
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                  child: Text(
                                    'Sign In',
                                    style: TextStyle(
                                      color: !isSignUp ? Colors.white : AppColors.muted,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => isSignUp = true),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: isSignUp ? AppColors.navy : Colors.transparent,
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                  child: Text(
                                    'Register',
                                    style: TextStyle(
                                      color: isSignUp ? Colors.white : AppColors.muted,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        isSignUp ? 'Create Partner Account' : 'Welcome Back',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: AppColors.navy,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isSignUp
                            ? 'Join Hyderabad’s premier chauffeur network.'
                            : 'Continue securely with SMS OTP.',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (isSignUp) ...[
                        TextField(
                          controller: _nameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: 'Full Name',
                            prefixIcon: const Icon(Icons.person_outline_rounded, color: AppColors.navy),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        maxLength: 10,
                        decoration: InputDecoration(
                          labelText: 'Mobile Number',
                          counterText: '',
                          prefixText: '+91  ',
                          prefixIcon: const Icon(Icons.phone_android_rounded, color: AppColors.navy),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.navy,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          onPressed: isLoading ? null : handleSendOtp,
                          icon: const Icon(Icons.chat_rounded),
                          label: isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Text(
                                  'SEND OTP',
                                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.5),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Center(
                        child: Text(
                          'SMS OTP • Powered by Firebase',
                          style: TextStyle(color: AppColors.muted, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

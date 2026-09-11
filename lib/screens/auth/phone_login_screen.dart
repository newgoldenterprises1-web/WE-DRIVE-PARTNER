import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../services/partner_plan_service.dart';
import '../../services/phone_auth_service.dart';
import '../../theme/app_theme.dart';
import '../home/home_screen.dart';

class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  bool register = false;
  bool otpStep = false;
  bool loading = false;
  String? verificationId;
  final name = TextEditingController();
  final phone = TextEditingController(text: '+91 ');
  final email = TextEditingController();
  final password = TextEditingController();
  final otp = TextEditingController();

  @override
  void dispose() {
    name.dispose(); phone.dispose(); email.dispose(); password.dispose(); otp.dispose();
    super.dispose();
  }

  String get normalizedPhone {
    var value = phone.text.trim().replaceAll(' ', '');
    if (value.startsWith('0')) value = '+91${value.substring(1)}';
    if (!value.startsWith('+')) value = '+91$value';
    return value;
  }

  void message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), backgroundColor: error ? Colors.red : null, behavior: SnackBarBehavior.floating));
  }

  Future<void> primary() async => otpStep ? verifyOtp() : (register ? registerAccount() : startLogin());

  Future<void> registerAccount() async {
    final p = normalizedPhone;
    if (name.text.trim().length < 2 || !RegExp(r'^\+91[6-9]\d{9}$').hasMatch(p) || !email.text.contains('@') || password.text.length < 6) {
      message('Enter valid name, Indian mobile, email and 6+ character password.', error: true); return;
    }
    setState(() => loading = true);
    try {
      final c = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email.text.trim(), password: password.text);
      final user = c.user!;
      await user.updateDisplayName(name.text.trim());
      await FirebaseFirestore.instance.collection('partners').doc(user.uid).set({
        'uid': user.uid, 'name': name.text.trim(), 'email': email.text.trim(), 'phone': p,
        'isOnline': false, 'isPremium': false, 'plan': PartnerPlanService.standardPlanName,
        'onboardingFee': PartnerPlanService.onboardingFee, 'onboardingPaymentStatus': 'PENDING',
        'accountStatus': 'PENDING_ONBOARDING_FEE', 'createdAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await requestOtp(link: true);
    } on FirebaseAuthException catch (e) { message(e.message ?? 'Registration failed.', error: true); }
    catch (e) { message('Registration failed: $e', error: true); }
    finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> startLogin() async {
    if (!RegExp(r'^\+91[6-9]\d{9}$').hasMatch(normalizedPhone)) { message('Enter a valid Indian mobile number.', error: true); return; }
    setState(() => loading = true);
    await requestOtp(link: false);
    if (mounted) setState(() => loading = false);
  }

  Future<void> requestOtp({required bool link}) async {
    void sent(String id) {
      if (!mounted) return;
      setState(() { verificationId = id; otpStep = true; loading = false; });
      message('OTP sent to $normalizedPhone');
    }
    void failed(FirebaseAuthException e) => message(e.message ?? 'Phone verification failed.', error: true);
    Future<void> verified(UserCredential c) async {
      final user = c.user ?? FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await ensurePartner(user, allowCreate: link);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const HomeScreen()), (_) => false);
    }
    if (link) {
      await PhoneAuthService.verifyAndLinkPhone(phoneNumber: normalizedPhone, onCodeSent: sent, onVerified: verified, onError: failed);
    } else {
      await PhoneAuthService.verifyAndSignIn(phoneNumber: normalizedPhone, onCodeSent: sent, onVerified: verified, onError: failed);
    }
  }

  Future<void> verifyOtp() async {
    if (verificationId == null || otp.text.trim().length < 6) { message('Enter the 6-digit OTP.', error: true); return; }
    setState(() => loading = true);
    try {
      UserCredential c;
      if (register) {
        c = await PhoneAuthService.linkPhoneWithSmsCode(verificationId: verificationId!, smsCode: otp.text);
      } else {
        c = await PhoneAuthService.signInWithSmsCode(verificationId: verificationId!, smsCode: otp.text);
      }
      final user = c.user!;
      await ensurePartner(user, allowCreate: register);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const HomeScreen()), (_) => false);
    } on FirebaseAuthException catch (e) { message(e.message ?? 'Invalid OTP.', error: true); }
    catch (e) { message(e.toString().contains('registered') ? 'This mobile number is not registered as a WE DRIVE partner.' : 'OTP verification failed: $e', error: true); }
    finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> ensurePartner(User user, {required bool allowCreate}) async {
    final ref = FirebaseFirestore.instance.collection('partners').doc(user.uid);
    final snap = await ref.get();
    if (!snap.exists && !allowCreate) {
      await FirebaseAuth.instance.signOut();
      throw StateError('mobile number is not registered');
    }
    final d = snap.data() ?? <String, dynamic>{};
    await ref.set({
      'uid': user.uid, 'name': d['name'] ?? user.displayName ?? 'Partner', 'email': d['email'] ?? user.email ?? '',
      'phone': normalizedPhone, 'isOnline': d['isOnline'] == true, 'isPremium': d['isPremium'] == true,
      'plan': d['plan'] ?? PartnerPlanService.standardPlanName, 'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: Column(children: [Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: AppColors.navy.withOpacity(.22), blurRadius: 16, offset: const Offset(0, 8))]), child: const Icon(Icons.local_taxi_rounded, color: AppColors.gold, size: 40)), const SizedBox(height: 16), const Text('WE DRIVE', style: TextStyle(color: AppColors.navy, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 1.5)), const SizedBox(height: 4), const Text('Partner Portal • Hyderabad', style: TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w600))])),
        const SizedBox(height: 28),
        Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: Colors.grey.shade200), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.035), blurRadius: 18, offset: const Offset(0, 7))]), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!otpStep) Row(children: [Expanded(child: mode('Sign In', !register, () => setState(() => register = false))), Expanded(child: mode('Register', register, () => setState(() => register = true)))]),
          if (!otpStep) const SizedBox(height: 20),
          Text(otpStep ? 'Verify Mobile Number' : (register ? 'Create Partner Account' : 'Welcome Back'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: AppColors.navy)), const SizedBox(height: 6),
          Text(otpStep ? 'Enter the 6-digit OTP sent to your mobile.' : (register ? 'Email is used only for registration. Future logins use mobile OTP.' : 'Login securely with your registered mobile number.'), style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.35)), const SizedBox(height: 20),
          if (otpStep) field(otp, '6-Digit OTP', Icons.verified_rounded, keyboard: TextInputType.number, maxLength: 6) else ...[
            if (register) ...[field(name, 'Full Name', Icons.person_outline_rounded), const SizedBox(height: 14)],
            field(phone, 'Mobile Number', Icons.phone_iphone_rounded, keyboard: TextInputType.phone),
            if (register) ...[const SizedBox(height: 14), field(email, 'Email Address', Icons.email_outlined, keyboard: TextInputType.emailAddress), const SizedBox(height: 14), field(password, 'Password', Icons.lock_outline_rounded, obscure: true)],
          ],
          const SizedBox(height: 22),
          SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0), onPressed: loading ? null : primary, child: loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Text(otpStep ? 'VERIFY & CONTINUE' : (register ? 'REGISTER & VERIFY MOBILE' : 'SEND OTP'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: .4)))),
        ])),
        if (register && !otpStep) ...[const SizedBox(height: 14), Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: AppColors.gold.withOpacity(.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.gold.withOpacity(.25))), child: const Text('New partner onboarding: ₹299. Premium Chauffeur upgrade: ₹699 with a separate 90% earnings tier.', style: TextStyle(color: AppColors.navy, fontSize: 11.5, height: 1.35, fontWeight: FontWeight.w600)))],
      ]))),
    );
  }

  Widget mode(String label, bool selected, VoidCallback tap) => GestureDetector(onTap: tap, child: Container(padding: const EdgeInsets.symmetric(vertical: 12), alignment: Alignment.center, decoration: BoxDecoration(color: selected ? AppColors.navy : Colors.transparent, borderRadius: BorderRadius.circular(11)), child: Text(label, style: TextStyle(color: selected ? Colors.white : AppColors.muted, fontWeight: FontWeight.w900, fontSize: 13))));

  Widget field(TextEditingController c, String label, IconData icon, {TextInputType? keyboard, bool obscure = false, int? maxLength}) => TextField(controller: c, keyboardType: keyboard, obscureText: obscure, maxLength: maxLength, decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, color: AppColors.navy), counterText: '', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300))));
}

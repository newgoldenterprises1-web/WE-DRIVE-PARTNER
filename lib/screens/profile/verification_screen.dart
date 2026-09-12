import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class VerificationScreen extends StatelessWidget {
  const VerificationScreen({super.key});

  Color _statusColor(String status) {
    final normalized = status.toUpperCase();
    if (normalized == 'APPROVED' || normalized == 'VERIFIED' || normalized == 'ACTIVE') return AppColors.green;
    if (normalized == 'UNDER_REVIEW' || normalized == 'PENDING' || normalized == 'PENDING_REVIEW') return const Color(0xFF8D6900);
    if (normalized == 'REJECTED' || normalized == 'FAILED') return Colors.red;
    return AppColors.muted;
  }

  Widget document(String title, String status, IconData icon) {
    final color = _statusColor(status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Row(children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppColors.navy.withOpacity(0.06), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: AppColors.navy, size: 22)),
          const SizedBox(width: 14),
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppColors.navy))),
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(6)), child: Text(status.toUpperCase(), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900))),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Scaffold(body: Center(child: Text('Please sign in again.')));

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('partners').doc(uid).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? <String, dynamic>{};
        final accountStatus = (data['accountStatus'] ?? 'PENDING').toString().toUpperCase();
        final verificationStatus = (data['verificationStatus'] ?? 'PENDING').toString().toUpperCase();
        final onboardingStatus = (data['onboardingPaymentStatus'] ?? 'PENDING').toString().toUpperCase();
        final onboardingFee = (data['onboardingFee'] is num) ? (data['onboardingFee'] as num).toInt() : 299;
        final dlStatus = (data['dlStatus'] ?? data['licenseStatus'] ?? 'PENDING').toString();
        final idStatus = (data['idStatus'] ?? data['governmentIdStatus'] ?? 'PENDING').toString();
        final selfieStatus = (data['selfieStatus'] ?? data['profilePhotoStatus'] ?? 'PENDING').toString();
        final paid = onboardingStatus == 'PAID' || data['onboardingPaymentStatus'] == 'SUCCESS' || data['onboardingPaymentStatus'] == 'VERIFIED';
        final activated = accountStatus == 'ACTIVE' && paid;

        final bannerColor = activated ? const Color(0xFFE7F7EE) : const Color(0xFFFFF8DD);
        final bannerIcon = activated ? Icons.verified_rounded : Icons.hourglass_top_rounded;
        final bannerText = activated
            ? 'ACCOUNT ACTIVE — Your partner verification is complete.'
            : paid
                ? 'PAYMENT VERIFIED — Your documents are under review.'
                : 'ONBOARDING PAYMENT PENDING — Complete the onboarding payment before activation.';

        return Scaffold(
          backgroundColor: const Color(0xFFF7F9FC),
          appBar: AppBar(title: const Text('Verification & KYC'), elevation: 0),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
            children: [
              AppCard(color: bannerColor, child: Row(children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: (activated ? AppColors.green : AppColors.gold).withOpacity(0.3), borderRadius: BorderRadius.circular(8)), child: Icon(bannerIcon, color: AppColors.navy, size: 22)), const SizedBox(width: 14), Expanded(child: Text(bannerText, style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w800, fontSize: 12, height: 1.3)))])),
              const SizedBox(height: 18),
              AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Verification Status', style: TextStyle(color: AppColors.navy, fontSize: 16, fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Account', style: TextStyle(color: AppColors.muted, fontSize: 12)), Text(accountStatus, style: TextStyle(color: _statusColor(accountStatus), fontWeight: FontWeight.w900, fontSize: 12))]),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Documents', style: TextStyle(color: AppColors.muted, fontSize: 12)), Text(verificationStatus, style: TextStyle(color: _statusColor(verificationStatus), fontWeight: FontWeight.w900, fontSize: 12))]),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Onboarding Payment', style: TextStyle(color: AppColors.muted, fontSize: 12)), Text(paid ? 'PAID' : 'PENDING • ₹$onboardingFee', style: TextStyle(color: _statusColor(paid ? 'APPROVED' : 'PENDING'), fontWeight: FontWeight.w900, fontSize: 12))]),
              ])),
              const SizedBox(height: 18),
              const Text('Submitted Documents', style: TextStyle(color: AppColors.navy, fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              document('Driving Licence', dlStatus, Icons.badge_outlined),
              document('Government ID (Aadhaar / PAN)', idStatus, Icons.perm_identity_rounded),
              document('Profile Photo / Selfie', selfieStatus, Icons.photo_camera_outlined),
              const SizedBox(height: 8),
              if (!paid)
                AppCard(color: AppColors.navy, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Onboarding Payment', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text('The onboarding fee is ₹$onboardingFee. Payment and account activation are handled through the controlled onboarding flow.', style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4)),
                  const SizedBox(height: 14),
                  SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold, foregroundColor: AppColors.navy), onPressed: () => Navigator.of(context).pushNamed('/onboarding-payment'), child: Text('COMPLETE ONBOARDING • ₹$onboardingFee', style: const TextStyle(fontWeight: FontWeight.w900)))),
                ])),
            ],
          ),
        );
      },
    );
  }
}

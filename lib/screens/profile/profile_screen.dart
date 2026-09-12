import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../services/partner_presence_service.dart';
import '../../theme/app_theme.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  String _text(Map<String, dynamic> data, List<String> keys, String fallback) {
    for (final key in keys) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Please sign in again.')));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('partners').doc(user.uid).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? <String, dynamic>{};
        final name = _text(data, ['name', 'fullName'], user.displayName ?? 'Partner');
        final partnerCode = _text(
          data,
          ['partnerCode', 'partnerId'],
          'WD-${user.uid.substring(0, user.uid.length > 8 ? 8 : user.uid.length).toUpperCase()}',
        );
        final verification = _text(data, ['verificationStatus', 'accountStatus'], 'PENDING');
        final verificationUpper = verification.toUpperCase();
        final isVerified = verificationUpper == 'VERIFIED' || verificationUpper == 'ACTIVE';
        final isOnline = data['isOnline'] == true;
        final vehicle = _text(data, ['vehicleModel', 'vehicleType'], 'Vehicle details unavailable');
        final registration = _text(data, ['vehicleNumber', 'registrationNumber'], 'Registration unavailable');
        final fuel = _text(data, ['fuelType'], 'Not provided');
        final inspection = _text(data, ['inspectionStatus'], 'Pending');
        final license = _text(data, ['licenseNumber', 'dlNumber'], 'Not provided');
        final licenseValidity = _text(data, ['licenseValidity'], 'Not provided');
        final badge = _text(data, ['transportBadge', 'badgeStatus'], 'Not provided');

        return Scaffold(
          backgroundColor: const Color(0xFFF7F9FC),
          appBar: AppBar(title: const Text('My Profile'), elevation: 0),
          body: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              AppCard(
                color: AppColors.navy,
                child: Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: AppColors.gold.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: const Icon(Icons.person_rounded, color: AppColors.gold, size: 32),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 2),
                          Text('ID: $partnerCode', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: (isVerified ? Colors.green : AppColors.gold).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isVerified ? 'KYC Verified' : 'Verification: $verification',
                              style: TextStyle(
                                color: isVerified ? Colors.greenAccent : Colors.amberAccent,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AppCard(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Duty Status', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.navy)),
                        const SizedBox(height: 2),
                        Text(
                          isOnline ? 'You are online for bookings' : 'You are currently offline',
                          style: TextStyle(fontSize: 12, color: isOnline ? Colors.green[700] : AppColors.muted, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    Switch.adaptive(
                      value: isOnline,
                      activeColor: AppColors.navy,
                      onChanged: (value) async {
                        if (value) {
                          final success = await PartnerPresenceService.setOnline(true);
                          if (!context.mounted) return;
                          if (!success) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Unable to go online. Please enable location and check your account status.'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                          }
                        } else {
                          await PartnerPresenceService.setOfflineBestEffort();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('You are now offline.')),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text('Account Settings & Documents', style: TextStyle(color: AppColors.navy, fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              _buildMenuTile(Icons.directions_car_rounded, 'Assigned Vehicle', '$vehicle • $registration', () => _showVehicleDetails(context, data)),
              const SizedBox(height: 10),
              _buildMenuTile(Icons.badge_outlined, 'Driving Licence', '$license • Validity: $licenseValidity', () => _showLicenseDetails(context, data, badge)),
              const SizedBox(height: 10),
              _buildMenuTile(Icons.account_balance_rounded, 'Bank / Payout Details', 'Manage your payout account', () => _showBankDetails(context, data, user.uid)),
              const SizedBox(height: 10),
              _buildMenuTile(Icons.support_agent_rounded, 'Support', 'Contact the partner support team', () => Navigator.of(context).pushNamed('/support')),
              const SizedBox(height: 10),
              _buildMenuTile(Icons.logout_rounded, 'Logout', 'Sign out of this partner account', () async {
                await FirebaseAuth.instance.signOut();
                if (context.mounted) Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
              }),
              const SizedBox(height: 20),
              AppCard(
                child: Row(
                  children: [
                    const Icon(Icons.verified_user_rounded, color: AppColors.navy),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Vehicle Inspection', style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 2),
                          Text('Fuel: $fuel • Inspection: $inspection', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMenuTile(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.navy.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.navy),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900, fontSize: 14)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
        ],
      ),
    );
  }

  void _showVehicleDetails(BuildContext context, Map<String, dynamic> data) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Assigned Vehicle'),
        content: Text(
          'Model: ${_text(data, ['vehicleModel', 'vehicleType'], 'Not provided')}\n'
          'Registration: ${_text(data, ['vehicleNumber', 'registrationNumber'], 'Not provided')}\n'
          'Fuel: ${_text(data, ['fuelType'], 'Not provided')}\n'
          'Inspection: ${_text(data, ['inspectionStatus'], 'Pending')}',
        ),
      ),
    );
  }

  void _showLicenseDetails(BuildContext context, Map<String, dynamic> data, String badge) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Driving Licence'),
        content: Text(
          'DL Number: ${_text(data, ['licenseNumber', 'dlNumber'], 'Not provided')}\n'
          'Validity: ${_text(data, ['licenseValidity'], 'Not provided')}\n'
          'Transport Badge: $badge',
        ),
      ),
    );
  }

  Future<void> _showBankDetails(BuildContext context, Map<String, dynamic> data, String uid) async {
    final account = TextEditingController(text: data['bankAccountNo']?.toString() ?? '');
    final ifsc = TextEditingController(text: data['ifscCode']?.toString() ?? '');
    final holder = TextEditingController(text: data['accountHolder']?.toString() ?? '');
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Bank / Payout Details'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: holder, decoration: const InputDecoration(labelText: 'Account holder')),
                TextField(controller: account, decoration: const InputDecoration(labelText: 'Bank account number'), keyboardType: TextInputType.number),
                TextField(controller: ifsc, decoration: const InputDecoration(labelText: 'IFSC')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
            ElevatedButton(
              onPressed: () async {
                await FirebaseFirestore.instance.collection('partners').doc(uid).set({
                  'bankAccountNo': account.text.trim(),
                  'ifscCode': ifsc.text.trim().toUpperCase(),
                  'accountHolder': holder.text.trim(),
                  'bankUpdatedTime': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('SAVE'),
            ),
          ],
        ),
      );
    } finally {
      account.dispose();
      ifsc.dispose();
      holder.dispose();
    }
  }
}

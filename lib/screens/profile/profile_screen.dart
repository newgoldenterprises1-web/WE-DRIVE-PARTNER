import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../services/partner_presence_service.dart';
import '../../theme/app_theme.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _showVehicleDetails(BuildContext context, Map<String, dynamic> data) async {
    final vehicle = (data['vehicleModel'] ?? data['vehicleType'] ?? 'Not assigned').toString();
    final registration = (data['vehicleNumber'] ?? data['registrationNumber'] ?? 'Not assigned').toString();
    final fuel = (data['fuelType'] ?? 'Not specified').toString();
    final inspection = (data['inspectionStatus'] ?? 'Pending').toString();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Assigned Vehicle Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.navy)),
            const SizedBox(height: 16),
            _modalRow('Vehicle Model', vehicle),
            _modalRow('Registration No.', registration),
            _modalRow('Fuel Type', fuel),
            _modalRow('Inspection Status', inspection),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: Colors.white),
                onPressed: () {
                  Navigator.pop(sheetContext);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vehicle updates are handled by WE DRIVE support.')));
                },
                child: const Text('Request Vehicle Update'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDLDetails(BuildContext context, Map<String, dynamic> data) async {
    final license = (data['licenseNumber'] ?? data['dlNumber'] ?? 'Not submitted').toString();
    final holder = (data['name'] ?? data['fullName'] ?? 'Partner').toString();
    final validity = (data['licenseValidity'] ?? 'Pending verification').toString();
    final badge = (data['transportBadge'] ?? data['badgeStatus'] ?? 'Pending').toString();
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Driving License & Badge', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.navy)),
            const SizedBox(height: 16),
            _modalRow('License Number', license),
            _modalRow('Holder Name', holder),
            _modalRow('Validity', validity),
            _modalRow('Transport Badge', badge),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                onPressed: () {
                  Navigator.pop(sheetContext);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verification status is controlled by WE DRIVE review.')));
                },
                child: const Text('Re-verify Documents'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showBankDetails(BuildContext context, Map<String, dynamic> data) async {
    final accountController = TextEditingController(text: (data['bankAccountNo'] ?? '').toString());
    final ifscController = TextEditingController(text: (data['ifscCode'] ?? '').toString());
    final holderController = TextEditingController(text: (data['accountHolder'] ?? data['name'] ?? '').toString());

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Bank & Payout Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.navy)),
            const SizedBox(height: 16),
            TextField(controller: holderController, decoration: const InputDecoration(labelText: 'Account Holder', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: accountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Bank Account Number', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: ifscController, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'IFSC Code', border: OutlineInputBorder())),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: Colors.white),
                onPressed: () async {
                  final user = FirebaseAuth.instance.currentUser;
                  if (user == null) return;
                  try {
                    await FirebaseFirestore.instance.collection('partners').doc(user.uid).set({
                      'accountHolder': holderController.text.trim(),
                      'bankAccountNo': accountController.text.trim(),
                      'ifscCode': ifscController.text.trim().toUpperCase(),
                      'bankUpdatedTime': FieldValue.serverTimestamp(),
                    }, SetOptions(merge: true));
                    if (!sheetContext.mounted) return;
                    Navigator.pop(sheetContext);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bank details updated successfully.'), backgroundColor: Colors.green));
                  } catch (_) {
                    if (!sheetContext.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to update bank details.'), backgroundColor: Colors.red));
                  }
                },
                child: const Text('Save & Update Bank Account'),
              ),
            ),
          ],
        ),
      ),
    );
    accountController.dispose();
    ifscController.dispose();
    holderController.dispose();
  }

  Future<void> _showSupportSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('We Drive Partner Support', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.navy)),
            const SizedBox(height: 12),
            const Text('Need assistance with a trip, verification or payment? Contact WE DRIVE support.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
            const SizedBox(height: 16),
            const Text('Support contact details are configured by WE DRIVE.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
            const SizedBox(height: 20),
            SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: Colors.white), onPressed: () { Navigator.pop(sheetContext); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please use the official WE DRIVE support channel.'))); }, child: const Text('Contact Support'))),
          ],
        ),
      ),
    );
  }

  Future<void> _showTermsSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Terms & Safety Guidelines', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.navy)),
            const SizedBox(height: 12),
            const Text('1. Complete all required vehicle inspections.\n2. Follow traffic and safety regulations.\n3. Partner earnings are calculated using the configured settlement share.\n4. Do not misuse your partner account or assigned vehicle.', style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4)),
            const SizedBox(height: 20),
            SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: Colors.white), onPressed: () => Navigator.pop(sheetContext), child: const Text('I Agree & Understand'))),
          ],
        ),
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  Widget _modalRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text(title, style: const TextStyle(color: AppColors.muted, fontSize: 13))), const SizedBox(width: 12), Flexible(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.navy)))]),
    );
  }

  Widget _buildMenuTile(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AppCard(
          child: Row(children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppColors.navy.withOpacity(0.06), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: AppColors.navy, size: 22)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.navy)), const SizedBox(height: 2), Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 12))])),
            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.muted),
          ]),
        ),
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
        final name = (data['name'] ?? data['fullName'] ?? 'Partner').toString();
        final partnerCode = (data['partnerCode'] ?? data['partnerId'] ?? uid.substring(0, uid.length > 8 ? 8 : uid.length)).toString();
        final verification = (data['verificationStatus'] ?? data['accountStatus'] ?? 'PENDING').toString().toUpperCase();
        final isVerified = verification == 'VERIFIED' || verification == 'APPROVED' || verification == 'ACTIVE';
        final isOnline = data['isOnline'] == true;
        final vehicle = (data['vehicleModel'] ?? data['vehicleType'] ?? 'Vehicle not assigned').toString();
        final registration = (data['vehicleNumber'] ?? data['registrationNumber'] ?? 'Not assigned').toString();
        final licenseStatus = (data['dlStatus'] ?? data['licenseStatus'] ?? 'Pending').toString();
        final accountMasked = (data['bankAccountNo'] ?? '').toString();
        final maskedSuffix = accountMasked.length >= 4 ? accountMasked.substring(accountMasked.length - 4) : '----';

        return Scaffold(
          appBar: AppBar(title: const Text('Driver Profile & Status'), elevation: 0),
          body: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              AppCard(
                color: AppColors.navy,
                child: Row(children: [
                  Container(width: 60, height: 60, decoration: BoxDecoration(color: AppColors.gold.withOpacity(0.2), borderRadius: BorderRadius.circular(30)), child: const Icon(Icons.person_rounded, color: AppColors.gold, size: 32)),
                  const SizedBox(width: 16),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text('ID: $partnerCode', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 6),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: (isVerified ? Colors.green : AppColors.gold).withOpacity(0.2), borderRadius: BorderRadius.circular(4)), child: Text(isVerified ? 'KYC Verified' : 'Verification: $verification', style: TextStyle(color: isVerified ? Colors.greenAccent : Colors.amberAccent, fontSize: 10, fontWeight: FontWeight.bold))),
                  ])),
                ]),
              ),
              const SizedBox(height: 16),
              AppCard(
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Duty Status', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.navy)), const SizedBox(height: 2), Text(isOnline ? 'You are online for bookings' : 'You are currently offline', style: TextStyle(fontSize: 12, color: isOnline ? Colors.green[700] : AppColors.muted, fontWeight: FontWeight.w600))]),
                  Switch.adaptive(
                    value: isOnline,
                    activeColor: AppColors.navy,
                    onChanged: (value) async {
                      final messenger = ScaffoldMessenger.of(context);
                      final success = value ? await PartnerPresenceService.setOnline() : await PartnerPresenceService.setOfflineBestEffort();
                      if (!success && value && context.mounted) messenger.showSnackBar(const SnackBar(content: Text('Unable to go online. Please enable location and check your account status.'), backgroundColor: Colors.orange));
                      if (!success && !value && context.mounted) messenger.showSnackBar(const SnackBar(content: Text('Unable to update duty status.'), backgroundColor: Colors.red));
                    },
                  ),
                ]),
              ),
              const SizedBox(height: 20),
              const Text('Account Settings & Documents', style: TextStyle(color: AppColors.navy, fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              _buildMenuTile(Icons.directions_car_rounded, 'Assigned Vehicle', '$vehicle • $registration', () => _showVehicleDetails(context, data)),
              _buildMenuTile(Icons.verified_user_rounded, 'Driving License & Badge', licenseStatus, () => _showDLDetails(context, data)),
              _buildMenuTile(Icons.account_balance_rounded, 'Bank & Payout Details', maskedSuffix == '----' ? 'Not added' : '•••• $maskedSuffix', () => _showBankDetails(context, data)),
              _buildMenuTile(Icons.support_agent_rounded, 'We Drive Partner Support', 'Support options', () => _showSupportSheet(context)),
              _buildMenuTile(Icons.privacy_tip_rounded, 'Terms & Safety Guidelines', 'View Policies', () => _showTermsSheet(context)),
              const SizedBox(height: 20),
              AppOutlineButton(label: 'LOG OUT', icon: Icons.logout_rounded, onPressed: () async {
                final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(title: const Text('Log Out'), content: const Text('Are you sure you want to log out from We Drive Partner App?'), actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Log Out'))]));
                if (confirmed == true) await _logout(context);
              }),
            ],
          ),
        );
      },
    );
  }
}

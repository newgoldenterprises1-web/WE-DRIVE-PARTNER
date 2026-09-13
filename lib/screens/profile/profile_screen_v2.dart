import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/partner_presence_service.dart';
import '../../theme/app_theme.dart';
import '../account/account_screen.dart';
import 'verification_screen.dart';

class ProfileScreenV2 extends StatefulWidget {
  const ProfileScreenV2({super.key});

  @override
  State<ProfileScreenV2> createState() => _ProfileScreenV2State();
}

class _ProfileScreenV2State extends State<ProfileScreenV2> {
  bool isOnline = false;
  bool loading = true;
  Map<String, dynamic> data = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => loading = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance.collection('partners').doc(user.uid).get();
      if (!mounted) return;
      setState(() {
        data = doc.data() ?? {};
        isOnline = data['online'] == true;
        loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _toggleOnline(bool value) async {
    setState(() => isOnline = value);
    try {
      await PartnerPresenceService.instance.setOnline(value);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => isOnline = !value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('StateError: ', '')), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _editProfile() async {
    final name = TextEditingController(text: data['name'] ?? data['fullName'] ?? '');
    final city = TextEditingController(text: data['city'] ?? '');
    final experience = TextEditingController(text: '${data['drivingExperience'] ?? ''}');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 24, 20, MediaQuery.of(context).viewInsets.bottom + 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Edit Partner Profile', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.navy)),
          const SizedBox(height: 18),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Full Name', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: city, decoration: const InputDecoration(labelText: 'City', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: experience, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Driving Experience (years)', border: OutlineInputBorder())),
          const SizedBox(height: 18),
          SizedBox(width: double.infinity, child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: Colors.white),
            onPressed: () async {
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid == null) return;
              await FirebaseFirestore.instance.collection('partners').doc(uid).set({
                'name': name.text.trim(),
                'fullName': name.text.trim(),
                'city': city.text.trim(),
                'drivingExperience': experience.text.trim(),
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
              if (!context.mounted) return;
              Navigator.pop(context);
              await _load();
            },
            child: const Text('SAVE PROFILE', style: TextStyle(fontWeight: FontWeight.w900)),
          )),
        ]),
      ),
    );
    name.dispose();
    city.dispose();
    experience.dispose();
  }

  Future<void> _callSupport() async {
    final launched = await launchUrl(Uri.parse('tel:+914068927800'), mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the phone dialer.')));
    }
  }

  Future<void> _emailSupport() async {
    final launched = await launchUrl(Uri.parse('mailto:support@wedrive.co.in?subject=WE%20DRIVE%20Partner%20Support'), mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the email app.')));
    }
  }

  void _showVehicleDetails() {
    final vehicle = data['vehicleModel'] ?? data['vehicleType'] ?? 'Not assigned';
    final number = data['vehicleNumber'] ?? 'Not assigned';
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Assigned Vehicle', style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.navy)),
        content: Text('Vehicle: $vehicle\nVehicle Number: $number'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('CLOSE'))],
      ),
    );
  }

  void _openVerification() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VerificationScreen()));
  }

  void _openBankDetails() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccountScreen()));
  }

  Widget _menuTile(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        onTap: onTap,
        child: Row(children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppColors.navy.withOpacity(0.06), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: AppColors.navy, size: 22)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppColors.navy)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w500)),
          ])),
          const Icon(Icons.chevron_right_rounded, color: AppColors.muted, size: 20),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final name = data['name'] ?? data['fullName'] ?? user?.displayName ?? 'Partner';
    final phone = user?.phoneNumber ?? data['phoneNumber'] ?? '—';
    final vehicle = data['vehicleModel'] ?? data['vehicleType'] ?? 'Not assigned';
    final vehicleNumber = data['vehicleNumber'] ?? 'Not assigned';
    final dl = data['dlNumber'] ?? 'Not submitted';
    final verification = data['verificationStatus'] ?? 'PENDING';

    return Scaffold(
      appBar: AppBar(title: const Text('Driver Profile & Status'), elevation: 0),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
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
                      Text(phone, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      const SizedBox(height: 6),
                      Text('Verification: $verification', style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                    ])),
                    IconButton(onPressed: _editProfile, icon: const Icon(Icons.edit_rounded, color: Colors.white)),
                  ]),
                ),
                const SizedBox(height: 16),
                AppCard(
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Duty Status', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.navy)),
                      const SizedBox(height: 2),
                      Text(isOnline ? 'You are online for bookings' : 'You are currently offline', style: TextStyle(fontSize: 12, color: isOnline ? Colors.green[700] : AppColors.muted, fontWeight: FontWeight.w600)),
                    ]),
                    Switch.adaptive(value: isOnline, activeColor: AppColors.navy, onChanged: _toggleOnline),
                  ]),
                ),
                const SizedBox(height: 20),
                const Text('Account Settings & Documents', style: TextStyle(color: AppColors.navy, fontSize: 16, fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                _menuTile(Icons.directions_car_rounded, 'Assigned Vehicle', '$vehicle • $vehicleNumber', _showVehicleDetails),
                _menuTile(Icons.verified_user_rounded, 'Driving License & Badge', dl, _openVerification),
                _menuTile(Icons.account_balance_rounded, 'Bank & Payout Details', 'Manage from Account tab', _openBankDetails),
                _menuTile(Icons.support_agent_rounded, 'We Drive Partner Support', '24/7 Helpline Available', _callSupport),
                _menuTile(Icons.email_outlined, 'Partner Email Support', 'support@wedrive.co.in', _emailSupport),
                _menuTile(Icons.privacy_tip_rounded, 'Terms & Safety Guidelines', 'View policies', () {
                  showDialog(context: context, builder: (_) => const AlertDialog(title: Text('Terms & Safety'), content: Text('Follow traffic laws, complete required inspections, maintain professional conduct, and use the assigned vehicle only for authorized WE DRIVE services.')));
                }),
              ],
            ),
    );
  }
}

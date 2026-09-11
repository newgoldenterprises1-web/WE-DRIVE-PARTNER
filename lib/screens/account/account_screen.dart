import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../data/app_data.dart';
import '../auth/login_screen.dart';
import '../profile/profile_screen.dart';
import '../profile/verification_screen.dart';
import '../history/history_screen.dart';
import '../notifications/notifications_screen.dart';
import '../support/support_screen.dart';
import '../premium/premium_bookings_screen.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final TextEditingController _accountNoController = TextEditingController();
  final TextEditingController _ifscController = TextEditingController();
  final TextEditingController _holderController = TextEditingController();
  
  bool isSavingBank = false;
  bool isLoadingData = true;
  String partnerName = 'Partner';

  @override
  void initState() {
    super.initState();
    _loadPartnerAndBankData();
  }

  @override
  void dispose() {
    _accountNoController.dispose();
    _ifscController.dispose();
    _holderController.dispose();
    super.dispose();
  }

  // Firestore se existing bank aur profile details load karna
  Future<void> _loadPartnerAndBankData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance.collection('partners').doc(user.uid).get();
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          setState(() {
            partnerName = data['name'] ?? data['fullName'] ?? 'Partner';
            _holderController.text = data['accountHolder'] ?? '';
            _accountNoController.text = data['bankAccountNo'] ?? '';
            _ifscController.text = data['ifscCode'] ?? '';
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading account info: $e');
    } finally {
      if (mounted) {
        setState(() {
          isLoadingData = false;
        });
      }
    }
  }

  Future<void> _saveBankDetails(BuildContext context) async {
    if (_accountNoController.text.trim().isEmpty || _ifscController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter Account Number and IFSC Code')),
      );
      return;
    }

    setState(() {
      isSavingBank = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('partners').doc(user.uid).set({
          'bankAccountNo': _accountNoController.text.trim(),
          'ifscCode': _ifscController.text.trim().toUpperCase(),
          'accountHolder': _holderController.text.trim(),
          'bankUpdatedTime': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      setState(() {
        isSavingBank = false;
      });

      if (!context.mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bank payout details saved securely!'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      setState(() {
        isSavingBank = false;
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save bank details: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showBankDetailsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 24, 20, MediaQuery.of(context).viewInsets.bottom + 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.navy.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.account_balance_rounded, color: AppColors.navy, size: 24),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bank & Payout Details',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.navy),
                      ),
                      SizedBox(height: 2),
                      Text('Weekly 85% revenue settlement account', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Divider(height: 1),
            ),
            TextField(
              controller: _holderController,
              decoration: InputDecoration(
                labelText: 'Account Holder Name',
                hintText: 'e.g. Mohd Shahed',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _accountNoController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Bank Account Number',
                hintText: 'Enter account number',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ifscController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'IFSC Code',
                hintText: 'e.g. HDFC0001234',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.navy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              onPressed: isSavingBank ? null : () => _saveBankDetails(context),
              child: isSavingBank
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('SAVE BANK DETAILS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
            ),
          ],
        ),
      ),
    );
  }

  Widget menuItem(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        onTap: onTap,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.navy.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.navy, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.muted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  void _showInfoModal(BuildContext context, String title, String subtitle, String content, IconData icon) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 24, 20, MediaQuery.of(context).viewInsets.bottom + 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.navy.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: AppColors.navy, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.navy),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Divider(height: 1),
            ),
            Text(
              content,
              style: const TextStyle(color: AppColors.navy, fontSize: 13, height: 1.5, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('GOT IT', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final userPhone = user?.phoneNumber ?? '+91 7834046404';
    final userEmail = user?.email ?? 'partner@wedrive.in';

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: const Text('Account & Settings'),
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
        children: [
          // Profile Header Card
          AppCard(
            color: AppColors.navy,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const CircleAvatar(
                    radius: 28,
                    backgroundColor: AppColors.navyDark,
                    child: Icon(
                      Icons.person_rounded,
                      color: AppColors.gold,
                      size: 30,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        partnerName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        userPhone,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      Text(
                        userEmail,
                        style: const TextStyle(color: Colors.white60, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const ProfileScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.edit_rounded, color: Colors.white, size: 20),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Menu Items
          menuItem(
            context,
            Icons.verified_user_outlined,
            'Verification',
            'Documents and status',
            () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const VerificationScreen(),
                ),
              );
            },
          ),
          if (AppData.premiumFeatureVisible)
            menuItem(
              context,
              Icons.workspace_premium_outlined,
              'Premium Bookings',
              'Exclusive premium chauffeur requests',
              () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const PremiumBookingsScreen(),
                  ),
                );
              },
            ),
          menuItem(
            context,
            Icons.history_rounded,
            'Journey History',
            'Completed and cancelled trips',
            () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const HistoryScreen(),
                ),
              );
            },
          ),
          menuItem(
            context,
            Icons.notifications_none_rounded,
            'Notifications',
            'Booking and settlement updates',
            () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const NotificationsScreen(),
                ),
              );
            },
          ),
          menuItem(
            context,
            Icons.support_agent_rounded,
            'Support',
            'Help and FAQs',
            () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const SupportScreen(),
                ),
              );
            },
          ),
          menuItem(
            context,
            Icons.account_balance_rounded,
            'Bank / Payout Details',
            _accountNoController.text.isNotEmpty
                ? 'Linked: ${_accountNoController.text.length > 4 ? "****" + _accountNoController.text.substring(_accountNoController.text.length - 4) : _accountNoController.text}'
                : 'Add settlement bank details',
            () => _showBankDetailsModal(context),
          ),
          menuItem(
            context,
            Icons.privacy_tip_outlined,
            'Privacy & Terms',
            'WE DRIVE policies and guidelines',
            () {
              _showInfoModal(
                context,
                'Privacy & Terms',
                'WE DRIVE Partner Agreement',
                'By operating as a driver partner in Hyderabad, you agree to adhere to background check verifications, uniform standards, safety protocols, and fair ride allocation terms as per company guidelines.',
                Icons.privacy_tip_outlined,
              );
            },
          ),
          menuItem(
            context,
            Icons.info_outline_rounded,
            'About WE DRIVE',
            'Your Car. Your Comfort. Our Chauffeur.',
            () {
              _showInfoModal(
                context,
                'About WE DRIVE',
                'Version 2.1.4 • Partner Portal',
                'WE DRIVE is Hyderabad’s premier chauffeur service platform, connecting car owners with verified, professional drivers to ensure safe and comfortable journeys.',
                Icons.info_outline_rounded,
              );
            },
          ),
          const SizedBox(height: 10),
          AppOutlineButton(
            label: 'LOGOUT',
            icon: Icons.logout_rounded,
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (context) => const LoginScreen(),
                ),
                (route) => false,
              );
            },
          ),
        ],
      ),
    );
  }
}
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/payout_service.dart';
import '../../theme/app_theme.dart';

class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  String payoutFrequency = 'weekly';
  bool updatingFrequency = false;
  bool withdrawing = false;

  Widget metric(String title, String value, IconData icon) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.navy.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.navy, size: 24),
          ),
          const SizedBox(height: 14),
          Text(title, style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: AppColors.navy, fontSize: 20, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget transaction(String title, String date, String amount) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.arrow_downward_rounded, color: AppColors.green, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.navy)),
                  const SizedBox(height: 2),
                  Text(date, style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            Text(amount, style: const TextStyle(color: AppColors.green, fontWeight: FontWeight.w900, fontSize: 15)),
          ],
        ),
      ),
    );
  }

  String _dateLabel(Timestamp? timestamp) {
    if (timestamp == null) return 'Completed';
    final d = timestamp.toDate();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  Future<void> _selectFrequency(String value) async {
    if (updatingFrequency) return;
    setState(() => updatingFrequency = true);
    try {
      final frequency = await PayoutService.instance.setFrequency(value);
      if (!mounted) return;
      setState(() => payoutFrequency = frequency);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payout preference updated to ${frequency[0].toUpperCase()}${frequency.substring(1)}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => updatingFrequency = false);
    }
  }

  Future<void> _withdraw() async {
    if (withdrawing) return;
    setState(() => withdrawing = true);
    try {
      final result = await PayoutService.instance.withdraw();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message']?.toString() ?? 'Payout request submitted.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => withdrawing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Earnings & Analytics'), elevation: 0),
      body: uid == null
          ? const Center(child: Text('Please sign in again.'))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('partners').doc(uid).snapshots(),
              builder: (context, partnerSnapshot) {
                final partner = partnerSnapshot.data?.data() ?? {};
                final serverFrequency = (partner['payoutFrequency'] ?? payoutFrequency).toString().toLowerCase();
                if (serverFrequency == 'daily' || serverFrequency == 'weekly') {
                  payoutFrequency = serverFrequency;
                }

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('partners')
                      .doc(uid)
                      .collection('earnings')
                      .orderBy('completedAt', descending: true)
                      .limit(100)
                      .snapshots(),
                  builder: (context, earningsSnapshot) {
                    if (earningsSnapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('Could not load earnings. ${earningsSnapshot.error}', textAlign: TextAlign.center),
                        ),
                      );
                    }
                    if (!earningsSnapshot.hasData) return const Center(child: CircularProgressIndicator());

                    final docs = earningsSnapshot.data!.docs;
                    double total = 0;
                    for (final doc in docs) {
                      final value = doc.data()['earnings'];
                      if (value is num) total += value.toDouble();
                    }
                    final totalText = '₹${total.toStringAsFixed(0)}';

                    return ListView(
                      padding: const EdgeInsets.all(18),
                      children: [
                        AppCard(
                          color: AppColors.navy,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: const [
                                  Text('Available Balance', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
                                  Text('Verified Partner', style: TextStyle(color: AppColors.gold, fontSize: 10, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(totalText, style: const TextStyle(color: AppColors.gold, fontSize: 34, fontWeight: FontWeight.w900)),
                              const SizedBox(height: 12),
                              const Divider(color: Colors.white24, height: 1),
                              const SizedBox(height: 12),
                              const Text('Settlement share: 85% driver earnings', style: TextStyle(color: Colors.white70, fontSize: 11)),
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: withdrawing ? null : _withdraw,
                                  icon: withdrawing
                                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.navyDark))
                                      : const Icon(Icons.account_balance_rounded),
                                  label: const Text('WITHDRAW NOW', style: TextStyle(fontWeight: FontWeight.w900)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.gold,
                                    foregroundColor: AppColors.navyDark,
                                    minimumSize: const Size.fromHeight(48),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Payout Preference', style: TextStyle(color: AppColors.navy, fontSize: 16, fontWeight: FontWeight.w900)),
                              const SizedBox(height: 4),
                              const Text('Choose how often your earnings should be settled.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: ChoiceChip(
                                      label: const Text('Daily'),
                                      selected: payoutFrequency == 'daily',
                                      onSelected: (_) => _selectFrequency('daily'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ChoiceChip(
                                      label: const Text('Weekly'),
                                      selected: payoutFrequency == 'weekly',
                                      onSelected: (_) => _selectFrequency('weekly'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: metric('Completed Trips', '${docs.length}', Icons.check_circle_outline_rounded)),
                            const SizedBox(width: 12),
                            Expanded(child: metric('Total Revenue', totalText, Icons.account_balance_wallet_outlined)),
                          ],
                        ),
                        const SizedBox(height: 24),
                        const Text('Withdrawal History', style: TextStyle(color: AppColors.navy, fontSize: 18, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 12),
                        const AppCard(child: Text('Withdrawal history will appear after RazorpayX payout activation.', style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600))),
                        const SizedBox(height: 18),
                        const Text('Recent Completed Rides', style: TextStyle(color: AppColors.navy, fontSize: 18, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 12),
                        if (docs.isEmpty)
                          const AppCard(child: Text('No completed trips yet.', style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)))
                        else
                          ...docs.map((doc) {
                            final data = doc.data();
                            final amount = data['earnings'] is num ? (data['earnings'] as num).toStringAsFixed(0) : '0';
                            final date = _dateLabel(data['completedAt'] as Timestamp?);
                            return transaction('Trip ${data['bookingId'] ?? doc.id}', date, '+ ₹$amount');
                          }),
                      ],
                    );
                  },
                );
              },
            ),
    );
  }
}

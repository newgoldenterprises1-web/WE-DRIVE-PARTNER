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
  bool payoutSaving = false;
  bool withdrawLoading = false;

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

  Future<void> _saveFrequency(String value) async {
    if (payoutSaving) return;
    setState(() {
      payoutSaving = true;
      payoutFrequency = value;
    });
    try {
      await PayoutService.instance.setFrequency(value);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payout preference saved: ${value[0].toUpperCase()}${value.substring(1)}')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => payoutFrequency = payoutFrequency == 'daily' ? 'weekly' : 'daily');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('StateError: ', '')), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => payoutSaving = false);
    }
  }

  Future<void> _withdraw() async {
    if (withdrawLoading) return;
    setState(() => withdrawLoading = true);
    try {
      final result = await PayoutService.instance.withdraw();
      if (!mounted) return;
      final amount = result['amount'] ?? 0;
      final status = String(result['status'] ?? 'queued').toUpperCase();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Withdrawal of ₹$amount submitted. Status: $status'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Withdrawal failed.'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('StateError: ', '')), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
      );
    } finally {
      if (mounted) setState(() => withdrawLoading = false);
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
                final serverFrequency = String(partner['payoutFrequency'] ?? 'weekly').toLowerCase();
                if (!payoutSaving && (serverFrequency == 'daily' || serverFrequency == 'weekly')) {
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

                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('payoutRequests')
                          .where('partnerId', isEqualTo: uid)
                          .orderBy('createdAt', descending: true)
                          .limit(100)
                          .snapshots(),
                      builder: (context, payoutSnapshot) {
                        final payoutDocs = payoutSnapshot.data?.docs ?? [];
                        double reserved = 0;
                        for (final doc in payoutDocs) {
                          final data = doc.data();
                          final status = String(data['status'] ?? '').toUpperCase();
                          final value = data['amount'];
                          if (value is num && ['REQUESTED', 'QUEUED', 'PENDING', 'PROCESSING', 'PROCESSED'].contains(status)) {
                            reserved += value.toDouble();
                          }
                        }
                        final available = (total - reserved).clamp(0, double.infinity).toDouble();
                        final totalText = '₹${total.toStringAsFixed(0)}';
                        final availableText = '₹${available.toStringAsFixed(0)}';

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
                                  Text(availableText, style: const TextStyle(color: AppColors.gold, fontSize: 34, fontWeight: FontWeight.w900)),
                                  const SizedBox(height: 12),
                                  const Divider(color: Colors.white24, height: 1),
                                  const SizedBox(height: 12),
                                  const Text('Settlement share: 85% driver earnings', style: TextStyle(color: Colors.white70, fontSize: 11)),
                                  const SizedBox(height: 14),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      onPressed: available >= 100 && !withdrawLoading ? _withdraw : null,
                                      icon: withdrawLoading
                                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                          : const Icon(Icons.account_balance_rounded),
                                      label: Text(withdrawLoading ? 'PROCESSING...' : 'WITHDRAW NOW', style: const TextStyle(fontWeight: FontWeight.w900)),
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
                                  const Text('Choose how often your available earnings should be settled.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ChoiceChip(
                                          label: const Text('Daily'),
                                          selected: payoutFrequency == 'daily',
                                          onSelected: payoutSaving ? null : (_) => _saveFrequency('daily'),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: ChoiceChip(
                                          label: const Text('Weekly'),
                                          selected: payoutFrequency == 'weekly',
                                          onSelected: payoutSaving ? null : (_) => _saveFrequency('weekly'),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (payoutSaving) ...[
                                    const SizedBox(height: 8),
                                    const LinearProgressIndicator(minHeight: 2),
                                  ],
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
                            if (payoutDocs.isEmpty)
                              const AppCard(child: Text('No withdrawals yet.', style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)))
                            else
                              ...payoutDocs.map((doc) {
                                final data = doc.data();
                                final amount = data['amount'] is num ? (data['amount'] as num).toStringAsFixed(0) : '0';
                                final status = String(data['status'] ?? 'REQUESTED').toUpperCase();
                                final date = _dateLabel(data['createdAt'] as Timestamp?);
                                return transaction('Withdrawal • $status', date, '₹$amount');
                              }),
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
                );
              },
            ),
    );
  }
}

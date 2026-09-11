import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../services/partner_plan_service.dart';
import '../../theme/app_theme.dart';

class EarningsScreen extends StatelessWidget {
  const EarningsScreen({super.key});

  double _fare(Map<String, dynamic> data) {
    final value = data['fare'] ?? data['estimatedFare'];
    if (value is num) return value.toDouble();
    return 0;
  }

  bool _premiumBooking(Map<String, dynamic> data) {
    final value = data['isPremiumBooking'];
    return value == true || data['serviceTier'].toString().toUpperCase() == 'PREMIUM';
  }

  double _partnerShare(Map<String, dynamic> data) => PartnerPlanService.partnerShare(fare: _fare(data), premium: _premiumBooking(data));

  Widget metric(String title, String value, IconData icon) => AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppColors.navy.withOpacity(.08), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: AppColors.navy, size: 24)), const SizedBox(height: 14), Text(title, style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600)), const SizedBox(height: 4), Text(value, style: const TextStyle(color: AppColors.navy, fontSize: 20, fontWeight: FontWeight.w900))]));

  Widget transaction(String title, String date, String amount, Color color) => Padding(padding: const EdgeInsets.only(bottom: 12), child: AppCard(child: Row(children: [Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withOpacity(.1), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.arrow_downward_rounded, color: color, size: 20)), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.navy)), const SizedBox(height: 2), Text(date, style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w500))])), Text(amount, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 15))])));

  DateTime? _timestamp(Map<String, dynamic> data, String key) {
    final value = data[key];
    return value is Timestamp ? value.toDate() : null;
  }

  bool _isToday(DateTime? value) {
    if (value == null) return false;
    final local = value.toLocal();
    final now = DateTime.now();
    return local.year == now.year && local.month == now.month && local.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final partnerId = FirebaseAuth.instance.currentUser?.uid;
    if (partnerId == null) return const Scaffold(body: Center(child: Text('Please sign in again.')));

    return Scaffold(
      appBar: AppBar(title: const Text('Earnings & Analytics'), elevation: 0),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('bookings').where('partnerId', isEqualTo: partnerId).snapshots(),
        builder: (context, snapshot) {
          final docs = (snapshot.data?.docs ?? []).where((doc) => (doc.data()['status'] ?? '').toString().toUpperCase() == 'COMPLETED').toList();
          docs.sort((a, b) {
            final ad = _timestamp(a.data(), 'completedAt') ?? _timestamp(a.data(), 'updatedAt');
            final bd = _timestamp(b.data(), 'completedAt') ?? _timestamp(b.data(), 'updatedAt');
            if (ad == null && bd == null) return 0;
            if (ad == null) return 1;
            if (bd == null) return -1;
            return bd.compareTo(ad);
          });

          var totalEarnings = 0.0;
          var todayEarnings = 0.0;
          var todayTrips = 0;
          for (final doc in docs) {
            final data = doc.data();
            final share = _partnerShare(data);
            totalEarnings += share;
            final completedAt = _timestamp(data, 'completedAt') ?? _timestamp(data, 'updatedAt');
            if (_isToday(completedAt)) { todayTrips++; todayEarnings += share; }
          }

          final displayEarnings = '₹${totalEarnings.toStringAsFixed(0)}';
          final displayToday = '₹${todayEarnings.toStringAsFixed(0)}';

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('partners').doc(partnerId).snapshots(),
            builder: (context, partnerSnapshot) {
              final partnerData = partnerSnapshot.data?.data() ?? <String, dynamic>{};
              final rating = partnerData['rating'];
              final ratingText = rating is num ? '${rating.toStringAsFixed(1)} ★' : '—';
              return ListView(padding: const EdgeInsets.all(18), children: [
                AppCard(color: AppColors.navy, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Available Balance', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: AppColors.gold.withOpacity(.2), borderRadius: BorderRadius.circular(6)), child: Text(partnerData['isPremium'] == true ? 'Premium Partner' : 'Verified Partner', style: const TextStyle(color: AppColors.gold, fontSize: 10, fontWeight: FontWeight.bold)))]), const SizedBox(height: 8), Text(displayEarnings, style: const TextStyle(color: AppColors.gold, fontSize: 34, fontWeight: FontWeight.w900)), const SizedBox(height: 12), const Divider(color: Colors.white24, height: 1), const SizedBox(height: 12), Text('Standard rides: ${PartnerPlanService.standardSharePercent}% • Premium rides: ${PartnerPlanService.premiumSharePercent}%', style: const TextStyle(color: Colors.white70, fontSize: 11))])),
                const SizedBox(height: 16),
                Row(children: [Expanded(child: metric('Completed Trips', '${docs.length}', Icons.check_circle_outline_rounded)), const SizedBox(width: 12), Expanded(child: metric('Total Revenue', displayEarnings, Icons.account_balance_wallet_outlined))]),
                const SizedBox(height: 12),
                Row(children: [Expanded(child: metric('Today Trips', '$todayTrips', Icons.route_rounded)), const SizedBox(width: 12), Expanded(child: metric('Today Earnings', displayToday, Icons.today_outlined))]),
                const SizedBox(height: 24),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Recent Completed Rides', style: TextStyle(color: AppColors.navy, fontSize: 18, fontWeight: FontWeight.w900)), Text(ratingText, style: const TextStyle(color: AppColors.gold, fontSize: 12, fontWeight: FontWeight.bold))]),
                const SizedBox(height: 12),
                if (docs.isEmpty) AppCard(child: Column(children: const [Icon(Icons.receipt_long_outlined, color: AppColors.muted, size: 36), SizedBox(height: 10), Text('No completed rides yet.', style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w800)), SizedBox(height: 4), Text('Completed trips and earnings will appear here.', style: TextStyle(color: AppColors.muted, fontSize: 12))])) else ...docs.take(20).map((doc) { final data = doc.data(); final customer = (data['customerName'] ?? 'Passenger').toString(); final fare = _partnerShare(data).toStringAsFixed(0); final completedAt = _timestamp(data, 'completedAt') ?? _timestamp(data, 'updatedAt'); final dateText = completedAt == null ? 'Completed' : '${completedAt.toLocal().day.toString().padLeft(2, '0')}/${completedAt.toLocal().month.toString().padLeft(2, '0')}/${completedAt.toLocal().year}'; return transaction('Trip for $customer', dateText, '+ ₹$fare', AppColors.green); }),
              ]);
            },
          );
        },
      ),
    );
  }
}

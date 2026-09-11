import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../data/app_data.dart';
import '../../models/booking.dart';
import '../../services/partner_plan_service.dart';
import '../../theme/app_theme.dart';
import 'premium_booking_detail_screen.dart';

class PremiumBookingsScreen extends StatefulWidget {
  const PremiumBookingsScreen({super.key});

  @override
  State<PremiumBookingsScreen> createState() => _PremiumBookingsScreenState();
}

class _PremiumBookingsScreenState extends State<PremiumBookingsScreen> {
  int selectedTab = 0;
  bool premium = false;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadPlan();
  }

  Future<void> _loadPlan() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final snap = await FirebaseFirestore.instance.collection('partners').doc(uid).get();
      premium = snap.data()?['isPremium'] == true;
      AppData.isPremiumPartner = premium;
    } catch (_) {
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _paymentNotConfigured() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Premium payment gateway is not configured yet. No payment was processed.'),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (!premium) return _upgradeView();

    final available = AppData.premiumBookings.where((b) => b.status == 'REQUESTED').toList();
    final upcoming = AppData.premiumBookings.where((b) => b.status == 'RESERVATION' || b.status == 'ACCEPTED').toList();
    final completed = AppData.premiumBookings.where((b) => b.status == 'COMPLETED').toList();
    final tabs = <List<Booking>>[available, upcoming, completed];
    final current = tabs[selectedTab];

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(title: const Text('Premium Bookings'), elevation: 0, actions: const [Padding(padding: EdgeInsets.only(right: 16), child: Icon(Icons.workspace_premium_rounded, color: AppColors.gold))]),
      body: Column(children: [
        const SizedBox(height: 12),
        Container(margin: const EdgeInsets.symmetric(horizontal: 18), padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: AppColors.navy.withOpacity(.15), blurRadius: 10, offset: const Offset(0, 4))]), child: Row(children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.workspace_premium_rounded, color: AppColors.navyDark, size: 28)),
          const SizedBox(width: 14),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('PREMIUM PARTNER', style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1.2)), SizedBox(height: 3), Text('High-value corporate requests • 90% share', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14))])),
        ])),
        const SizedBox(height: 16),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: Row(children: [tabButton('Immediate', 0), tabButton('Reservation', 1), tabButton('Completed', 2)])),
        const SizedBox(height: 12),
        Expanded(child: current.isEmpty ? const Center(child: Text('No premium bookings available right now.', style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600))) : ListView.separated(padding: const EdgeInsets.fromLTRB(18, 6, 18, 24), itemCount: current.length, separatorBuilder: (_, __) => const SizedBox(height: 14), itemBuilder: (_, i) => premiumCard(current[i]))),
      ]),
    );
  }

  Widget _upgradeView() {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(title: const Text('Premium Drive'), elevation: 0),
      body: ListView(padding: const EdgeInsets.fromLTRB(18, 24, 18, 28), children: [
        Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(22)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.workspace_premium_rounded, color: AppColors.gold, size: 42), SizedBox(height: 14), Text('Become a Premium Chauffeur', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)), SizedBox(height: 8), Text('Access premium corporate rides, priority allocations and the higher premium earnings tier.', style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4))])),
        const SizedBox(height: 16),
        AppCard(child: Column(children: [
          _benefit(Icons.business_center_rounded, 'Premium corporate bookings'),
          _benefit(Icons.bolt_rounded, 'Priority allocation opportunities'),
          _benefit(Icons.payments_rounded, '90% driver earnings share on premium rides'),
          _benefit(Icons.workspace_premium_rounded, 'Premium Chauffeur profile tier'),
          const Divider(height: 28),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [Text('Premium upgrade fee', style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w800)), Text('₹699', style: TextStyle(color: AppColors.gold, fontSize: 22, fontWeight: FontWeight.w900))]),
        ])),
        const SizedBox(height: 18),
        SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0), onPressed: _paymentNotConfigured, child: const Text('PAY ₹699 & UPGRADE', style: TextStyle(fontWeight: FontWeight.w900)))),
        const SizedBox(height: 10),
        const Text('Payment activation will be enabled once WE DRIVE connects its production payment gateway. No fake payment or instant premium activation is performed.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.4)),
      ]),
    );
  }

  Widget _benefit(IconData icon, String text) => Padding(padding: const EdgeInsets.only(bottom: 14), child: Row(children: [Icon(icon, color: AppColors.navy, size: 20), const SizedBox(width: 10), Expanded(child: Text(text, style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w600, fontSize: 13)))]));

  Widget tabButton(String label, int index) {
    final selected = selectedTab == index;
    return Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: TextButton(onPressed: () => setState(() => selectedTab = index), style: TextButton.styleFrom(backgroundColor: selected ? AppColors.navy : Colors.white, foregroundColor: selected ? Colors.white : AppColors.navy, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: selected ? AppColors.navy : Colors.grey.shade300))), child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)))));
  }

  Widget premiumCard(Booking booking) {
    return AppCard(onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PremiumBookingDetailScreen(booking: booking))), color: const Color(0xFFFEFBF2), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [const Icon(Icons.workspace_premium_rounded, color: AppColors.gold, size: 20), const SizedBox(width: 6), const Text('PREMIUM BOOKING', style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900, fontSize: 12)), const Spacer(), Text('90% SHARE', style: TextStyle(color: AppColors.green, fontSize: 10, fontWeight: FontWeight.w900))]),
      const SizedBox(height: 14),
      Row(children: [Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppColors.navy.withOpacity(.08), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.person_rounded, color: AppColors.navy)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(booking.customer, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.navy)), const SizedBox(height: 2), Text('${booking.date} • ${booking.time}', style: const TextStyle(color: AppColors.muted, fontSize: 12))])), Text('₹${booking.earnings}', style: const TextStyle(color: AppColors.navy, fontSize: 18, fontWeight: FontWeight.w900))]),
      const SizedBox(height: 12), const Divider(height: 1), const SizedBox(height: 12), Text('${booking.pickup} → ${booking.destination}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.navy, fontSize: 13, fontWeight: FontWeight.w600)),
    ]));
  }
}

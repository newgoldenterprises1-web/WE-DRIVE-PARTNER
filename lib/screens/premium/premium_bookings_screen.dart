import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../models/booking.dart';
import '../../services/partner_plan_service.dart';
import '../../services/razorpay_payment_service.dart';
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
  bool processing = false;

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
      if (!mounted) return;
      setState(() => premium = snap.data()?['isPremium'] == true);
    } catch (_) {
      if (mounted) setState(() => premium = false);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _startPremiumPayment() async {
    if (processing) return;
    setState(() => processing = true);
    final paymentService = RazorpayPaymentService.instance;
    final success = await paymentService.payPlan(plan: 'PREMIUM');
    if (!mounted) return;

    if (success && paymentService.isTestMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'TEST PAYMENT SUCCESSFUL • No real money charged. Premium is still locked until server verification.',
          ),
          backgroundColor: Colors.blueGrey,
        ),
      );
    } else if (success) {
      await _loadPlan();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Premium Drive activated successfully.')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment was not completed or could not be verified.'),
          backgroundColor: Colors.orange,
        ),
      );
    }

    if (mounted) setState(() => processing = false);
  }

  Booking _bookingFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final fare = d['fare'] is num
        ? (d['fare'] as num).toDouble()
        : d['estimatedFare'] is num
            ? (d['estimatedFare'] as num).toDouble()
            : 0.0;
    final createdAt = d['createdAt'];
    final date = createdAt is Timestamp ? _date(createdAt.toDate()) : 'Upcoming';
    final time = createdAt is Timestamp ? _time(createdAt.toDate()) : 'Scheduled';
    return Booking(
      id: doc.id,
      customer: (d['customerName'] ?? 'Passenger').toString(),
      date: date,
      time: time,
      pickup: (d['pickupLocation'] ?? 'Pickup unavailable').toString(),
      destination: (d['dropLocation'] ?? 'Destination unavailable').toString(),
      vehicle: (d['vehicleType'] ?? 'Premium Sedan').toString(),
      status: (d['status'] ?? 'SEARCHING').toString().toUpperCase(),
      earnings: PartnerPlanService.partnerShare(fare: fare, premium: true).round(),
      partnerId: (d['partnerId'] ?? '').toString().trim().isEmpty ? null : (d['partnerId'] ?? '').toString().trim(),
      acceptedBy: (d['acceptedBy'] ?? '').toString().trim().isEmpty ? null : (d['acceptedBy'] ?? '').toString().trim(),
      acceptedAt: d['acceptedAt'] is Timestamp ? (d['acceptedAt'] as Timestamp).toDate() : null,
    );
  }

  bool _isPremiumDoc(Map<String, dynamic> data) {
    return data['isPremiumBooking'] == true ||
        (data['serviceTier'] ?? '').toString().toUpperCase() == 'PREMIUM';
  }

  String _date(DateTime value) => '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
  String _time(DateTime value) => '${((value.hour + 11) % 12) + 1}:${value.minute.toString().padLeft(2, '0')} ${value.hour >= 12 ? 'PM' : 'AM'}';

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (!premium) return _upgradeView();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Scaffold(body: Center(child: Text('Please sign in again.')));

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: const Text('Premium Bookings'),
        elevation: 0,
        actions: const [Padding(padding: EdgeInsets.only(right: 16), child: Icon(Icons.workspace_premium_rounded, color: AppColors.gold))],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('bookings').where('status', whereIn: const ['REQUESTED', 'SEARCHING']).snapshots(),
        builder: (context, pendingSnapshot) {
          final immediate = (pendingSnapshot.data?.docs ?? []).where((d) => _isPremiumDoc(d.data())).map(_bookingFromDoc).toList();
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('bookings').where('partnerId', isEqualTo: uid).snapshots(),
            builder: (context, assignedSnapshot) {
              final assigned = (assignedSnapshot.data?.docs ?? []).where((d) => _isPremiumDoc(d.data())).map(_bookingFromDoc).toList();
              final upcoming = assigned.where((b) => b.status == 'ACCEPTED' || b.status == 'ARRIVING' || b.status == 'ARRIVED' || b.status == 'TRIP_STARTED').toList();
              final completed = assigned.where((b) => b.status == 'COMPLETED').toList();
              final lists = <List<Booking>>[immediate, upcoming, completed];
              final current = lists[selectedTab];

              return Column(children: [
                const SizedBox(height: 12),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 18),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(20)),
                  child: const Row(children: [
                    CircleAvatar(backgroundColor: AppColors.gold, child: Icon(Icons.workspace_premium_rounded, color: AppColors.navyDark)),
                    SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('PREMIUM PARTNER', style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1.2)),
                      SizedBox(height: 3),
                      Text('High-value corporate rides • 90% share', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                    ])),
                  ]),
                ),
                const SizedBox(height: 16),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: Row(children: [tabButton('Immediate', 0), tabButton('Upcoming', 1), tabButton('Completed', 2)])),
                const SizedBox(height: 12),
                Expanded(child: current.isEmpty ? const Center(child: Text('No premium bookings available right now.', style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600))) : ListView.separated(padding: const EdgeInsets.fromLTRB(18, 6, 18, 24), itemCount: current.length, separatorBuilder: (_, __) => const SizedBox(height: 14), itemBuilder: (_, i) => premiumCard(current[i]))),
              ]);
            },
          );
        },
      ),
    );
  }

  Widget _upgradeView() {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(title: const Text('Premium Drive'), elevation: 0),
      body: ListView(padding: const EdgeInsets.fromLTRB(18, 24, 18, 28), children: [
        Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(22)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.workspace_premium_rounded, color: AppColors.gold, size: 42),
          SizedBox(height: 14),
          Text('Become a Premium Chauffeur', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
          SizedBox(height: 8),
          Text('Pay the Premium Drive fee to unlock exclusive corporate bookings and the 90% premium earnings tier.', style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4)),
        ])),
        const SizedBox(height: 16),
        AppCard(child: Column(children: [
          _benefit(Icons.business_center_rounded, 'Premium corporate bookings'),
          _benefit(Icons.bolt_rounded, 'Priority allocation opportunities'),
          _benefit(Icons.payments_rounded, '90% driver earnings share'),
          const Divider(height: 28),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [Text('Premium Drive fee', style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w800)), Text('₹699', style: TextStyle(color: AppColors.gold, fontSize: 22, fontWeight: FontWeight.w900))]),
        ])),
        const SizedBox(height: 18),
        SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0), onPressed: processing ? null : _startPremiumPayment, child: processing ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('PAY ₹699 & UPGRADE', style: TextStyle(fontWeight: FontWeight.w900)))),
        const SizedBox(height: 10),
        Text(
          RazorpayPaymentService.testMode
              ? 'TEST MODE: no real charge and no Premium activation until server verification is connected.'
              : 'Premium bookings remain locked until the Premium Drive payment is verified and the partner account is marked Premium.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.4),
        ),
      ]),
    );
  }

  Widget _benefit(IconData icon, String text) => Padding(padding: const EdgeInsets.only(bottom: 14), child: Row(children: [Icon(icon, color: AppColors.navy, size: 20), const SizedBox(width: 10), Expanded(child: Text(text, style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w600, fontSize: 13)))]));

  Widget tabButton(String label, int index) {
    final selected = selectedTab == index;
    return Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: TextButton(onPressed: () => setState(() => selectedTab = index), style: TextButton.styleFrom(backgroundColor: selected ? AppColors.navy : Colors.white, foregroundColor: selected ? Colors.white : AppColors.navy, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: selected ? AppColors.navy : Colors.grey.shade300))), child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)))));
  }

  Widget premiumCard(Booking booking) => AppCard(
    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PremiumBookingDetailScreen(booking: booking))),
    color: const Color(0xFFFEFBF2),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [const Icon(Icons.workspace_premium_rounded, color: AppColors.gold, size: 20), const SizedBox(width: 6), const Text('PREMIUM BOOKING', style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900, fontSize: 12)), const Spacer(), const Text('90% SHARE', style: TextStyle(color: AppColors.green, fontSize: 10, fontWeight: FontWeight.w900))]),
      const SizedBox(height: 14),
      Row(children: [
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppColors.navy.withOpacity(.08), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.person_rounded, color: AppColors.navy)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(booking.customer, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.navy)), const SizedBox(height: 2), Text('${booking.date} • ${booking.time}', style: const TextStyle(color: AppColors.muted, fontSize: 12))])),
        Text('₹${booking.earnings}', style: const TextStyle(color: AppColors.navy, fontSize: 18, fontWeight: FontWeight.w900)),
      ]),
      const SizedBox(height: 12),
      const Divider(height: 1),
      const SizedBox(height: 12),
      Text('${booking.pickup} → ${booking.destination}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.navy, fontSize: 13, fontWeight: FontWeight.w600)),
    ]),
  );
}
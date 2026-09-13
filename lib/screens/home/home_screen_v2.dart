import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../data/app_data.dart';
import '../../models/booking.dart';
import '../../services/partner_presence_service.dart';
import '../../theme/app_theme.dart';
import '../account/account_screen.dart';
import '../bookings/booking_detail_screen.dart';
import '../bookings/bookings_screen.dart';
import '../earnings/earnings_screen.dart';
import '../notifications/notifications_screen.dart';
import '../premium/premium_bookings_screen.dart';

class HomeScreenV2 extends StatefulWidget {
  const HomeScreenV2({super.key});

  @override
  State<HomeScreenV2> createState() => _HomeScreenV2State();
}

class _HomeScreenV2State extends State<HomeScreenV2> {
  int selectedTab = 0;
  bool online = false;
  bool presenceLoading = false;
  Map<String, dynamic> partnerData = {};

  @override
  void initState() {
    super.initState();
    _loadPartner();
  }

  Future<void> _loadPartner() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('partners').doc(uid).get();
      if (!mounted || !doc.exists) return;
      setState(() {
        partnerData = doc.data() ?? {};
        online = partnerData['online'] == true;
      });
    } catch (_) {}
  }

  Future<void> _setOnline(bool value) async {
    if (presenceLoading) return;
    setState(() {
      presenceLoading = true;
      online = value;
    });
    try {
      await PartnerPresenceService.instance.setOnline(value);
      await _loadPartner();
    } catch (e) {
      if (mounted) {
        setState(() => online = !value);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('StateError: ', '')),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => presenceLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      homeBody(),
      BookingsScreen(bookings: AppData.bookings),
      const EarningsScreen(),
      const AccountScreen(),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      body: pages[selectedTab],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: NavigationBar(
          backgroundColor: Colors.white,
          elevation: 0,
          selectedIndex: selectedTab,
          onDestinationSelected: (index) => setState(() => selectedTab = index),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month_rounded), label: 'Bookings'),
            NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet_rounded), label: 'Earnings'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person_rounded), label: 'Account'),
          ],
        ),
      ),
    );
  }

  Widget homeBody() {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return SafeArea(
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('bookings')
            .orderBy('createdAt', descending: true)
            .limit(30)
            .snapshots(),
        builder: (context, bookingSnapshot) {
          final allDocs = bookingSnapshot.data?.docs ?? [];
          final docs = allDocs.where((doc) {
            final data = doc.data();
            final status = String(data['status'] ?? '').toUpperCase();
            final assigned = data['partnerId'] == uid;
            final declined = (data['declinedBy'] is List) &&
                (data['declinedBy'] as List).contains(uid);
            return !declined && (assigned || status == 'SEARCHING' || status == 'REQUESTED');
          }).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.navy.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.local_taxi_rounded, color: AppColors.navy, size: 20),
                        ),
                        const SizedBox(width: 10),
                        const Text('WE DRIVE', style: TextStyle(color: AppColors.navy, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                      ],
                    ),
                  ),
                  IconButton(
                    style: IconButton.styleFrom(backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade200))),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
                    icon: const Icon(Icons.notifications_none_rounded, color: AppColors.navy, size: 22),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    style: IconButton.styleFrom(backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade200))),
                    onPressed: () => setState(() => selectedTab = 3),
                    icon: const Icon(Icons.person_outline_rounded, color: AppColors.navy, size: 22),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Welcome, ${partnerData['name'] ?? 'Partner'}',
                style: const TextStyle(color: AppColors.navy, fontSize: 28, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              const Text('Stay ready. Great journeys start here.', style: TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 18),
              availabilityCard(),
              if (AppData.premiumFeatureVisible) ...[
                const SizedBox(height: 14),
                premiumEntryCard(),
              ],
              const SizedBox(height: 18),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: uid == null
                    ? null
                    : FirebaseFirestore.instance.collection('partners').doc(uid).collection('earnings').snapshots(),
                builder: (context, earningsSnapshot) {
                  final earningsDocs = earningsSnapshot.data?.docs ?? [];
                  double earnings = 0;
                  for (final doc in earningsDocs) {
                    final value = doc.data()['earnings'];
                    if (value is num) earnings += value.toDouble();
                  }
                  final onlineSeconds = (partnerData['totalOnlineSeconds'] is num)
                      ? (partnerData['totalOnlineSeconds'] as num).toInt()
                      : 0;
                  final hours = onlineSeconds ~/ 3600;
                  final minutes = (onlineSeconds % 3600) ~/ 60;

                  return Column(
                    children: [
                      Row(children: [
                        Expanded(child: metricCard('Today Trips', '${earningsDocs.length}', Icons.route_rounded)),
                        const SizedBox(width: 12),
                        Expanded(child: metricCard('Earnings', '₹${earnings.toStringAsFixed(0)}', Icons.payments_outlined)),
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(child: metricCard('Online Hours', '${hours}h ${minutes}m', Icons.schedule_rounded)),
                        const SizedBox(width: 12),
                        Expanded(child: metricCard('Rating', partnerData['rating'] == null ? '—' : '${partnerData['rating']} ★', Icons.star_rounded)),
                      ]),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Expanded(child: Text('Live Incoming Requests', style: TextStyle(color: AppColors.navy, fontSize: 18, fontWeight: FontWeight.w900))),
                  TextButton(onPressed: () => setState(() => selectedTab = 1), child: const Text('View all', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
              ),
              const SizedBox(height: 8),
              if (docs.isEmpty)
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
                  child: const Column(children: [
                    Icon(Icons.radar_rounded, size: 40, color: AppColors.muted),
                    SizedBox(height: 12),
                    Text('No incoming ride requests right now.', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppColors.navy)),
                    SizedBox(height: 4),
                    Text('Stay online to receive bookings.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  ]),
                )
              else
                ...docs.map((doc) {
                  final data = doc.data();
                  final booking = Booking(
                    id: doc.id,
                    vehicle: data['vehicleType'] ?? 'Sedan',
                    customer: data['customerName'] ?? 'Passenger',
                    status: data['status'] ?? 'SEARCHING',
                    date: 'Today',
                    time: 'Now',
                    pickup: data['pickupLocation'] ?? 'Hyderabad',
                    destination: data['dropLocation'] ?? 'Hyderabad',
                    earnings: data['fare'] is num ? ((data['fare'] as num) * 0.85).toInt() : 0,
                    customerPhone: data['customerPhone']?.toString(),
                  );
                  return Padding(padding: const EdgeInsets.only(bottom: 12), child: bookingCard(booking));
                }),
            ],
          );
        },
      ),
    );
  }

  Widget availabilityCard() {
    final color = online ? AppColors.green : AppColors.red;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))]),
      child: Row(
        children: [
          CircleAvatar(radius: 26, backgroundColor: Colors.white, child: Icon(Icons.person_pin_circle_outlined, color: color, size: 28)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Your availability', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(online ? 'ONLINE' : 'OFFLINE', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(online ? 'You can receive new bookings.' : 'Go online to receive requests.', style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ])),
          presenceLoading
              ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Switch.adaptive(
                  value: online,
                  activeColor: Colors.white,
                  activeTrackColor: Colors.white30,
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: Colors.black26,
                  onChanged: _setOnline,
                ),
        ],
      ),
    );
  }

  Widget premiumEntryCard() {
    final requests = AppData.premiumBookings.where((booking) => booking.status == 'REQUESTED').length;
    return Container(
      decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.gold.withOpacity(0.4), width: 1.5)),
      child: Material(color: Colors.transparent, child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PremiumBookingsScreen())),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            const CircleAvatar(radius: 24, backgroundColor: AppColors.gold, child: Icon(Icons.workspace_premium_rounded, color: AppColors.navyDark, size: 24)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Premium Bookings', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(requests == 0 ? 'Exclusive chauffeur opportunities' : '$requests new premium request${requests == 1 ? '' : 's'}', style: const TextStyle(color: AppColors.gold, fontSize: 12, fontWeight: FontWeight.w500)),
            ])),
            const Icon(Icons.chevron_right_rounded, color: AppColors.gold),
          ]),
        ),
      )),
    );
  }

  Widget metricCard(String title, String value, IconData icon) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppColors.navy.withOpacity(0.06), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: AppColors.navy, size: 22)),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: AppColors.navy, fontSize: 18, fontWeight: FontWeight.w900)),
      ]),
    );
  }

  Widget bookingCard(Booking booking) {
    return AppCard(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookingDetailScreen(booking: booking))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(child: Text(booking.customer, style: const TextStyle(color: AppColors.navy, fontSize: 16, fontWeight: FontWeight.w900))),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: AppColors.navy.withOpacity(0.08), borderRadius: BorderRadius.circular(6)), child: Text(booking.status.toUpperCase(), style: const TextStyle(color: AppColors.navy, fontSize: 10, fontWeight: FontWeight.bold))),
        ]),
        const SizedBox(height: 8),
        Text('Pickup: ${booking.pickup}', style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 3),
        Text('Destination: ${booking.destination}', style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Vehicle: ${booking.vehicle}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          Text('₹${booking.earnings}', style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w900)),
        ]),
      ]),
    );
  }
}

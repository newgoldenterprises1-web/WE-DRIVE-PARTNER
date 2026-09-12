import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../data/app_data.dart';
import '../../services/partner_presence_service.dart';
import '../../services/booking_assignment_service.dart';
import '../../services/booking_decline_service.dart';
import '../../models/booking.dart';
import '../bookings/bookings_screen.dart';
import '../earnings/earnings_screen.dart';
import '../account/account_screen.dart';
import '../notifications/notifications_screen.dart';
import '../bookings/booking_detail_screen.dart';
import '../premium/premium_bookings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int selectedTab = 0;
  bool online = false;
  bool presenceLoading = true;

  @override
  void initState() {
    super.initState();
    _restorePartnerPresence();
  }

  Future<void> _restorePartnerPresence() async {
    final saved = await PartnerPresenceService.getOnlineStatus();
    if (!mounted) return;
    setState(() {
      online = saved ?? false;
      presenceLoading = false;
    });
  }

  Future<void> _setPartnerPresence(bool value) async {
    if (presenceLoading) return;
    final previous = online;
    setState(() { online = value; presenceLoading = true; });
    final success = await PartnerPresenceService.setOnline(value);
    if (!mounted) return;
    if (!success) {
      setState(() { online = previous; });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not update availability. Please try again.'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
    }
    setState(() { presenceLoading = false; });
  }

  double _numericFare(Map<String, dynamic> data) {
    for (final candidate in [data['fare'], data['estimatedFare']]) {
      if (candidate is num) return candidate.toDouble();
    }
    final display = data['fareDisplay'];
    if (display != null) {
      final match = RegExp(r'[0-9]+(?:\.[0-9]+)?').firstMatch(display.toString());
      if (match != null) return double.tryParse(match.group(0)!) ?? 0;
    }
    return 0;
  }

  String _formatOnlineHours(Map<String, dynamic> partnerData) {
    var minutes = partnerData['onlineMinutesToday'] is num ? (partnerData['onlineMinutesToday'] as num).toInt() : 0;
    final started = partnerData['onlineStartedAt'];
    if (partnerData['isOnline'] == true && started is Timestamp) {
      final elapsed = DateTime.now().difference(started.toDate()).inMinutes;
      if (elapsed > 0) minutes += elapsed;
    }
    final hours = minutes ~/ 60;
    final remaining = minutes % 60;
    return '${hours}h ${remaining.toString().padLeft(2, '0')}m';
  }

  bool _isToday(Map<String, dynamic> data) {
    final value = data['completedAt'] ?? data['updatedAt'];
    if (value is! Timestamp) return false;
    final date = value.toDate().toLocal();
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[homeBody(), BookingsScreen(bookings: AppData.bookings, partnerOnline: online), const EarningsScreen(), const AccountScreen()];
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      body: pages[selectedTab],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -4))]),
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
    final isPremium = AppData.isPremiumPartner;
    return SafeArea(
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('bookings').where('status', whereIn: const ['REQUESTED', 'SEARCHING']).where('isPremiumBooking', isEqualTo: isPremium).snapshots(),
        builder: (context, snapshot) {
          final allDocs = snapshot.data?.docs ?? [];
          final docs = online
              ? (allDocs.where((doc) => (doc.data()['partnerId'] ?? '').toString().trim().isEmpty).toList()..sort((a, b) {
                  final aCreated = a.data()['createdAt'];
                  final bCreated = b.data()['createdAt'];
                  if (aCreated is Timestamp && bCreated is Timestamp) return bCreated.compareTo(aCreated);
                  if (aCreated is Timestamp) return -1;
                  if (bCreated is Timestamp) return 1;
                  return 0;
                }))
              : <QueryDocumentSnapshot<Map<String, dynamic>>>[];

          final visibleDocs = docs.take(5).toList();
          final partnerId = FirebaseAuth.instance.currentUser?.uid;
          final assignedStream = partnerId == null ? null : FirebaseFirestore.instance.collection('bookings').where('partnerId', isEqualTo: partnerId).snapshots();

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: assignedStream,
            builder: (context, assignedSnapshot) {
              final assignedDocs = assignedSnapshot.data?.docs ?? [];
              final completedToday = assignedDocs.where((doc) {
                final data = doc.data();
                return (data['status'] ?? '').toString().toUpperCase() == 'COMPLETED' && _isToday(data);
              }).toList();
              final todayTrips = completedToday.length;
              final todayEarnings = completedToday.fold<double>(0, (sum, doc) => sum + (_numericFare(doc.data()) * 0.85));

              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: partnerId == null ? null : FirebaseFirestore.instance.collection('partners').doc(partnerId).snapshots(),
                builder: (context, partnerSnapshot) {
                  final partnerData = partnerSnapshot.data?.data() ?? <String, dynamic>{};
                  final rating = partnerData['rating'];
                  final ratingText = rating is num ? '${rating.toStringAsFixed(1)} ★' : '—';
                  final onlineHours = _formatOnlineHours(partnerData);
                  final earningsText = '₹${todayEarnings.toStringAsFixed(0)}';

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
                    children: [
                      Row(children: [
                        Expanded(child: Row(children: [
                          Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: AppColors.navy.withOpacity(0.08), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.local_taxi_rounded, color: AppColors.navy, size: 20)),
                          const SizedBox(width: 10),
                          const Text('WE DRIVE', style: TextStyle(color: AppColors.navy, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                        ])),
                        IconButton(style: IconButton.styleFrom(backgroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade200))), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())), icon: const Icon(Icons.notifications_none_rounded, color: AppColors.navy, size: 22)),
                        const SizedBox(width: 8),
                        IconButton(style: IconButton.styleFrom(backgroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade200))), onPressed: () => setState(() => selectedTab = 3), icon: const Icon(Icons.person_outline_rounded, color: AppColors.navy, size: 22)),
                      ]),
                      const SizedBox(height: 20),
                      const Text('Welcome, Partner', style: TextStyle(color: AppColors.navy, fontSize: 28, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      const Text('Stay ready. Great journeys start here.', style: TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 18),
                      availabilityCard(),
                      if (AppData.premiumFeatureVisible) ...[const SizedBox(height: 14), premiumEntryCard()],
                      const SizedBox(height: 18),
                      Row(children: [Expanded(child: metricCard('Today Trips', '$todayTrips', Icons.route_rounded)), const SizedBox(width: 12), Expanded(child: metricCard('Earnings', earningsText, Icons.payments_outlined))]),
                      const SizedBox(height: 12),
                      Row(children: [Expanded(child: metricCard('Online Hours', onlineHours, Icons.schedule_rounded)), const SizedBox(width: 12), Expanded(child: metricCard('Rating', ratingText, Icons.star_rounded))]),
                      const SizedBox(height: 24),
                      Row(children: [const Expanded(child: Text('Live Incoming Requests', style: TextStyle(color: AppColors.navy, fontSize: 18, fontWeight: FontWeight.w900))), TextButton(onPressed: () => setState(() => selectedTab = 1), child: const Text('View all', style: TextStyle(fontWeight: FontWeight.bold)))]),
                      const SizedBox(height: 8),
                      if (visibleDocs.isEmpty)
                        Container(padding: const EdgeInsets.all(28), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)), child: const Column(children: [Icon(Icons.radar_rounded, size: 40, color: AppColors.muted), SizedBox(height: 12), Text('No incoming ride requests right now.', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppColors.navy)), SizedBox(height: 4), Text('Stay online to receive bookings.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 12))]))
                      else
                        ...visibleDocs.map((doc) {
                          final data = doc.data();
                          final booking = Booking(id: doc.id, vehicle: data['vehicleType'] ?? 'Sedan', customer: data['customerName'] ?? 'Passenger', status: data['status'] ?? 'SEARCHING', date: 'Today', time: 'Now', pickup: data['pickupLocation'] ?? 'Hyderabad', destination: data['dropLocation'] ?? 'Hyderabad', earnings: (_numericFare(data) > 0) ? (_numericFare(data) * 0.85).toInt() : 0);
                          return Padding(padding: const EdgeInsets.only(bottom: 12), child: bookingCard(booking));
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

  Widget availabilityCard() {
    final Color color = online ? AppColors.green : AppColors.red;
    return Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))]), child: Row(children: [CircleAvatar(radius: 26, backgroundColor: Colors.white, child: Icon(Icons.person_pin_circle_outlined, color: color, size: 28)), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Your availability', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)), const SizedBox(height: 2), Text(online ? 'ONLINE' : 'OFFLINE', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)), const SizedBox(height: 2), Text(online ? 'You can receive new bookings.' : 'Go online to receive requests.', style: const TextStyle(color: Colors.white70, fontSize: 11))])), Switch.adaptive(value: online, activeColor: Colors.white, activeTrackColor: Colors.white30, inactiveThumbColor: Colors.white, inactiveTrackColor: Colors.black26, onChanged: presenceLoading ? null : _setPartnerPresence)]));
  }

  Widget premiumEntryCard() {
    final int requests = AppData.premiumBookings.where((booking) => booking.status == 'REQUESTED').length;
    return Container(decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.gold.withOpacity(0.4), width: 1.5), boxShadow: [BoxShadow(color: AppColors.navy.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 4))]), child: Material(color: Colors.transparent, child: InkWell(borderRadius: BorderRadius.circular(16), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PremiumBookingsScreen())), child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [const CircleAvatar(radius: 24, backgroundColor: AppColors.gold, child: Icon(Icons.workspace_premium_rounded, color: AppColors.navyDark, size: 24)), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Premium Bookings', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)), const SizedBox(height: 2), Text(requests == 0 ? 'Exclusive chauffeur opportunities' : '$requests new premium request${requests == 1 ? '' : 's'}', style: const TextStyle(color: AppColors.gold, fontSize: 12, fontWeight: FontWeight.w500))])), const Icon(Icons.chevron_right_rounded, color: AppColors.gold)]))));
  }

  Widget metricCard(String title, String value, IconData icon) => AppCard(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppColors.navy.withOpacity(0.06), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: AppColors.navy, size: 22)), const SizedBox(height: 12), Text(title, style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600)), const SizedBox(height: 2), Text(value, style: const TextStyle(color: AppColors.navy, fontSize: 18, fontWeight: FontWeight.w900))]));

  Widget bookingCard(Booking booking) => AppCard(
    onTap: () => showModalBottomSheet(context: context, backgroundColor: Colors.white, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), builder: (context) => Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [const Text('Live Booking Request', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.navy)), const SizedBox(height: 12), Text('Customer: ${booking.customer}', style: const TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text('Pickup: ${booking.pickup}'), Text('Destination: ${booking.destination}'), const SizedBox(height: 8), Text('Estimated Earnings: ₹${booking.earnings}', style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold)), const SizedBox(height: 24), Row(children: [Expanded(child: OutlinedButton(onPressed: () async {
      final navigator = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(this.context);
      final declined = await BookingDeclineService.declineBooking(booking.id);
      if (!mounted) return;
      if (declined) {
        navigator.pop();
        messenger.showSnackBar(const SnackBar(content: Text('Booking declined successfully.'), behavior: SnackBarBehavior.floating));
      } else {
        messenger.showSnackBar(const SnackBar(content: Text('Booking could not be declined. It may already be assigned, completed, or expired.'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
      }
    }, style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: const Text('DECLINE', style: TextStyle(fontWeight: FontWeight.bold)))), const SizedBox(width: 16), Expanded(child: ElevatedButton(onPressed: online ? () async { final accepted = await BookingAssignmentService.acceptBooking(booking.id); if (!mounted) return; if (!accepted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking could not be accepted. Make sure you are online and the booking is still available.'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating)); return; } Navigator.pop(context); Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookingDetailScreen(booking: booking))); } : null, style: ElevatedButton.styleFrom(backgroundColor: AppColors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0), child: const Text('ACCEPT', style: TextStyle(fontWeight: FontWeight.bold))))])))) ,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Expanded(child: Text(booking.customer, style: const TextStyle(color: AppColors.navy, fontSize: 16, fontWeight: FontWeight.w900))), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: AppColors.navy.withOpacity(0.08), borderRadius: BorderRadius.circular(6)), child: Text(booking.status.toUpperCase(), style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 10)))]), const SizedBox(height: 6), Text('${booking.date} • ${booking.time}', style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600, fontSize: 12)), const SizedBox(height: 10), Row(children: [const Icon(Icons.trip_origin, size: 14, color: Colors.green), const SizedBox(width: 8), Expanded(child: Text(booking.pickup, style: const TextStyle(fontSize: 13, color: AppColors.navy, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis))]), const SizedBox(height: 4), Row(children: [const Icon(Icons.location_pin, size: 14, color: Colors.red), const SizedBox(width: 8), Expanded(child: Text('To: ${booking.destination}', style: const TextStyle(fontSize: 13, color: AppColors.muted), maxLines: 1, overflow: TextOverflow.ellipsis))]), const SizedBox(height: 14), const Divider(height: 1, color: Color(0xFFEEEEEE)), const SizedBox(height: 12), Row(children: [const Icon(Icons.payments_outlined, color: AppColors.gold, size: 18), const SizedBox(width: 6), Text('₹${booking.earnings} (85% Share)', style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900, fontSize: 13)), const Spacer(), const Text('Tap to Action', style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 12)), const SizedBox(width: 2), const Icon(Icons.chevron_right_rounded, color: AppColors.navy, size: 16)])]),
  );
}

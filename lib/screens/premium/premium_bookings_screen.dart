import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../data/app_data.dart';
import '../../models/booking.dart';
import '../../theme/app_theme.dart';
import 'premium_booking_detail_screen.dart';

class PremiumBookingsScreen extends StatefulWidget {
  const PremiumBookingsScreen({super.key});

  @override
  State<PremiumBookingsScreen> createState() {
    return _PremiumBookingsScreenState();
  }
}

class _PremiumBookingsScreenState extends State<PremiumBookingsScreen> {
  int selectedTab = 0;
  bool isProcessingPayment = false;

  // Real UPI / PhonePe Payment Gateway Simulation for ₹699 Premium Upgrade
  Future<void> _processPremiumPayment(BuildContext context) async {
    setState(() {
      isProcessingPayment = true;
    });

    // Simulate UPI Intent / Gateway secure connection
    await Future.delayed(const Duration(seconds: 2));

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Update user status in Firestore to Premium
        await FirebaseFirestore.instance.collection('partners').doc(user.uid).set({
          'isPremium': true,
          'premiumPaidAt': FieldValue.serverTimestamp(),
          'plan': '₹699_PREMIUM_CHAUFFEUR',
        }, SetOptions(merge: true));
      }

      // Enable globally in app data for session
      AppData.premiumFeatureVisible = true;

      setState(() {
        isProcessingPayment = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment Successful! Welcome to WE DRIVE Premium Chauffeur Tier.'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() {}); // Refresh UI
    } catch (e) {
      setState(() {
        isProcessingPayment = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment failed: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showPaymentGatewaySheet(BuildContext context) {
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
                    color: AppColors.gold.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.workspace_premium_rounded, color: AppColors.navy, size: 24),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Unlock Premium Chauffeur',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.navy),
                      ),
                      SizedBox(height: 2),
                      Text('Get exclusive high-fare corporate bookings', style: TextStyle(color: AppColors.muted, fontSize: 12)),
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
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F9FC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text('Premium Subscription Fee', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.navy)),
                  Text('₹699', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.gold)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Select Payment Method (UPI / PhonePe / GPay)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.muted),
            ),
            const SizedBox(height: 10),
            ListTile(
              tileColor: Colors.grey.shade50,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              leading: const Icon(Icons.phone_android_rounded, color: AppColors.navy),
              title: const Text('PhonePe / UPI Intent', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              trailing: const Icon(Icons.check_circle, color: Colors.green),
              onTap: () {},
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.navy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              onPressed: () {
                Navigator.pop(context);
                _processPremiumPayment(context);
              },
              child: const Text('PAY ₹699 & UNLOCK NOW', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!AppData.premiumFeatureVisible) {
      return Scaffold(
        appBar: AppBar(title: const Text('Premium Bookings')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.workspace_premium_rounded, size: 64, color: AppColors.gold),
                const SizedBox(height: 16),
                const Text(
                  'Exclusive Chauffeur Opportunities',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.navy),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Upgrade to WE DRIVE Premium Partner tier to access high-value corporate bookings and priority allocations.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
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
                    onPressed: isProcessingPayment
                        ? null
                        : () => _showPaymentGatewaySheet(context),
                    child: isProcessingPayment
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('UPGRADE TO PREMIUM (₹699)', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final List<Booking> available = AppData.premiumBookings
        .where((booking) => booking.status == 'REQUESTED')
        .toList();
    final List<Booking> upcoming = AppData.premiumBookings
        .where((booking) => booking.status == 'RESERVATION' || booking.status == 'ACCEPTED')
        .toList();
    final List<Booking> completed = AppData.premiumBookings
        .where((booking) => booking.status == 'COMPLETED')
        .toList();

    final List<List<Booking>> tabs = <List<Booking>>[
      available,
      upcoming,
      completed,
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: const Text('Premium Bookings'),
        elevation: 0,
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Icon(Icons.workspace_premium_rounded, color: AppColors.gold, size: 26),
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          // Banner Card
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 18),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.navyDark, AppColors.navy],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.navy.withOpacity(0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.gold,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.workspace_premium_rounded, color: AppColors.navyDark, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PREMIUM PARTNER',
                        style: TextStyle(
                          color: AppColors.gold,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Exclusive chauffeur requests',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Tabs Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                tabButton('Immediate', 0),
                tabButton('Reservation', 1),
                tabButton('Completed', 2),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Tab Content List
          Expanded(
            child: tabs[selectedTab].isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.inbox_rounded, size: 48, color: AppColors.muted),
                        SizedBox(height: 10),
                        Text(
                          'No premium bookings available right now.',
                          style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
                    itemCount: tabs[selectedTab].length,
                    separatorBuilder: (context, index) => const SizedBox(height: 14),
                    itemBuilder: (context, index) => premiumCard(tabs[selectedTab][index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget tabButton(String label, int index) {
    final bool selected = selectedTab == index;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: TextButton(
          onPressed: () {
            setState(() {
              selectedTab = index;
            });
          },
          style: TextButton.styleFrom(
            backgroundColor: selected ? AppColors.navy : Colors.white,
            foregroundColor: selected ? Colors.white : AppColors.navy,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: selected ? AppColors.navy : Colors.grey.shade300,
                width: 1,
              ),
            ),
            elevation: 0,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: selected ? Colors.white : AppColors.navy,
            ),
          ),
        ),
      ),
    );
  }

  Widget premiumCard(Booking booking) {
    final bool request = booking.status == 'REQUESTED';
    return AppCard(
      onTap: () {
        Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                PremiumBookingDetailScreen(booking: booking),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 150),
          ),
        );
      },
      color: const Color(0xFFFEFBF2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium_rounded, color: AppColors.gold, size: 20),
              const SizedBox(width: 6),
              const Text(
                'PREMIUM BOOKING',
                style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900, fontSize: 12),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: request ? const Color(0xFFFFF2C9) : const Color(0xFFE7F7EE),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  booking.status.toUpperCase(),
                  style: TextStyle(
                    color: request ? const Color(0xFF8D6900) : AppColors.green,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.navy.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.person_rounded, color: AppColors.navy, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      booking.customer,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.navy),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${booking.date} • ${booking.time}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              Text(
                '₹${booking.earnings}',
                style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900, fontSize: 18),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(height: 1, color: Color(0xFFEFE8D8)),
          ),
          Row(
            children: [
              Column(
                children: [
                  const Icon(Icons.trip_origin, size: 14, color: Colors.green),
                  Container(width: 2, height: 20, color: Colors.grey.withOpacity(0.3)),
                  const Icon(Icons.location_pin, size: 14, color: Colors.red),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      booking.pickup,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.navy),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      booking.destination,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.muted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: const [
              Icon(Icons.route_rounded, size: 15, color: AppColors.muted),
              SizedBox(width: 6),
              Text('Premium chauffeur service', style: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }
}
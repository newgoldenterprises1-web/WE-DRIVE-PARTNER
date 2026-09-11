import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../models/booking.dart';
import '../../theme/app_theme.dart';
import 'booking_detail_screen.dart';

class BookingsScreen extends StatelessWidget {
  final List<Booking>? bookings;

  const BookingsScreen({
    super.key,
    this.bookings,
  });

  @override
  Widget build(BuildContext context) {
    final currentPartnerId = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: const Text('Live Bookings'),
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('bookings')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text(
                'Unable to load live bookings.',
                style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];

          final liveDocs = docs.where((doc) {
            final data = doc.data();
            final status = (data['status'] ?? 'SEARCHING').toString().toUpperCase();
            final partnerId = (data['partnerId'] ?? '').toString().trim();

            if ((status == 'REQUESTED' || status == 'SEARCHING') && partnerId.isEmpty) {
              return true;
            }

            return status == 'ACCEPTED' &&
                currentPartnerId != null &&
                partnerId == currentPartnerId;
          }).toList();

          final liveBookings = liveDocs.map((doc) {
            final data = doc.data();
            DateTime? acceptedAt;
            final rawAcceptedAt = data['acceptedAt'];
            if (rawAcceptedAt is Timestamp) {
              acceptedAt = rawAcceptedAt.toDate();
            }

            return Booking(
              id: doc.id,
              vehicle: (data['vehicleType'] ?? 'Sedan').toString(),
              customer: (data['customerName'] ?? 'Passenger').toString(),
              status: (data['status'] ?? 'SEARCHING').toString(),
              date: 'Today',
              time: 'Now',
              pickup: (data['pickupLocation'] ?? 'Hyderabad').toString(),
              destination: (data['dropLocation'] ?? 'Hyderabad').toString(),
              earnings: (data['fare'] is num) ? ((data['fare'] as num) * 0.85).toInt() : 799,
              partnerId: (data['partnerId'] ?? '').toString().trim().isEmpty
                  ? null
                  : (data['partnerId'] ?? '').toString().trim(),
              acceptedBy: (data['acceptedBy'] ?? '').toString().trim().isEmpty
                  ? null
                  : (data['acceptedBy'] ?? '').toString().trim(),
              acceptedAt: acceptedAt,
            );
          }).toList();

          if (liveBookings.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.radar_rounded, size: 48, color: AppColors.muted),
                  SizedBox(height: 10),
                  Text(
                    'No live bookings right now.',
                    style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
            itemCount: liveBookings.length,
            separatorBuilder: (context, index) => const SizedBox(height: 14),
            itemBuilder: (context, index) {
              final booking = liveBookings[index];
              final bool isRequested = booking.status.toUpperCase() == 'REQUESTED';

              return AppCard(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => BookingDetailScreen(booking: booking),
                    ),
                  );
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isRequested ? const Color(0xFFFFF2C9) : const Color(0xFFE7F7EE),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            booking.status.toUpperCase(),
                            style: TextStyle(
                              color: isRequested ? const Color(0xFF8D6900) : AppColors.green,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Divider(height: 1, color: Color(0xFFEEEEEE)),
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
                      children: [
                        const Icon(Icons.payments_outlined, size: 16, color: AppColors.gold),
                        const SizedBox(width: 6),
                        Text(
                          '₹${booking.earnings} (85% Share)',
                          style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900, fontSize: 13),
                        ),
                        const Spacer(),
                        const Text(
                          'Manage',
                          style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        const SizedBox(width: 2),
                        const Icon(Icons.chevron_right_rounded, color: AppColors.navy, size: 16),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

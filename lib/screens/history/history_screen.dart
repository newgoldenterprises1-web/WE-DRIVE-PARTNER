import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../models/booking.dart';
import '../bookings/booking_detail_screen.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: const Text('Journey History'),
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('bookings')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          final docs = snapshot.data?.docs ?? [];
          
          // Map Firestore documents to Booking models, filtering for completed or cancelled
          final List<Booking> historyList = docs.map((doc) {
            final data = doc.data();
            return Booking(
              id: doc.id,
              vehicle: data['vehicleType'] ?? "Sedan",
              customer: data['customerName'] ?? "Passenger",
              status: data['status'] ?? "COMPLETED",
              date: "Recent",
              time: "Verified",
              pickup: data['pickupLocation'] ?? "Hyderabad",
              destination: data['dropLocation'] ?? "Hyderabad",
              earnings: (data['fare'] is num) ? ((data['fare'] as num) * 0.85).toInt() : 799,
            );
          }).where((b) => b.status == 'COMPLETED' || b.status == 'CANCELLED').toList();

          if (historyList.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.history_rounded, size: 48, color: AppColors.muted),
                  SizedBox(height: 10),
                  Text(
                    'No past journeys found.',
                    style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
            itemCount: historyList.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final booking = historyList[index];
              final bool isCompleted = booking.status.toUpperCase() == 'COMPLETED';

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
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.directions_car_rounded, color: AppColors.navy, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                booking.customer,
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.navy),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${booking.date} • ${booking.time}',
                                style: const TextStyle(color: AppColors.muted, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isCompleted ? const Color(0xFFE7F7EE) : Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            booking.status.toUpperCase(),
                            style: TextStyle(
                              color: isCompleted ? AppColors.green : Colors.red,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(height: 1, color: Color(0xFFEEEEEE)),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.trip_origin, size: 14, color: Colors.green),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            booking.pickup,
                            style: const TextStyle(fontSize: 12, color: AppColors.navy, fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_pin, size: 14, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            booking.destination,
                            style: const TextStyle(fontSize: 12, color: AppColors.muted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.payments_outlined, size: 16, color: AppColors.gold),
                        const SizedBox(width: 6),
                        Text(
                          '₹${booking.earnings}',
                          style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900, fontSize: 13),
                        ),
                        const Spacer(),
                        const Text(
                          'View Details',
                          style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 11),
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
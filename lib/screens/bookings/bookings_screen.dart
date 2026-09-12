import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../models/booking.dart';
import '../../theme/app_theme.dart';
import 'booking_detail_screen.dart';

class BookingsScreen extends StatelessWidget {
  final List<Booking>? bookings;
  final bool partnerOnline;

  const BookingsScreen({super.key, this.bookings, this.partnerOnline = false});

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _mergeDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> pendingDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> assignedDocs,
  ) {
    final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final doc in pendingDocs) {
      byId[doc.id] = doc;
    }
    for (final doc in assignedDocs) {
      byId[doc.id] = doc;
    }
    final merged = byId.values.toList();
    merged.sort((a, b) {
      final aCreated = a.data()['createdAt'];
      final bCreated = b.data()['createdAt'];
      if (aCreated is Timestamp && bCreated is Timestamp) {
        return bCreated.compareTo(aCreated);
      }
      if (aCreated is Timestamp) return -1;
      if (bCreated is Timestamp) return 1;
      return 0;
    });
    return merged;
  }

  String _formatDate(DateTime value) {
    return '${value.day.toString().padLeft(2, '0')}/'
        '${value.month.toString().padLeft(2, '0')}/'
        '${value.year}';
  }

  String _formatTime(DateTime value) {
    final hour = value.hour;
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final suffix = hour >= 12 ? 'PM' : 'AM';
    return '$displayHour:${value.minute.toString().padLeft(2, '0')} $suffix';
  }

  List<Booking> _toBookings(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.map((doc) {
      final data = doc.data();
      DateTime? acceptedAt;
      final rawAcceptedAt = data['acceptedAt'];
      if (rawAcceptedAt is Timestamp) {
        acceptedAt = rawAcceptedAt.toDate();
      }

      final rawCreatedAt = data['createdAt'];
      final createdAt = rawCreatedAt is Timestamp ? rawCreatedAt.toDate().toLocal() : null;

      return Booking(
        id: doc.id,
        vehicle: (data['vehicleType'] ?? 'Sedan').toString(),
        customer: (data['customerName'] ?? 'Passenger').toString(),
        status: (data['status'] ?? 'SEARCHING').toString(),
        date: createdAt == null ? 'Upcoming' : _formatDate(createdAt),
        time: createdAt == null ? 'Scheduled' : _formatTime(createdAt),
        pickup: (data['pickupLocation'] ?? 'Hyderabad').toString(),
        destination: (data['dropLocation'] ?? 'Hyderabad').toString(),
        earnings: (data['fare'] is num) ? ((data['fare'] as num) * 0.85).toInt() : 0,
        partnerId: (data['partnerId'] ?? '').toString().trim().isEmpty
            ? null
            : (data['partnerId'] ?? '').toString().trim(),
        acceptedBy: (data['acceptedBy'] ?? '').toString().trim().isEmpty
            ? null
            : (data['acceptedBy'] ?? '').toString().trim(),
        acceptedAt: acceptedAt,
      );
    }).toList();
  }

  Widget _bookingList(BuildContext context, List<Booking> liveBookings) {
    if (liveBookings.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.radar_rounded, size: 48, color: AppColors.muted),
            SizedBox(height: 10),
            Text(
              'No live bookings right now.',
              style: TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
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
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => BookingDetailScreen(booking: booking),
            ),
          ),
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
                    child: const Icon(
                      Icons.person_rounded,
                      color: AppColors.navy,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          booking.customer,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: AppColors.navy,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${booking.date} • ${booking.time}',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isRequested
                          ? const Color(0xFFFFF2C9)
                          : const Color(0xFFE7F7EE),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      booking.status.toUpperCase(),
                      style: TextStyle(
                        color: isRequested
                            ? const Color(0xFF8D6900)
                            : AppColors.green,
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
                      Container(
                        width: 2,
                        height: 20,
                        color: Colors.grey.withOpacity(0.3),
                      ),
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
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: AppColors.navy,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          booking.destination,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: AppColors.muted,
                          ),
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
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'Manage',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.navy,
                    size: 16,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

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
            .where('status', whereIn: const ['REQUESTED', 'SEARCHING'])
            .where('isPremiumBooking', isEqualTo: false)
            .snapshots(),
        builder: (context, pendingSnapshot) {
          if (pendingSnapshot.hasError) {
            return const Center(
              child: Text(
                'Unable to load live bookings.',
                style: TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }

          final pendingDocs = partnerOnline
              ? (pendingSnapshot.data?.docs ?? [])
                  .where(
                    (doc) =>
                        (doc.data()['partnerId'] ?? '').toString().trim().isEmpty,
                  )
                  .toList()
              : <QueryDocumentSnapshot<Map<String, dynamic>>>[];

          if (currentPartnerId == null) {
            return _bookingList(context, _toBookings(pendingDocs));
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('bookings')
                .where('partnerId', isEqualTo: currentPartnerId)
                .snapshots(),
            builder: (context, assignedSnapshot) {
              if (assignedSnapshot.hasError) {
                return const Center(
                  child: Text(
                    'Unable to load assigned bookings.',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }
              final assignedDocs = assignedSnapshot.data?.docs ?? [];
              return _bookingList(
                context,
                _toBookings(_mergeDocs(pendingDocs, assignedDocs)),
              );
            },
          );
        },
      ),
    );
  }
}

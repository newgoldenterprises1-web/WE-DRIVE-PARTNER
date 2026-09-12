import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  String _timeAgo(DateTime value) {
    final difference = DateTime.now().difference(value.toLocal());
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    if (difference.inDays < 7) return '${difference.inDays}d ago';
    return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
  }

  DateTime? _timestamp(Map<String, dynamic> data, String key) {
    final value = data[key];
    return value is Timestamp ? value.toDate() : null;
  }

  List<Map<String, dynamic>> _buildNotifications({
    required Map<String, dynamic> partnerData,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> pendingDocs,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> assignedDocs,
  }) {
    final items = <Map<String, dynamic>>[];

    final accountStatus = (partnerData['accountStatus'] ?? '').toString().toUpperCase();
    if (accountStatus.isNotEmpty && accountStatus != 'ACTIVE') {
      final isPending = accountStatus == 'PENDING_ONBOARDING_FEE';
      items.add({
        'title': isPending ? 'Account activation pending' : 'Account status update',
        'sub': isPending
            ? 'Complete the onboarding payment flow to activate your partner account.'
            : 'Your current partner account status is $accountStatus.',
        'time': 'Current status',
        'icon': Icons.verified_user_outlined,
      });
    }

    final premium = partnerData['isPremium'] == true;
    for (final doc in pendingDocs) {
      final data = doc.data();
      final createdAt = _timestamp(data, 'createdAt');
      final isPremiumBooking = data['isPremiumBooking'] == true;
      items.add({
        'title': isPremiumBooking ? 'New premium booking request' : 'New booking request',
        'sub': '${data['customerName'] ?? 'Passenger'} • ${data['pickupLocation'] ?? 'Pickup'} → ${data['dropLocation'] ?? 'Destination'}${premium && isPremiumBooking ? ' • Premium' : ''}',
        'time': createdAt == null ? 'Available now' : _timeAgo(createdAt),
        'icon': isPremiumBooking ? Icons.workspace_premium_outlined : Icons.local_taxi_outlined,
        'createdAt': createdAt,
      });
    }

    for (final doc in assignedDocs) {
      final data = doc.data();
      final status = (data['status'] ?? '').toString().toUpperCase();
      final stamp = _timestamp(data, 'completedAt') ??
          _timestamp(data, 'cancelledAt') ??
          _timestamp(data, 'tripStartedAt') ??
          _timestamp(data, 'arrivedAt') ??
          _timestamp(data, 'acceptedAt') ??
          _timestamp(data, 'updatedAt');

      if (stamp == null) continue;

      String? title;
      String? sub;
      IconData? icon;

      switch (status) {
        case 'ACCEPTED':
          title = 'Booking accepted';
          sub = 'Your booking with ${data['customerName'] ?? 'Passenger'} is assigned to you.';
          icon = Icons.check_circle_outline_rounded;
          break;
        case 'ARRIVING':
          title = 'On the way to pickup';
          sub = 'You are marked as arriving for ${data['customerName'] ?? 'Passenger'}.';
          icon = Icons.navigation_outlined;
          break;
        case 'ARRIVED':
          title = 'Arrived at pickup';
          sub = 'Pickup marked arrived for ${data['customerName'] ?? 'Passenger'}.';
          icon = Icons.location_on_outlined;
          break;
        case 'TRIP_STARTED':
          title = 'Trip started';
          sub = 'Trip with ${data['customerName'] ?? 'Passenger'} is now active.';
          icon = Icons.route_outlined;
          break;
        case 'COMPLETED':
          title = 'Trip completed';
          sub = 'Your trip with ${data['customerName'] ?? 'Passenger'} has been completed.';
          icon = Icons.task_alt_rounded;
          break;
        case 'CANCELLED':
          title = 'Booking cancelled';
          sub = 'Booking ${doc.id} is marked cancelled.';
          icon = Icons.cancel_outlined;
          break;
      }

      if (title != null && sub != null && icon != null) {
        items.add({
          'title': title,
          'sub': sub,
          'time': _timeAgo(stamp),
          'icon': icon,
          'createdAt': stamp,
        });
      }
    }

    items.sort((a, b) {
      final aDate = a['createdAt'];
      final bDate = b['createdAt'];
      if (aDate is DateTime && bDate is DateTime) return bDate.compareTo(aDate);
      if (aDate is DateTime) return -1;
      if (bDate is DateTime) return 1;
      return 0;
    });

    return items.take(30).toList();
  }

  @override
  Widget build(BuildContext context) {
    final partnerId = FirebaseAuth.instance.currentUser?.uid;
    if (partnerId == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in again.')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: const Text('Notifications'),
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('partners').doc(partnerId).snapshots(),
        builder: (context, partnerSnapshot) {
          final partnerData = partnerSnapshot.data?.data() ?? <String, dynamic>{};
          final isPremium = partnerData['isPremium'] == true;

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('bookings')
                .where('status', whereIn: const ['REQUESTED', 'SEARCHING'])
                .where('isPremiumBooking', isEqualTo: isPremium)
                .snapshots(),
            builder: (context, pendingSnapshot) {
              final pendingDocs = pendingSnapshot.data?.docs ?? [];
              final visiblePendingDocs = pendingDocs
                  .where((doc) => (doc.data()['partnerId'] ?? '').toString().trim().isEmpty)
                  .toList();

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('bookings')
                    .where('partnerId', isEqualTo: partnerId)
                    .snapshots(),
                builder: (context, assignedSnapshot) {
                  final items = _buildNotifications(
                    partnerData: partnerData,
                    pendingDocs: visiblePendingDocs,
                    assignedDocs: assignedSnapshot.data?.docs ?? [],
                  );

                  if (items.isEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.notifications_none_rounded, size: 48, color: AppColors.muted),
                          SizedBox(height: 12),
                          Text(
                            'No new notifications',
                            style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w800),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Booking and account updates will appear here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.muted, fontSize: 12),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.all(18),
                    itemCount: items.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final icon = item['icon'] as IconData? ?? Icons.notifications_none_rounded;

                      return AppCard(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.navy.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(icon, color: AppColors.navy, size: 22),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item['title']?.toString() ?? 'Notification',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 15,
                                            color: AppColors.navy,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        item['time']?.toString() ?? '',
                                        style: const TextStyle(
                                          color: AppColors.muted,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item['sub']?.toString() ?? '',
                                    style: const TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 13,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
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

import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class ActiveTripScreen extends StatefulWidget {
  const ActiveTripScreen({super.key});

  @override
  State<ActiveTripScreen> createState() => _ActiveTripScreenState();
}

class _ActiveTripScreenState extends State<ActiveTripScreen> {
  String tripStatus = 'Heading to Pickup'; // Heading to Pickup -> Trip Started -> Completed

  void _updateTripState() {
    setState(() {
      if (tripStatus == 'Heading to Pickup') {
        tripStatus = 'Trip in Progress';
      } else if (tripStatus == 'Trip in Progress') {
        tripStatus = 'Trip Completed';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: const Text('Active Chauffeur Ride'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Simulated Map Container
          Expanded(
            flex: 5,
            child: Container(
              width: double.infinity,
              color: AppColors.navy.withOpacity(0.08),
              child: Stack(
                children: [
                  const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.map_rounded, size: 64, color: AppColors.navy),
                        SizedBox(height: 12),
                        Text(
                          'Live GPS Tracking • Hyderabad',
                          style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.navy, fontSize: 14),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Route tracking active via Google Maps SDK',
                          style: TextStyle(color: AppColors.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 16,
                    left: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.navy,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        tripStatus,
                        style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Ride Details & Action Panel
          Expanded(
            flex: 4,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Customer Info Row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.gold.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.person_rounded, color: AppColors.navy, size: 24),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Rahul Sharma',
                              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.navy),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Honda City • TS 09 EA 5542',
                              style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        style: IconButton.styleFrom(backgroundColor: Colors.green.withOpacity(0.1)),
                        icon: const Icon(Icons.phone_rounded, color: Colors.green),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Calling customer...'), behavior: SnackBarBehavior.floating),
                          );
                        },
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Divider(height: 1),
                  ),

                  // Locations
                  const Row(
                    children: [
                      Icon(Icons.circle, size: 10, color: Colors.blue),
                      SizedBox(width: 12),
                      Text('Jubilee Hills Check Post, Hyderabad', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.navy)),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: SizedBox(height: 16, child: VerticalDivider(thickness: 2, color: Colors.black12)),
                  ),
                  const Row(
                    children: [
                      Icon(Icons.location_on_rounded, size: 16, color: Colors.red),
                      SizedBox(width: 10),
                      Text('Financial District, Gachibowli', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.navy)),
                    ],
                  ),
                  const Spacer(),

                  // Action Button
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
                      onPressed: tripStatus == 'Trip Completed' ? () => Navigator.pop(context) : _updateTripState,
                      child: Text(
                        tripStatus == 'Heading to Pickup'
                            ? 'ARRIVED AT PICKUP'
                            : tripStatus == 'Trip in Progress'
                                ? 'COMPLETE TRIP'
                                : 'BACK TO HOME',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
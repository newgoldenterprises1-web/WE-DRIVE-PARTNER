import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import '../../theme/app_theme.dart';
import '../../models/booking.dart';

class BookingDetailScreen extends StatefulWidget {
  final Booking booking;

  const BookingDetailScreen({
    super.key,
    required this.booking,
  });

  @override
  State<BookingDetailScreen> createState() {
    return _BookingDetailScreenState();
  }
}

class _BookingDetailScreenState extends State<BookingDetailScreen> {
  late String status;
  bool isLoading = false;

  File? preTripFront;
  File? preTripBack;
  File? preTripRight;
  File? preTripLeft;
  File? driverSelfie;

  File? postTripFront;
  File? postTripBack;
  File? postTripRight;
  File? postTripLeft;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    status = widget.booking.status.toUpperCase();
    _fetchExistingInspectionData();
  }

  Future<void> _fetchExistingInspectionData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('bookings')
          .doc(widget.booking.id)
          .get();

      if (doc.exists && mounted) {
        final data = doc.data();
        if (data != null) {
          debugPrint("Existing inspection data retrieved successfully.");
        }
      }
    } catch (e) {
      debugPrint('Error fetching inspection data: $e');
    }
  }

  // Real Google Maps Navigation Integration
  Future<void> _openMapNavigation(String destinationAddress) async {
    final String encodedAddress = Uri.encodeComponent(destinationAddress);
    final Uri googleMapsUrl = Uri.parse('https://www.google.com/maps/search/?api=1&query=$encodedAddress');

    try {
      if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not launch Google Maps.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Navigation error: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _capturePhoto(String type) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
      );
      if (image != null) {
        setState(() {
          if (type == 'Front') preTripFront = File(image.path);
          if (type == 'Back') preTripBack = File(image.path);
          if (type == 'Right') preTripRight = File(image.path);
          if (type == 'Left') preTripLeft = File(image.path);
          if (type == 'Selfie') driverSelfie = File(image.path);
          if (type == 'PostFront') postTripFront = File(image.path);
          if (type == 'PostBack') postTripBack = File(image.path);
          if (type == 'PostRight') postTripRight = File(image.path);
          if (type == 'PostLeft') postTripLeft = File(image.path);
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$type photo captured successfully!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to capture photo: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  bool get areAllPreTripPhotosCaptured {
    return preTripFront != null &&
        preTripBack != null &&
        preTripRight != null &&
        preTripLeft != null &&
        driverSelfie != null;
  }

  bool get areAllPostTripPhotosCaptured {
    return postTripFront != null &&
        postTripBack != null &&
        postTripRight != null &&
        postTripLeft != null;
  }

  Future<String?> _uploadImageToStorageWithRetry(File imageFile, String folderName, {int retries = 3}) async {
    for (int i = 0; i < retries; i++) {
      try {
        String fileName = '${widget.booking.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        Reference ref = FirebaseStorage.instance
            .ref()
            .child('inspections')
            .child(folderName)
            .child(fileName);

        UploadTask uploadTask = ref.putFile(imageFile);
        TaskSnapshot snapshot = await uploadTask;
        String downloadUrl = await snapshot.ref.getDownloadURL();
        return downloadUrl;
      } catch (e) {
        if (i == retries - 1) {
          debugPrint('Upload failed after $retries attempts: $e');
          return null;
        }
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    return null;
  }

  Future<void> changeStatus(String nextStatus) async {
    setState(() {
      isLoading = true;
    });

    try {
      Map<String, dynamic> updateData = {
        'status': nextStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (nextStatus == 'TRIP_STARTED') {
        updateData['preTripFrontUrl'] = preTripFront != null ? await _uploadImageToStorageWithRetry(preTripFront!, 'pre_trip') : null;
        updateData['preTripBackUrl'] = preTripBack != null ? await _uploadImageToStorageWithRetry(preTripBack!, 'pre_trip') : null;
        updateData['preTripRightUrl'] = preTripRight != null ? await _uploadImageToStorageWithRetry(preTripRight!, 'pre_trip') : null;
        updateData['preTripLeftUrl'] = preTripLeft != null ? await _uploadImageToStorageWithRetry(preTripLeft!, 'pre_trip') : null;
        updateData['driverSelfieUrl'] = driverSelfie != null ? await _uploadImageToStorageWithRetry(driverSelfie!, 'selfies') : null;
      }

      if (nextStatus == 'COMPLETED') {
        updateData['postTripFrontUrl'] = postTripFront != null ? await _uploadImageToStorageWithRetry(postTripFront!, 'post_trip') : null;
        updateData['postTripBackUrl'] = postTripBack != null ? await _uploadImageToStorageWithRetry(postTripBack!, 'post_trip') : null;
        updateData['postTripRightUrl'] = postTripRight != null ? await _uploadImageToStorageWithRetry(postTripRight!, 'post_trip') : null;
        updateData['postTripLeftUrl'] = postTripLeft != null ? await _uploadImageToStorageWithRetry(postTripLeft!, 'post_trip') : null;
      }

      final docRef = FirebaseFirestore.instance.collection('bookings').doc(widget.booking.id);
      final docSnap = await docRef.get();

      if (docSnap.exists) {
        await docRef.set(updateData, SetOptions(merge: true));
      } else {
        final query = await FirebaseFirestore.instance
            .collection('bookings')
            .where('id', isEqualTo: widget.booking.id)
            .get();

        if (query.docs.isNotEmpty) {
          await query.docs.first.reference.set(updateData, SetOptions(merge: true));
        } else {
          await docRef.set(updateData, SetOptions(merge: true));
        }
      }

      setState(() {
        status = nextStatus.toUpperCase();
        widget.booking.status = nextStatus;
        isLoading = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Booking status updated to: $nextStatus'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating status: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildPhotoRow(String title, File? file, String typeKey) {
    bool isCaptured = file != null;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isCaptured ? Colors.green.withOpacity(0.05) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCaptured ? Colors.green.withOpacity(0.3) : Colors.grey.withOpacity(0.2),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (isCaptured)
                Container(
                  width: 40,
                  height: 40,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    image: DecorationImage(image: FileImage(file), fit: BoxFit.cover),
                  ),
                )
              else
                Container(
                  width: 40,
                  height: 40,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: AppColors.muted.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.camera_alt, size: 20, color: AppColors.muted),
                ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.navy, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isCaptured ? 'Captured Successfully' : 'Pending',
                    style: TextStyle(
                      fontSize: 11,
                      color: isCaptured ? Colors.green[700] : AppColors.muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
          ElevatedButton.icon(
            onPressed: () => _capturePhoto(typeKey),
            icon: Icon(isCaptured ? Icons.check_circle : Icons.camera_alt, size: 16),
            label: Text(isCaptured ? 'Retake' : 'Capture', style: const TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: isCaptured ? Colors.green : AppColors.navy,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: const Size(80, 32),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Booking b = widget.booking;
    final currentStatus = status.toUpperCase();

    bool showPreTrip = currentStatus == 'ARRIVED' || currentStatus == 'TRIP_STARTED';
    bool showPostTrip = currentStatus == 'TRIP_STARTED';
    
    bool showNavigate = currentStatus != 'ARRIVED' && 
                        currentStatus != 'TRIP_STARTED' && 
                        currentStatus != 'COMPLETED' && 
                        currentStatus != 'CANCELLED';

    bool showContact = currentStatus != 'TRIP_STARTED' && 
                       currentStatus != 'COMPLETED' && 
                       currentStatus != 'CANCELLED';

    return Scaffold(
      appBar: AppBar(
        title: Text('Booking ${b.id}'),
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: AppColors.navy,
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(18),
              children: [
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            b.customer,
                            style: const TextStyle(
                              color: AppColors.navy,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.navy.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              currentStatus,
                              style: const TextStyle(
                                color: AppColors.navy,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text('Pickup: ${b.pickup}'),
                      const SizedBox(height: 4),
                      Text('Destination: ${b.destination}'),
                      const SizedBox(height: 4),
                      Text('Date: ${b.date}'),
                      const SizedBox(height: 4),
                      Text('Time: ${b.time}'),
                      const SizedBox(height: 4),
                      Text('Vehicle: ${b.vehicle}'),
                      const SizedBox(height: 4),
                      Text('Booking ID: ${b.id}'),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                if (showPreTrip) ...[
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Pre-Trip Verification & Inspection',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.navy),
                        ),
                        const SizedBox(height: 4),
                        const Text('Upload 4-side vehicle photos and your selfie before starting trip.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                        const SizedBox(height: 12),
                        _buildPhotoRow('Front Side', preTripFront, 'Front'),
                        _buildPhotoRow('Back Side', preTripBack, 'Back'),
                        _buildPhotoRow('Right Side', preTripRight, 'Right'),
                        _buildPhotoRow('Left Side', preTripLeft, 'Left'),
                        const Divider(height: 24),
                        _buildPhotoRow('Driver Selfie', driverSelfie, 'Selfie'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                if (showPostTrip) ...[
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Post-Trip Vehicle Inspection (4 Sides)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.navy),
                        ),
                        const SizedBox(height: 4),
                        const Text('Capture photos of all 4 sides after completing trip.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                        const SizedBox(height: 12),
                        _buildPhotoRow('Front Side', postTripFront, 'PostFront'),
                        _buildPhotoRow('Back Side', postTripBack, 'PostBack'),
                        _buildPhotoRow('Right Side', postTripRight, 'PostRight'),
                        _buildPhotoRow('Left Side', postTripLeft, 'PostLeft'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                if (currentStatus == 'SEARCHING' || currentStatus == 'REQUESTED') ...[
                  AppPrimaryButton(
                    label: 'ACCEPT BOOKING',
                    onPressed: () => changeStatus('ACCEPTED'),
                  ),
                  const SizedBox(height: 12),
                  AppOutlineButton(
                    label: 'REJECT BOOKING',
                    onPressed: () => changeStatus('CANCELLED'),
                  ),
                ],
                if (currentStatus == 'ACCEPTED') ...[
                  AppPrimaryButton(
                    label: 'START ARRIVING',
                    onPressed: () => changeStatus('ARRIVING'),
                  ),
                ],
                if (currentStatus == 'ARRIVING') ...[
                  AppPrimaryButton(
                    label: 'MARK ARRIVED',
                    onPressed: () => changeStatus('ARRIVED'),
                  ),
                ],
                if (currentStatus == 'ARRIVED') ...[
                  AppPrimaryButton(
                    label: areAllPreTripPhotosCaptured ? 'START TRIP' : 'COMPLETE PHOTOS TO START TRIP',
                    onPressed: areAllPreTripPhotosCaptured
                        ? () => changeStatus('TRIP_STARTED')
                        : () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please capture all 4-side photos and driver selfie first!'),
                                backgroundColor: Colors.red,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                  ),
                ],
                if (currentStatus == 'TRIP_STARTED') ...[
                  AppPrimaryButton(
                    label: areAllPostTripPhotosCaptured ? 'COMPLETE TRIP' : 'COMPLETE POST-TRIP PHOTOS',
                    onPressed: areAllPostTripPhotosCaptured
                        ? () => changeStatus('COMPLETED')
                        : () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please capture all 4 post-trip photos first!'),
                                backgroundColor: Colors.red,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                  ),
                ],
                const SizedBox(height: 12),
                if (showNavigate) ...[
                  AppOutlineButton(
                    label: 'NAVIGATE TO PICKUP',
                    icon: Icons.navigation_rounded,
                    onPressed: () => _openMapNavigation(b.pickup),
                  ),
                  const SizedBox(height: 12),
                ],
                if (showContact) ...[
                  AppOutlineButton(
                    label: 'CONTACT CUSTOMER',
                    icon: Icons.call_rounded,
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Customer contact action ready.'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
    );
  }
}
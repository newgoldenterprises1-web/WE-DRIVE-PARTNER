import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../theme/app_theme.dart';
import '../../models/booking.dart';
import '../../services/booking_status_service.dart';
import '../../services/inspection_service.dart';
import '../../services/location_service.dart';
import '../../services/navigation_service.dart';

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

  String? preTripFrontUrl;
  String? preTripBackUrl;
  String? preTripRightUrl;
  String? preTripLeftUrl;
  String? driverSelfieUrl;

  String? postTripFrontUrl;
  String? postTripBackUrl;
  String? postTripRightUrl;
  String? postTripLeftUrl;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    status = widget.booking.status.toUpperCase();
    _fetchExistingInspectionData();
  }

  Future<void> _fetchExistingInspectionData() async {
    try {
      final inspection = await InspectionService.getInspection(widget.booking.id);
      if (!mounted || inspection == null) return;

      setState(() {
        preTripFrontUrl = inspection.preTripFrontUrl;
        preTripBackUrl = inspection.preTripBackUrl;
        preTripRightUrl = inspection.preTripRightUrl;
        preTripLeftUrl = inspection.preTripLeftUrl;
        driverSelfieUrl = inspection.driverSelfieUrl;
        postTripFrontUrl = inspection.postTripFrontUrl;
        postTripBackUrl = inspection.postTripBackUrl;
        postTripRightUrl = inspection.postTripRightUrl;
        postTripLeftUrl = inspection.postTripLeftUrl;
      });
    } catch (e) {
      debugPrint('Error fetching inspection data: $e');
    }
  }

  Future<void> _openMapNavigation(String destinationAddress) async {
    final address = destinationAddress.trim();
    if (address.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pickup location is unavailable.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      await LocationService.getCurrentPosition();
      final launched = await NavigationService.openDrivingNavigation(address);

      if (!mounted) return;
      if (!launched) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open Google Maps navigation.'),
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
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
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
          if (type == 'Front') {
            preTripFront = File(image.path);
            preTripFrontUrl = null;
          }
          if (type == 'Back') {
            preTripBack = File(image.path);
            preTripBackUrl = null;
          }
          if (type == 'Right') {
            preTripRight = File(image.path);
            preTripRightUrl = null;
          }
          if (type == 'Left') {
            preTripLeft = File(image.path);
            preTripLeftUrl = null;
          }
          if (type == 'Selfie') {
            driverSelfie = File(image.path);
            driverSelfieUrl = null;
          }
          if (type == 'PostFront') {
            postTripFront = File(image.path);
            postTripFrontUrl = null;
          }
          if (type == 'PostBack') {
            postTripBack = File(image.path);
            postTripBackUrl = null;
          }
          if (type == 'PostRight') {
            postTripRight = File(image.path);
            postTripRightUrl = null;
          }
          if (type == 'PostLeft') {
            postTripLeft = File(image.path);
            postTripLeftUrl = null;
          }
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
    return (preTripFront != null || preTripFrontUrl != null) &&
        (preTripBack != null || preTripBackUrl != null) &&
        (preTripRight != null || preTripRightUrl != null) &&
        (preTripLeft != null || preTripLeftUrl != null) &&
        (driverSelfie != null || driverSelfieUrl != null);
  }

  bool get areAllPostTripPhotosCaptured {
    return (postTripFront != null || postTripFrontUrl != null) &&
        (postTripBack != null || postTripBackUrl != null) &&
        (postTripRight != null || postTripRightUrl != null) &&
        (postTripLeft != null || postTripLeftUrl != null);
  }

  Future<String?> _uploadImageToStorageWithRetry(
    File imageFile,
    String folderName, {
    int retries = 3,
  }) async {
    for (int i = 0; i < retries; i++) {
      try {
        final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
        final ref = FirebaseStorage.instance
            .ref()
            .child('inspections')
            .child(widget.booking.id)
            .child(folderName)
            .child(fileName);

        final uploadTask = ref.putFile(imageFile);
        final snapshot = await uploadTask;
        return snapshot.ref.getDownloadURL();
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
    if (isLoading) return;

    final target = nextStatus.trim().toUpperCase();
    if (!BookingStatusService.canTransition(status, target)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invalid booking transition: $status → $target'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final updateData = <String, dynamic>{};

      if (target == 'TRIP_STARTED') {
        if (!areAllPreTripPhotosCaptured) {
          throw StateError('missing_pre_trip_photos');
        }

        if (preTripFrontUrl == null) {
          preTripFrontUrl = await _uploadImageToStorageWithRetry(preTripFront!, 'pre_trip');
        }
        if (preTripBackUrl == null) {
          preTripBackUrl = await _uploadImageToStorageWithRetry(preTripBack!, 'pre_trip');
        }
        if (preTripRightUrl == null) {
          preTripRightUrl = await _uploadImageToStorageWithRetry(preTripRight!, 'pre_trip');
        }
        if (preTripLeftUrl == null) {
          preTripLeftUrl = await _uploadImageToStorageWithRetry(preTripLeft!, 'pre_trip');
        }
        if (driverSelfieUrl == null) {
          driverSelfieUrl = await _uploadImageToStorageWithRetry(driverSelfie!, 'selfies');
        }

        updateData['preTripFrontUrl'] = preTripFrontUrl;
        updateData['preTripBackUrl'] = preTripBackUrl;
        updateData['preTripRightUrl'] = preTripRightUrl;
        updateData['preTripLeftUrl'] = preTripLeftUrl;
        updateData['driverSelfieUrl'] = driverSelfieUrl;

        if (updateData.values.any((value) => value == null)) {
          throw StateError('pre_trip_upload_failed');
        }
      }

      if (target == 'COMPLETED') {
        if (!areAllPostTripPhotosCaptured) {
          throw StateError('missing_post_trip_photos');
        }

        if (postTripFrontUrl == null) {
          postTripFrontUrl = await _uploadImageToStorageWithRetry(postTripFront!, 'post_trip');
        }
        if (postTripBackUrl == null) {
          postTripBackUrl = await _uploadImageToStorageWithRetry(postTripBack!, 'post_trip');
        }
        if (postTripRightUrl == null) {
          postTripRightUrl = await _uploadImageToStorageWithRetry(postTripRight!, 'post_trip');
        }
        if (postTripLeftUrl == null) {
          postTripLeftUrl = await _uploadImageToStorageWithRetry(postTripLeft!, 'post_trip');
        }

        updateData['postTripFrontUrl'] = postTripFrontUrl;
        updateData['postTripBackUrl'] = postTripBackUrl;
        updateData['postTripRightUrl'] = postTripRightUrl;
        updateData['postTripLeftUrl'] = postTripLeftUrl;

        if (updateData.values.any((value) => value == null)) {
          throw StateError('post_trip_upload_failed');
        }
      }

      final updated = await BookingStatusService.updateStatus(
        bookingId: widget.booking.id,
        nextStatus: target,
      );

      if (!updated) {
        throw StateError('status_update_rejected');
      }

      if (updateData.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('bookings')
            .doc(widget.booking.id)
            .set(updateData, SetOptions(merge: true));
      }

      if (!mounted) return;
      setState(() {
        status = target;
        widget.booking.status = target;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Booking status updated to: $target'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      String message = 'Error updating booking status.';
      if (e is StateError) {
        switch (e.message) {
          case 'missing_pre_trip_photos':
            message = 'Please capture all pre-trip photos and driver selfie first.';
            break;
          case 'missing_post_trip_photos':
            message = 'Please capture all post-trip photos first.';
            break;
          case 'pre_trip_upload_failed':
            message = 'Pre-trip inspection upload failed. Please retry.';
            break;
          case 'post_trip_upload_failed':
            message = 'Post-trip inspection upload failed. Please retry.';
            break;
          case 'status_update_rejected':
            message = 'Booking is no longer available for this action.';
            break;
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Widget _buildPhotoRow(
    String title,
    File? file,
    String? remoteUrl,
    String typeKey,
  ) {
    final isCaptured = file != null || (remoteUrl != null && remoteUrl.isNotEmpty);

    ImageProvider? imageProvider;
    if (file != null) {
      imageProvider = FileImage(file);
    } else if (remoteUrl != null && remoteUrl.isNotEmpty) {
      imageProvider = NetworkImage(remoteUrl);
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isCaptured ? Colors.green.withOpacity(0.05) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCaptured
              ? Colors.green.withOpacity(0.3)
              : Colors.grey.withOpacity(0.2),
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
                    image: imageProvider == null
                        ? null
                        : DecorationImage(
                            image: imageProvider,
                            fit: BoxFit.cover,
                          ),
                  ),
                  child: imageProvider == null
                      ? const Icon(Icons.broken_image_outlined, size: 20)
                      : null,
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
                  child: const Icon(
                    Icons.camera_alt,
                    size: 20,
                    color: AppColors.muted,
                  ),
                ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.navy,
                      fontSize: 14,
                    ),
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
            onPressed: isLoading ? null : () => _capturePhoto(typeKey),
            icon: Icon(
              isCaptured ? Icons.check_circle : Icons.camera_alt,
              size: 16,
            ),
            label: Text(
              isCaptured ? 'Retake' : 'Capture',
              style: const TextStyle(fontSize: 12),
            ),
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

    final showPreTrip = currentStatus == 'ARRIVED' || currentStatus == 'TRIP_STARTED';
    final showPostTrip = currentStatus == 'TRIP_STARTED';
    final showNavigate = currentStatus != 'ARRIVED' &&
        currentStatus != 'TRIP_STARTED' &&
        currentStatus != 'COMPLETED' &&
        currentStatus != 'CANCELLED';
    final showContact = currentStatus != 'TRIP_STARTED' &&
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
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: AppColors.navy,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Upload 4-side vehicle photos and your selfie before starting trip.',
                          style: TextStyle(color: AppColors.muted, fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        _buildPhotoRow('Front Side', preTripFront, preTripFrontUrl, 'Front'),
                        _buildPhotoRow('Back Side', preTripBack, preTripBackUrl, 'Back'),
                        _buildPhotoRow('Right Side', preTripRight, preTripRightUrl, 'Right'),
                        _buildPhotoRow('Left Side', preTripLeft, preTripLeftUrl, 'Left'),
                        const Divider(height: 24),
                        _buildPhotoRow('Driver Selfie', driverSelfie, driverSelfieUrl, 'Selfie'),
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
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: AppColors.navy,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Capture photos of all 4 sides after completing trip.',
                          style: TextStyle(color: AppColors.muted, fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        _buildPhotoRow('Front Side', postTripFront, postTripFrontUrl, 'PostFront'),
                        _buildPhotoRow('Back Side', postTripBack, postTripBackUrl, 'PostBack'),
                        _buildPhotoRow('Right Side', postTripRight, postTripRightUrl, 'PostRight'),
                        _buildPhotoRow('Left Side', postTripLeft, postTripLeftUrl, 'PostLeft'),
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
                    label: areAllPreTripPhotosCaptured
                        ? 'START TRIP'
                        : 'COMPLETE PHOTOS TO START TRIP',
                    onPressed: areAllPreTripPhotosCaptured
                        ? () => changeStatus('TRIP_STARTED')
                        : () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Please capture all 4-side photos and driver selfie first!',
                                ),
                                backgroundColor: Colors.red,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                  ),
                ],
                if (currentStatus == 'TRIP_STARTED') ...[
                  AppPrimaryButton(
                    label: areAllPostTripPhotosCaptured
                        ? 'COMPLETE TRIP'
                        : 'COMPLETE POST-TRIP PHOTOS',
                    onPressed: areAllPostTripPhotosCaptured
                        ? () => changeStatus('COMPLETED')
                        : () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Please capture all 4 post-trip photos first!',
                                ),
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
                    onPressed: isLoading
                        ? null
                        : () => _openMapNavigation(b.pickup),
                  ),
                  const SizedBox(height: 12),
                ],
                if (showContact) ...[
                  AppOutlineButton(
                    label: 'CONTACT CUSTOMER',
                    icon: Icons.call_rounded,
                    onPressed: isLoading
                        ? null
                        : () {
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

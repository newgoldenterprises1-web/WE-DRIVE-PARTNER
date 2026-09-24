import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/booking.dart';
import '../../theme/app_theme.dart';

class BookingDetailScreen extends StatefulWidget {
  final Booking booking;

  const BookingDetailScreen({super.key, required this.booking});

  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
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
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'asia-south1');
  final TextEditingController _otpController = TextEditingController();

  @override
  void initState() {
    super.initState();
    status = widget.booking.status.toUpperCase();
    _fetchExistingInspectionData();
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _fetchExistingInspectionData() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('bookings').doc(widget.booking.id).get();
      if (doc.exists) {
        debugPrint('Existing booking data loaded for ${widget.booking.id}.');
      }
    } catch (e) {
      debugPrint('Error fetching inspection data: $e');
    }
  }

  Future<void> _openMapNavigation(String destinationAddress) async {
    final address = destinationAddress.trim();
    if (address.isEmpty) return;

    final uri = Uri.https('www.google.com', '/maps/search/', <String, String>{
      'api': '1',
      'query': address,
    });

    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Map launch failed: $e');
    }
  }

  Future<void> _callCustomer() async {
    final phone = widget.booking.customerPhone?.replaceAll(RegExp(r'\D'), '') ?? '';
    if (phone.length < 10) return;
    final local = phone.startsWith('91') && phone.length == 12 ? phone.substring(2) : phone;
    final uri = Uri.parse('tel:+91$local');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _capturePhoto(String type) async {
    try {
      final image = await _picker.pickImage(source: ImageSource.camera, imageQuality: 70);
      if (image == null) return;
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
        SnackBar(content: Text('$type photo captured successfully!'), behavior: SnackBarBehavior.floating),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to capture photo: $e'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
      );
    }
  }

  bool get areAllPreTripPhotosCaptured =>
      preTripFront != null && preTripBack != null && preTripRight != null && preTripLeft != null && driverSelfie != null;

  bool get areAllPostTripPhotosCaptured =>
      postTripFront != null && postTripBack != null && postTripRight != null && postTripLeft != null;

  Future<String?> _uploadImageToStorage(File imageFile, String folderName) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    final fileName = '${DateTime.now().millisecondsSinceEpoch}_${imageFile.uri.pathSegments.isNotEmpty ? imageFile.uri.pathSegments.last : 'photo'}.jpg';
    final ref = FirebaseStorage.instance
        .ref()
        .child('inspections')
        .child(uid)
        .child(widget.booking.id)
        .child(folderName)
        .child(fileName);
    final snapshot = await ref.putFile(imageFile);
    return snapshot.ref.getDownloadURL();
  }

  Future<void> _acceptBooking() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Partner session is not available.');
    final partner = await FirebaseFirestore.instance.collection('partners').doc(uid).get();
    if (!partner.exists || partner.data()?['online'] != true) {
      throw StateError('Go online before accepting a booking.');
    }
    await _functions.httpsCallable('acceptBooking').call({'bookingId': widget.booking.id});
  }

  Future<void> _declineBooking() async {
    await _functions.httpsCallable('declineBooking').call({'bookingId': widget.booking.id});
  }

  Future<void> _transitionBooking(String nextStatus, {String? otp}) async {
    final payload = <String, dynamic>{'bookingId': widget.booking.id, 'status': nextStatus};

    if (nextStatus == 'TRIP_STARTED') {
      if (!areAllPreTripPhotosCaptured) {
        throw StateError('Please capture all pre-trip photos first.');
      }
      if (otp == null || otp.trim().isEmpty) {
        throw StateError('Trip start OTP is required.');
      }

      final uploads = await Future.wait([
        _uploadImageToStorage(preTripFront!, 'pre_trip'),
        _uploadImageToStorage(preTripBack!, 'pre_trip'),
        _uploadImageToStorage(preTripRight!, 'pre_trip'),
        _uploadImageToStorage(preTripLeft!, 'pre_trip'),
        _uploadImageToStorage(driverSelfie!, 'selfies'),
      ]);
      if (uploads.any((url) => url == null)) {
        throw StateError('One or more inspection photos failed to upload. Please retry.');
      }
      payload.addAll({
        'preTripFrontUrl': uploads[0],
        'preTripBackUrl': uploads[1],
        'preTripRightUrl': uploads[2],
        'preTripLeftUrl': uploads[3],
        'driverSelfieUrl': uploads[4],
        'otp': otp.trim(),
      });
    }

    if (nextStatus == 'COMPLETED') {
      if (!areAllPostTripPhotosCaptured) {
        throw StateError('Please capture all post-trip photos first.');
      }
      final uploads = await Future.wait([
        _uploadImageToStorage(postTripFront!, 'post_trip'),
        _uploadImageToStorage(postTripBack!, 'post_trip'),
        _uploadImageToStorage(postTripRight!, 'post_trip'),
        _uploadImageToStorage(postTripLeft!, 'post_trip'),
      ]);
      if (uploads.any((url) => url == null)) {
        throw StateError('One or more post-trip photos failed to upload. Please retry.');
      }
      payload.addAll({
        'postTripFrontUrl': uploads[0],
        'postTripBackUrl': uploads[1],
        'postTripRightUrl': uploads[2],
        'postTripLeftUrl': uploads[3],
      });
    }

    await _functions.httpsCallable('transitionBooking').call(payload);
  }

  Future<void> _promptAndStartTrip() async {
    _otpController.clear();
    final otp = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Start Trip OTP'),
        content: TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          maxLength: 4,
          decoration: const InputDecoration(
            hintText: 'Enter 4-digit OTP',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, _otpController.text.trim()),
            child: const Text('Verify'),
          ),
        ],
      ),
    );

    if (otp == null || otp.isEmpty) return;
    await changeStatus('TRIP_STARTED', otp: otp);
  }

  Future<void> changeStatus(String nextStatus, {String? otp}) async {
    if (isLoading) return;
    setState(() => isLoading = true);
    try {
      if (nextStatus == 'ACCEPTED') {
        await _acceptBooking();
      } else if (nextStatus == 'CANCELLED') {
        await _declineBooking();
      } else {
        await _transitionBooking(nextStatus, otp: otp);
      }

      if (!mounted) return;
      setState(() {
        status = nextStatus;
        widget.booking.status = nextStatus;
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(nextStatus == 'CANCELLED' ? 'Booking declined successfully.' : 'Booking status updated to: $nextStatus'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Booking action failed.'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('StateError: ', '')), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
      );
    }
  }

  Widget _photoRow(String title, File? file, String typeKey) {
    final isCaptured = file != null;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isCaptured ? Colors.green.withOpacity(0.05) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isCaptured ? Colors.green.withOpacity(0.3) : Colors.grey.withOpacity(0.2)),
      ),
      child: Row(
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
              decoration: BoxDecoration(color: AppColors.muted.withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
              child: const Icon(Icons.camera_alt, size: 20, color: AppColors.muted),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.navy, fontSize: 14)),
                const SizedBox(height: 2),
                Text(isCaptured ? 'Captured Successfully' : 'Pending', style: TextStyle(fontSize: 11, color: isCaptured ? Colors.green[700] : AppColors.muted, fontWeight: FontWeight.w500)),
              ],
            ),
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
    final b = widget.booking;
    final currentStatus = status.toUpperCase();
    final showPreTrip = currentStatus == 'ARRIVED' || currentStatus == 'TRIP_STARTED';
    final showPostTrip = currentStatus == 'TRIP_STARTED';

    return Scaffold(
      appBar: AppBar(title: Text('Booking ${b.id}')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.navy))
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
                          Text(b.customer, style: const TextStyle(color: AppColors.navy, fontSize: 24, fontWeight: FontWeight.w900)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: AppColors.navy.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                            child: Text(currentStatus, style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 12)),
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
                AppPrimaryButton(label: 'OPEN NAVIGATION', onPressed: () => _openMapNavigation(b.pickup)),
                const SizedBox(height: 12),
                AppOutlineButton(label: 'CALL CUSTOMER', onPressed: _callCustomer),
                const SizedBox(height: 18),
                if (showPreTrip) ...[
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Pre-Trip Verification & Inspection', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.navy)),
                        const SizedBox(height: 4),
                        const Text('Upload 4-side vehicle photos and your selfie before starting trip.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                        const SizedBox(height: 12),
                        _photoRow('Front Side', preTripFront, 'Front'),
                        _photoRow('Back Side', preTripBack, 'Back'),
                        _photoRow('Right Side', preTripRight, 'Right'),
                        _photoRow('Left Side', preTripLeft, 'Left'),
                        const Divider(height: 24),
                        _photoRow('Driver Selfie', driverSelfie, 'Selfie'),
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
                        const Text('Post-Trip Vehicle Inspection (4 Sides)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.navy)),
                        const SizedBox(height: 4),
                        const Text('Capture photos of all 4 sides after completing trip.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                        const SizedBox(height: 12),
                        _photoRow('Front Side', postTripFront, 'PostFront'),
                        _photoRow('Back Side', postTripBack, 'PostBack'),
                        _photoRow('Right Side', postTripRight, 'PostRight'),
                        _photoRow('Left Side', postTripLeft, 'PostLeft'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (currentStatus == 'SEARCHING' || currentStatus == 'REQUESTED') ...[
                  AppPrimaryButton(label: 'ACCEPT BOOKING', onPressed: () => changeStatus('ACCEPTED')),
                  const SizedBox(height: 12),
                  AppOutlineButton(label: 'REJECT BOOKING', onPressed: () => changeStatus('CANCELLED')),
                ],
                if (currentStatus == 'ACCEPTED') AppPrimaryButton(label: 'START ARRIVING', onPressed: () => changeStatus('ARRIVING')),
                if (currentStatus == 'ARRIVING') AppPrimaryButton(label: 'MARK ARRIVED', onPressed: () => changeStatus('ARRIVED')),
                if (currentStatus == 'ARRIVED')
                  AppPrimaryButton(
                    label: areAllPreTripPhotosCaptured ? 'START TRIP' : 'COMPLETE PHOTOS TO START TRIP',
                    onPressed: areAllPreTripPhotosCaptured ? _promptAndStartTrip : () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please capture all 4-side photos and driver selfie first!'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
                      );
                    },
                  ),
                if (currentStatus == 'TRIP_STARTED')
                  AppPrimaryButton(
                    label: areAllPostTripPhotosCaptured ? 'COMPLETE TRIP' : 'COMPLETE POST-TRIP PHOTOS',
                    onPressed: areAllPostTripPhotosCaptured ? () => changeStatus('COMPLETED') : () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please capture all post-trip photos first!'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
                      );
                    },
                  ),
              ],
            ),
    );
  }
}

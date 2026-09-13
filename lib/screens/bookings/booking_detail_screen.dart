import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  static const MethodChannel _mapsChannel = MethodChannel('we_drive/maps');

  @override
  void initState() {
    super.initState();
    status = widget.booking.status.toUpperCase();
    _fetchExistingInspectionData();
  }

  Future<void> _fetchExistingInspectionData() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('bookings').doc(widget.booking.id).get();
      if (doc.exists) debugPrint('Existing inspection data retrieved successfully.');
    } catch (e) {
      debugPrint('Error fetching inspection data: $e');
    }
  }

  Future<void> _openMapNavigation(String destinationAddress) async {
    final address = destinationAddress.trim();
    if (address.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pickup location is not available.')),
      );
      return;
    }

    // Android: use an explicit Google Maps intent first. This avoids Android
    // package-visibility/browser-handler issues and starts turn-by-turn driving.
    if (Platform.isAndroid) {
      try {
        final opened = await _mapsChannel.invokeMethod<bool>(
          'openGoogleMaps',
          <String, dynamic>{'destination': address},
        );
        if (opened == true) return;
      } catch (e) {
        debugPrint('Native Google Maps launch failed: $e');
      }
    }

    // Universal Maps URL: Google documents this as the cross-platform fallback;
    // it opens the Maps app when installed and otherwise opens Maps in a browser.
    final directionsUri = Uri.https(
      'www.google.com',
      '/maps/dir/',
      <String, String>{
        'api': '1',
        'destination': address,
        'travelmode': 'driving',
        'dir_action': 'navigate',
      },
    );
    final searchUri = Uri.https(
      'www.google.com',
      '/maps/search/',
      <String, String>{
        'api': '1',
        'query': address,
      },
    );
    final geoUri = Uri.parse('geo:0,0?q=${Uri.encodeComponent(address)}');

    for (final uri in <Uri>[directionsUri, searchUri, geoUri]) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
      } catch (e) {
        debugPrint('Maps fallback launch failed for $uri: $e');
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Google Maps could not be opened. Please install or enable Google Maps or a web browser.'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _contactCustomer() async {
    final phone = widget.booking.customerPhone?.replaceAll(RegExp(r'\D'), '') ?? '';
    if (phone.length < 10) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Customer contact number is not available for this booking.')),
      );
      return;
    }
    final local = phone.startsWith('91') && phone.length == 12 ? phone.substring(2) : phone;
    try {
      if (await launchUrl(Uri.parse('tel:+91$local'))) return;
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open the phone dialer.')),
    );
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

  bool get areAllPreTripPhotosCaptured => preTripFront != null && preTripBack != null && preTripRight != null && preTripLeft != null && driverSelfie != null;
  bool get areAllPostTripPhotosCaptured => postTripFront != null && postTripBack != null && postTripRight != null && postTripLeft != null;

  Future<String?> _uploadImageToStorageWithRetry(File imageFile, String folderName, {int retries = 3}) async {
    for (var i = 0; i < retries; i++) {
      try {
        final fileName = '${widget.booking.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final ref = FirebaseStorage.instance.ref().child('inspections').child(folderName).child(fileName);
        final snapshot = await ref.putFile(imageFile);
        return await snapshot.ref.getDownloadURL();
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

  Future<void> changeStatus(String nextStatus) async {
    if (isLoading) return;
    setState(() => isLoading = true);
    try {
      if (nextStatus == 'ACCEPTED') {
        await _acceptBooking();
      } else if (nextStatus == 'CANCELLED') {
        await _declineBooking();
      } else {
        final updateData = <String, dynamic>{'status': nextStatus, 'updatedAt': FieldValue.serverTimestamp()};
        if (nextStatus == 'ARRIVING') updateData['arrivingAt'] = FieldValue.serverTimestamp();
        if (nextStatus == 'ARRIVED') updateData['arrivedAt'] = FieldValue.serverTimestamp();

        if (nextStatus == 'TRIP_STARTED') {
          if (!areAllPreTripPhotosCaptured) throw StateError('Please capture all pre-trip photos first.');
          final uploads = await Future.wait([
            _uploadImageToStorageWithRetry(preTripFront!, 'pre_trip'),
            _uploadImageToStorageWithRetry(preTripBack!, 'pre_trip'),
            _uploadImageToStorageWithRetry(preTripRight!, 'pre_trip'),
            _uploadImageToStorageWithRetry(preTripLeft!, 'pre_trip'),
            _uploadImageToStorageWithRetry(driverSelfie!, 'selfies'),
          ]);
          if (uploads.any((url) => url == null)) throw StateError('One or more inspection photos failed to upload. Please retry.');
          updateData.addAll({'preTripFrontUrl': uploads[0], 'preTripBackUrl': uploads[1], 'preTripRightUrl': uploads[2], 'preTripLeftUrl': uploads[3], 'driverSelfieUrl': uploads[4], 'startedAt': FieldValue.serverTimestamp()});
        }

        if (nextStatus == 'COMPLETED') {
          if (!areAllPostTripPhotosCaptured) throw StateError('Please capture all post-trip photos first.');
          final uploads = await Future.wait([
            _uploadImageToStorageWithRetry(postTripFront!, 'post_trip'),
            _uploadImageToStorageWithRetry(postTripBack!, 'post_trip'),
            _uploadImageToStorageWithRetry(postTripRight!, 'post_trip'),
            _uploadImageToStorageWithRetry(postTripLeft!, 'post_trip'),
          ]);
          if (uploads.any((url) => url == null)) throw StateError('One or more post-trip photos failed to upload. Please retry.');
          updateData.addAll({'postTripFrontUrl': uploads[0], 'postTripBackUrl': uploads[1], 'postTripRightUrl': uploads[2], 'postTripLeftUrl': uploads[3], 'completedAt': FieldValue.serverTimestamp()});
        }

        await FirebaseFirestore.instance.collection('bookings').doc(widget.booking.id).set(updateData, SetOptions(merge: true));
      }

      if (!mounted) return;
      setState(() {
        status = nextStatus;
        widget.booking.status = nextStatus;
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(nextStatus == 'CANCELLED' ? 'Booking declined successfully.' : 'Booking status updated to: $nextStatus'), behavior: SnackBarBehavior.floating),
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

  Widget _buildPhotoRow(String title, File? file, String typeKey) {
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            if (isCaptured)
              Container(width: 40, height: 40, margin: const EdgeInsets.only(right: 10), decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), image: DecorationImage(image: FileImage(file), fit: BoxFit.cover)))
            else
              Container(width: 40, height: 40, margin: const EdgeInsets.only(right: 10), decoration: BoxDecoration(color: AppColors.muted.withOpacity(0.2), borderRadius: BorderRadius.circular(6)), child: const Icon(Icons.camera_alt, size: 20, color: AppColors.muted)),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.navy, fontSize: 14)),
              const SizedBox(height: 2),
              Text(isCaptured ? 'Captured Successfully' : 'Pending', style: TextStyle(fontSize: 11, color: isCaptured ? Colors.green[700] : AppColors.muted, fontWeight: FontWeight.w500)),
            ]),
          ]),
          ElevatedButton.icon(onPressed: () => _capturePhoto(typeKey), icon: Icon(isCaptured ? Icons.check_circle : Icons.camera_alt, size: 16), label: Text(isCaptured ? 'Retake' : 'Capture', style: const TextStyle(fontSize: 12)), style: ElevatedButton.styleFrom(backgroundColor: isCaptured ? Colors.green : AppColors.navy, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: const Size(80, 32), elevation: 0)),
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
    final showNavigate = currentStatus != 'ARRIVED' && currentStatus != 'TRIP_STARTED' && currentStatus != 'COMPLETED' && currentStatus != 'CANCELLED';
    final showContact = currentStatus != 'TRIP_STARTED' && currentStatus != 'COMPLETED' && currentStatus != 'CANCELLED';

    return Scaffold(
      appBar: AppBar(title: Text('Booking ${b.id}')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.navy))
          : ListView(
              padding: const EdgeInsets.all(18),
              children: [
                AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(b.customer, style: const TextStyle(color: AppColors.navy, fontSize: 24, fontWeight: FontWeight.w900)),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: AppColors.navy.withOpacity(0.1), borderRadius: BorderRadius.circular(6)), child: Text(currentStatus, style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.bold, fontSize: 12))),
                    ]),
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
                  ]),
                ),
                const SizedBox(height: 18),
                if (showPreTrip) ...[
                  AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Pre-Trip Verification & Inspection', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.navy)),
                    const SizedBox(height: 4),
                    const Text('Upload 4-side vehicle photos and your selfie before starting trip.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    const SizedBox(height: 12),
                    _buildPhotoRow('Front Side', preTripFront, 'Front'),
                    _buildPhotoRow('Back Side', preTripBack, 'Back'),
                    _buildPhotoRow('Right Side', preTripRight, 'Right'),
                    _buildPhotoRow('Left Side', preTripLeft, 'Left'),
                    const Divider(height: 24),
                    _buildPhotoRow('Driver Selfie', driverSelfie, 'Selfie'),
                  ])),
                  const SizedBox(height: 12),
                ],
                if (showPostTrip) ...[
                  AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Post-Trip Vehicle Inspection (4 Sides)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.navy)),
                    const SizedBox(height: 4),
                    const Text('Capture photos of all 4 sides after completing trip.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    const SizedBox(height: 12),
                    _buildPhotoRow('Front Side', postTripFront, 'PostFront'),
                    _buildPhotoRow('Back Side', postTripBack, 'PostBack'),
                    _buildPhotoRow('Right Side', postTripRight, 'PostRight'),
                    _buildPhotoRow('Left Side', postTripLeft, 'PostLeft'),
                  ])),
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
                    onPressed: areAllPreTripPhotosCaptured ? () => changeStatus('TRIP_STARTED') : () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please capture all 4-side photos and driver selfie first!'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating)),
                  ),
                if (currentStatus == 'TRIP_STARTED')
                  AppPrimaryButton(
                    label: areAllPostTripPhotosCaptured ? 'COMPLETE TRIP' : 'COMPLETE POST-TRIP PHOTOS',
                    onPressed: areAllPostTripPhotosCaptured ? () => changeStatus('COMPLETED') : () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please capture all 4 post-trip photos first!'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating)),
                  ),
                const SizedBox(height: 12),
                if (showNavigate) ...[
                  AppOutlineButton(label: 'NAVIGATE TO PICKUP', icon: Icons.navigation_rounded, onPressed: () => _openMapNavigation(b.pickup)),
                  const SizedBox(height: 12),
                ],
                if (showContact) AppOutlineButton(label: 'CONTACT CUSTOMER', icon: Icons.call_rounded, onPressed: _contactCustomer),
              ],
            ),
    );
  }
}

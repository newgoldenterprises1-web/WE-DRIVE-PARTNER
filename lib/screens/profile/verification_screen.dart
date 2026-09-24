import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  bool isProcessing = false;
  bool isPaid = false;
  String verificationStatus = 'PENDING';
  String dlStatus = 'Pending';
  String idStatus = 'Pending';
  String selfieStatus = 'Pending';
  final ImagePicker _imagePicker = ImagePicker();
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'asia-south1');

  @override
  void initState() {
    super.initState();
    _fetchVerificationStatus();
  }

  Future<void> _fetchVerificationStatus() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance.collection('partners').doc(user.uid).get();
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          setState(() {
            isPaid = data['registrationFeePaid'] ?? false;
            verificationStatus = data['verificationStatus'] ?? 'PENDING';
            dlStatus = data['dlStatus'] ?? (isPaid ? 'Pending Review' : 'Payment Required');
            idStatus = data['idStatus'] ?? (isPaid ? 'Pending Review' : 'Payment Required');
            selfieStatus = data['selfieStatus'] ?? 'Pending';
          });
        }
      }
    } catch (e) {
      print('Error fetching status: $e');
    }
  }

  Future<void> _processRegistrationFeePayment() async {
    setState(() {
      isProcessing = true;
    });

    // Simulate UPI / PhonePe Payment Gateway Intent
    await Future.delayed(const Duration(seconds: 2));

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('partners').doc(user.uid).set({
          'registrationFeePaid': true,
          'feePaidAt': FieldValue.serverTimestamp(),
          'registrationAmount': 399,
          'verificationStatus': 'UNDER_REVIEW',
          'dlStatus': 'Pending Review',
          'idStatus': 'Pending Review',
        }, SetOptions(merge: true));
      }

      setState(() {
        isProcessing = false;
        isPaid = true;
        verificationStatus = 'UNDER_REVIEW';
        dlStatus = 'Pending Review';
        idStatus = 'Pending Review';
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('₹399 Payment Successful! Documents submitted for review.'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      setState(() {
        isProcessing = false;
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

  Future<void> _uploadDocument(String type, ImageSource source) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in again.')),
      );
      return;
    }

    try {
      final image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 86,
        maxWidth: 2200,
      );
      if (image == null) return;

      setState(() => isProcessing = true);

      final fileName = type + '.jpg';
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('verification')
          .child(user.uid)
          .child(fileName);

      await storageRef.putData(
        await image.readAsBytes(),
        SettableMetadata(contentType: 'image/jpeg'),
      );

      final url = await storageRef.getDownloadURL();

      await _functions.httpsCallable('submitVerificationDocument').call({
        'type': type,
        'url': url,
      });

      await _fetchVerificationStatus();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            type == 'license'
                ? 'Driving Licence submitted.'
                : type == 'id'
                    ? 'Government ID submitted.'
                    : 'Profile photo submitted.',
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload failed: ' + e.toString()),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  Future<void> _handleDocumentTap(String type) async {
    final source = type == 'selfie'
        ? ImageSource.camera
        : ImageSource.gallery;
    await _uploadDocument(type, source);
  }

  void _showPaymentSheet(BuildContext context) {
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
                    color: AppColors.navy.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.payment_rounded, color: AppColors.navy, size: 24),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Partner Registration Fee',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.navy),
                      ),
                      SizedBox(height: 2),
                      Text('Activation & Verification charges', style: TextStyle(color: AppColors.muted, fontSize: 12)),
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
                  Text('One-Time Exchange / Setup Fee', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.navy)),
                  Text('₹399', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.navy)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Select UPI App (PhonePe / GPay / Paytm)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.muted),
            ),
            const SizedBox(height: 10),
            ListTile(
              tileColor: Colors.grey.shade50,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              leading: const Icon(Icons.phone_android_rounded, color: AppColors.navy),
              title: const Text('UPI Payment Intent', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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
                _processRegistrationFeePayment();
              },
              child: const Text('PAY ₹399 & SUBMIT', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
            ),
          ],
        ),
      ),
    );
  }

  Widget document(String title, String status, IconData icon, VoidCallback onTap) {
    final bool isAdded = status == 'Added' || status == 'Approved';
    final bool isPending = status == 'Pending Review';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AppCard(
          child: Row(
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
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  color: AppColors.navy,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isAdded
                    ? const Color(0xFFE7F7EE)
                    : isPending
                        ? const Color(0xFFFFF2C9)
                        : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                status.toUpperCase(),
                style: TextStyle(
                  color: isAdded
                      ? AppColors.green
                      : isPending
                          ? const Color(0xFF8D6900)
                          : AppColors.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: const Text('Verification & KYC'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
        children: [
          // Status Banner
          AppCard(
            color: isPaid ? const Color(0xFFE7F7EE) : const Color(0xFFFFF8DD),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (isPaid ? AppColors.green : AppColors.gold).withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isPaid ? Icons.verified_rounded : Icons.hourglass_top_rounded,
                    color: AppColors.navy,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    isPaid
                        ? 'FEE PAID (₹399) — Your account is under verification.'
                        : 'PAY REGISTRATION FEE — Complete ₹399 payment to submit documents.',
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          if (!isPaid) ...[
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
                onPressed: isProcessing ? null : () => _showPaymentSheet(context),
                child: isProcessing
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('PAY REGISTRATION FEE (₹399)', style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
            const SizedBox(height: 18),
          ],

          const Text(
            'Submitted Documents',
            style: TextStyle(
              color: AppColors.navy,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),

          document(
            'Driving Licence',
            dlStatus,
            Icons.badge_outlined,
            () => _handleDocumentTap('license'),
          ),
          document(
            'Government ID (Aadhaar / PAN)',
            idStatus,
            Icons.perm_identity_rounded,
            () => _handleDocumentTap('id'),
          ),
          document(
            'Profile Photo',
            selfieStatus,
            Icons.photo_camera_outlined,
            () => _handleDocumentTap('selfie'),
          ),
        ],
      ),
    );
  }
}
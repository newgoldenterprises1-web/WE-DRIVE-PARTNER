import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../auth/payment_screen.dart';

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  bool isProcessing = false;
  String? uploadingDocument;
  final ImagePicker _picker = ImagePicker();
  bool isPaid = false;
  String verificationStatus = 'PENDING';
  String dlStatus = 'Pending';
  String idStatus = 'Pending';
  String selfieStatus = 'Added';

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
            dlStatus = data['licenseDocumentStatus'] ?? data['dlStatus'] ?? (isPaid ? 'Pending' : 'Payment Required');
            idStatus = data['governmentIdDocumentStatus'] ?? data['governmentIdDocumentStatus'] ?? data['governmentIdStatus'] ?? data['idStatus'] ?? (isPaid ? 'Pending Review' : 'Payment Required');
          });
        }
      }
    } catch (e) {
      print('Error fetching status: $e');
    }
  }

  Future<void> _processRegistrationFeePayment() async {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PaymentScreen()),
    );
  }


  void _showPaymentSheet(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PaymentScreen()),
    );
  }


  Future<void> _uploadDocument(String type) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      setState(() => uploadingDocument = type);
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (image == null) return;

      final file = XFile(image.path);
      final ref = FirebaseStorage.instance
          .ref()
          .child('verification')
          .child(user.uid)
          .child(type + '.jpg');

      await ref.putFile(File(image.path));
      final url = await ref.getDownloadURL();

      final fieldPrefix = type == 'driving_license' ? 'license' : 'governmentId';
      await FirebaseFirestore.instance.collection('partners').doc(user.uid).set({
        fieldPrefix + 'DocumentUrl': url,
        fieldPrefix + 'DocumentStatus': 'SUBMITTED',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _fetchVerificationStatus();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(type == 'driving_license' ? 'Driving Licence submitted for review.' : 'Government ID submitted for review.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Document upload failed: ' + e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => uploadingDocument = null);
    }
  }

  Widget document(String title, String status, IconData icon, String type) {
    final bool isAdded = status == 'Added' || status == 'Approved' || status == 'SUBMITTED';
    final bool isPending = status == 'Pending Review' || status == 'SUBMITTED';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
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
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppColors.navy),
              ),
            ),
            if (uploadingDocument == type)
              const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
            else if (status == 'Pending' || status == 'Pending Review' || status == 'REUPLOAD_REQUIRED' || status == 'Payment Required')
              IconButton(
                tooltip: 'Upload',
                onPressed: () => _uploadDocument(type),
                icon: const Icon(Icons.upload_file_rounded, color: AppColors.navy),
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
                        ? 'FEE PAID (₹299) — Your account is under verification.'
                        : 'PAY REGISTRATION FEE — Complete ₹299 payment to submit documents.',
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
                    : const Text('PAY REGISTRATION FEE (₹299)', style: TextStyle(fontWeight: FontWeight.w900)),
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
            'driving_license',
          ),
          document(
            'Government ID (Aadhaar / PAN)',
            idStatus,
            Icons.perm_identity_rounded,
            'government_id',
          ),
          document(
            'Profile Photo',
            selfieStatus,
            Icons.photo_camera_outlined,
          ),
        ],
      ),
    );
  }
}
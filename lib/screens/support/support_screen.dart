import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _messageController = TextEditingController();
  bool submitting = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _submitTicket(BuildContext sheetContext, String category) async {
    final text = _messageController.text.trim();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (text.isEmpty) {
      showMessage('Please enter your message.');
      return;
    }
    if (uid == null) {
      showMessage('Please sign in again before contacting support.');
      return;
    }

    setState(() => submitting = true);
    try {
      await FirebaseFirestore.instance.collection('supportTickets').add({
        'userId': uid,
        'category': category,
        'message': text,
        'status': 'OPEN',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _messageController.clear();
      if (!mounted) return;
      Navigator.pop(sheetContext);
      showMessage('Support ticket submitted successfully.');
    } catch (e) {
      if (!mounted) return;
      showMessage('Could not submit support ticket: $e');
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  void _openSupportDialog(String category) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(20, 24, 20, MediaQuery.of(sheetContext).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Support: $category', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.navy)),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(sheetContext)),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Describe your issue below. Your request will be saved with your partner account.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
            const SizedBox(height: 16),
            TextField(
              controller: _messageController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Type your message here...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.navy, width: 2)),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
                onPressed: submitting ? null : () => _submitTicket(sheetContext, category),
                child: submitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('SUBMIT TICKET', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget item(BuildContext context, String title, String subtitle, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        onTap: () => _openSupportDialog(title),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppColors.navy.withOpacity(0.06), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: AppColors.navy, size: 22)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppColors.navy)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w500)),
          ])),
          const Icon(Icons.chevron_right_rounded, color: AppColors.muted, size: 20),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(title: const Text('Partner Support'), elevation: 0),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
        children: [
          AppCard(
            color: AppColors.navy,
            child: Row(children: [
              Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppColors.gold.withOpacity(0.2), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.support_agent_rounded, color: AppColors.gold, size: 26)),
              const SizedBox(width: 14),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('24/7 Partner Helpline', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
                SizedBox(height: 2),
                Text('Hyderabad Support Hub', style: TextStyle(color: Colors.white70, fontSize: 12)),
              ])),
            ]),
          ),
          const SizedBox(height: 20),
          const Text('How can we help you?', style: TextStyle(color: AppColors.navy, fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          item(context, 'Booking Support', 'Help with a customer journey', Icons.calendar_today_outlined),
          item(context, 'Payment Support', 'Earnings and settlement help', Icons.payments_outlined),
          item(context, 'Account Support', 'Profile, documents and verification', Icons.person_outline),
          item(context, 'FAQ', 'Frequently asked questions', Icons.help_outline),
          const SizedBox(height: 12),
          AppPrimaryButton(label: 'CONTACT SUPPORT', icon: Icons.support_agent, onPressed: () => _openSupportDialog('General Inquiry')),
        ],
      ),
    );
  }
}

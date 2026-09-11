import 'package:cloud_firestore/cloud_firestore.dart';

class InspectionData {
  final String? preTripFrontUrl;
  final String? preTripBackUrl;
  final String? preTripRightUrl;
  final String? preTripLeftUrl;
  final String? driverSelfieUrl;
  final String? postTripFrontUrl;
  final String? postTripBackUrl;
  final String? postTripRightUrl;
  final String? postTripLeftUrl;

  const InspectionData({
    this.preTripFrontUrl,
    this.preTripBackUrl,
    this.preTripRightUrl,
    this.preTripLeftUrl,
    this.driverSelfieUrl,
    this.postTripFrontUrl,
    this.postTripBackUrl,
    this.postTripRightUrl,
    this.postTripLeftUrl,
  });

  factory InspectionData.fromMap(Map<String, dynamic> data) {
    String? read(String key) {
      final value = data[key];
      final text = value?.toString().trim();
      return text == null || text.isEmpty ? null : text;
    }

    return InspectionData(
      preTripFrontUrl: read('preTripFrontUrl'),
      preTripBackUrl: read('preTripBackUrl'),
      preTripRightUrl: read('preTripRightUrl'),
      preTripLeftUrl: read('preTripLeftUrl'),
      driverSelfieUrl: read('driverSelfieUrl'),
      postTripFrontUrl: read('postTripFrontUrl'),
      postTripBackUrl: read('postTripBackUrl'),
      postTripRightUrl: read('postTripRightUrl'),
      postTripLeftUrl: read('postTripLeftUrl'),
    );
  }

  bool get hasAnyData =>
      preTripFrontUrl != null ||
      preTripBackUrl != null ||
      preTripRightUrl != null ||
      preTripLeftUrl != null ||
      driverSelfieUrl != null ||
      postTripFrontUrl != null ||
      postTripBackUrl != null ||
      postTripRightUrl != null ||
      postTripLeftUrl != null;

  bool get hasCompletePreTrip =>
      preTripFrontUrl != null &&
      preTripBackUrl != null &&
      preTripRightUrl != null &&
      preTripLeftUrl != null &&
      driverSelfieUrl != null;

  bool get hasCompletePostTrip =>
      postTripFrontUrl != null &&
      postTripBackUrl != null &&
      postTripRightUrl != null &&
      postTripLeftUrl != null;
}

class InspectionService {
  InspectionService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> _bookingRef(String bookingId) {
    return _firestore.collection('bookings').doc(bookingId.trim());
  }

  static Future<InspectionData?> getInspection(String bookingId) async {
    final id = bookingId.trim();
    if (id.isEmpty) return null;

    final snapshot = await _bookingRef(id).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;

    final inspection = InspectionData.fromMap(data);
    return inspection.hasAnyData ? inspection : null;
  }

  static Future<void> savePreTrip({
    required String bookingId,
    required String preTripFrontUrl,
    required String preTripBackUrl,
    required String preTripRightUrl,
    required String preTripLeftUrl,
    required String driverSelfieUrl,
  }) async {
    await _bookingRef(bookingId).set({
      'preTripFrontUrl': preTripFrontUrl,
      'preTripBackUrl': preTripBackUrl,
      'preTripRightUrl': preTripRightUrl,
      'preTripLeftUrl': preTripLeftUrl,
      'driverSelfieUrl': driverSelfieUrl,
      'inspectionUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> savePostTrip({
    required String bookingId,
    required String postTripFrontUrl,
    required String postTripBackUrl,
    required String postTripRightUrl,
    required String postTripLeftUrl,
  }) async {
    await _bookingRef(bookingId).set({
      'postTripFrontUrl': postTripFrontUrl,
      'postTripBackUrl': postTripBackUrl,
      'postTripRightUrl': postTripRightUrl,
      'postTripLeftUrl': postTripLeftUrl,
      'inspectionUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

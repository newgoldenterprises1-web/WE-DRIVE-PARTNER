const { onCall, onRequest } = require('firebase-functions/v2/https');
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

initializeApp();

const auth = getAuth();
const db = getFirestore();

function requireAuth(request) {
  if (!request.auth?.uid) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }
  return request.auth.uid;
}

function optionalString(value, max = 500) {
  if (value == null) return null;
  const text = String(value).trim();
  if (!text) return null;
  return text.slice(0, max);
}

function optionalNumber(value) {
  if (value == null || value === '') return null;
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function requireCustomer(request) {
  const uid = requireAuth(request);
  if (request.auth?.token?.role !== 'customer') {
    throw new HttpsError('permission-denied', 'Customer access is required.');
  }
  return uid;
}

exports.ensureCustomerAccount = onCall(
  { region: 'asia-south1' },
  async (request) => {
    const uid = requireAuth(request);
    const user = await auth.getUser(uid);
    const existingClaims = user.customClaims || {};
    const userRef = db.collection('users').doc(uid);
    const snap = await userRef.get();
    const existing = snap.data() || {};

    const name = optionalString(request.data?.name, 120) || user.displayName || existing.name || 'WE DRIVE Customer';
    const email = user.email || optionalString(request.data?.email, 200) || existing.email || null;
    const phone = user.phoneNumber || optionalString(request.data?.phone, 30) || existing.phone || null;

    await auth.setCustomUserClaims(uid, {
      ...existingClaims,
      role: 'customer',
    });

    const profile = {
      uid,
      role: 'customer',
      name,
      email,
      phone,
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (!snap.exists) profile.createdAt = FieldValue.serverTimestamp();

    await userRef.set(profile, { merge: true });
    await db.collection('profiles').doc(uid).set(profile, { merge: true });

    return { ok: true, uid, role: 'customer' };
  },
);

exports.createCustomerBooking = onCall(
  { region: 'asia-south1' },
  async (request) => {
    const uid = requireCustomer(request);
    const input = request.data || {};

    const serviceType = optionalString(input.serviceType, 100);
    const pickupLocation = optionalString(input.pickupLocation, 500);
    if (!serviceType || !pickupLocation) {
      throw new HttpsError('invalid-argument', 'Service type and pickup location are required.');
    }

    const fare = Math.max(0, Number(input.fare || 0));
    if (!Number.isFinite(fare)) {
      throw new HttpsError('invalid-argument', 'Invalid fare.');
    }

    const userSnap = await db.collection('users').doc(uid).get();
    const userData = userSnap.data() || {};
    const bookingRef = db.collection('bookings').doc();

    const data = {
      bookingId: bookingRef.id,
      customerId: uid,
      customerName: userData.name || 'WE DRIVE Customer',
      customerPhone: userData.phone || null,
      customerEmail: userData.email || null,
      serviceType,
      vehicleType: optionalString(input.vehicleType, 120),
      transmission: optionalString(input.transmission, 80),
      fuelType: optionalString(input.fuelType, 80),
      pickupLocation,
      dropLocation: optionalString(input.dropLocation, 500),
      pickupLatitude: optionalNumber(input.pickupLatitude),
      pickupLongitude: optionalNumber(input.pickupLongitude),
      dropLatitude: optionalNumber(input.dropLatitude),
      dropLongitude: optionalNumber(input.dropLongitude),
      bookingDate: input.bookingDate || null,
      bookingTime: optionalString(input.bookingTime, 50),
      selectedHours: input.selectedHours == null ? null : Number(input.selectedHours),
      fare,
      currency: 'INR',
      paymentMethod: 'Cash',
      paymentStatus: 'pending',
      status: 'REQUESTED',
      bookingStatus: 'REQUESTED',
      partnerId: null,
      driverId: null,
      driverName: null,
      driverPhone: null,
      driverRating: null,
      driverExperience: null,
      driverVerified: false,
      assignedVehicle: null,
      specialInstruction: optionalString(input.specialInstruction, 1000),
      serviceMode: optionalString(input.serviceMode, 80),
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    };

    await bookingRef.set(data);
    return { ok: true, bookingId: bookingRef.id, status: 'REQUESTED' };
  },
);

exports.enrichCustomerBookingOnAssign = onDocumentWritten(
  { document: 'bookings/{bookingId}', region: 'asia-south1' },
  async (event) => {
    const before = event.data?.before?.data() || null;
    const after = event.data?.after?.data();
    if (!after) return;

    const afterStatus = String(after.status || '').toUpperCase();
    const beforeStatus = String(before?.status || '').toUpperCase();
    const partnerId = String(after.partnerId || '').trim();
    if (!partnerId || afterStatus !== 'ACCEPTED' || beforeStatus === 'ACCEPTED') return;

    const partnerSnap = await db.collection('partners').doc(partnerId).get();
    const partner = partnerSnap.data() || {};
    const existingVehicle = after.assignedVehicle;
    const partnerVehicle = {
      model: partner.vehicleModel || partner.vehicleType || null,
      color: partner.vehicleColor || null,
      number: partner.vehicleNumber || partner.registrationNumber || null,
    };

    const otp = String(Math.floor(1000 + Math.random() * 9000));
    await event.data.after.ref.set(
      {
        driverId: partnerId,
        driverName: partner.name || partner.fullName || 'WE DRIVE Chauffeur',
        driverPhone: partner.phoneNumber || null,
        driverRating: Number(partner.rating || 5),
        driverExperience: partner.experienceYears ?? partner.experience ?? null,
        driverVerified: partner.verified === true || partner.verificationStatus === 'VERIFIED',
        assignedVehicle: existingVehicle || partnerVehicle,
        otp,
        bookingStatus: 'ACCEPTED',
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    const customerId = String(after.customerId || '').trim();
    if (customerId) {
      await db.collection('notifications').add({
        userId: customerId,
        type: 'booking',
        title: 'Chauffeur assigned',
        message: `${partner.name || 'Your chauffeur'} has accepted your WE DRIVE request.`,
        bookingId: event.params.bookingId,
        read: false,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
  },
);

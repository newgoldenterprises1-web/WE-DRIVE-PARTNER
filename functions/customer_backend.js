const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { getApps, initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { notifyAvailableDrivers } = require('./notification_service');

if (!getApps().length) initializeApp();

const auth = getAuth();
const db = getFirestore();

function requireAuth(request) {
  if (!request.auth?.uid) throw new HttpsError('unauthenticated', 'Authentication is required.');
  return request.auth.uid;
}

function optionalString(value, max = 500) {
  if (value == null) return null;
  const text = String(value).trim();
  return text ? text.slice(0, max) : null;
}

function optionalNumber(value) {
  if (value == null || value === '') return null;
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function safeList(value, maxItems = 10) {
  if (!Array.isArray(value)) return [];
  return value.map((item) => optionalString(item, 80)).filter(Boolean).slice(0, maxItems);
}

function requireCustomer(request) {
  const uid = requireAuth(request);
  if (request.auth?.token?.role !== 'customer') {
    throw new HttpsError('permission-denied', 'Customer access is required.');
  }
  return uid;
}

function distanceKm(lat1, lng1, lat2, lng2) {
  const toRad = (v) => (v * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function chauffeurLevel(score, trips) {
  if (score >= 95 && trips >= 1000) return 'SIGNATURE';
  if (score >= 92 && trips >= 500) return 'EXECUTIVE';
  if (score >= 88 && trips >= 250) return 'ELITE';
  if (score >= 82 && trips >= 100) return 'PROFESSIONAL';
  return 'VERIFIED';
}

exports.ensureCustomerAccount = onCall(
  { region: 'asia-south1', enforceAppCheck: true },
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

    await auth.setCustomUserClaims(uid, { ...existingClaims, role: 'customer' });

    const profile = { uid, role: 'customer', name, email, phone, updatedAt: FieldValue.serverTimestamp() };
    if (!snap.exists) profile.createdAt = FieldValue.serverTimestamp();

    await userRef.set(profile, { merge: true });
    await db.collection('profiles').doc(uid).set(profile, { merge: true });
    return { ok: true, uid, role: 'customer' };
  },
);

exports.createCustomerBooking = onCall(
  { region: 'asia-south1', enforceAppCheck: true },
  async (request) => {
    const uid = requireCustomer(request);
    const input = request.data || {};

    const serviceType = optionalString(input.serviceType, 100);
    const pickupLocation = optionalString(input.pickupLocation, 500);
    if (!serviceType || !pickupLocation) {
      throw new HttpsError('invalid-argument', 'Service type and pickup location are required.');
    }

    const fare = Math.max(0, Number(input.fare || 0));
    if (!Number.isFinite(fare) || fare <= 0) throw new HttpsError('invalid-argument', 'Invalid fare.');

    const paymentMethod = String(input.paymentMethod || 'Cash').trim();
    if (!['UPI', 'Card', 'Cash'].includes(paymentMethod)) {
      throw new HttpsError('invalid-argument', 'Unsupported payment method.');
    }
    const requiresPayment = paymentMethod !== 'Cash';
    const initialStatus = requiresPayment ? 'PAYMENT_PENDING' : 'REQUESTED';

    const userSnap = await db.collection('users').doc(uid).get();
    const userData = userSnap.data() || {};
    const preferences = input.requestPreferences || {};
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
      paymentMethod,
      paymentStatus: 'pending',
      status: initialStatus,
      bookingStatus: initialStatus,
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
      requestPreferences: {
        communicationStyle: optionalString(preferences.communicationStyle, 40) || 'NORMAL',
        privacyMode: preferences.privacyMode === true,
        preferredChauffeurId: optionalString(preferences.preferredChauffeurId, 160),
        luggageMode: optionalString(preferences.luggageMode, 40) || 'LIGHT',
        pickupMode: optionalString(preferences.pickupMode, 50) || 'CUSTOM_PIN',
        guestName: optionalString(preferences.guestName, 120),
        guestPhone: optionalString(preferences.guestPhone, 30),
        guestRelationship: optionalString(preferences.guestRelationship, 60),
        trustedContactName: optionalString(preferences.trustedContactName, 120),
        trustedContactPhone: optionalString(preferences.trustedContactPhone, 30),
        eventType: optionalString(preferences.eventType, 80),
        corporateAccountId: optionalString(preferences.corporateAccountId, 120),
        conciergeMode: preferences.conciergeMode === true,
        whiteGlove: preferences.whiteGlove === true,
        preferredLanguages: safeList(preferences.preferredLanguages, 5),
        multipleStops: Array.isArray(preferences.multipleStops) ? preferences.multipleStops.slice(0, 8) : [],
        recurringBooking: preferences.recurringBooking == null ? null : preferences.recurringBooking,
      },
      signatureMatchRequested: true,
      matchStatus: requiresPayment ? 'PAYMENT_REQUIRED' : 'WAITING',
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    };

    await bookingRef.set(data);

    if (!requiresPayment) {
      await notifyAvailableDrivers({
        bookingId: bookingRef.id,
        title: 'New chauffeur booking',
        message: 'A customer booking is available. Open WE DRIVE Partner to respond.',
      });
    }

    return { ok: true, bookingId: bookingRef.id, status: initialStatus, paymentRequired: requiresPayment };
  },
);

exports.cancelCustomerBooking = onCall(
  { region: 'asia-south1', enforceAppCheck: true },
  async (request) => {
    const uid = requireCustomer(request);
    const bookingId = optionalString(request.data?.bookingId, 160);
    const reason = optionalString(request.data?.reason, 300) || 'Cancelled by customer';
    if (!bookingId) throw new HttpsError('invalid-argument', 'Booking ID is required.');

    const bookingRef = db.collection('bookings').doc(bookingId);
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(bookingRef);
      if (!snap.exists) throw new HttpsError('not-found', 'Booking not found.');

      const data = snap.data() || {};
      if (String(data.customerId || '') !== uid) {
        throw new HttpsError('permission-denied', 'You cannot cancel this booking.');
      }

      const current = String(data.status || data.bookingStatus || '').toUpperCase();
      if (['COMPLETED', 'CANCELLED', 'TRIP_STARTED', 'IN_PROGRESS', 'STARTED'].includes(current)) {
        throw new HttpsError('failed-precondition', 'This booking can no longer be cancelled.');
      }

      tx.set(bookingRef, {
        status: 'CANCELLED',
        bookingStatus: 'CANCELLED',
        cancelledBy: 'customer',
        cancellationReason: reason,
        cancelledAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    });

    return { ok: true, bookingId, status: 'CANCELLED' };
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



    const prefs = after.requestPreferences || {};

    const driverRating = Number(partner.rating || 5);
    const experience = Number(partner.experienceYears ?? partner.experience ?? 0);
    const trips = Number(partner.completedTrips ?? partner.totalTrips ?? partner.tripsCompleted ?? 0);
    const punctuality = Number(partner.punctualityScore ?? partner.punctuality ?? 95);
    const verified = partner.verified === true || partner.verificationStatus === 'VERIFIED';
    const distance = Number.isFinite(Number(after.pickupLatitude)) && Number.isFinite(Number(after.pickupLongitude)) &&
        Number.isFinite(Number(partner.latitude)) && Number.isFinite(Number(partner.longitude))
      ? distanceKm(Number(after.pickupLatitude), Number(after.pickupLongitude), Number(partner.latitude), Number(partner.longitude))
      : null;

    let matchScore = Math.round(Math.min(100,
      driverRating * 12 +
      Math.min(15, experience * 2) +
      Math.min(15, punctuality / 7) +
      (verified ? 15 : 0) +
      (distance == null ? 5 : Math.max(0, 18 - distance * 3)) +
      (prefs.preferredChauffeurId === partnerId ? 15 : 0)
    ));
    matchScore = Math.max(55, Math.min(100, matchScore));

    const badges = [];
    if (verified) badges.push('VERIFIED');
    if (driverRating >= 4.8) badges.push('TOP RATED');
    if (punctuality >= 95) badges.push('PUNCTUAL');
    if (trips >= 500) badges.push('EXPERIENCED');
    if (prefs.preferredChauffeurId === partnerId) badges.push('PREFERRED');
    if (prefs.whiteGlove === true) badges.push('WHITE GLOVE');

    const score = Math.round((driverRating * 0.45 + punctuality * 0.35 + (verified ? 100 : 70) * 0.20));
    const level = chauffeurLevel(score, trips);
    const existingVehicle = after.assignedVehicle;
    const partnerVehicle = {
      model: partner.vehicleModel || partner.vehicleType || null,
      color: partner.vehicleColor || null,
      number: partner.vehicleNumber || partner.registrationNumber || null,
    };

    const otp = String(Math.floor(1000 + Math.random() * 9000));
    await event.data.after.ref.set({
      driverId: partnerId,
      driverName: partner.name || partner.fullName || 'WE DRIVE Chauffeur',
      driverPhone: partner.phoneNumber || null,
      driverRating,
      driverExperience: experience,
      driverVerified: verified,
      assignedVehicle: existingVehicle || partnerVehicle,
      otp,
      bookingStatus: 'ACCEPTED',
      matchStatus: 'MATCHED',
      matchScore,
      matchReasons: [
        verified ? 'Verified identity' : 'Profile available',
        `${driverRating.toFixed(1)} rating`,
        `${punctuality}% punctuality`,
        experience > 0 ? `${experience} yrs experience` : 'Professional chauffeur',
        distance == null ? null : `${distance.toFixed(1)} km away`,
      ].filter(Boolean),
      chauffeurLevel: level,
      chauffeurBadges: badges,
      chauffeurPassportId: `WD-${partnerId.slice(0, 8).toUpperCase()}`,
      reliabilityScore: score,
      estimatedDistanceKm: distance,
      signatureMatch: matchScore >= 90,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });

    const customerId = String(after.customerId || '').trim();
    if (customerId) {
      await db.collection('notifications').add({
        userId: customerId,
        type: 'booking',
        title: 'Signature chauffeur matched',
        message: `${partner.name || 'Your chauffeur'} matched your WE DRIVE preferences with a ${matchScore}% match.`,
        bookingId: event.params.bookingId,
        read: false,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
  },
);

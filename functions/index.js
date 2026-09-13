const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');

admin.initializeApp();

const MSG91_AUTHKEY = defineSecret('MSG91_AUTHKEY');
const db = admin.firestore();

function requireAuth(request) {
  if (!request.auth?.uid) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }
  return request.auth.uid;
}

function requireDriver(request) {
  const uid = requireAuth(request);
  if (request.auth.token?.role !== 'driver') {
    throw new HttpsError('permission-denied', 'Driver access is required.');
  }
  return uid;
}

function normalizePhone(phoneNumber) {
  const digits = String(phoneNumber || '').replace(/\D/g, '');
  if (!/^91\d{10}$/.test(digits)) {
    throw new HttpsError('invalid-argument', 'Use a valid Indian mobile number.');
  }
  return `+${digits}`;
}

async function verifyWithMsg91(accessToken) {
  if (!accessToken || typeof accessToken !== 'string') {
    throw new HttpsError('unauthenticated', 'MSG91 verification token is missing.');
  }

  const response = await fetch('https://control.msg91.com/api/v5/widget/verifyAccessToken', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      authkey: MSG91_AUTHKEY.value(),
      'access-token': accessToken,
    }),
  });

  const body = await response.json().catch(() => ({}));
  const statusText = String(body?.type || body?.status || '').toLowerCase();

  if (!response.ok || (statusText && !['success', 'ok'].includes(statusText))) {
    throw new HttpsError('unauthenticated', 'MSG91 OTP verification could not be completed.');
  }

  return body;
}

async function createFirebaseSession({ accessToken, phoneNumber, role }) {
  const phone = normalizePhone(phoneNumber);
  await verifyWithMsg91(accessToken);

  let user;
  try {
    user = await admin.auth().getUserByPhoneNumber(phone);
  } catch (error) {
    if (error?.code !== 'auth/user-not-found') throw error;
    user = await admin.auth().createUser({ phoneNumber: phone });
  }

  await admin.auth().setCustomUserClaims(user.uid, { role });
  const customToken = await admin.auth().createCustomToken(user.uid, { role });

  return { customToken, uid: user.uid, role };
}

exports.verifyDriverMsg91AccessToken = onCall(
  { secrets: [MSG91_AUTHKEY], region: 'asia-south1' },
  async (request) => createFirebaseSession({
    accessToken: request.data?.accessToken,
    phoneNumber: request.data?.phoneNumber,
    role: 'driver',
  }),
);

exports.verifyCustomerMsg91AccessToken = onCall(
  { secrets: [MSG91_AUTHKEY], region: 'asia-south1' },
  async (request) => createFirebaseSession({
    accessToken: request.data?.accessToken,
    phoneNumber: request.data?.phoneNumber,
    role: 'customer',
  }),
);

exports.setDriverPresence = onCall(
  { region: 'asia-south1' },
  async (request) => {
    const uid = requireDriver(request);
    const online = Boolean(request.data?.online);

    await db.collection('partners').doc(uid).set({
      online,
      role: 'driver',
      lastSeenAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    return { ok: true, online };
  },
);

exports.updateDriverLocation = onCall(
  { region: 'asia-south1' },
  async (request) => {
    const uid = requireDriver(request);
    const latitude = Number(request.data?.latitude);
    const longitude = Number(request.data?.longitude);

    if (!Number.isFinite(latitude) || !Number.isFinite(longitude) ||
        latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
      throw new HttpsError('invalid-argument', 'Invalid coordinates.');
    }

    await db.collection('partners').doc(uid).set({
      online: true,
      latitude,
      longitude,
      locationAccuracy: Number(request.data?.accuracy || 0),
      heading: Number(request.data?.heading || 0),
      speed: Number(request.data?.speed || 0),
      locationUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    return { ok: true };
  },
);

exports.acceptBooking = onCall(
  { region: 'asia-south1' },
  async (request) => {
    const uid = requireDriver(request);
    const bookingId = String(request.data?.bookingId || '');
    if (!bookingId) throw new HttpsError('invalid-argument', 'Booking ID is required.');

    const ref = db.collection('bookings').doc(bookingId);
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) throw new HttpsError('not-found', 'Booking not found.');
      const data = snap.data() || {};
      const status = String(data.status || '').toUpperCase();
      if (!['REQUESTED', 'SEARCHING'].includes(status)) {
        throw new HttpsError('failed-precondition', 'This booking is no longer available.');
      }
      tx.set(ref, {
        status: 'ACCEPTED',
        partnerId: uid,
        acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    });

    return { ok: true, bookingId, status: 'ACCEPTED' };
  },
);

exports.declineBooking = onCall(
  { region: 'asia-south1' },
  async (request) => {
    const uid = requireDriver(request);
    const bookingId = String(request.data?.bookingId || '');
    if (!bookingId) throw new HttpsError('invalid-argument', 'Booking ID is required.');

    const ref = db.collection('bookings').doc(bookingId);
    const snap = await ref.get();
    if (!snap.exists) throw new HttpsError('not-found', 'Booking not found.');

    await ref.set({
      declinedBy: admin.firestore.FieldValue.arrayUnion(uid),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    return { ok: true, bookingId, status: 'DECLINED' };
  },
);

// Idempotent earnings ledger: one completed booking creates at most one ledger row.
exports.onBookingWritten = onDocumentWritten(
  { document: 'bookings/{bookingId}', region: 'asia-south1' },
  async (event) => {
    const after = event.data?.after?.data();
    if (!after) return;
    if (String(after.status || '').toUpperCase() !== 'COMPLETED') return;

    const partnerId = after.partnerId;
    if (!partnerId) return;

    const fare = Number(after.fare || 0);
    const share = Number(after.partnerSharePercent ?? 85);
    const earnings = Math.max(0, Math.round(fare * share / 100));
    const bookingId = event.params.bookingId;

    await db.collection('partners').doc(partnerId).collection('earnings').doc(bookingId).set({
      bookingId,
      fare,
      partnerSharePercent: share,
      earnings,
      completedAt: after.completedAt || admin.firestore.FieldValue.serverTimestamp(),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  },
);

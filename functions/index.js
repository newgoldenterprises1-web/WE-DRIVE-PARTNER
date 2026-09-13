const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');

admin.initializeApp();
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

exports.ensureDriverAccount = onCall(
  { region: 'asia-south1' },
  async (request) => {
    const uid = requireAuth(request);
    const user = await admin.auth().getUser(uid);
    const requestedName = String(request.data?.name || '').trim();
    const phone = user.phoneNumber || normalizePhone(request.data?.phoneNumber);
    const name = requestedName || user.displayName || 'WE DRIVE Partner';
    const partnerRef = db.collection('partners').doc(uid);
    const existing = await partnerRef.get();

    await admin.auth().setCustomUserClaims(uid, { role: 'driver' });

    const profile = {
      uid,
      role: 'driver',
      phoneNumber: phone,
      name,
      fullName: name,
      onboardingStatus: existing.exists ? (existing.data()?.onboardingStatus || 'ACTIVE') : 'ACTIVE',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (!existing.exists) {
      profile.createdAt = admin.firestore.FieldValue.serverTimestamp();
      profile.online = false;
    }
    await partnerRef.set(profile, { merge: true });

    return { ok: true, uid, role: 'driver', phoneNumber: phone };
  },
);

exports.setDriverPresence = onCall(
  { region: 'asia-south1' },
  async (request) => {
    const uid = requireDriver(request);
    const online = Boolean(request.data?.online);
    const ref = db.collection('partners').doc(uid);
    const snap = await ref.get();
    const existing = snap.data() || {};
    const update = {
      online,
      role: 'driver',
      lastSeenAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (online) {
      update.onlineSince = admin.firestore.FieldValue.serverTimestamp();
    } else if (existing.onlineSince?.toDate) {
      const seconds = Math.max(0, Math.floor((Date.now() - existing.onlineSince.toDate().getTime()) / 1000));
      update.totalOnlineSeconds = Number(existing.totalOnlineSeconds || 0) + seconds;
      update.onlineSince = null;
    }

    await ref.set(update, { merge: true });
    return { ok: true, online };
  },
);

exports.updateDriverLocation = onCall(
  { region: 'asia-south1' },
  async (request) => {
    const uid = requireDriver(request);
    const latitude = Number(request.data?.latitude);
    const longitude = Number(request.data?.longitude);
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude) || latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
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
    const data = snap.data() || {};
    const status = String(data.status || '').toUpperCase();
    if (!['REQUESTED', 'SEARCHING'].includes(status)) {
      throw new HttpsError('failed-precondition', 'This booking is no longer available.');
    }
    await ref.set({
      declinedBy: admin.firestore.FieldValue.arrayUnion(uid),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    return { ok: true, bookingId, status: 'DECLINED' };
  },
);

exports.onBookingWritten = onDocumentWritten(
  { document: 'bookings/{bookingId}', region: 'asia-south1' },
  async (event) => {
    const before = event.data?.before?.data() || null;
    const after = event.data?.after?.data();
    if (!after) return;

    const bookingId = event.params.bookingId;
    const partnerId = after.partnerId;
    if (!partnerId) return;

    const beforeStatus = String(before?.status || '').toUpperCase();
    const afterStatus = String(after.status || '').toUpperCase();

    if (afterStatus === 'ACCEPTED' && beforeStatus !== 'ACCEPTED') {
      await db.collection('notifications').add({
        userId: partnerId,
        type: 'booking',
        title: 'Booking accepted',
        message: `Booking ${bookingId} has been assigned to you.`,
        bookingId,
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    if (afterStatus === 'COMPLETED') {
      const fare = Number(after.fare || 0);
      const share = Number(after.partnerSharePercent ?? 85);
      const earnings = Math.max(0, Math.round(fare * share / 100));

      await db.collection('partners').doc(partnerId).collection('earnings').doc(bookingId).set({
        bookingId,
        fare,
        partnerSharePercent: share,
        earnings,
        completedAt: after.completedAt || admin.firestore.FieldValue.serverTimestamp(),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      if (beforeStatus !== 'COMPLETED') {
        await db.collection('notifications').add({
          userId: partnerId,
          type: 'earning',
          title: 'Trip completed',
          message: `₹${earnings} has been added to your earnings ledger.`,
          bookingId,
          read: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    }
  },
);

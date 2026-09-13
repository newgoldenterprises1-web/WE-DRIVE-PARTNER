const { onCall, HttpsError } = require('firebase-functions/v2/https');
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

function requireDriver(request) {
  const uid = requireAuth(request);
  if (request.auth?.token?.role !== 'driver') {
    throw new HttpsError('permission-denied', 'Driver access is required.');
  }
  return uid;
}

function normalizeIndianPhone(phoneNumber) {
  const digits = String(phoneNumber || '').replace(/\D/g, '');
  const local = digits.startsWith('91') && digits.length === 12 ? digits.slice(2) : digits;
  if (!/^[6-9]\d{9}$/.test(local)) {
    throw new HttpsError('invalid-argument', 'Use a valid Indian mobile number.');
  }
  return `+91${local}`;
}

exports.ensureDriverAccount = onCall(
  { region: 'asia-south1' },
  async (request) => {
    const uid = requireAuth(request);
    const user = await auth.getUser(uid);
    const requestedName = String(request.data?.name || '').trim();
    const phone = user.phoneNumber || normalizeIndianPhone(request.data?.phoneNumber);
    const name = requestedName || user.displayName || 'WE DRIVE Partner';

    const partnerRef = db.collection('partners').doc(uid);
    const partnerSnap = await partnerRef.get();
    const existing = partnerSnap.data() || {};
    const existingClaims = user.customClaims || {};

    await auth.setCustomUserClaims(uid, {
      ...existingClaims,
      role: 'driver',
    });

    const profile = {
      uid,
      role: 'driver',
      phoneNumber: phone,
      name,
      fullName: name,
      onboardingStatus: existing.onboardingStatus || 'ACTIVE',
      updatedAt: FieldValue.serverTimestamp(),
    };

    if (!partnerSnap.exists) {
      profile.createdAt = FieldValue.serverTimestamp();
      profile.online = false;
      profile.totalOnlineSeconds = 0;
    }

    await partnerRef.set(profile, { merge: true });
    await db.collection('profiles').doc(uid).set(
      {
        uid,
        role: 'driver',
        phoneNumber: phone,
        name,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

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
    if (!snap.exists) {
      throw new HttpsError('failed-precondition', 'Partner account is not initialized.');
    }

    const existing = snap.data() || {};
    const update = {
      role: 'driver',
      online,
      lastSeenAt: FieldValue.serverTimestamp(),
    };

    if (online) {
      update.onlineSince = FieldValue.serverTimestamp();
    } else if (existing.onlineSince?.toDate) {
      const seconds = Math.max(
        0,
        Math.floor((Date.now() - existing.onlineSince.toDate().getTime()) / 1000),
      );
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

    if (
      !Number.isFinite(latitude) ||
      !Number.isFinite(longitude) ||
      latitude < -90 ||
      latitude > 90 ||
      longitude < -180 ||
      longitude > 180
    ) {
      throw new HttpsError('invalid-argument', 'Invalid coordinates.');
    }

    const partnerRef = db.collection('partners').doc(uid);
    const partnerSnap = await partnerRef.get();
    if (!partnerSnap.exists || partnerSnap.data()?.online !== true) {
      throw new HttpsError('failed-precondition', 'Partner must be online to share location.');
    }

    await partnerRef.set(
      {
        latitude,
        longitude,
        locationAccuracy: Math.max(0, Number(request.data?.accuracy || 0)),
        heading: Number(request.data?.heading || 0),
        speed: Math.max(0, Number(request.data?.speed || 0)),
        locationUpdatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return { ok: true };
  },
);

exports.acceptBooking = onCall(
  { region: 'asia-south1' },
  async (request) => {
    const uid = requireDriver(request);
    const bookingId = String(request.data?.bookingId || '').trim();
    if (!bookingId) {
      throw new HttpsError('invalid-argument', 'Booking ID is required.');
    }

    const partnerRef = db.collection('partners').doc(uid);
    const partnerSnap = await partnerRef.get();
    if (!partnerSnap.exists || partnerSnap.data()?.online !== true) {
      throw new HttpsError('failed-precondition', 'Go online before accepting a booking.');
    }

    const bookingRef = db.collection('bookings').doc(bookingId);

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(bookingRef);
      if (!snap.exists) {
        throw new HttpsError('not-found', 'Booking not found.');
      }

      const data = snap.data() || {};
      const status = String(data.status || '').toUpperCase();
      const declinedBy = Array.isArray(data.declinedBy) ? data.declinedBy : [];

      if (declinedBy.includes(uid)) {
        throw new HttpsError('failed-precondition', 'You already declined this booking.');
      }

      if (!['REQUESTED', 'SEARCHING'].includes(status)) {
        throw new HttpsError('failed-precondition', 'This booking is no longer available.');
      }

      tx.set(
        bookingRef,
        {
          status: 'ACCEPTED',
          partnerId: uid,
          acceptedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    });

    return { ok: true, bookingId, status: 'ACCEPTED' };
  },
);

exports.declineBooking = onCall(
  { region: 'asia-south1' },
  async (request) => {
    const uid = requireDriver(request);
    const bookingId = String(request.data?.bookingId || '').trim();
    if (!bookingId) {
      throw new HttpsError('invalid-argument', 'Booking ID is required.');
    }

    const bookingRef = db.collection('bookings').doc(bookingId);
    const snap = await bookingRef.get();
    if (!snap.exists) {
      throw new HttpsError('not-found', 'Booking not found.');
    }

    const data = snap.data() || {};
    const status = String(data.status || '').toUpperCase();
    const assignedPartner = String(data.partnerId || '');

    if (!['REQUESTED', 'SEARCHING'].includes(status)) {
      throw new HttpsError('failed-precondition', 'This booking is no longer available.');
    }

    if (assignedPartner && assignedPartner !== uid) {
      throw new HttpsError('permission-denied', 'This booking is assigned to another partner.');
    }

    await bookingRef.set(
      {
        declinedBy: FieldValue.arrayUnion(uid),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return { ok: true, bookingId, status: 'DECLINED' };
  },
);

exports.transitionBooking = onCall(
  { region: 'asia-south1' },
  async (request) => {
    const uid = requireDriver(request);
    const bookingId = String(request.data?.bookingId || '').trim();
    const nextStatus = String(request.data?.status || '').trim().toUpperCase();

    if (!bookingId) {
      throw new HttpsError('invalid-argument', 'Booking ID is required.');
    }
    if (!['ARRIVING', 'ARRIVED', 'TRIP_STARTED', 'COMPLETED'].includes(nextStatus)) {
      throw new HttpsError('invalid-argument', 'Unsupported booking status transition.');
    }

    const bookingRef = db.collection('bookings').doc(bookingId);
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(bookingRef);
      if (!snap.exists) {
        throw new HttpsError('not-found', 'Booking not found.');
      }

      const data = snap.data() || {};
      const currentStatus = String(data.status || '').toUpperCase();
      const partnerId = String(data.partnerId || '');
      if (partnerId !== uid) {
        throw new HttpsError('permission-denied', 'This booking is not assigned to you.');
      }

      const allowed = {
        ACCEPTED: 'ARRIVING',
        ARRIVING: 'ARRIVED',
        ARRIVED: 'TRIP_STARTED',
        TRIP_STARTED: 'COMPLETED',
      };
      if (allowed[currentStatus] !== nextStatus) {
        throw new HttpsError('failed-precondition', `Invalid transition from ${currentStatus} to ${nextStatus}.`);
      }

      const update = {
        status: nextStatus,
        updatedAt: FieldValue.serverTimestamp(),
      };

      if (nextStatus === 'ARRIVING') update.arrivingAt = FieldValue.serverTimestamp();
      if (nextStatus === 'ARRIVED') update.arrivedAt = FieldValue.serverTimestamp();

      if (nextStatus === 'TRIP_STARTED') {
        const required = ['preTripFrontUrl', 'preTripBackUrl', 'preTripRightUrl', 'preTripLeftUrl', 'driverSelfieUrl'];
        if (required.some((field) => typeof request.data?.[field] !== 'string' || !request.data[field].trim())) {
          throw new HttpsError('invalid-argument', 'All pre-trip inspection photos are required.');
        }
        for (const field of required) update[field] = request.data[field].trim();
        update.startedAt = FieldValue.serverTimestamp();
      }

      if (nextStatus === 'COMPLETED') {
        const required = ['postTripFrontUrl', 'postTripBackUrl', 'postTripRightUrl', 'postTripLeftUrl'];
        if (required.some((field) => typeof request.data?.[field] !== 'string' || !request.data[field].trim())) {
          throw new HttpsError('invalid-argument', 'All post-trip inspection photos are required.');
        }
        for (const field of required) update[field] = request.data[field].trim();
        update.completedAt = FieldValue.serverTimestamp();
      }

      tx.set(bookingRef, update, { merge: true });
    });

    return { ok: true, bookingId, status: nextStatus };
  },
);

exports.onBookingWritten = onDocumentWritten(
  { document: 'bookings/{bookingId}', region: 'asia-south1' },
  async (event) => {
    const before = event.data?.before?.data() || null;
    const after = event.data?.after?.data();
    if (!after) return;

    const bookingId = event.params.bookingId;
    const partnerId = String(after.partnerId || '').trim();
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
        createdAt: FieldValue.serverTimestamp(),
      });
    }

    if (afterStatus === 'COMPLETED' && beforeStatus !== 'COMPLETED') {
      const fare = Math.max(0, Number(after.fare || 0));
      const share = Math.min(100, Math.max(0, Number(after.partnerSharePercent ?? 85)));
      const earnings = Math.max(0, Math.round((fare * share) / 100));

      await db.collection('partners').doc(partnerId).collection('earnings').doc(bookingId).set(
        {
          bookingId,
          fare,
          partnerSharePercent: share,
          earnings,
          completedAt: after.completedAt || FieldValue.serverTimestamp(),
          createdAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      await db.collection('notifications').add({
        userId: partnerId,
        type: 'earning',
        title: 'Trip completed',
        message: `₹${earnings} has been added to your earnings ledger.`,
        bookingId,
        read: false,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
  },
);

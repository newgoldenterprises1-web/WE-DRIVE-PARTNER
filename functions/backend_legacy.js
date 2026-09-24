const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { getApps, initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { sendPushToUser } = require('./notifications_backend');

if (!getApps().length) initializeApp();

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

function isApprovedDriverProfile(data = {}) {
  return (
    data.driverApproved === true ||
    data.onboardingStatus === 'APPROVED' ||
    data.verificationStatus === 'VERIFIED' ||
    data.verificationStatus === 'APPROVED'
  );
}

function requireApprovedDriver(data) {
  if (!isApprovedDriverProfile(data)) {
    throw new HttpsError('failed-precondition', 'Partner account is pending approval.');
  }
}

function distanceKm(lat1, lng1, lat2, lng2) {
  const toRad = (value) => (value * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) *
      Math.cos(toRad(lat2)) *
      Math.sin(dLng / 2) ** 2;
  return 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

async function dispatchBookingOffers(bookingId, bookingData) {
  const pickupLat = Number(bookingData.pickupLatitude);
  const pickupLng = Number(bookingData.pickupLongitude);
  const declinedBy = Array.isArray(bookingData.declinedBy) ? bookingData.declinedBy : [];
  const preferences = bookingData.requestPreferences || {};
  const preferredId = String(preferences.preferredChauffeurId || '').trim();

  const partnerSnap = await db.collection('partners')
    .where('online', '==', true)
    .limit(100)
    .get();

  const ranked = [];

  for (const doc of partnerSnap.docs) {
    const partner = doc.data() || {};
    const uid = doc.id;

    if (declinedBy.includes(uid) || !isApprovedDriverProfile(partner)) continue;

    const partnerLat = Number(partner.latitude);
    const partnerLng = Number(partner.longitude);
    let distance = null;

    if (
      Number.isFinite(pickupLat) &&
      Number.isFinite(pickupLng) &&
      Number.isFinite(partnerLat) &&
      Number.isFinite(partnerLng)
    ) {
      distance = distanceKm(pickupLat, pickupLng, partnerLat, partnerLng);
    }

    const rating = Math.max(0, Math.min(5, Number(partner.rating || 5)));
    const punctuality = Math.max(0, Math.min(100, Number(partner.punctualityScore ?? 95)));
    const experience = Math.max(
      0,
      Number(partner.experienceYears ?? partner.experience ?? 0),
    );

    let score = rating * 15;
    score += Math.min(15, punctuality / 7);
    score += Math.min(15, experience * 2);
    score += distance == null ? 5 : Math.max(0, 35 - distance * 4);
    if (preferredId === uid) score += 30;

    ranked.push({
      uid,
      name: partner.name || partner.fullName || 'WE DRIVE Chauffeur',
      rating,
      experience,
      punctuality,
      distance,
      score: Math.round(score),
    });
  }

  ranked.sort((a, b) => b.score - a.score);
  const selected = ranked.slice(0, 5);

  if (!selected.length) {
    await db.collection('bookings').doc(bookingId).set(
      {
        matchStatus: 'WAITING',
        candidatePartnerIds: [],
        matchCandidates: [],
        lastMatchAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return [];
  }

  const candidateIds = selected.map((candidate) => candidate.uid);

  await db.collection('bookings').doc(bookingId).set(
    {
      status: 'SEARCHING',
      bookingStatus: 'SEARCHING',
      matchStatus: 'SEARCHING',
      candidatePartnerIds: candidateIds,
      matchCandidates: selected.map((candidate) => ({
        partnerId: candidate.uid,
        name: candidate.name,
        rating: candidate.rating,
        experience: candidate.experience,
        punctuality: candidate.punctuality,
        distanceKm: candidate.distance,
        score: candidate.score,
      })),
      lastMatchAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  await Promise.all(selected.map(async (candidate) => {
    const message = 'New chauffeur request near ' +
      String(bookingData.pickupLocation || 'pickup') +
      '. Review and accept it in your WE DRIVE Partner app.';

    await db.collection('notifications').add({
      userId: candidate.uid,
      type: 'booking_request',
      title: 'New chauffeur request',
      message,
      bookingId,
      read: false,
      createdAt: FieldValue.serverTimestamp(),
    });

    await sendPushToUser(candidate.uid, {
      title: 'New chauffeur request',
      body: message,
      role: 'driver',
      data: {
        type: 'booking_request',
        bookingId,
        pickupLocation: bookingData.pickupLocation || '',
      },
    });
  }));

  return candidateIds;
}

exports.ensureDriverAccount = onCall(
  { region: 'asia-south1', enforceAppCheck: true },
  async (request) => {
    const uid = requireAuth(request);
    const user = await auth.getUser(uid);
    const requestedName = String(request.data?.name || '').trim();
    const phone = user.phoneNumber || normalizeIndianPhone(request.data?.phoneNumber);

    const partnerRef = db.collection('partners').doc(uid);
    const partnerSnap = await partnerRef.get();
    const existing = partnerSnap.data() || {};
    const existingClaims = user.customClaims || {};

    const alreadyApprovedDriver =
      existingClaims.role === 'driver' ||
      existing.role === 'driver' ||
      existing.driverApproved === true ||
      existing.onboardingStatus === 'APPROVED';

    if (!alreadyApprovedDriver) {
      throw new HttpsError('permission-denied', 'Partner account is pending WE DRIVE approval.');
    }

    const name = requestedName || user.displayName || existing.name || 'WE DRIVE Partner';

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
      onboardingStatus: existing.onboardingStatus || 'APPROVED',
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
  { region: 'asia-south1', enforceAppCheck: true },
  async (request) => {
    const uid = requireDriver(request);
    const online = Boolean(request.data?.online);
    const ref = db.collection('partners').doc(uid);
    const snap = await ref.get();
    if (!snap.exists) {
      throw new HttpsError('failed-precondition', 'Partner account is not initialized.');
    }

    const existing = snap.data() || {};
    if (online) {
      requireApprovedDriver(existing);
    }

    const update = {
      role: 'driver',
      online,
      lastSeenAt: FieldValue.serverTimestamp(),
    };

    if (online) {
      update.onlineSince = FieldValue.serverTimestamp();
    } else if (existing.onlineSince?.toDate) {
      const seconds = Math.max(0, Math.floor((Date.now() - existing.onlineSince.toDate().getTime()) / 1000));
      update.totalOnlineSeconds = Number(existing.totalOnlineSeconds || 0) + seconds;
      update.onlineSince = null;
    }

    await ref.set(update, { merge: true });

    if (online) {
      const openBookings = await db.collection('bookings')
        .where('status', 'in', ['REQUESTED', 'SEARCHING'])
        .limit(50)
        .get();

      await Promise.all(
        openBookings.docs
          .filter((doc) => !doc.data()?.partnerId)
          .map((doc) => dispatchBookingOffers(doc.id, doc.data() || {})),
      );
    }

    return { ok: true, online };
  },
);

exports.updateDriverLocation = onCall(
  { region: 'asia-south1', enforceAppCheck: true },
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

    const partnerData = partnerSnap.data() || {};
    requireApprovedDriver(partnerData);

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

    const activeBookings = await db.collection('bookings')
      .where('partnerId', '==', uid)
      .where('status', 'in', ['ACCEPTED', 'ARRIVING', 'ARRIVED', 'TRIP_STARTED'])
      .limit(20)
      .get();

    const batch = db.batch();
    activeBookings.docs.forEach((bookingDoc) => {
      batch.set(bookingDoc.ref, {
        chauffeurLatitude: latitude,
        chauffeurLongitude: longitude,
        chauffeurLocationAccuracy: Math.max(0, Number(request.data?.accuracy || 0)),
        chauffeurHeading: Number(request.data?.heading || 0),
        chauffeurSpeed: Math.max(0, Number(request.data?.speed || 0)),
        chauffeurLocationUpdatedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    });

    if (!activeBookings.empty) {
      await batch.commit();
    }

    return { ok: true };
  },
);

exports.acceptBooking = onCall(
  { region: 'asia-south1', enforceAppCheck: true },
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
    requireApprovedDriver(partnerSnap.data() || {});

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

      const candidatePartnerIds = Array.isArray(data.candidatePartnerIds)
          ? data.candidatePartnerIds
          : [];
      if (candidatePartnerIds.length && !candidatePartnerIds.includes(uid)) {
        throw new HttpsError(
          'permission-denied',
          'This booking is currently being offered to another matched chauffeur.',
        );
      }

      tx.set(bookingRef, {
        status: 'ACCEPTED',
        bookingStatus: 'ACCEPTED',
        partnerId: uid,
        acceptedAt: FieldValue.serverTimestamp(),
        matchStatus: 'MATCHED',
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    });

    return { ok: true, bookingId, status: 'ACCEPTED' };
  },
);

exports.declineBooking = onCall(
  { region: 'asia-south1', enforceAppCheck: true },
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
  { region: 'asia-south1', enforceAppCheck: true },
  async (request) => {
    const uid = requireDriver(request);
    const bookingId = String(request.data?.bookingId || '').trim();
    const nextStatus = String(request.data?.status || '').trim().toUpperCase();
    const providedOtp = String(request.data?.otp || request.data?.startOtp || '').trim();

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

        const expectedOtp = String(data.otp || data.startOtp || '').trim();
        if (!expectedOtp) {
          throw new HttpsError('failed-precondition', 'Trip start OTP is not available for this booking.');
        }
        if (providedOtp !== expectedOtp) {
          throw new HttpsError('permission-denied', 'Invalid trip start OTP.');
        }

        for (const field of required) update[field] = request.data[field].trim();
        update.startedAt = FieldValue.serverTimestamp();
        update.otpVerifiedAt = FieldValue.serverTimestamp();
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
    const beforeStatus = String(before?.status || '').toUpperCase();
    const afterStatus = String(after.status || '').toUpperCase();
    const partnerId = String(after.partnerId || '').trim();

    if (
      !partnerId &&
      ['REQUESTED', 'SEARCHING'].includes(afterStatus) &&
      String(after.matchStatus || '').toUpperCase() !== 'NO_DRIVER'
    ) {
      const beforeDeclined = Array.isArray(before?.declinedBy) ? before.declinedBy : [];
      const afterDeclined = Array.isArray(after.declinedBy) ? after.declinedBy : [];
      const hasCandidates = Array.isArray(after.candidatePartnerIds) &&
        after.candidatePartnerIds.length > 0;
      const newBooking = !before;
      const declinedChanged = afterDeclined.length !== beforeDeclined.length;
      const needsInitialDispatch =
        newBooking ||
        declinedChanged ||
        (!hasCandidates && String(after.matchStatus || '').toUpperCase() === 'WAITING') ||
        (afterStatus === 'REQUESTED' && beforeStatus !== 'SEARCHING');

      if (needsInitialDispatch) {
        await dispatchBookingOffers(bookingId, after);
      }
    }

    if (afterStatus === 'ACCEPTED' && beforeStatus !== 'ACCEPTED' && partnerId) {
      await db.collection('notifications').add({
        userId: partnerId,
        type: 'booking',
        title: 'Booking accepted',
        message: 'Booking ' + bookingId + ' has been assigned to you.',
        bookingId,
        read: false,
        createdAt: FieldValue.serverTimestamp(),
      });

      await sendPushToUser(partnerId, {
        title: 'Booking accepted',
        body: 'Booking ' + bookingId + ' has been assigned to you.',
        role: 'driver',
        data: {
          type: 'booking_accepted',
          bookingId,
        },
      });

      const customerId = String(after.customerId || '').trim();
      if (customerId) {
        await db.collection('notifications').add({
          userId: customerId,
          type: 'booking',
          title: 'Chauffeur matched',
          message: (after.driverName || 'Your chauffeur') + ' has accepted your WE DRIVE booking.',
          bookingId,
          read: false,
          createdAt: FieldValue.serverTimestamp(),
        });

        await sendPushToUser(customerId, {
          title: 'Chauffeur matched',
          body: (after.driverName || 'Your chauffeur') + ' has accepted your WE DRIVE booking.',
          role: 'customer',
          data: {
            type: 'chauffeur_matched',
            bookingId,
          },
        });
      }
    }

    if (afterStatus === 'COMPLETED' && beforeStatus !== 'COMPLETED' && partnerId) {
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
        message: '₹' + earnings + ' has been added to your earnings ledger.',
        bookingId,
        read: false,
        createdAt: FieldValue.serverTimestamp(),
      });

      await sendPushToUser(partnerId, {
        title: 'Trip completed',
        body: '₹' + earnings + ' has been added to your earnings ledger.',
        role: 'driver',
        data: {
          type: 'trip_completed',
          bookingId,
        },
      });

      const customerId = String(after.customerId || '').trim();
      if (customerId) {
        await sendPushToUser(customerId, {
          title: 'Trip completed',
          body: 'Your WE DRIVE trip is complete. Your receipt is ready in the app.',
          role: 'customer',
          data: {
            type: 'trip_completed',
            bookingId,
          },
        });
      }
    }
  },
);

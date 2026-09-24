const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { getApps, initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

if (!getApps().length) initializeApp();

const auth = getAuth();
const db = getFirestore();
const messaging = getMessaging();

function requireAuth(request) {
  if (!request.auth?.uid) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }
  return request.auth.uid;
}

function asString(value, fallback = '') {
  const text = String(value ?? fallback).trim();
  return text;
}

async function sendToUserToken(userId, collectionName, payload) {
  const snap = await db.collection(collectionName).doc(userId).get();
  const token = asString(snap.data()?.fcmToken);
  if (!token) return false;

  try {
    await messaging.send({
      token,
      notification: {
        title: payload.title,
        body: payload.body,
      },
      data: Object.fromEntries(
        Object.entries(payload.data || {}).map(([key, value]) => [key, asString(value)]),
      ),
      android: {
        priority: 'high',
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
          },
        },
      },
    });
    return true;
  } catch (error) {
    console.error('FCM send failed:', error);
    return false;
  }
}

exports.registerFcmToken = onCall({ region: 'asia-south1', enforceAppCheck: true }, async (request) => {
  const uid = requireAuth(request);
  const token = asString(request.data?.token);
  if (!token) {
    throw new HttpsError('invalid-argument', 'FCM token is required.');
  }

  const role = String(request.auth?.token?.role || '').toLowerCase();
  const collection = role === 'driver' ? 'partners' : 'users';

  await db.collection(collection).doc(uid).set({
    fcmToken: token,
    fcmTokenUpdatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });

  if (role === 'driver') {
    await db.collection('profiles').doc(uid).set({
      fcmToken: token,
      fcmTokenUpdatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  }

  return { ok: true };
});

exports.onBookingNotificationFanout = onDocumentWritten(
  { document: 'bookings/{bookingId}', region: 'asia-south1' },
  async (event) => {
    const before = event.data?.before?.data() || null;
    const after = event.data?.after?.data();
    if (!after) return;

    const bookingId = event.params.bookingId;
    const status = String(after.status || after.bookingStatus || '').toUpperCase();
    const beforeStatus = String(before?.status || before?.bookingStatus || '').toUpperCase();
    const customerId = asString(after.customerId);
    const serviceType = asString(after.serviceType, 'WE DRIVE Ride');

    if (!before && ['REQUESTED', 'SEARCHING'].includes(status)) {
      await messaging.send({
        topic: 'ride_requests',
        notification: {
          title: 'New ride request',
          body: `${serviceType} is waiting for a chauffeur.`,
        },
        data: {
          bookingId,
          status,
          serviceType,
          pickupLocation: asString(after.pickupLocation),
          dropLocation: asString(after.dropLocation),
        },
        android: { priority: 'high' },
      }).catch((error) => console.error('Ride-request topic send failed:', error));
    }

    if (customerId && status === 'ACCEPTED' && beforeStatus !== 'ACCEPTED') {
      await sendToUserToken(customerId, 'users', {
        title: 'Chauffeur assigned',
        body: `${asString(after.driverName, 'Your chauffeur')} is on the way.`,
        data: { bookingId, status, driverName: after.driverName || '', driverPhone: after.driverPhone || '' },
      });
    }

    if (customerId && status === 'TRIP_STARTED' && beforeStatus !== 'TRIP_STARTED') {
      await sendToUserToken(customerId, 'users', {
        title: 'Trip started',
        body: 'Your WE DRIVE trip is now live.',
        data: { bookingId, status },
      });
    }

    if (customerId && status === 'COMPLETED' && beforeStatus !== 'COMPLETED') {
      await sendToUserToken(customerId, 'users', {
        title: 'Trip completed',
        body: 'Your trip is complete. Receipt is ready.',
        data: { bookingId, status },
      });
    }
  },
);

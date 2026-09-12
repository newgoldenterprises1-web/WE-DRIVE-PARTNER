const { onSchedule } = require('firebase-functions/v2/scheduler');
const { logger } = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

const db = admin.firestore();
const { createPaymentOrder, verifyPayment } = require('./payment');
const { registerFcmToken } = require('./fcm');
const {
  notifyPartnerOnBookingCreate,
  notifyPartnerOnBookingUpdate,
} = require('./notifications');

const PENDING_STATUSES = new Set(['REQUESTED', 'SEARCHING']);
const STALE_AFTER_MS = 15 * 60 * 1000;
const BATCH_LIMIT = 500;

function toDate(value) {
  if (!value) return null;
  if (value instanceof admin.firestore.Timestamp) return value.toDate();
  if (value instanceof Date) return value;
  if (typeof value.toDate === 'function') return value.toDate();
  return null;
}

function isUnassigned(data) {
  const partnerId = (data.partnerId || '').toString().trim();
  return partnerId.length === 0;
}

function isStale(data, nowMs) {
  const createdAt = toDate(data.createdAt);
  if (!createdAt) return false;
  return nowMs - createdAt.getTime() >= STALE_AFTER_MS;
}

exports.createPaymentOrder = createPaymentOrder;
exports.verifyPayment = verifyPayment;
exports.registerFcmToken = registerFcmToken;
exports.notifyPartnerOnBookingCreate = notifyPartnerOnBookingCreate;
exports.notifyPartnerOnBookingUpdate = notifyPartnerOnBookingUpdate;

exports.expireStaleBookings = onSchedule(
  {
    schedule: 'every 5 minutes',
    timeZone: 'Asia/Kolkata',
    region: 'asia-south1',
    memory: '256MiB',
    timeoutSeconds: 60,
    maxInstances: 1,
  },
  async () => {
    const nowMs = Date.now();
    const cutoff = admin.firestore.Timestamp.fromMillis(nowMs - STALE_AFTER_MS);

    const snapshot = await db
      .collection('bookings')
      .where('status', 'in', Array.from(PENDING_STATUSES))
      .where('createdAt', '<=', cutoff)
      .limit(BATCH_LIMIT)
      .get();

    if (snapshot.empty) {
      logger.info('No stale bookings found.');
      return;
    }

    const batch = db.batch();
    let expiredCount = 0;

    for (const doc of snapshot.docs) {
      const data = doc.data();
      const status = (data.status || '').toString().toUpperCase();

      if (!PENDING_STATUSES.has(status) || !isUnassigned(data) || !isStale(data, nowMs)) {
        continue;
      }

      batch.update(doc.ref, {
        status: 'CANCELLED',
        cancelledBy: 'SYSTEM_TIMEOUT',
        cancellationReason: 'REQUEST_EXPIRED',
        cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
        timeoutAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      expiredCount += 1;
    }

    if (expiredCount === 0) {
      logger.info('No eligible stale unassigned bookings found.');
      return;
    }

    await batch.commit();
    logger.info(`Expired ${expiredCount} stale unassigned booking(s).`);
  },
);

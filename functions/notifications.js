const { onDocumentCreated, onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { logger } = require('firebase-functions');
const admin = require('firebase-admin');

const db = admin.firestore();
const PENDING_STATUSES = new Set(['REQUESTED', 'SEARCHING']);
const NOTIFIABLE_STATUSES = new Set(['ACCEPTED', 'ARRIVING', 'ARRIVED', 'TRIP_STARTED', 'COMPLETED', 'CANCELLED']);
const PRESENCE_FRESH_MS = 5 * 60 * 1000;
const BATCH_LIMIT = 500;

function toDate(value) {
  if (!value) return null;
  if (value instanceof admin.firestore.Timestamp) return value.toDate();
  if (value instanceof Date) return value;
  if (typeof value.toDate === 'function') return value.toDate();
  return null;
}

function isFreshlyOnline(data, nowMs) {
  if (data.accountStatus !== 'ACTIVE' || data.isOnline !== true) return false;
  const lastSeen = toDate(data.lastSeenAt);
  return !lastSeen || nowMs - lastSeen.getTime() <= PRESENCE_FRESH_MS;
}

async function sendPush(recipients, title, body, data) {
  const unique = new Map();
  for (const recipient of recipients) {
    const token = (recipient.token || '').toString().trim();
    const partnerId = (recipient.partnerId || '').toString().trim();
    if (token && partnerId) unique.set(token, partnerId);
  }
  const entries = Array.from(unique.entries());
  if (entries.length === 0) return;

  for (let start = 0; start < entries.length; start += BATCH_LIMIT) {
    const chunk = entries.slice(start, start + BATCH_LIMIT);
    const result = await admin.messaging().sendEachForMulticast({
      tokens: chunk.map(([token]) => token),
      notification: { title, body },
      data: {
        type: String(data.type || ''),
        bookingId: String(data.bookingId || ''),
        status: String(data.status || ''),
      },
      android: { priority: 'high' },
      apns: { payload: { aps: { sound: 'default' } } },
    });

    const invalidPartnerIds = [];
    result.responses.forEach((response, index) => {
      const code = response.error?.code || '';
      if (!response.success && (code.includes('registration-token-not-registered') || code.includes('invalid-registration-token'))) {
        invalidPartnerIds.push(chunk[index][1]);
      }
    });

    await Promise.all(invalidPartnerIds.map((partnerId) =>
      db.collection('partners').doc(partnerId).set({
        fcmToken: admin.firestore.FieldValue.delete(),
        fcmTokenUpdatedAt: admin.firestore.FieldValue.delete(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true }),
    ));

    logger.info('Partner push notification result', {
      type: data.type,
      bookingId: data.bookingId,
      success: result.successCount,
      failure: result.failureCount,
    });
  }
}

async function notifyEligiblePartners(bookingId, booking) {
  const status = (booking.status || '').toString().toUpperCase();
  if (!PENDING_STATUSES.has(status)) return;
  if ((booking.partnerId || '').toString().trim()) return;

  const snapshot = await db.collection('partners').where('isOnline', '==', true).limit(BATCH_LIMIT).get();
  if (snapshot.empty) return;

  const nowMs = Date.now();
  const premiumBooking = booking.isPremiumBooking === true;
  const recipients = [];

  for (const doc of snapshot.docs) {
    const partner = doc.data();
    if (!isFreshlyOnline(partner, nowMs)) continue;
    if (premiumBooking && partner.isPremium !== true) continue;
    const token = (partner.fcmToken || '').toString().trim();
    if (token) recipients.push({ partnerId: doc.id, token });
  }

  const pickup = (booking.pickup || booking.pickupAddress || 'Pickup location').toString().trim();
  const time = (booking.time || '').toString().trim();
  await sendPush(
    recipients,
    premiumBooking ? 'Premium Ride Request' : 'New Ride Request',
    `New ride request${time ? ` at ${time}` : ''} · ${pickup}`.slice(0, 180),
    { type: 'BOOKING_REQUEST', bookingId, status },
  );
}

async function notifyAssignedPartner(bookingId, before, after) {
  const partnerId = (after.partnerId || '').toString().trim();
  const status = (after.status || '').toString().toUpperCase();
  const previousStatus = (before.status || '').toString().toUpperCase();
  const previousPartnerId = (before.partnerId || '').toString().trim();
  if (!partnerId || !NOTIFIABLE_STATUSES.has(status)) return;
  if (partnerId === previousPartnerId && status === previousStatus) return;

  const snapshot = await db.collection('partners').doc(partnerId).get();
  const partner = snapshot.exists ? snapshot.data() || {} : {};
  const token = (partner.fcmToken || '').toString().trim();
  if (!token) return;

  const messages = {
    ACCEPTED: ['Ride accepted', 'The booking has been assigned to you.'],
    ARRIVING: ['Driver arriving', 'Navigate to the pickup location.'],
    ARRIVED: ['At pickup', 'You have arrived. Complete the pre-trip checks.'],
    TRIP_STARTED: ['Trip started', 'The passenger trip is now active.'],
    COMPLETED: ['Trip completed', 'Trip completed successfully.'],
    CANCELLED: ['Booking cancelled', 'This booking is no longer active.'],
  };
  const [title, body] = messages[status] || ['WE DRIVE update', 'Your booking status has changed.'];

  await sendPush(
    [{ partnerId, token }],
    title,
    body,
    { type: 'BOOKING_STATUS', bookingId, status },
  );
}

exports.notifyPartnerOnBookingCreate = onDocumentCreated(
  { document: 'bookings/{bookingId}', region: 'asia-south1', memory: '256MiB', timeoutSeconds: 60 },
  async (event) => {
    const booking = event.data?.data();
    if (booking) await notifyEligiblePartners(event.params.bookingId, booking);
  },
);

exports.notifyPartnerOnBookingUpdate = onDocumentUpdated(
  { document: 'bookings/{bookingId}', region: 'asia-south1', memory: '256MiB', timeoutSeconds: 60 },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (before && after) await notifyAssignedPartner(event.params.bookingId, before, after);
  },
);

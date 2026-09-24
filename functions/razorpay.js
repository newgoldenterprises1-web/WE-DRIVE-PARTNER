const crypto = require('crypto');
const { onCall, onRequest, HttpsError } = require('firebase-functions/v2/https');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');
const { notifyAvailableDrivers } = require('./notification_service');

const db = getFirestore();
const auth = getAuth();

function requireAuth(request) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Authentication is required.');
  return uid;
}

function requireCustomer(request) {
  const uid = requireAuth(request);
  if (request.auth?.token?.role !== 'customer') {
    throw new HttpsError('permission-denied', 'Customer access is required.');
  }
  return uid;
}

function getRazorpayKeys() {
  const keyId = String(process.env.RAZORPAY_KEY_ID || '').trim();
  const keySecret = String(process.env.RAZORPAY_KEY_SECRET || '').trim();
  if (!keyId || !keySecret) {
    throw new HttpsError('failed-precondition', 'Razorpay server keys are not configured.');
  }
  return { keyId, keySecret };
}

async function razorpayRequest(path, { method = 'GET', body } = {}) {
  const { keyId, keySecret } = getRazorpayKeys();
  const authHeader = Buffer.from(keyId + ':' + keySecret).toString('base64');
  const response = await fetch('https://api.razorpay.com/v1' + path, {
    method,
    headers: {
      Authorization: 'Basic ' + authHeader,
      'Content-Type': 'application/json',
    },
    body: body == null ? undefined : JSON.stringify(body),
  });

  const raw = await response.text();
  let data = {};
  try {
    data = raw ? JSON.parse(raw) : {};
  } catch (_) {
    data = { raw };
  }

  if (!response.ok) {
    throw new HttpsError(
      'failed-precondition',
      data?.error?.description || data?.message || 'Razorpay request failed.',
    );
  }
  return data;
}

function verifySignature(keySecret, orderId, paymentId, signature) {
  const expected = crypto
    .createHmac('sha256', keySecret)
    .update(orderId + '|' + paymentId)
    .digest('hex');

  const a = Buffer.from(expected);
  const b = Buffer.from(String(signature || ''));
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

async function finalizeCustomerPayment({ uid, bookingId, orderId, paymentId, signature }) {
  const ref = db.collection('bookings').doc(bookingId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError('not-found', 'Booking not found.');

  const booking = snap.data() || {};
  if (String(booking.customerId || '') !== uid) {
    throw new HttpsError('permission-denied', 'This booking does not belong to you.');
  }
  if (String(booking.paymentOrderId || '') !== orderId) {
    throw new HttpsError('failed-precondition', 'Payment order does not match the booking.');
  }

  const { keySecret } = getRazorpayKeys();
  if (!verifySignature(keySecret, orderId, paymentId, signature)) {
    throw new HttpsError('permission-denied', 'Razorpay payment signature verification failed.');
  }

  const payment = await razorpayRequest('/payments/' + encodeURIComponent(paymentId));
  if (String(payment.order_id || '') !== orderId) {
    throw new HttpsError('failed-precondition', 'Razorpay payment belongs to a different order.');
  }
  if (!['captured', 'authorized'].includes(String(payment.status || '').toLowerCase())) {
    throw new HttpsError('failed-precondition', 'Razorpay payment is not captured.');
  }

  await ref.set({
    paymentMethod: String(booking.paymentMethod || 'UPI'),
    paymentStatus: 'paid',
    razorpayOrderId: orderId,
    razorpayPaymentId: paymentId,
    razorpaySignature: signature,
    paymentVerifiedAt: FieldValue.serverTimestamp(),
    status: 'REQUESTED',
    bookingStatus: 'REQUESTED',
    matchStatus: 'WAITING',
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });

  await notifyAvailableDrivers({
    bookingId,
    title: 'New chauffeur booking',
    message: 'A customer booking is available. Open WE DRIVE Partner to respond.',
  });

  return { ok: true, bookingId, paymentId, status: 'REQUESTED' };
}

exports.createRazorpayOrder = onCall(
  { region: 'asia-south1', enforceAppCheck: true },
  async (request) => {
    const uid = requireCustomer(request);
    const bookingId = String(request.data?.bookingId || '').trim();
    if (!bookingId) throw new HttpsError('invalid-argument', 'Booking ID is required.');

    const ref = db.collection('bookings').doc(bookingId);
    const snap = await ref.get();
    if (!snap.exists) throw new HttpsError('not-found', 'Booking not found.');

    const booking = snap.data() || {};
    if (String(booking.customerId || '') !== uid) {
      throw new HttpsError('permission-denied', 'This booking does not belong to you.');
    }
    if (String(booking.status || '').toUpperCase() !== 'PAYMENT_PENDING') {
      throw new HttpsError('failed-precondition', 'This booking is not awaiting payment.');
    }

    const amount = Math.round(Number(booking.fare || 0) * 100);
    if (!Number.isFinite(amount) || amount <= 0) {
      throw new HttpsError('invalid-argument', 'Invalid booking amount.');
    }

    const { keyId } = getRazorpayKeys();
    const order = await razorpayRequest('/orders', {
      method: 'POST',
      body: {
        amount,
        currency: 'INR',
        receipt: 'WD-' + bookingId,
        notes: {
          bookingId,
          customerId: uid,
          serviceType: booking.serviceType || 'Chauffeur Service',
        },
      },
    });

    await ref.set({
      paymentOrderId: order.id,
      razorpayOrderId: order.id,
      paymentGateway: 'razorpay',
      paymentStatus: 'pending',
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });

    return {
      ok: true,
      keyId,
      orderId: order.id,
      amount: order.amount,
      currency: order.currency,
      bookingId,
    };
  },
);

exports.verifyRazorpayPayment = onCall(
  { region: 'asia-south1', enforceAppCheck: true },
  async (request) => {
    const uid = requireCustomer(request);
    const bookingId = String(request.data?.bookingId || '').trim();
    const orderId = String(request.data?.orderId || '').trim();
    const paymentId = String(request.data?.paymentId || '').trim();
    const signature = String(request.data?.signature || '').trim();

    if (!bookingId || !orderId || !paymentId || !signature) {
      throw new HttpsError('invalid-argument', 'Complete Razorpay payment details are required.');
    }

    return finalizeCustomerPayment({ uid, bookingId, orderId, paymentId, signature });
  },
);

exports.createPartnerRegistrationOrder = onCall(
  { region: 'asia-south1', enforceAppCheck: true },
  async (request) => {
    const uid = requireAuth(request);
    const user = await auth.getUser(uid);
    const partnerRef = db.collection('partners').doc(uid);
    const snap = await partnerRef.get();
    const existing = snap.data() || {};

    if (existing.registrationFeePaid === true) {
      return { ok: true, alreadyPaid: true, status: 'UNDER_REVIEW' };
    }

    const { keyId } = getRazorpayKeys();
    const amount = 29900;
    const order = await razorpayRequest('/orders', {
      method: 'POST',
      body: {
        amount,
        currency: 'INR',
        receipt: 'WD-PARTNER-' + uid.slice(0, 16),
        notes: {
          uid,
          phoneNumber: user.phoneNumber || '',
          purpose: 'partner_registration',
        },
      },
    });

    await partnerRef.set({
      uid,
      role: existing.role || 'partner_candidate',
      name: existing.name || user.displayName || 'WE DRIVE Partner',
      phoneNumber: existing.phoneNumber || user.phoneNumber || null,
      registrationOrderId: order.id,
      registrationAmount: 299,
      registrationPaymentStatus: 'pending',
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });

    return { ok: true, keyId, orderId: order.id, amount: order.amount, currency: order.currency };
  },
);

exports.verifyPartnerRegistrationPayment = onCall(
  { region: 'asia-south1', enforceAppCheck: true },
  async (request) => {
    const uid = requireAuth(request);
    const orderId = String(request.data?.orderId || '').trim();
    const paymentId = String(request.data?.paymentId || '').trim();
    const signature = String(request.data?.signature || '').trim();
    if (!orderId || !paymentId || !signature) {
      throw new HttpsError('invalid-argument', 'Complete Razorpay payment details are required.');
    }

    const partnerRef = db.collection('partners').doc(uid);
    const snap = await partnerRef.get();
    const partner = snap.data() || {};
    if (String(partner.registrationOrderId || '') !== orderId) {
      throw new HttpsError('failed-precondition', 'Registration payment order does not match.');
    }

    const { keySecret } = getRazorpayKeys();
    if (!verifySignature(keySecret, orderId, paymentId, signature)) {
      throw new HttpsError('permission-denied', 'Razorpay signature verification failed.');
    }

    const payment = await razorpayRequest('/payments/' + encodeURIComponent(paymentId));
    if (String(payment.order_id || '') !== orderId || !['captured', 'authorized'].includes(String(payment.status || '').toLowerCase())) {
      throw new HttpsError('failed-precondition', 'Registration payment could not be verified.');
    }

    await partnerRef.set({
      registrationFeePaid: true,
      feePaidAt: FieldValue.serverTimestamp(),
      registrationPaymentStatus: 'paid',
      registrationPaymentId: paymentId,
      verificationStatus: 'UNDER_REVIEW',
      onboardingStatus: 'UNDER_REVIEW',
      online: false,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });

    return { ok: true, status: 'UNDER_REVIEW', paymentId };
  },
);

// Razorpay webhook: configure this URL in the Razorpay dashboard and set RAZORPAY_WEBHOOK_SECRET.
// Client verification remains the primary UX path; webhook provides server-side recovery.
exports.razorpayWebhook = onRequest(
  { region: 'asia-south1' },
  async (req, res) => {
    try {
      const secret = String(process.env.RAZORPAY_WEBHOOK_SECRET || '').trim();
      const signature = String(req.headers['x-razorpay-signature'] || '').trim();
      if (!secret || !signature) return res.status(400).send('Webhook secret/signature missing.');

      const rawBody = req.rawBody || Buffer.from(JSON.stringify(req.body || {}));
      const expected = crypto.createHmac('sha256', secret).update(rawBody).digest('hex');
      if (expected !== signature) return res.status(401).send('Invalid signature.');

      const event = String(req.body?.event || '');
      if (event === 'payment.captured' || event === 'order.paid') {
        const paymentEntity = req.body?.payload?.payment?.entity;
        const orderId = String(paymentEntity?.order_id || req.body?.payload?.order?.entity?.id || '');
        const paymentId = String(paymentEntity?.id || '');
        if (orderId && paymentId) {
          const lookup = await db.collection('bookings').where('razorpayOrderId', '==', orderId).limit(1).get();
          if (!lookup.empty) {
            const bookingDoc = lookup.docs[0];
            const booking = bookingDoc.data() || {};
            if (booking.status === 'PAYMENT_PENDING') {
              await finalizeCustomerPayment({
                uid: String(booking.customerId || ''),
                bookingId: bookingDoc.id,
                orderId,
                paymentId,
                signature,
              });
            }
          }
        }
      }

      return res.status(200).send('ok');
    } catch (error) {
      console.error('Razorpay webhook error', error);
      return res.status(500).send('Webhook processing failed.');
    }
  },
);

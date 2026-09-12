const crypto = require('crypto');
const { onRequest } = require('firebase-functions/v2/https');
const { logger } = require('firebase-functions');
const admin = require('firebase-admin');
const Razorpay = require('razorpay');

const db = admin.firestore();
const PLANS = Object.freeze({ ONBOARDING: 29900, PREMIUM: 69900 });

function cors(req, res) {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Headers', 'Authorization, Content-Type');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return true;
  }
  return false;
}

async function requireUser(req, res) {
  const header = (req.get('Authorization') || '').trim();
  if (!header.startsWith('Bearer ')) {
    res.status(401).json({ error: 'Authentication required.' });
    return null;
  }
  try {
    return await admin.auth().verifyIdToken(header.substring(7).trim());
  } catch (error) {
    logger.warn('Invalid Firebase ID token.', error);
    res.status(401).json({ error: 'Invalid authentication token.' });
    return null;
  }
}

function razorpayClient() {
  const keyId = (process.env.RAZORPAY_KEY_ID || '').trim();
  const keySecret = (process.env.RAZORPAY_KEY_SECRET || '').trim();
  if (!keyId || !keySecret) throw new Error('Razorpay server credentials are not configured.');
  return { keyId, keySecret, client: new Razorpay({ key_id: keyId, key_secret: keySecret }) };
}

exports.createPaymentOrder = onRequest({ region: 'asia-south1', timeoutSeconds: 30, maxInstances: 10 }, async (req, res) => {
  if (cors(req, res)) return;
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST required.' });
  const user = await requireUser(req, res);
  if (!user) return;

  const plan = (req.body?.plan || '').toString().trim().toUpperCase();
  const amount = PLANS[plan];
  if (!amount) return res.status(400).json({ error: 'Unsupported payment plan.' });

  try {
    const partnerRef = db.collection('partners').doc(user.uid);
    const partnerSnapshot = await partnerRef.get();
    if (!partnerSnapshot.exists) return res.status(403).json({ error: 'Partner profile not found.' });
    const partner = partnerSnapshot.data() || {};
    if (plan === 'PREMIUM' && partner.accountStatus !== 'ACTIVE') {
      return res.status(403).json({ error: 'Activate your partner account first.' });
    }
    if (plan === 'PREMIUM' && partner.isPremium === true) {
      return res.status(409).json({ error: 'Premium plan is already active.' });
    }

    const { keyId, client } = razorpayClient();
    const order = await client.orders.create({
      amount,
      currency: 'INR',
      receipt: `WD-${plan}-${user.uid.substring(0, 10)}-${Date.now()}`,
      notes: { uid: user.uid, plan },
    });

    await db.collection('paymentOrders').doc(order.id).set({
      orderId: order.id,
      partnerId: user.uid,
      plan,
      amount,
      currency: 'INR',
      status: 'CREATED',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return res.status(200).json({ keyId, orderId: order.id, amount, currency: 'INR' });
  } catch (error) {
    logger.error('Payment order creation failed.', error);
    return res.status(500).json({ error: 'Unable to create payment order.' });
  }
});

exports.verifyPayment = onRequest({ region: 'asia-south1', timeoutSeconds: 30, maxInstances: 10 }, async (req, res) => {
  if (cors(req, res)) return;
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST required.' });
  const user = await requireUser(req, res);
  if (!user) return;

  const body = req.body || {};
  const plan = (body.plan || '').toString().trim().toUpperCase();
  const orderId = (body.orderId || '').toString().trim();
  const paymentId = (body.paymentId || '').toString().trim();
  const signature = (body.signature || '').toString().trim();
  if (!PLANS[plan] || !orderId || !paymentId || !signature) {
    return res.status(400).json({ error: 'Incomplete payment verification data.' });
  }

  try {
    const orderRef = db.collection('paymentOrders').doc(orderId);
    const orderSnapshot = await orderRef.get();
    if (!orderSnapshot.exists) return res.status(404).json({ error: 'Payment order not found.' });
    const orderData = orderSnapshot.data() || {};
    if (orderData.partnerId !== user.uid || orderData.plan !== plan || orderData.amount !== PLANS[plan]) {
      return res.status(403).json({ error: 'Payment order does not belong to this account.' });
    }
    if (orderData.status === 'VERIFIED') return res.status(200).json({ ok: true, alreadyVerified: true });

    const { keySecret, client } = razorpayClient();
    const expected = crypto.createHmac('sha256', keySecret).update(`${orderId}|${paymentId}`).digest('hex');
    if (!crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(signature))) {
      return res.status(400).json({ error: 'Payment signature verification failed.' });
    }

    const payment = await client.payments.fetch(paymentId);
    if ((payment.order_id || '').toString() !== orderId || Number(payment.amount || 0) !== PLANS[plan] || (payment.currency || '').toString().toUpperCase() !== 'INR') {
      return res.status(400).json({ error: 'Payment details do not match the order.' });
    }
    const paymentStatus = (payment.status || '').toString().toLowerCase();
    if (!['captured', 'authorized'].includes(paymentStatus)) {
      return res.status(400).json({ error: 'Payment has not been successfully captured.' });
    }

    const partnerRef = db.collection('partners').doc(user.uid);
    const updates = { updatedAt: admin.firestore.FieldValue.serverTimestamp() };
    if (plan === 'ONBOARDING') {
      updates.accountStatus = 'ACTIVE';
      updates.onboardingFee = 299;
      updates.onboardingPaymentStatus = 'PAID';
      updates.onboardingPaidAt = admin.firestore.FieldValue.serverTimestamp();
      updates.isOnline = false;
    } else {
      updates.isPremium = true;
      updates.premiumPlan = 'PREMIUM_CHAUFFEUR';
      updates.premiumFee = 699;
      updates.premiumPaymentStatus = 'PAID';
      updates.premiumActivatedAt = admin.firestore.FieldValue.serverTimestamp();
    }

    const batch = db.batch();
    batch.update(partnerRef, updates);
    batch.update(orderRef, {
      status: 'VERIFIED',
      paymentId,
      paymentStatus,
      verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    batch.set(db.collection('paymentTransactions').doc(paymentId), {
      paymentId,
      orderId,
      partnerId: user.uid,
      plan,
      amount: PLANS[plan],
      currency: 'INR',
      status: paymentStatus,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    await batch.commit();

    return res.status(200).json({ ok: true });
  } catch (error) {
    logger.error('Payment verification failed.', error);
    return res.status(500).json({ error: 'Unable to verify payment.' });
  }
});

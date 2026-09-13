const express = require('express');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
const admin = require('firebase-admin');

const app = express();
app.disable('x-powered-by');
app.use(cors({ origin: true }));
app.use(express.json({ limit: '256kb' }));

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 30,
  standardHeaders: true,
  legacyHeaders: false,
});

function loadFirebaseCredentials() {
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (!raw) throw new Error('FIREBASE_SERVICE_ACCOUNT_JSON is not configured.');
  return admin.credential.cert(JSON.parse(raw));
}

if (!admin.apps.length) admin.initializeApp({ credential: loadFirebaseCredentials() });
const db = admin.firestore();

function normalizePhone(phoneNumber) {
  const digits = String(phoneNumber || '').replace(/\D/g, '');
  const local = digits.replace(/^91/, '');
  if (!/^[6-9]\d{9}$/.test(local)) {
    const error = new Error('Use a valid Indian mobile number.');
    error.status = 400;
    throw error;
  }
  return `+91${local}`;
}

async function verifyMsg91AccessToken(accessToken) {
  if (!accessToken || typeof accessToken !== 'string') {
    const error = new Error('MSG91 verification token is missing.');
    error.status = 401;
    throw error;
  }
  const authkey = process.env.MSG91_AUTHKEY;
  if (!authkey) throw new Error('MSG91_AUTHKEY is not configured on the backend.');

  const response = await fetch('https://control.msg91.com/api/v5/widget/verifyAccessToken', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ authkey, 'access-token': accessToken }),
  });
  const body = await response.json().catch(() => ({}));
  const statusText = String(body?.type || body?.status || '').toLowerCase();
  if (!response.ok || (statusText && !['success', 'ok'].includes(statusText))) {
    const error = new Error('MSG91 OTP verification could not be completed.');
    error.status = 401;
    throw error;
  }
  return body;
}

async function createFirebaseSession({ accessToken, phoneNumber, role }) {
  const phone = normalizePhone(phoneNumber);
  await verifyMsg91AccessToken(accessToken);
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

async function requireDriver(req) {
  const header = String(req.headers.authorization || '');
  if (!header.startsWith('Bearer ')) {
    const error = new Error('Firebase authentication is required.');
    error.status = 401;
    throw error;
  }
  const token = await admin.auth().verifyIdToken(header.slice(7));
  if (token.role !== 'driver') {
    const error = new Error('Driver access is required.');
    error.status = 403;
    throw error;
  }
  return token.uid;
}

app.get('/health', (_req, res) => res.json({ ok: true, service: 'we-drive-backend' }));

app.post('/api/auth/driver/msg91', authLimiter, async (req, res, next) => {
  try {
    res.json(await createFirebaseSession({ accessToken: req.body?.accessToken, phoneNumber: req.body?.phoneNumber, role: 'driver' }));
  } catch (error) { next(error); }
});

app.post('/api/auth/customer/msg91', authLimiter, async (req, res, next) => {
  try {
    res.json(await createFirebaseSession({ accessToken: req.body?.accessToken, phoneNumber: req.body?.phoneNumber, role: 'customer' }));
  } catch (error) { next(error); }
});

app.post('/api/driver/presence', async (req, res, next) => {
  try {
    const uid = await requireDriver(req);
    const online = Boolean(req.body?.online);
    await db.collection('partners').doc(uid).set({ online, role: 'driver', lastSeenAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    res.json({ ok: true, online });
  } catch (error) { next(error); }
});

app.post('/api/driver/location', async (req, res, next) => {
  try {
    const uid = await requireDriver(req);
    const latitude = Number(req.body?.latitude);
    const longitude = Number(req.body?.longitude);
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude) || latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
      const error = new Error('Invalid coordinates.');
      error.status = 400;
      throw error;
    }
    await db.collection('partners').doc(uid).set({ online: true, latitude, longitude, locationAccuracy: Number(req.body?.accuracy || 0), heading: Number(req.body?.heading || 0), speed: Number(req.body?.speed || 0), locationUpdatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    res.json({ ok: true });
  } catch (error) { next(error); }
});

app.post('/api/bookings/:bookingId/accept', async (req, res, next) => {
  try {
    const uid = await requireDriver(req);
    const bookingId = String(req.params.bookingId || '');
    const ref = db.collection('bookings').doc(bookingId);
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) { const e = new Error('Booking not found.'); e.status = 404; throw e; }
      const data = snap.data() || {};
      if (!['REQUESTED', 'SEARCHING'].includes(String(data.status || '').toUpperCase())) { const e = new Error('This booking is no longer available.'); e.status = 409; throw e; }
      tx.set(ref, { status: 'ACCEPTED', partnerId: uid, acceptedAt: admin.firestore.FieldValue.serverTimestamp(), updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    });
    res.json({ ok: true, bookingId, status: 'ACCEPTED' });
  } catch (error) { next(error); }
});

app.post('/api/bookings/:bookingId/decline', async (req, res, next) => {
  try {
    const uid = await requireDriver(req);
    const bookingId = String(req.params.bookingId || '');
    const ref = db.collection('bookings').doc(bookingId);
    const snap = await ref.get();
    if (!snap.exists) { const e = new Error('Booking not found.'); e.status = 404; throw e; }
    await ref.set({ declinedBy: admin.firestore.FieldValue.arrayUnion(uid), updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    res.json({ ok: true, bookingId, status: 'DECLINED' });
  } catch (error) { next(error); }
});

// Replaces the old Firestore onDocumentWritten trigger. Keep one backend instance running.
function startBookingEarningsListener() {
  db.collection('bookings').onSnapshot((snapshot) => {
    for (const change of snapshot.docChanges()) {
      if (!['added', 'modified'].includes(change.type)) continue;
      const data = change.doc.data() || {};
      if (String(data.status || '').toUpperCase() !== 'COMPLETED' || !data.partnerId) continue;
      const fare = Number(data.fare || 0);
      const share = Number(data.partnerSharePercent ?? 85);
      const earnings = Math.max(0, Math.round(fare * share / 100));
      db.collection('partners').doc(data.partnerId).collection('earnings').doc(change.doc.id).set({ bookingId: change.doc.id, fare, partnerSharePercent: share, earnings, completedAt: data.completedAt || admin.firestore.FieldValue.serverTimestamp(), createdAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true }).catch(console.error);
    }
  }, (error) => console.error('Booking listener error:', error));
}

app.use((error, _req, res, _next) => {
  console.error(error);
  res.status(Number(error?.status) || 500).json({ error: error?.message || 'Internal server error.' });
});

const port = Number(process.env.PORT || 8080);
app.listen(port, () => {
  console.log(`WE DRIVE backend listening on ${port}`);
  startBookingEarningsListener();
});

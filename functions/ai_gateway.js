const crypto = require('crypto');
const { onRequest } = require('firebase-functions/v2/https');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

const db = getFirestore();

const ALLOWED_TOOLS = new Set([
  'get_booking',
  'get_available_drivers',
  'get_driver_status',
  'get_customer',
  'create_job',
  'assign_driver',
  'send_notification',
  'get_business_report',
  'get_system_health',
]);

const READ_ONLY_TOOLS = new Set([
  'get_booking',
  'get_available_drivers',
  'get_driver_status',
  'get_customer',
  'get_business_report',
  'get_system_health',
]);

function fail(status, message) {
  const error = new Error(message);
  error.status = status;
  throw error;
}

function text(value, name, max = 500) {
  if (typeof value !== 'string' || !value.trim()) fail(400, `${name} is required.`);
  return value.trim().slice(0, max);
}

function optionalText(value, max = 500) {
  if (value == null) return null;
  if (typeof value !== 'string') fail(400, 'Invalid text value.');
  const valueTrimmed = value.trim();
  return valueTrimmed ? valueTrimmed.slice(0, max) : null;
}

function finiteNumber(value, name) {
  const number = Number(value);
  if (!Number.isFinite(number)) fail(400, `${name} must be a valid number.`);
  return number;
}

function validateArgs(tool, args) {
  if (!args || typeof args !== 'object' || Array.isArray(args)) fail(400, 'arguments must be an object.');

  switch (tool) {
    case 'get_booking':
      return { bookingId: text(args.booking_id, 'booking_id', 160) };
    case 'get_customer':
      return { customerId: text(args.customer_id, 'customer_id', 160) };
    case 'get_driver_status':
      return { driverId: text(args.driver_id, 'driver_id', 160) };
    case 'get_available_drivers':
      return {
        serviceDate: text(args.service_date, 'service_date', 40),
        startTime: text(args.start_time, 'start_time', 40),
        location: text(args.location, 'location', 500),
        durationMinutes: args.duration_minutes == null ? null : finiteNumber(args.duration_minutes, 'duration_minutes'),
      };
    case 'create_job':
      return {
        customerId: text(args.customer_id, 'customer_id', 160),
        serviceDate: text(args.service_date, 'service_date', 40),
        startTime: text(args.start_time, 'start_time', 40),
        location: text(args.location, 'location', 500),
        durationMinutes: args.duration_minutes == null ? null : finiteNumber(args.duration_minutes, 'duration_minutes'),
        notes: optionalText(args.notes, 1000),
      };
    case 'assign_driver':
      return { jobId: text(args.job_id, 'job_id', 160), driverId: text(args.driver_id, 'driver_id', 160) };
    case 'send_notification':
      return {
        recipientId: text(args.recipient_id, 'recipient_id', 160),
        channel: text(args.channel, 'channel', 40).toLowerCase(),
        message: text(args.message, 'message', 2000),
        jobId: optionalText(args.job_id, 160),
      };
    case 'get_business_report':
      return {
        periodStart: text(args.period_start, 'period_start', 40),
        periodEnd: text(args.period_end, 'period_end', 40),
        metrics: Array.isArray(args.metrics) ? args.metrics.slice(0, 30).map((m) => String(m).slice(0, 80)) : null,
      };
    case 'get_system_health':
      return {};
    default:
      fail(403, 'Tool is not allowed.');
  }
}

function authenticate(request) {
  const configured = process.env.WE_DRIVE_AI_GATEWAY_TOKEN;
  const header = request.get('authorization') || '';
  const supplied = header.startsWith('Bearer ') ? header.slice(7).trim() : '';
  if (!configured || !supplied) fail(401, 'AI gateway authentication failed.');
  const expected = Buffer.from(configured);
  const actual = Buffer.from(supplied);
  if (expected.length !== actual.length || !crypto.timingSafeEqual(expected, actual)) {
    fail(401, 'AI gateway authentication failed.');
  }
}

function idempotencyKey(request) {
  const key = request.get('x-idempotency-key');
  if (!key || key.length > 200) fail(400, 'X-Idempotency-Key is required for write operations.');
  return key;
}

async function runTool(tool, args) {
  if (tool === 'get_system_health') {
    await db.collection('bookings').limit(1).get();
    return { ok: true, firestore: 'ok', region: 'asia-south1' };
  }

  if (tool === 'get_booking') {
    const snap = await db.collection('bookings').doc(args.bookingId).get();
    if (!snap.exists) fail(404, 'Booking not found.');
    return { ok: true, booking: { id: snap.id, ...snap.data() } };
  }

  if (tool === 'get_customer') {
    const [userSnap, profileSnap] = await Promise.all([
      db.collection('users').doc(args.customerId).get(),
      db.collection('profiles').doc(args.customerId).get(),
    ]);
    if (!userSnap.exists && !profileSnap.exists) fail(404, 'Customer not found.');
    return { ok: true, customer: { id: args.customerId, ...(userSnap.data() || {}), ...(profileSnap.data() || {}) } };
  }

  if (tool === 'get_driver_status') {
    const snap = await db.collection('partners').doc(args.driverId).get();
    if (!snap.exists) fail(404, 'Driver not found.');
    const data = snap.data() || {};
    return { ok: true, driver: { id: snap.id, online: data.online === true, lastSeenAt: data.lastSeenAt || null, latitude: data.latitude ?? null, longitude: data.longitude ?? null } };
  }

  if (tool === 'get_available_drivers') {
    const snap = await db.collection('partners').where('online', '==', true).limit(50).get();
    const drivers = snap.docs.map((doc) => {
      const data = doc.data() || {};
      return { id: doc.id, name: data.name || data.fullName || 'WE DRIVE Chauffeur', phoneNumber: data.phoneNumber || null, rating: Number(data.rating || 0), latitude: data.latitude ?? null, longitude: data.longitude ?? null, verified: data.verified === true };
    });
    return { ok: true, serviceDate: args.serviceDate, startTime: args.startTime, durationMinutes: args.durationMinutes, location: args.location, drivers };
  }

  if (tool === 'create_job') {
    const customerSnap = await db.collection('users').doc(args.customerId).get();
    if (!customerSnap.exists) fail(404, 'Customer not found.');
    const customer = customerSnap.data() || {};
    const ref = db.collection('bookings').doc();
    const data = {
      bookingId: ref.id,
      customerId: args.customerId,
      customerName: customer.name || 'WE DRIVE Customer',
      customerPhone: customer.phone || null,
      customerEmail: customer.email || null,
      serviceType: 'Driver on Demand',
      pickupLocation: args.location,
      bookingDate: args.serviceDate,
      bookingTime: args.startTime,
      selectedHours: args.durationMinutes == null ? null : args.durationMinutes / 60,
      fare: 0,
      currency: 'INR',
      paymentMethod: 'Cash',
      paymentStatus: 'pending',
      status: 'REQUESTED',
      bookingStatus: 'REQUESTED',
      partnerId: null,
      driverId: null,
      driverName: null,
      driverPhone: null,
      specialInstruction: args.notes,
      source: 'AI_GATEWAY',
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    };
    await ref.create(data);
    return { ok: true, bookingId: ref.id, status: 'REQUESTED' };
  }

  if (tool === 'assign_driver') {
    const bookingRef = db.collection('bookings').doc(args.jobId);
    const driverRef = db.collection('partners').doc(args.driverId);
    await db.runTransaction(async (tx) => {
      const [bookingSnap, driverSnap] = await Promise.all([tx.get(bookingRef), tx.get(driverRef)]);
      if (!bookingSnap.exists) fail(404, 'Booking not found.');
      if (!driverSnap.exists) fail(404, 'Driver not found.');
      const booking = bookingSnap.data() || {};
      const driver = driverSnap.data() || {};
      if (!['REQUESTED', 'SEARCHING'].includes(String(booking.status || '').toUpperCase())) fail(409, 'Booking is not available for assignment.');
      if (driver.online !== true) fail(409, 'Driver is not online.');
      tx.set(bookingRef, { partnerId: args.driverId, driverId: args.driverId, status: 'ACCEPTED', bookingStatus: 'ACCEPTED', acceptedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    });
    return { ok: true, bookingId: args.jobId, driverId: args.driverId, status: 'ACCEPTED' };
  }

  if (tool === 'send_notification') {
    const allowedChannels = new Set(['in_app', 'push', 'whatsapp']);
    if (!allowedChannels.has(args.channel)) fail(400, 'Unsupported notification channel.');
    const ref = await db.collection('notifications').add({ userId: args.recipientId, type: 'ai', channel: args.channel, message: args.message, bookingId: args.jobId || null, read: false, source: 'AI_GATEWAY', createdAt: FieldValue.serverTimestamp() });
    return { ok: true, notificationId: ref.id };
  }

  if (tool === 'get_business_report') {
    const snap = await db.collection('bookings').where('bookingDate', '>=', args.periodStart).where('bookingDate', '<=', args.periodEnd).limit(500).get();
    const bookings = snap.docs.map((doc) => doc.data() || {});
    const completed = bookings.filter((b) => String(b.status || '').toUpperCase() === 'COMPLETED').length;
    const cancelled = bookings.filter((b) => String(b.status || '').toUpperCase().includes('CANCEL')).length;
    const requested = bookings.length;
    const revenue = bookings.reduce((sum, b) => sum + Math.max(0, Number(b.fare || 0)), 0);
    return { ok: true, periodStart: args.periodStart, periodEnd: args.periodEnd, metrics: { bookings: requested, completed, cancelled, pending: Math.max(0, requested - completed - cancelled), grossFare: revenue } };
  }

  fail(403, 'Tool is not allowed.');
}

exports.aiGateway = onRequest({ region: 'asia-south1' }, async (request, response) => {
  const requestId = request.get('x-we-drive-ai-request-id') || crypto.randomUUID();
  try {
    authenticate(request);
    if (request.method !== 'POST') fail(405, 'POST is required.');

    const tool = request.body?.tool;
    if (!ALLOWED_TOOLS.has(tool)) fail(403, 'Tool is not allowed.');
    const args = validateArgs(tool, request.body?.arguments || {});

    let key = null;
    if (!READ_ONLY_TOOLS.has(tool)) {
      key = idempotencyKey(request);
      const idemRef = db.collection('aiIdempotency').doc(crypto.createHash('sha256').update(key).digest('hex'));
      const idemSnap = await idemRef.get();
      if (idemSnap.exists) {
        response.status(200).json({ ...idemSnap.data().response, replayed: true, requestId });
        return;
      }
    }

    const result = await runTool(tool, args);
    if (key) {
      const idemRef = db.collection('aiIdempotency').doc(crypto.createHash('sha256').update(key).digest('hex'));
      await idemRef.create({ response: result, tool, createdAt: FieldValue.serverTimestamp() });
    }

    response.status(200).json({ ...result, requestId });
  } catch (error) {
    const status = Number(error.status) || 500;
    console.error('WE DRIVE AI gateway error', { requestId, status, message: error.message });
    response.status(status).json({ ok: false, error: error.message || 'Internal gateway error.', requestId });
  }
});

exports._test = { validateArgs, authenticate, ALLOWED_TOOLS, READ_ONLY_TOOLS };

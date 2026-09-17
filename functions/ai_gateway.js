const crypto = require('crypto');
const { onRequest } = require('firebase-functions/v2/https');
const { getApps, initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { createBookingForAI, assignBookingForAI } = require('./ai_booking_service');
const { createApproval, getApproval } = require('./ai_approval');
const { recordAudit } = require('./ai_audit');
const { idempotencyDocId, argumentsFingerprint, beginIdempotentOperation, completeIdempotentOperation, failIdempotentOperation } = require('./ai_idempotency');

if (!getApps().length) initializeApp();
const db = getFirestore();

const ALLOWED_TOOLS = new Set(['get_booking', 'get_available_drivers', 'get_driver_status', 'get_customer', 'create_job', 'assign_driver', 'send_notification', 'get_business_report', 'get_system_health', 'request_approval', 'get_approval']);
const READ_ONLY_TOOLS = new Set(['get_booking', 'get_available_drivers', 'get_driver_status', 'get_customer', 'get_business_report', 'get_system_health', 'get_approval']);
const ARGUMENT_KEYS = {
  get_booking: ['booking_id'], get_customer: ['customer_id'], get_driver_status: ['driver_id'],
  get_available_drivers: ['service_date', 'start_time', 'location', 'duration_minutes', 'latitude', 'longitude', 'required_service'],
  create_job: ['customer_id', 'service_date', 'start_time', 'location', 'duration_minutes', 'notes'],
  assign_driver: ['job_id', 'driver_id'], send_notification: ['recipient_id', 'channel', 'message', 'job_id'],
  get_business_report: ['period_start', 'period_end', 'metrics'], get_system_health: [],
  request_approval: ['action', 'reason', 'metadata'], get_approval: ['approval_id'],
};
function fail(status, message) { const error = new Error(message); error.status = status; throw error; }
function text(value, name, max = 500) { if (typeof value !== 'string' || !value.trim()) fail(400, `${name} is required.`); return value.trim().slice(0, max); }
function optionalText(value, max = 500) { if (value == null) return null; if (typeof value !== 'string') fail(400, 'Invalid text value.'); const v = value.trim(); return v ? v.slice(0, max) : null; }
function finiteNumber(value, name) { const number = Number(value); if (!Number.isFinite(number)) fail(400, `${name} must be a valid number.`); return number; }
function optionalPositiveNumber(value, name) { if (value == null) return null; const number = finiteNumber(value, name); if (number <= 0) fail(400, `${name} must be greater than zero.`); return number; }
function optionalCoordinate(value, name, min, max) { if (value == null) return null; const number = finiteNumber(value, name); if (number < min || number > max) fail(400, `${name} is out of range.`); return number; }
function validateArgs(tool, args) {
  if (!args || typeof args !== 'object' || Array.isArray(args)) fail(400, 'arguments must be an object.');
  const allowed = new Set(ARGUMENT_KEYS[tool] || []); const unknown = Object.keys(args).filter((key) => !allowed.has(key));
  if (unknown.length) fail(400, `Unknown argument(s): ${unknown.join(', ')}.`);
  switch (tool) {
    case 'get_booking': return { bookingId: text(args.booking_id, 'booking_id', 160) };
    case 'get_customer': return { customerId: text(args.customer_id, 'customer_id', 160) };
    case 'get_driver_status': return { driverId: text(args.driver_id, 'driver_id', 160) };
    case 'get_available_drivers': return { serviceDate: text(args.service_date, 'service_date', 40), startTime: text(args.start_time, 'start_time', 40), location: text(args.location, 'location', 500), durationMinutes: optionalPositiveNumber(args.duration_minutes, 'duration_minutes'), latitude: optionalCoordinate(args.latitude, 'latitude', -90, 90), longitude: optionalCoordinate(args.longitude, 'longitude', -180, 180), requiredService: optionalText(args.required_service, 80) };
    case 'create_job': return { customerId: text(args.customer_id, 'customer_id', 160), serviceDate: text(args.service_date, 'service_date', 40), startTime: text(args.start_time, 'start_time', 40), location: text(args.location, 'location', 500), durationMinutes: optionalPositiveNumber(args.duration_minutes, 'duration_minutes'), notes: optionalText(args.notes, 1000) };
    case 'assign_driver': return { jobId: text(args.job_id, 'job_id', 160), driverId: text(args.driver_id, 'driver_id', 160) };
    case 'send_notification': return { recipientId: text(args.recipient_id, 'recipient_id', 160), channel: text(args.channel, 'channel', 40).toLowerCase(), message: text(args.message, 'message', 2000), jobId: optionalText(args.job_id, 160) };
    case 'get_business_report': return { periodStart: text(args.period_start, 'period_start', 40), periodEnd: text(args.period_end, 'period_end', 40), metrics: Array.isArray(args.metrics) ? args.metrics.slice(0, 30).map((m) => String(m).slice(0, 80)) : null };
    case 'get_system_health': return {};
    case 'request_approval': return { action: text(args.action, 'action', 100), reason: text(args.reason, 'reason', 1000), metadata: args.metadata && typeof args.metadata === 'object' && !Array.isArray(args.metadata) ? args.metadata : {} };
    case 'get_approval': return { approvalId: text(args.approval_id, 'approval_id', 160) };
    default: fail(403, 'Tool is not allowed.');
  }
}
function authenticate(request) { const configured = process.env.WE_DRIVE_AI_GATEWAY_TOKEN; const header = request.get('authorization') || ''; const match = /^Bearer\s+(.+)$/i.exec(header.trim()); const supplied = match ? match[1].trim() : ''; if (!configured || !supplied) fail(401, 'AI gateway authentication failed.'); const expected = Buffer.from(configured); const actual = Buffer.from(supplied); if (expected.length !== actual.length || !crypto.timingSafeEqual(expected, actual)) fail(401, 'AI gateway authentication failed.'); }
function idempotencyKey(request) { const key = request.get('x-idempotency-key'); if (!key || key.length > 200) fail(400, 'X-Idempotency-Key is required for write operations.'); return key; }
function actorId(request) { const actor = request.get('x-we-drive-ai-actor-id'); if (!actor || actor.length > 160) fail(400, 'X-WE-DRIVE-AI-Actor-ID is required.'); return actor.trim(); }
async function runTool(tool, args, actor) {
  if (tool === 'request_approval') return createApproval({ actorId: actor, action: args.action, reason: args.reason, metadata: args.metadata });
  if (tool === 'get_approval') return getApproval(args.approvalId);
  if (tool === 'get_system_health') { await db.collection('bookings').limit(1).get(); return { ok: true, firestore: 'ok', region: 'asia-south1' }; }
  if (tool === 'get_booking') { const snap = await db.collection('bookings').doc(args.bookingId).get(); if (!snap.exists) fail(404, 'Booking not found.'); return { ok: true, booking: { id: snap.id, ...snap.data() } }; }
  if (tool === 'get_customer') { const [u, p] = await Promise.all([db.collection('users').doc(args.customerId).get(), db.collection('profiles').doc(args.customerId).get()]); if (!u.exists && !p.exists) fail(404, 'Customer not found.'); return { ok: true, customer: { id: args.customerId, ...(u.data() || {}), ...(p.data() || {}) } }; }
  if (tool === 'get_driver_status') { const snap = await db.collection('partners').doc(args.driverId).get(); if (!snap.exists) fail(404, 'Driver not found.'); const d = snap.data() || {}; return { ok: true, driver: { id: snap.id, online: d.online === true, lastSeenAt: d.lastSeenAt || null, latitude: d.latitude ?? null, longitude: d.longitude ?? null } }; }
  if (tool === 'get_available_drivers') { const snap = await db.collection('partners').where('online', '==', true).limit(50).get(); const drivers = snap.docs.map((doc) => { const d = doc.data() || {}; return { id: doc.id, name: d.name || d.fullName || 'WE DRIVE Chauffeur', phoneNumber: d.phoneNumber || null, rating: Number(d.rating || 0), latitude: d.latitude ?? null, longitude: d.longitude ?? null, verified: d.verified === true }; }); return { ok: true, serviceDate: args.serviceDate, startTime: args.startTime, durationMinutes: args.durationMinutes, location: args.location, requestedLatitude: args.latitude, requestedLongitude: args.longitude, requiredService: args.requiredService, drivers }; }
  if (tool === 'create_job') return createBookingForAI(args);
  if (tool === 'assign_driver') return assignBookingForAI({ bookingId: args.jobId, driverId: args.driverId });
  if (tool === 'send_notification') { if (!new Set(['in_app', 'push', 'whatsapp']).has(args.channel)) fail(400, 'Unsupported notification channel.'); const ref = await db.collection('notifications').add({ userId: args.recipientId, type: 'ai', channel: args.channel, message: args.message, bookingId: args.jobId || null, read: false, source: 'AI_GATEWAY', createdAt: FieldValue.serverTimestamp() }); return { ok: true, notificationId: ref.id }; }
  if (tool === 'get_business_report') { const snap = await db.collection('bookings').where('bookingDate', '>=', args.periodStart).where('bookingDate', '<=', args.periodEnd).limit(500).get(); const bookings = snap.docs.map((doc) => doc.data() || {}); const completed = bookings.filter((b) => String(b.status || '').toUpperCase() === 'COMPLETED').length; const cancelled = bookings.filter((b) => String(b.status || '').toUpperCase().includes('CANCEL')).length; const requested = bookings.length; const revenue = bookings.reduce((sum, b) => sum + Math.max(0, Number(b.fare || 0)), 0); return { ok: true, periodStart: args.periodStart, periodEnd: args.periodEnd, metrics: { bookings: requested, completed, cancelled, pending: Math.max(0, requested - completed - cancelled), grossFare: revenue } }; }
  fail(403, 'Tool is not allowed.');
}
async function executeWrite(tool, args, actor, key, requestId, response) {
  const operation = await beginIdempotentOperation({ tool, key, actor, args });
  if (operation.replay) {
    response.status(200).json({ ...operation.response, replayed: true, requestId });
    return true;
  }
  try {
    const result = await runTool(tool, args, actor);
    await completeIdempotentOperation(operation.ref, result);
    response.status(200).json({ ...result, requestId });
    return true;
  } catch (error) {
    await failIdempotentOperation(operation.ref, error).catch((persistError) => console.error('WE DRIVE AI idempotency failure persistence failed', { requestId, message: persistError.message }));
    throw error;
  }
}
exports.aiGateway = onRequest({ region: 'asia-south1' }, async (request, response) => {
  const requestId = request.get('x-we-drive-ai-request-id') || crypto.randomUUID();
  let auditTool = request.body?.tool || null;
  let auditActor = null;
  response.on('finish', () => {
    recordAudit({ requestId, actorId: auditActor, tool: auditTool, status: response.statusCode, outcome: response.statusCode >= 400 ? 'error' : 'success' }).catch((auditError) => console.error('WE DRIVE AI audit logging failed', { requestId, message: auditError.message }));
  });
  try {
    authenticate(request);
    if (request.method !== 'POST') fail(405, 'POST is required.');
    if (Number(request.get('content-length') || 0) > 1024 * 1024) fail(413, 'Request body is too large.');
    const tool = request.body?.tool;
    auditTool = tool || null;
    if (!ALLOWED_TOOLS.has(tool)) fail(403, 'Tool is not allowed.');
    const args = validateArgs(tool, request.body?.arguments || {});
    const actor = READ_ONLY_TOOLS.has(tool) && tool === 'get_approval' ? actorId(request) : (!READ_ONLY_TOOLS.has(tool) ? actorId(request) : null);
    auditActor = actor;
    if (tool === 'get_approval') {
      const result = await runTool(tool, args, actor);
      response.status(200).json({ ...result, requestId });
      return;
    }
    if (!READ_ONLY_TOOLS.has(tool)) {
      const key = idempotencyKey(request);
      await executeWrite(tool, args, actor, key, requestId, response);
      return;
    }
    const result = await runTool(tool, args, actor);
    response.status(200).json({ ...result, requestId });
  } catch (error) {
    const status = Number(error.status) || 500;
    console.error('WE DRIVE AI gateway error', { requestId, status, message: error.message });
    response.status(status).json({ ok: false, error: error.message || 'Internal gateway error.', requestId });
  }
});
exports._test = { validateArgs, authenticate, ALLOWED_TOOLS, READ_ONLY_TOOLS, idempotencyDocId, argumentsFingerprint };

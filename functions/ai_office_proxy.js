const { onRequest } = require('firebase-functions/v2/https');
const { getApps, initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');

if (!getApps().length) initializeApp();

const MAX_BODY_BYTES = 1024 * 1024;
const ALLOWED_METHOD = 'POST';

function fail(status, message) {
  const error = new Error(message);
  error.status = status;
  throw error;
}

function applyCors(request, response) {
  const configuredOrigin = String(process.env.AI_OFFICE_ORIGIN || '').trim();
  const origin = String(request.get('origin') || '').trim();
  if (configuredOrigin && origin && origin !== configuredOrigin) {
    fail(403, 'AI Office origin is not allowed.');
  }
  if (configuredOrigin) response.set('Access-Control-Allow-Origin', configuredOrigin);
  response.set('Vary', 'Origin');
  response.set('Access-Control-Allow-Headers', 'Authorization, Content-Type');
  response.set('Access-Control-Allow-Methods', ALLOWED_METHOD);
}

function bearerToken(request) {
  const header = String(request.get('authorization') || '').trim();
  const match = /^Bearer\s+(.+)$/i.exec(header);
  if (!match) fail(401, 'Firebase authentication is required.');
  return match[1].trim();
}

function serviceConfig() {
  const baseUrl = String(process.env.WE_DRIVE_AI_SERVICE_URL || '').trim().replace(/\/$/, '');
  const token = String(process.env.WE_DRIVE_AI_API_TOKEN || '').trim();
  if (!baseUrl || !token) fail(503, 'AI Office service is not configured.');
  return { baseUrl, token };
}

function validateBody(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) fail(400, 'Request body must be an object.');
  if (typeof body.message !== 'string' || !body.message.trim() || body.message.length > 8000) {
    fail(400, 'message is required and must be at most 8000 characters.');
  }
  if (body.context != null && (typeof body.context !== 'object' || Array.isArray(body.context))) {
    fail(400, 'context must be an object.');
  }
  if (body.session_id != null && (typeof body.session_id !== 'string' || body.session_id.length > 160)) {
    fail(400, 'session_id is invalid.');
  }
}

exports.aiOfficeProxy = onRequest({ region: 'asia-south1', timeoutSeconds: 30 }, async (request, response) => {
  const requestId = request.get('x-we-drive-ai-request-id') || crypto.randomUUID();
  try {
    applyCors(request, response);
    if (request.method === 'OPTIONS') {
      response.status(204).send('');
      return;
    }
    if (request.method !== ALLOWED_METHOD) fail(405, 'POST is required.');
    if (Number(request.get('content-length') || 0) > MAX_BODY_BYTES) fail(413, 'Request body is too large.');

    const decoded = await getAuth().verifyIdToken(bearerToken(request), true);
    validateBody(request.body);
    const { baseUrl, token } = serviceConfig();

    const payload = {
      actor_id: decoded.uid,
      message: request.body.message.trim(),
      context: request.body.context || {},
      session_id: request.body.session_id || `office:${decoded.uid}`,
    };

    const upstream = await fetch(`${baseUrl}/v1/agent`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
        'X-WE-DRIVE-AI-Office': 'true',
        'X-WE-DRIVE-AI-Actor-ID': decoded.uid,
        'X-WE-DRIVE-AI-Request-ID': requestId,
      },
      body: JSON.stringify(payload),
    });

    const text = await upstream.text();
    let body = {};
    try { body = text ? JSON.parse(text) : {}; } catch (_) { body = { detail: 'AI service returned invalid JSON.' }; }

    response.status(upstream.status).json(body);
  } catch (error) {
    const status = Number(error.status) || (error.code === 'auth/id-token-revoked' || error.code === 'auth/argument-error' ? 401 : 500);
    console.error('WE DRIVE AI Office proxy error', { requestId, status, message: error.message });
    response.status(status).json({ ok: false, error: error.message || 'AI Office request failed.', requestId });
  }
});

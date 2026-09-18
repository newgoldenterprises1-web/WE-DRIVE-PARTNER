const crypto = require('crypto');
const { onRequest } = require('firebase-functions/v2/https');
const { getAuth, getApps, initializeApp } = require('firebase-admin/app');
const { decideApproval } = require('./ai_approval');

if (!getApps().length) initializeApp();

function fail(status, message) {
  const error = new Error(message);
  error.status = status;
  throw error;
}

async function requireAdmin(request) {
  const header = request.get('authorization') || '';
  const match = /^Bearer\s+(.+)$/i.exec(header.trim());
  if (!match) fail(401, 'Firebase admin authentication required.');
  let decoded;
  try {
    decoded = await getAuth().verifyIdToken(match[1].trim(), true);
  } catch (_) {
    fail(401, 'Firebase admin authentication failed.');
  }
  const isAdmin = decoded.admin === true || decoded.role === 'admin' || decoded.role === 'ADMIN';
  if (!isAdmin) fail(403, 'Admin approval permission required.');
  return decoded.uid;
}

exports.aiApprovalDecision = onRequest({ region: 'asia-south1' }, async (request, response) => {
  const requestId = request.get('x-we-drive-ai-request-id') || crypto.randomUUID();
  try {
    if (request.method !== 'POST') fail(405, 'POST is required.');
    const approverId = await requireAdmin(request);
    const body = request.body || {};
    const approvalId = typeof body.approval_id === 'string' ? body.approval_id.trim() : '';
    if (!approvalId) fail(400, 'approval_id is required.');
    if (approvalId.length > 160) fail(400, 'approval_id is too long.');
    if (typeof body.approved !== 'boolean') fail(400, 'approved must be a boolean.');
    const decisionReason = typeof body.decision_reason === 'string' ? body.decision_reason.slice(0, 1000) : '';
    const result = await decideApproval({ approvalId, approverId, approved: body.approved, decisionReason });
    response.status(200).json({ ...result, requestId });
  } catch (error) {
    const status = Number(error.status) || 500;
    console.error('WE DRIVE AI approval decision error', { requestId, status, message: error.message });
    response.status(status).json({ ok: false, error: error.message || 'Approval decision failed.', requestId });
  }
});

exports._test = { requireAdmin };

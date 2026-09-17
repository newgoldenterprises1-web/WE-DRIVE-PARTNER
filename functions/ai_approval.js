const crypto = require('crypto');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

const db = getFirestore();

const CRITICAL_ACTIONS = new Set([
  'large_refund',
  'large_financial_action',
  'driver_suspend',
  'critical_account_change',
  'production_deploy',
]);
const APPROVAL_TTL_MS = 15 * 60 * 1000;

function requireText(value, name, max = 200) {
  if (typeof value !== 'string' || !value.trim()) throw new Error(`${name} is required.`);
  return value.trim().slice(0, max);
}

function fingerprint(action, metadata = {}) {
  return crypto.createHash('sha256').update(JSON.stringify({ action, metadata })).digest('hex');
}

function assertCriticalAction(action) {
  if (!CRITICAL_ACTIONS.has(action)) {
    const error = new Error('Action does not require critical approval.');
    error.status = 400;
    throw error;
  }
}

async function createApproval({ actorId, action, reason, metadata = {} }) {
  assertCriticalAction(action);
  const actor = requireText(actorId, 'actorId');
  const safeMetadata = metadata && typeof metadata === 'object' && !Array.isArray(metadata) ? metadata : {};
  const approvalRef = db.collection('aiApprovals').doc();
  await approvalRef.create({
    approvalId: approvalRef.id,
    actorId: actor,
    action,
    reason: requireText(reason, 'reason', 1000),
    metadata: safeMetadata,
    actionFingerprint: fingerprint(action, safeMetadata),
    status: 'PENDING',
    expiresAt: new Date(Date.now() + APPROVAL_TTL_MS),
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return { ok: true, approvalId: approvalRef.id, status: 'PENDING' };
}

async function getApproval(approvalId) {
  const id = requireText(approvalId, 'approvalId');
  const snap = await db.collection('aiApprovals').doc(id).get();
  if (!snap.exists) {
    const error = new Error('Approval request not found.');
    error.status = 404;
    throw error;
  }
  return { ok: true, approval: { id: snap.id, ...snap.data() } };
}

async function decideApproval({ approvalId, approverId, approved, decisionReason = '' }) {
  const id = requireText(approvalId, 'approvalId');
  const approver = requireText(approverId, 'approverId');
  if (typeof approved !== 'boolean') {
    const error = new Error('approved must be a boolean.');
    error.status = 400;
    throw error;
  }
  const ref = db.collection('aiApprovals').doc(id);
  const result = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      const error = new Error('Approval request not found.');
      error.status = 404;
      throw error;
    }
    const current = snap.data() || {};
    if (current.status !== 'PENDING') {
      const error = new Error('Approval request has already been decided.');
      error.status = 409;
      throw error;
    }
    const expiresAt = current.expiresAt && typeof current.expiresAt.toMillis === 'function'
      ? current.expiresAt.toMillis()
      : new Date(current.expiresAt || 0).getTime();
    if (!Number.isFinite(expiresAt) || expiresAt <= Date.now()) {
      tx.update(ref, { status: 'EXPIRED', updatedAt: FieldValue.serverTimestamp() });
      const error = new Error('Approval request has expired.');
      error.status = 410;
      throw error;
    }
    const status = approved ? 'APPROVED' : 'REJECTED';
    tx.update(ref, {
      status,
      approvedBy: approver,
      approvedAt: FieldValue.serverTimestamp(),
      decisionReason: String(decisionReason || '').slice(0, 1000),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return status;
  });
  return { ok: true, approvalId: id, status: result, decidedBy: approver };
}

module.exports = { CRITICAL_ACTIONS, createApproval, getApproval, decideApproval, fingerprint, APPROVAL_TTL_MS };

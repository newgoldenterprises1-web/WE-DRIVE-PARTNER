const crypto = require('crypto');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { recordAudit } = require('./ai_audit');

const db = getFirestore();

const CRITICAL_ACTIONS = new Set([
  'large_refund',
  'large_financial_action',
  'driver_suspend',
  'critical_account_change',
  'production_deploy',
  'publish_social_content',
  'send_whatsapp_campaign',
]);
const APPROVAL_TTL_MS = 15 * 60 * 1000;

function requireText(value, name, max = 200) {
  if (typeof value !== 'string' || !value.trim()) {
    const error = new Error(`${name} is required.`);
    error.status = 400;
    throw error;
  }
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

function validateSafeObject(value, path = 'metadata', depth = 0) {
  if (depth > 5) {
    const error = new Error('Approval metadata is too deeply nested.');
    error.status = 400;
    throw error;
  }
  if (Array.isArray(value)) {
    if (value.length > 100) {
      const error = new Error('Approval metadata array is too large.');
      error.status = 400;
      throw error;
    }
    value.forEach((item, index) => validateSafeObject(item, `${path}[${index}]`, depth + 1));
    return;
  }
  if (value && typeof value === 'object') {
    const keys = Object.keys(value);
    if (keys.length > 100) {
      const error = new Error('Approval metadata contains too many fields.');
      error.status = 400;
      throw error;
    }
    for (const key of keys) {
      if (/token|secret|password|authorization|api.?key|private.?key/i.test(key)) {
        const error = new Error('Sensitive credentials are not permitted in approval metadata.');
        error.status = 400;
        throw error;
      }
      validateSafeObject(value[key], `${path}.${key}`, depth + 1);
    }
  }
}

function normalizeExecutionMetadata(metadata = {}) {
  const safeMetadata = metadata && typeof metadata === 'object' && !Array.isArray(metadata) ? metadata : {};
  validateSafeObject(safeMetadata);
  if (JSON.stringify(safeMetadata).length > 30000) { const error = new Error('Approval metadata is too large.'); error.status = 400; throw error; }
  const execution = safeMetadata.execution;
  if (!execution || typeof execution !== 'object' || Array.isArray(execution)) {
    const error = new Error('metadata.execution is required for critical approval.');
    error.status = 400;
    throw error;
  }
  const tool = requireText(execution.tool, 'metadata.execution.tool', 100);
  if (!execution.arguments || typeof execution.arguments !== 'object' || Array.isArray(execution.arguments)) {
    const error = new Error('metadata.execution.arguments is required.');
    error.status = 400;
    throw error;
  }
  return {
    ...safeMetadata,
    execution: {
      tool,
      arguments: execution.arguments,
    },
  };
}

async function createApproval({ actorId, action, reason, metadata = {} }) {
  assertCriticalAction(action);
  const actor = requireText(actorId, 'actorId');
  const safeMetadata = normalizeExecutionMetadata(metadata);
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
  recordAudit({ requestId: approvalRef.id, actorId: actor, tool: action, status: 202, outcome: 'approval_requested', metadata: { approvalId: approvalRef.id, action, reason: requireText(reason, 'reason', 1000) } }).catch(() => {});
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
  recordAudit({ requestId: id, actorId: approver, tool: 'decide_approval', status: 200, outcome: approved ? 'approval_approved' : 'approval_rejected', metadata: { approvalId: id, decisionReason: String(decisionReason || '').slice(0, 1000) } }).catch(() => {});
  return { ok: true, approvalId: id, status: result, decidedBy: approver };
}

async function consumeApproval({ approvalId, actorId, action, metadata = {} }) {
  const id = requireText(approvalId, 'approvalId');
  const actor = requireText(actorId, 'actorId');
  assertCriticalAction(action);
  const safeMetadata = normalizeExecutionMetadata(metadata);
  const expectedFingerprint = fingerprint(action, safeMetadata);
  const ref = db.collection('aiApprovals').doc(id);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      const error = new Error('Approval request not found.');
      error.status = 404;
      throw error;
    }
    const current = snap.data() || {};
    if (current.status !== 'APPROVED') {
      const error = new Error('Approval is not approved for execution.');
      error.status = 409;
      throw error;
    }
    if (current.actorId !== actor) {
      const error = new Error('Approval actor does not match execution actor.');
      error.status = 403;
      throw error;
    }
    if (current.actionFingerprint !== expectedFingerprint) {
      const error = new Error('Approval does not match the requested action or arguments.');
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
    tx.update(ref, {
      status: 'CONSUMED',
      consumedBy: actor,
      consumedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  recordAudit({ requestId: id, actorId: actor, tool: action, status: 200, outcome: 'approval_consumed', metadata: { approvalId: id, action } }).catch(() => {});
  return { ok: true, approvalId: id, status: 'CONSUMED' };
}

module.exports = {
  CRITICAL_ACTIONS,
  createApproval,
  getApproval,
  decideApproval,
  consumeApproval,
  fingerprint,
  normalizeExecutionMetadata,
  APPROVAL_TTL_MS,
};

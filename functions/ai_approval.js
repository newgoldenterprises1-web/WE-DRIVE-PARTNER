const { getFirestore, FieldValue } = require('firebase-admin/firestore');

const db = getFirestore();

const CRITICAL_ACTIONS = new Set([
  'large_refund',
  'large_financial_action',
  'driver_suspend',
  'critical_account_change',
  'production_deploy',
]);

function requireText(value, name, max = 200) {
  if (typeof value !== 'string' || !value.trim()) throw new Error(`${name} is required.`);
  return value.trim().slice(0, max);
}

async function createApproval({ actorId, action, reason, metadata = {} }) {
  if (!CRITICAL_ACTIONS.has(action)) {
    const error = new Error('Action does not require critical approval.');
    error.status = 400;
    throw error;
  }
  const actor = requireText(actorId, 'actorId');
  const approvalRef = db.collection('aiApprovals').doc();
  await approvalRef.create({
    approvalId: approvalRef.id,
    actorId: actor,
    action,
    reason: requireText(reason, 'reason', 1000),
    metadata: metadata && typeof metadata === 'object' && !Array.isArray(metadata) ? metadata : {},
    status: 'PENDING',
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

module.exports = { CRITICAL_ACTIONS, createApproval, getApproval };
